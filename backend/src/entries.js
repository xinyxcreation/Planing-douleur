import { v7 as uuidv7 } from 'uuid';

import { withConnection } from './db.js';
import { recordSyncChange } from './sync.js';

function validateDate(value) {
  const date = String(value ?? '');

  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    const error = new Error('Date invalide. Format attendu : YYYY-MM-DD.');
    error.code = 'VALIDATION_ERROR';
    throw error;
  }

  return date;
}

function mapEntry(row) {
  return {
    id: row.id,
    entryDate: String(row.entry_date),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at,
  };
}

export async function getEntry(userId, dateValue) {
  const date = validateDate(dateValue);

  return withConnection(async (conn) => {
    const entries = await conn.query(
      `SELECT
         id,
         DATE_FORMAT(entry_date, '%Y-%m-%d') AS entry_date,
         created_at,
         updated_at,
         deleted_at
       FROM day_entries
       WHERE user_id = ?
         AND entry_date = ?
         AND deleted_at IS NULL
       LIMIT 1`,
      [userId, date],
    );

    if (entries.length === 0) {
      return null;
    }

    const entry = mapEntry(entries[0]);

    const pains = await conn.query(
      `SELECT
         p.id,
         p.pain_category_id,
         p.level,
         p.created_at,
         p.updated_at,
         p.deleted_at,
         c.name AS category_name
       FROM day_pain_levels p
       INNER JOIN pain_categories c
         ON c.id = p.pain_category_id
        AND c.user_id = ?
       WHERE p.day_entry_id = ?
         AND p.deleted_at IS NULL
         AND c.deleted_at IS NULL
       ORDER BY c.position ASC, c.name ASC`,
      [userId, entry.id],
    );

    const activities = await conn.query(
      `SELECT
         a.id,
         a.activity_type_id,
         a.created_at,
         a.updated_at,
         a.deleted_at,
         t.name AS activity_name
       FROM day_activities a
       INNER JOIN activity_types t
         ON t.id = a.activity_type_id
        AND t.user_id = ?
       WHERE a.day_entry_id = ?
         AND a.deleted_at IS NULL
         AND t.deleted_at IS NULL
       ORDER BY t.position ASC, t.name ASC`,
      [userId, entry.id],
    );

    return {
      ...entry,
      painLevels: pains.map((row) => ({
        id: row.id,
        painCategoryId: row.pain_category_id,
        categoryName: row.category_name,
        level: row.level,
        createdAt: row.created_at,
        updatedAt: row.updated_at,
        deletedAt: row.deleted_at,
      })),
      activities: activities.map((row) => ({
        id: row.id,
        activityTypeId: row.activity_type_id,
        activityName: row.activity_name,
        createdAt: row.created_at,
        updatedAt: row.updated_at,
        deletedAt: row.deleted_at,
      })),
    };
  });
}

export async function saveEntry(userId, dateValue, input) {
  const date = validateDate(dateValue);

  const painLevels = Array.isArray(input?.painLevels)
    ? input.painLevels
    : [];

  const activities = Array.isArray(input?.activities)
    ? input.activities
    : [];

  return withConnection(async (conn) => {
    await conn.beginTransaction();

    try {
      let entries = await conn.query(
        `SELECT id
         FROM day_entries
         WHERE user_id = ?
           AND entry_date = ?
         LIMIT 1
         FOR UPDATE`,
        [userId, date],
      );

      let entryId;
      let entryOperation;

      if (entries.length === 0) {
        entryId = uuidv7();
        entryOperation = 'INSERT';

        await conn.query(
          `INSERT INTO day_entries
            (id, user_id, entry_date, created_at, updated_at)
           VALUES (?, ?, ?, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))`,
          [entryId, userId, date],
        );
      } else {
        entryId = entries[0].id;
        entryOperation = 'UPDATE';

        await conn.query(
          `UPDATE day_entries
           SET deleted_at = NULL,
               updated_at = UTC_TIMESTAMP(6)
           WHERE id = ?
             AND user_id = ?`,
          [entryId, userId],
        );
      }

      await recordSyncChange(
        conn,
        userId,
        'day_entry',
        entryId,
        entryOperation,
      );

      /*
       * DOULOUREURS
       *
       * Le contenu envoyé représente maintenant l'état complet
       * des douleurs de la journée.
       */

      const requestedPainIds = new Set();

      for (const pain of painLevels) {
        const categoryId = String(pain?.painCategoryId ?? '');
        const level = Number(pain?.level);

        if (
          !categoryId ||
          !Number.isInteger(level) ||
          level < 1 ||
          level > 4
        ) {
          const error = new Error('Niveau de douleur invalide.');
          error.code = 'VALIDATION_ERROR';
          throw error;
        }

        const category = await conn.query(
          `SELECT id
           FROM pain_categories
           WHERE id = ?
             AND user_id = ?
             AND deleted_at IS NULL
           LIMIT 1`,
          [categoryId, userId],
        );

        if (category.length === 0) {
          const error = new Error('Catégorie de douleur introuvable.');
          error.code = 'NOT_FOUND';
          throw error;
        }

        requestedPainIds.add(categoryId);

        const existing = await conn.query(
          `SELECT id
           FROM day_pain_levels
           WHERE day_entry_id = ?
             AND pain_category_id = ?
           LIMIT 1
           FOR UPDATE`,
          [entryId, categoryId],
        );

        if (existing.length === 0) {
          const painId = uuidv7();

          await conn.query(
            `INSERT INTO day_pain_levels
              (id, day_entry_id, pain_category_id, level, created_at, updated_at)
             VALUES (?, ?, ?, ?, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))`,
            [
              painId,
              entryId,
              categoryId,
              level,
            ],
          );

          await recordSyncChange(
            conn,
            userId,
            'day_pain_level',
            painId,
            'INSERT',
          );
        } else {
          const painId = existing[0].id;

          await conn.query(
            `UPDATE day_pain_levels
             SET level = ?,
                 deleted_at = NULL,
                 updated_at = UTC_TIMESTAMP(6)
             WHERE id = ?
               AND day_entry_id = ?`,
            [
              level,
              painId,
              entryId,
            ],
          );

          await recordSyncChange(
            conn,
            userId,
            'day_pain_level',
            painId,
            'UPDATE',
          );
        }
      }

      /*
       * Toute douleur existante mais absente de la requête
       * est considérée comme supprimée.
       */

      const existingPains = await conn.query(
        `SELECT id, pain_category_id
         FROM day_pain_levels
         WHERE day_entry_id = ?
           AND deleted_at IS NULL
         FOR UPDATE`,
        [entryId],
      );

      for (const pain of existingPains) {
        if (!requestedPainIds.has(pain.pain_category_id)) {
          await conn.query(
            `UPDATE day_pain_levels
             SET deleted_at = UTC_TIMESTAMP(6),
                 updated_at = UTC_TIMESTAMP(6)
             WHERE id = ?
               AND day_entry_id = ?`,
            [pain.id, entryId],
          );

          await recordSyncChange(
            conn,
            userId,
            'day_pain_level',
            pain.id,
            'DELETE',
          );
        }
      }

      /*
       * ACTIVITÉS
       *
       * Même principe : la liste reçue représente l'état complet
       * des activités de la journée.
       */

      const requestedActivityIds = new Set();

      for (const activity of activities) {
        const activityTypeId = String(
          activity?.activityTypeId ?? '',
        );

        if (!activityTypeId) {
          const error = new Error('Activité invalide.');
          error.code = 'VALIDATION_ERROR';
          throw error;
        }

        const type = await conn.query(
          `SELECT id
           FROM activity_types
           WHERE id = ?
             AND user_id = ?
             AND deleted_at IS NULL
           LIMIT 1`,
          [activityTypeId, userId],
        );

        if (type.length === 0) {
          const error = new Error('Type d’activité introuvable.');
          error.code = 'NOT_FOUND';
          throw error;
        }

        requestedActivityIds.add(activityTypeId);

        const existing = await conn.query(
          `SELECT id
           FROM day_activities
           WHERE day_entry_id = ?
             AND activity_type_id = ?
           LIMIT 1
           FOR UPDATE`,
          [entryId, activityTypeId],
        );

        if (existing.length === 0) {
          const activityId = uuidv7();

          await conn.query(
            `INSERT INTO day_activities
              (id, day_entry_id, activity_type_id, created_at, updated_at)
             VALUES (?, ?, ?, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))`,
            [
              activityId,
              entryId,
              activityTypeId,
            ],
          );

          await recordSyncChange(
            conn,
            userId,
            'day_activity',
            activityId,
            'INSERT',
          );
        } else {
          const activityId = existing[0].id;

          await conn.query(
            `UPDATE day_activities
             SET deleted_at = NULL,
                 updated_at = UTC_TIMESTAMP(6)
             WHERE id = ?
               AND day_entry_id = ?`,
            [
              activityId,
              entryId,
            ],
          );

          await recordSyncChange(
            conn,
            userId,
            'day_activity',
            activityId,
            'UPDATE',
          );
        }
      }

      const existingActivities = await conn.query(
        `SELECT id, activity_type_id
         FROM day_activities
         WHERE day_entry_id = ?
           AND deleted_at IS NULL
         FOR UPDATE`,
        [entryId],
      );

      for (const activity of existingActivities) {
        if (!requestedActivityIds.has(activity.activity_type_id)) {
          await conn.query(
            `UPDATE day_activities
             SET deleted_at = UTC_TIMESTAMP(6),
                 updated_at = UTC_TIMESTAMP(6)
             WHERE id = ?
               AND day_entry_id = ?`,
            [
              activity.id,
              entryId,
            ],
          );

          await recordSyncChange(
            conn,
            userId,
            'day_activity',
            activity.id,
            'DELETE',
          );
        }
      }

      await conn.commit();

      return getEntry(userId, date);
    } catch (error) {
      await conn.rollback();
      throw error;
    }
  });
}

export async function deleteEntry(userId, dateValue) {
  const date = validateDate(dateValue);

  return withConnection(async (conn) => {
    await conn.beginTransaction();

    try {
      const entries = await conn.query(
        `SELECT id
         FROM day_entries
         WHERE user_id = ?
           AND entry_date = ?
           AND deleted_at IS NULL
         LIMIT 1
         FOR UPDATE`,
        [userId, date],
      );

      if (entries.length === 0) {
        const error = new Error('Entrée introuvable.');
        error.code = 'NOT_FOUND';
        throw error;
      }

      const entryId = entries[0].id;

      const pains = await conn.query(
        `SELECT id
         FROM day_pain_levels
         WHERE day_entry_id = ?
           AND deleted_at IS NULL
         FOR UPDATE`,
        [entryId],
      );

      for (const pain of pains) {
        await conn.query(
          `UPDATE day_pain_levels
           SET deleted_at = UTC_TIMESTAMP(6),
               updated_at = UTC_TIMESTAMP(6)
           WHERE id = ?`,
          [pain.id],
        );

        await recordSyncChange(
          conn,
          userId,
          'day_pain_level',
          pain.id,
          'DELETE',
        );
      }

      const activities = await conn.query(
        `SELECT id
         FROM day_activities
         WHERE day_entry_id = ?
           AND deleted_at IS NULL
         FOR UPDATE`,
        [entryId],
      );

      for (const activity of activities) {
        await conn.query(
          `UPDATE day_activities
           SET deleted_at = UTC_TIMESTAMP(6),
               updated_at = UTC_TIMESTAMP(6)
           WHERE id = ?`,
          [activity.id],
        );

        await recordSyncChange(
          conn,
          userId,
          'day_activity',
          activity.id,
          'DELETE',
        );
      }

      await conn.query(
        `UPDATE day_entries
         SET deleted_at = UTC_TIMESTAMP(6),
             updated_at = UTC_TIMESTAMP(6)
         WHERE id = ?
           AND user_id = ?`,
        [entryId, userId],
      );

      await recordSyncChange(
        conn,
        userId,
        'day_entry',
        entryId,
        'DELETE',
      );

      await conn.commit();

      return {
        ok: true,
        date,
      };
    } catch (error) {
      await conn.rollback();
      throw error;
    }
  });
}

import { withConnection } from './db.js';

export async function recordSyncChange(
  conn,
  userId,
  entity,
  entityId,
  operation,
) {
  const result = await conn.query(
    `INSERT INTO sync_changes
      (user_id, entity, entity_id, operation, changed_at)
     VALUES (?, ?, ?, ?, UTC_TIMESTAMP(6))`,
    [userId, entity, entityId, operation],
  );

  const cursor = Number(result.insertId);

  await conn.query(
    `UPDATE sync_cursor
     SET cursor_value = ?,
         updated_at = UTC_TIMESTAMP(6)
     WHERE id = 1`,
    [cursor],
  );

  return cursor;
}

function validateCursor(value) {
  const cursor = String(value ?? '0');

  if (!/^\d+$/.test(cursor)) {
    const error = new Error('Cursor invalide.');
    error.code = 'VALIDATION_ERROR';
    throw error;
  }

  const parsed = Number(cursor);

  if (!Number.isSafeInteger(parsed) || parsed < 0) {
    const error = new Error('Cursor invalide.');
    error.code = 'VALIDATION_ERROR';
    throw error;
  }

  return parsed;
}

async function loadEntityData(conn, userId, change) {
  switch (change.entity) {
    case 'day_entry': {
      const rows = await conn.query(
        `SELECT
           id,
           entry_date,
           created_at,
           updated_at,
           deleted_at
         FROM day_entries
         WHERE id = ?
           AND user_id = ?
         LIMIT 1`,
        [change.entityId, userId],
      );

      if (rows.length === 0) return null;

      return {
        id: rows[0].id,
        entryDate: (() => {
          const date = rows[0].entry_date;
          const year = date.getFullYear();
          const month = String(date.getMonth() + 1).padStart(2, '0');
          const day = String(date.getDate()).padStart(2, '0');
          return `${year}-${month}-${day}`;
        })(),
        createdAt: rows[0].created_at,
        updatedAt: rows[0].updated_at,
        deletedAt: rows[0].deleted_at,
      };
    }

    case 'pain_category': {
      const rows = await conn.query(
        `SELECT
           id,
           name,
           position,
           created_at,
           updated_at,
           deleted_at
         FROM pain_categories
         WHERE id = ?
           AND user_id = ?
         LIMIT 1`,
        [change.entityId, userId],
      );

      if (rows.length === 0) return null;

      return {
        id: rows[0].id,
        name: rows[0].name,
        position: rows[0].position,
        createdAt: rows[0].created_at,
        updatedAt: rows[0].updated_at,
        deletedAt: rows[0].deleted_at,
      };
    }

    case 'activity_type': {
      const rows = await conn.query(
        `SELECT
           id,
           name,
           position,
           created_at,
           updated_at,
           deleted_at
         FROM activity_types
         WHERE id = ?
           AND user_id = ?
         LIMIT 1`,
        [change.entityId, userId],
      );

      if (rows.length === 0) return null;

      return {
        id: rows[0].id,
        name: rows[0].name,
        position: rows[0].position,
        createdAt: rows[0].created_at,
        updatedAt: rows[0].updated_at,
        deletedAt: rows[0].deleted_at,
      };
    }

    case 'day_pain_level': {
      const rows = await conn.query(
        `SELECT
           p.id,
           p.day_entry_id,
           p.pain_category_id,
           p.level,
           p.created_at,
           p.updated_at,
           p.deleted_at,
           c.name AS category_name
         FROM day_pain_levels p
         INNER JOIN day_entries d
           ON d.id = p.day_entry_id
          AND d.user_id = ?
         INNER JOIN pain_categories c
           ON c.id = p.pain_category_id
          AND c.user_id = ?
         WHERE p.id = ?
         LIMIT 1`,
        [userId, userId, change.entityId],
      );

      if (rows.length === 0) return null;

      return {
        id: rows[0].id,
        dayEntryId: rows[0].day_entry_id,
        painCategoryId: rows[0].pain_category_id,
        categoryName: rows[0].category_name,
        level: rows[0].level,
        createdAt: rows[0].created_at,
        updatedAt: rows[0].updated_at,
        deletedAt: rows[0].deleted_at,
      };
    }

    case 'day_activity': {
      const rows = await conn.query(
        `SELECT
           a.id,
           a.day_entry_id,
           a.activity_type_id,
           a.created_at,
           a.updated_at,
           a.deleted_at,
           t.name AS activity_name
         FROM day_activities a
         INNER JOIN day_entries d
           ON d.id = a.day_entry_id
          AND d.user_id = ?
         INNER JOIN activity_types t
           ON t.id = a.activity_type_id
          AND t.user_id = ?
         WHERE a.id = ?
         LIMIT 1`,
        [userId, userId, change.entityId],
      );

      if (rows.length === 0) return null;

      return {
        id: rows[0].id,
        dayEntryId: rows[0].day_entry_id,
        activityTypeId: rows[0].activity_type_id,
        activityName: rows[0].activity_name,
        createdAt: rows[0].created_at,
        updatedAt: rows[0].updated_at,
        deletedAt: rows[0].deleted_at,
      };
    }

    default:
      return null;
  }
}

export async function getSyncChanges(userId, cursorValue) {
  const cursor = validateCursor(cursorValue);

  return withConnection(async (conn) => {
    const rows = await conn.query(
      `SELECT
         sync_cursor,
         entity,
         entity_id,
         operation,
         changed_at
       FROM sync_changes
       WHERE user_id = ?
         AND sync_cursor > ?
       ORDER BY sync_cursor ASC
       LIMIT 500`,
      [userId, cursor],
    );

    const changes = [];

    for (const row of rows) {
      const change = {
        cursor: Number(row.sync_cursor),
        entity: row.entity,
        entityId: row.entity_id,
        operation: row.operation,
        changedAt: row.changed_at,
        data: await loadEntityData(conn, userId, {
          entity: row.entity,
          entityId: row.entity_id,
          operation: row.operation,
        }),
      };

      changes.push(change);
    }

    const nextCursor = changes.length > 0
      ? changes[changes.length - 1].cursor
      : cursor;

    return {
      cursor,
      changes,
      nextCursor,
      hasMore: changes.length === 500,
    };
  });
}


function validatePushChanges(value) {
  if (!Array.isArray(value)) {
    const error = new Error('Le champ changes doit être un tableau.');
    error.code = 'VALIDATION_ERROR';
    throw error;
  }

  if (value.length > 500) {
    const error = new Error('Maximum 500 changements par requête.');
    error.code = 'VALIDATION_ERROR';
    throw error;
  }

  return value;
}

function pushError(message, code = 'VALIDATION_ERROR') {
  const error = new Error(message);
  error.code = code;
  return error;
}

async function pushCatalogChange(conn, userId, change) {
  const entity = change?.entity;
  const operation = change?.operation;
  const data = change?.data || {};

  const table =
    entity === 'pain_category'
      ? 'pain_categories'
      : entity === 'activity_type'
        ? 'activity_types'
        : null;

  if (!table) {
    throw pushError('Entité catalogue invalide.');
  }

  if (!['INSERT', 'UPDATE', 'DELETE'].includes(operation)) {
    throw pushError('Opération invalide.');
  }

  const id = String(data.id ?? '');

  if (!id) {
    throw pushError('Identifiant manquant.');
  }

  if (operation === 'INSERT') {
    const name = String(data.name ?? '').trim();

    if (!name || name.length > 120) {
      throw pushError(
        'Le nom doit contenir entre 1 et 120 caractères.',
      );
    }

    const position = Number.isInteger(data.position)
      ? data.position
      : 0;

    const existing = await conn.query(
      `SELECT id
       FROM ${table}
       WHERE id = ?
         AND user_id = ?
       LIMIT 1`,
      [id, userId],
    );

    if (existing.length === 0) {
      await conn.query(
        `INSERT INTO ${table}
          (id, user_id, name, position, created_at, updated_at, deleted_at)
         VALUES (?, ?, ?, ?, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6), NULL)`,
        [id, userId, name, position],
      );

      await recordSyncChange(
        conn,
        userId,
        entity,
        id,
        'INSERT',
      );
    }

    return;
  }

  const existing = await conn.query(
    `SELECT id
     FROM ${table}
     WHERE id = ?
       AND user_id = ?
     LIMIT 1
     FOR UPDATE`,
    [id, userId],
  );

  if (existing.length === 0) {
    throw pushError('Élément introuvable.', 'NOT_FOUND');
  }

  if (operation === 'UPDATE') {
    const name = String(data.name ?? '').trim();

    if (!name || name.length > 120) {
      throw pushError(
        'Le nom doit contenir entre 1 et 120 caractères.',
      );
    }

    const position = Number.isInteger(data.position)
      ? data.position
      : 0;

    await conn.query(
      `UPDATE ${table}
       SET name = ?,
           position = ?,
           deleted_at = NULL,
           updated_at = UTC_TIMESTAMP(6)
       WHERE id = ?
         AND user_id = ?`,
      [name, position, id, userId],
    );

    await recordSyncChange(
      conn,
      userId,
      entity,
      id,
      'UPDATE',
    );

    return;
  }

  await conn.query(
    `UPDATE ${table}
     SET deleted_at = UTC_TIMESTAMP(6),
         updated_at = UTC_TIMESTAMP(6)
     WHERE id = ?
       AND user_id = ?`,
    [id, userId],
  );

  await recordSyncChange(
    conn,
    userId,
    entity,
    id,
    'DELETE',
  );
}

async function pushDayEntryChange(conn, userId, change) {
  const operation = change?.operation;
  const data = change?.data || {};
  const id = String(data.id ?? '');

  if (!['INSERT', 'UPDATE', 'DELETE'].includes(operation)) {
    throw pushError('Opération invalide.');
  }

  if (!id) {
    throw pushError('Identifiant de l’entrée manquant.');
  }

  if (operation === 'DELETE') {
    const result = await conn.query(
      `UPDATE day_entries
       SET deleted_at = UTC_TIMESTAMP(6),
           updated_at = UTC_TIMESTAMP(6)
       WHERE id = ?
         AND user_id = ?
         AND deleted_at IS NULL`,
      [id, userId],
    );

    if (result.affectedRows === 0) {
      const existing = await conn.query(
        `SELECT id
         FROM day_entries
         WHERE id = ?
           AND user_id = ?
         LIMIT 1`,
        [id, userId],
      );

      if (existing.length === 0) {
        throw pushError('Entrée introuvable.', 'NOT_FOUND');
      }
    }

    await recordSyncChange(
      conn,
      userId,
      'day_entry',
      id,
      'DELETE',
    );

    return;
  }

  const entryDate = String(data.entryDate ?? '');

  if (!/^\d{4}-\d{2}-\d{2}$/.test(entryDate)) {
    throw pushError(
      'Date invalide. Format attendu : YYYY-MM-DD.',
    );
  }

  const existing = await conn.query(
    `SELECT id
     FROM day_entries
     WHERE id = ?
       AND user_id = ?
     LIMIT 1
     FOR UPDATE`,
    [id, userId],
  );

  if (operation === 'INSERT' && existing.length === 0) {
    const sameDate = await conn.query(
      `SELECT id
       FROM day_entries
       WHERE user_id = ?
         AND entry_date = ?
       LIMIT 1
       FOR UPDATE`,
      [userId, entryDate],
    );

    if (sameDate.length > 0 && sameDate[0].id !== id) {
      throw pushError(
        'Une entrée existe déjà pour cette date.',
        'CONFLICT',
      );
    }

    await conn.query(
      `INSERT INTO day_entries
        (id, user_id, entry_date, created_at, updated_at, deleted_at)
       VALUES (?, ?, ?, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6), NULL)`,
      [id, userId, entryDate],
    );

    await recordSyncChange(
      conn,
      userId,
      'day_entry',
      id,
      'INSERT',
    );

    return;
  }

  if (existing.length === 0) {
    throw pushError('Entrée introuvable.', 'NOT_FOUND');
  }

  await conn.query(
    `UPDATE day_entries
     SET entry_date = ?,
         deleted_at = NULL,
         updated_at = UTC_TIMESTAMP(6)
     WHERE id = ?
       AND user_id = ?`,
    [entryDate, id, userId],
  );

  await recordSyncChange(
    conn,
    userId,
    'day_entry',
    id,
    'UPDATE',
  );
}

async function pushDayPainLevelChange(conn, userId, change) {
  const operation = change?.operation;
  const data = change?.data || {};
  const id = String(data.id ?? '');

  if (!['INSERT', 'UPDATE', 'DELETE'].includes(operation)) {
    throw pushError('Opération invalide.');
  }

  if (!id) {
    throw pushError('Identifiant du niveau de douleur manquant.');
  }

  const existing = await conn.query(
    `SELECT p.id
     FROM day_pain_levels p
     INNER JOIN day_entries d
       ON d.id = p.day_entry_id
      AND d.user_id = ?
     WHERE p.id = ?
     LIMIT 1
     FOR UPDATE`,
    [userId, id],
  );

  if (operation === 'DELETE') {
    if (existing.length === 0) {
      throw pushError(
        'Niveau de douleur introuvable.',
        'NOT_FOUND',
      );
    }

    await conn.query(
      `UPDATE day_pain_levels
       SET deleted_at = UTC_TIMESTAMP(6),
           updated_at = UTC_TIMESTAMP(6)
       WHERE id = ?`,
      [id],
    );

    await recordSyncChange(
      conn,
      userId,
      'day_pain_level',
      id,
      'DELETE',
    );

    return;
  }

  const dayEntryId = String(data.dayEntryId ?? '');
  const painCategoryId = String(data.painCategoryId ?? '');
  const level = Number(data.level);

  if (!dayEntryId || !painCategoryId) {
    throw pushError('Références du niveau de douleur manquantes.');
  }

  if (!Number.isInteger(level) || level < 1 || level > 4) {
    throw pushError('Niveau de douleur invalide.');
  }

  const entry = await conn.query(
    `SELECT id
     FROM day_entries
     WHERE id = ?
       AND user_id = ?
       AND deleted_at IS NULL
     LIMIT 1`,
    [dayEntryId, userId],
  );

  if (entry.length === 0) {
    throw pushError('Entrée introuvable.', 'NOT_FOUND');
  }

  const category = await conn.query(
    `SELECT id
     FROM pain_categories
     WHERE id = ?
       AND user_id = ?
       AND deleted_at IS NULL
     LIMIT 1`,
    [painCategoryId, userId],
  );

  if (category.length === 0) {
    throw pushError(
      'Catégorie de douleur introuvable.',
      'NOT_FOUND',
    );
  }

  if (existing.length === 0) {
    await conn.query(
      `INSERT INTO day_pain_levels
        (id, day_entry_id, pain_category_id, level,
         created_at, updated_at, deleted_at)
       VALUES (?, ?, ?, ?, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6), NULL)`,
      [id, dayEntryId, painCategoryId, level],
    );

    await recordSyncChange(
      conn,
      userId,
      'day_pain_level',
      id,
      'INSERT',
    );

    return;
  }

  await conn.query(
    `UPDATE day_pain_levels
     SET day_entry_id = ?,
         pain_category_id = ?,
         level = ?,
         deleted_at = NULL,
         updated_at = UTC_TIMESTAMP(6)
     WHERE id = ?`,
    [dayEntryId, painCategoryId, level, id],
  );

  await recordSyncChange(
    conn,
    userId,
    'day_pain_level',
    id,
    'UPDATE',
  );
}

async function pushDayActivityChange(conn, userId, change) {
  const operation = change?.operation;
  const data = change?.data || {};
  const id = String(data.id ?? '');

  if (!['INSERT', 'UPDATE', 'DELETE'].includes(operation)) {
    throw pushError('Opération invalide.');
  }

  if (!id) {
    throw pushError('Identifiant de l’activité manquant.');
  }

  const existing = await conn.query(
    `SELECT a.id
     FROM day_activities a
     INNER JOIN day_entries d
       ON d.id = a.day_entry_id
      AND d.user_id = ?
     WHERE a.id = ?
     LIMIT 1
     FOR UPDATE`,
    [userId, id],
  );

  if (operation === 'DELETE') {
    if (existing.length === 0) {
      throw pushError(
        'Activité introuvable.',
        'NOT_FOUND',
      );
    }

    await conn.query(
      `UPDATE day_activities
       SET deleted_at = UTC_TIMESTAMP(6),
           updated_at = UTC_TIMESTAMP(6)
       WHERE id = ?`,
      [id],
    );

    await recordSyncChange(
      conn,
      userId,
      'day_activity',
      id,
      'DELETE',
    );

    return;
  }

  const dayEntryId = String(data.dayEntryId ?? '');
  const activityTypeId = String(data.activityTypeId ?? '');

  if (!dayEntryId || !activityTypeId) {
    throw pushError('Références de l’activité manquantes.');
  }

  const entry = await conn.query(
    `SELECT id
     FROM day_entries
     WHERE id = ?
       AND user_id = ?
       AND deleted_at IS NULL
     LIMIT 1`,
    [dayEntryId, userId],
  );

  if (entry.length === 0) {
    throw pushError('Entrée introuvable.', 'NOT_FOUND');
  }

  const activityType = await conn.query(
    `SELECT id
     FROM activity_types
     WHERE id = ?
       AND user_id = ?
       AND deleted_at IS NULL
     LIMIT 1`,
    [activityTypeId, userId],
  );

  if (activityType.length === 0) {
    throw pushError(
      'Type d’activité introuvable.',
      'NOT_FOUND',
    );
  }

  if (existing.length === 0) {
    await conn.query(
      `INSERT INTO day_activities
        (id, day_entry_id, activity_type_id,
         created_at, updated_at, deleted_at)
       VALUES (?, ?, ?, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6), NULL)`,
      [id, dayEntryId, activityTypeId],
    );

    await recordSyncChange(
      conn,
      userId,
      'day_activity',
      id,
      'INSERT',
    );

    return;
  }

  await conn.query(
    `UPDATE day_activities
     SET day_entry_id = ?,
         activity_type_id = ?,
         deleted_at = NULL,
         updated_at = UTC_TIMESTAMP(6)
     WHERE id = ?`,
    [dayEntryId, activityTypeId, id],
  );

  await recordSyncChange(
    conn,
    userId,
    'day_activity',
    id,
    'UPDATE',
  );
}

export async function pushSyncChanges(userId, changesInput) {
  const changes = validatePushChanges(changesInput);

  return withConnection(async (conn) => {
    await conn.beginTransaction();

    try {
      let applied = 0;
      let lastCursor = null;

      for (const change of changes) {
        if (!change || typeof change !== 'object') {
          throw pushError('Changement invalide.');
        }

        switch (change.entity) {
          case 'pain_category':
          case 'activity_type':
            await pushCatalogChange(conn, userId, change);
            break;

          case 'day_entry':
            await pushDayEntryChange(conn, userId, change);
            break;

          case 'day_pain_level':
            await pushDayPainLevelChange(conn, userId, change);
            break;

          case 'day_activity':
            await pushDayActivityChange(conn, userId, change);
            break;

          default:
            throw pushError(
              `Entité non supportée par le push : ${change.entity ?? ''}`,
            );
        }

        applied += 1;

        const cursorRows = await conn.query(
          `SELECT cursor_value
           FROM sync_cursor
           WHERE id = 1
           LIMIT 1`,
        );

        if (cursorRows.length > 0) {
          lastCursor = Number(cursorRows[0].cursor_value);
        }
      }

      await conn.commit();

      return {
        applied,
        cursor: lastCursor ?? 0,
      };
    } catch (error) {
      await conn.rollback();
      throw error;
    }
  });
}


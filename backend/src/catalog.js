import { v7 as uuidv7 } from 'uuid';

import { withConnection } from './db.js';
import { recordSyncChange } from './sync.js';

function cleanName(value) {
  const name = String(value ?? '').trim();

  if (!name || name.length > 120) {
    const error = new Error(
      'Le nom doit contenir entre 1 et 120 caractères.',
    );
    error.code = 'VALIDATION_ERROR';
    throw error;
  }

  return name;
}

function mapItem(row) {
  return {
    id: row.id,
    name: row.name,
    position: row.position,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at,
  };
}

const TABLES = {
  pain: 'pain_categories',
  activity: 'activity_types',
};

function tableFor(type) {
  const table = TABLES[type];

  if (!table) {
    const error = new Error('Type de catalogue invalide.');
    error.code = 'VALIDATION_ERROR';
    throw error;
  }

  return table;
}

export async function listCatalog(type, userId) {
  const table = tableFor(type);

  return withConnection(async (conn) => {
    const rows = await conn.query(
      `SELECT
         id,
         name,
         position,
         created_at,
         updated_at,
         deleted_at
       FROM ${table}
       WHERE user_id = ?
         AND deleted_at IS NULL
       ORDER BY position ASC, name ASC`,
      [userId],
    );

    return rows.map(mapItem);
  });
}

export async function createCatalogItem(type, userId, input) {
  const table = tableFor(type);
  const name = cleanName(input?.name);

  return withConnection(async (conn) => {
    await conn.beginTransaction();

    try {
      const existing = await conn.query(
        `SELECT id
         FROM ${table}
         WHERE user_id = ?
           AND name = ?
           AND deleted_at IS NULL
         LIMIT 1`,
        [userId, name],
      );

      if (existing.length > 0) {
        const error = new Error('Cet élément existe déjà.');
        error.code = 'CONFLICT';
        throw error;
      }

      const position = Number.isInteger(input?.position)
        ? input.position
        : 0;

      const id = uuidv7();
      const now = new Date();

      await conn.query(
        `INSERT INTO ${table}
          (id, user_id, name, position, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?)`,
        [
          id,
          userId,
          name,
          position,
          now,
          now,
        ],
      );

      await recordSyncChange(
        conn,
        userId,
        type === 'pain' ? 'pain_category' : 'activity_type',
        id,
        'INSERT',
      );

      const rows = await conn.query(
        `SELECT
           id,
           name,
           position,
           created_at,
           updated_at,
           deleted_at
         FROM ${table}
         WHERE id = ?
           AND user_id = ?
         LIMIT 1`,
        [id, userId],
      );

      await conn.commit();

      return mapItem(rows[0]);
    } catch (error) {
      await conn.rollback();
      throw error;
    }
  });
}

export async function updateCatalogItem(
  type,
  userId,
  itemId,
  input,
) {
  const table = tableFor(type);
  const name = cleanName(input?.name);

  return withConnection(async (conn) => {
    await conn.beginTransaction();

    try {
      const rows = await conn.query(
        `SELECT id
         FROM ${table}
         WHERE id = ?
           AND user_id = ?
           AND deleted_at IS NULL
         LIMIT 1
         FOR UPDATE`,
        [itemId, userId],
      );

      if (rows.length === 0) {
        const error = new Error('Élément introuvable.');
        error.code = 'NOT_FOUND';
        throw error;
      }

      const duplicate = await conn.query(
        `SELECT id
         FROM ${table}
         WHERE user_id = ?
           AND name = ?
           AND id <> ?
           AND deleted_at IS NULL
         LIMIT 1`,
        [userId, name, itemId],
      );

      if (duplicate.length > 0) {
        const error = new Error('Cet élément existe déjà.');
        error.code = 'CONFLICT';
        throw error;
      }

      const position = Number.isInteger(input?.position)
        ? input.position
        : 0;

      await conn.query(
        `UPDATE ${table}
         SET name = ?,
             position = ?,
             updated_at = UTC_TIMESTAMP(6)
         WHERE id = ?
           AND user_id = ?`,
        [
          name,
          position,
          itemId,
          userId,
        ],
      );

      await recordSyncChange(
        conn,
        userId,
        type === 'pain' ? 'pain_category' : 'activity_type',
        itemId,
        'UPDATE',
      );

      const result = await conn.query(
        `SELECT
           id,
           name,
           position,
           created_at,
           updated_at,
           deleted_at
         FROM ${table}
         WHERE id = ?
           AND user_id = ?
         LIMIT 1`,
        [itemId, userId],
      );

      await conn.commit();

      return mapItem(result[0]);
    } catch (error) {
      await conn.rollback();
      throw error;
    }
  });
}

export async function deleteCatalogItem(
  type,
  userId,
  itemId,
) {
  const table = tableFor(type);

  return withConnection(async (conn) => {
    await conn.beginTransaction();

    try {
      const result = await conn.query(
        `UPDATE ${table}
         SET deleted_at = UTC_TIMESTAMP(6),
             updated_at = UTC_TIMESTAMP(6)
         WHERE id = ?
           AND user_id = ?
           AND deleted_at IS NULL`,
        [
          itemId,
          userId,
        ],
      );

      if (result.affectedRows === 0) {
        const error = new Error('Élément introuvable.');
        error.code = 'NOT_FOUND';
        throw error;
      }

      await recordSyncChange(
        conn,
        userId,
        type === 'pain' ? 'pain_category' : 'activity_type',
        itemId,
        'DELETE',
      );

      await conn.commit();

      return {
        ok: true,
        id: itemId,
      };
    } catch (error) {
      await conn.rollback();
      throw error;
    }
  });
}


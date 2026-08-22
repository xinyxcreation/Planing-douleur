import 'dotenv/config';
import Fastify from 'fastify';
import cors from '@fastify/cors';
import { v7 as uuidv7 } from 'uuid';
import { withConnection } from './db.js';
import {
  registerUser,
  loginUser,
  createSession,
  getUserFromSessionToken,
  revokeSession,
} from './auth.js';


async function authenticate(request, reply) {
  const header = request.headers.authorization || '';
  const match = header.match(/^Bearer\\s+(.+)$/i);

  if (!match) {
    return reply.code(401).send({
      error: 'AUTHENTICATION_ERROR',
      message: 'Authentification requise.'
    });
  }

  const session = await getUserFromSessionToken(match[1]);

  if (!session) {
    return reply.code(401).send({
      error: 'AUTHENTICATION_ERROR',
      message: 'Session invalide ou expirée.'
    });
  }

  request.user = session.user;
  request.session = session;
}

const app = Fastify({ logger: true });

await app.register(cors, {
  origin: process.env.CORS_ORIGIN || true,
  credentials: true
});

const TABLE = {
  pain_category: 'pain_categories',
  activity_type: 'activity_types'
};

function now() {
  return 'UTC_TIMESTAMP(6)';
}

function cleanName(value) {
  const name = String(value ?? '').trim();
  if (!name || name.length > 120) {
    const e = new Error('Le nom doit contenir entre 1 et 120 caractères.');
    e.code = 'VALIDATION_ERROR';
    throw e;
  }
  return name;
}

async function recordChange(conn, userId, entity, entityId, operation) {
  const result = await conn.query(
    `INSERT INTO sync_changes
      (user_id, entity, entity_id, operation, changed_at)
     VALUES (?, ?, ?, ?, UTC_TIMESTAMP(6))`,
    [userId, entity, entityId, operation]
  );
  const cursor = Number(result.insertId);
  await conn.query(
    `UPDATE sync_cursor SET cursor_value=?, updated_at=UTC_TIMESTAMP(6) WHERE id=1`,
    [cursor]
  );
  return cursor;
}


/* ============================================================
 * AUTHENTIFICATION
 * ============================================================ */

app.post('/auth/register', async (request, reply) => {
  try {
    const body = request.body || {};

    const user = await registerUser({
      email: body.email,
      password: body.password,
      displayName: body.displayName,
    });

    const session = await createSession(user.id);

    return reply.code(201).send({
      user,
      session: {
        id: session.id,
        token: session.token,
        expiresAt: session.expiresAt,
      },
    });
  } catch (error) {
    request.log.error(error);

    const status =
      error.code === 'CONFLICT' ? 409 :
      error.code === 'VALIDATION_ERROR' ? 400 :
      500;

    return reply.code(status).send({
      error: error.code || 'INTERNAL_ERROR',
      message: error.message || 'Erreur serveur.',
    });
  }
});


app.post('/auth/login', async (request, reply) => {
  try {
    const body = request.body || {};

    const user = await loginUser({
      email: body.email,
      password: body.password,
    });

    const session = await createSession(user.id);

    return reply.send({
      user,
      session: {
        id: session.id,
        token: session.token,
        expiresAt: session.expiresAt,
      },
    });
  } catch (error) {
    request.log.error(error);

    const status =
      error.code === 'AUTHENTICATION_ERROR' ? 401 :
      error.code === 'VALIDATION_ERROR' ? 400 :
      500;

    return reply.code(status).send({
      error: error.code || 'INTERNAL_ERROR',
      message: error.message || 'Erreur serveur.',
    });
  }
});


app.get('/auth/me', async (request, reply) => {
  const authenticated = await authenticate(request, reply);

  if (authenticated) {
    return authenticated;
  }

  return reply.send({
    user: request.user,
    session: {
      id: request.session.sessionId,
      expiresAt: request.session.expiresAt,
    },
  });
});


app.post('/auth/logout', async (request, reply) => {
  const header = request.headers.authorization || '';
  const match = header.match(/^Bearer\s+(.+)$/i);

  if (match) {
    try {
      await revokeSession(match[1]);
    } catch (error) {
      request.log.error(error);
    }
  }

  return reply.send({
    ok: true,
  });
});


app.get('/health', async () => ({ ok: true }));

app.get('/catalog/pain', { preHandler: authenticate }, async (request) => {
  return listCatalog('pain_category', request.user.id);
});

app.get('/catalog/activity', { preHandler: authenticate }, async (request) => {
  return listCatalog('activity_type', request.user.id);
});

async function listCatalog(entity, userId) {
  const table = TABLE[entity];
  return withConnection(async conn => {
    const rows = await conn.query(
      `SELECT id,name,position,created_at,updated_at,deleted_at
       FROM ${table}
       WHERE user_id=? AND deleted_at IS NULL
       ORDER BY position ASC,name ASC`,
      [userId]
    );
    return rows.map(r => ({
      id: r.id,
      name: r.name,
      position: r.position,
      createdAt: r.created_at,
      updatedAt: r.updated_at,
      deletedAt: r.deleted_at
    }));
  });
}

app.post('/catalog/:type', { preHandler: authenticate }, async (request, reply) => {
  const entity = request.params.type === 'pain' ? 'pain_category' : 'activity_type';
  if (!TABLE[entity]) return reply.code(400).send({error:'VALIDATION_ERROR',message:'Type invalide.'});

  const name = cleanName(request.body?.name);
  const position = Number.isInteger(request.body?.position) ? request.body.position : 0;
  const id = uuidv7();

  try {
    return await withConnection(async conn => {
      await conn.beginTransaction();
      try {
        const duplicate = await conn.query(
          `SELECT id FROM ${TABLE[entity]}
           WHERE user_id=? AND name=? AND deleted_at IS NULL LIMIT 1 FOR UPDATE`,
          [request.user.id, name]
        );
        if (duplicate.length) {
          const e = new Error('Cet élément existe déjà.');
          e.code = 'CONFLICT';
          throw e;
        }

        await conn.query(
          `INSERT INTO ${TABLE[entity]}
           (id,user_id,name,position,created_at,updated_at,deleted_at)
           VALUES (?,?,?,?,UTC_TIMESTAMP(6),UTC_TIMESTAMP(6),NULL)`,
          [id, request.user.id, name, position]
        );
        await recordChange(conn, request.user.id, entity, id, 'INSERT');
        await conn.commit();
        return { id, name, position, deletedAt: null };
      } catch(e) {
        await conn.rollback();
        throw e;
      }
    });
  } catch(e) {
    return reply.code(e.code === 'CONFLICT' ? 409 : 500).send({
      error: e.code || 'SERVER_ERROR',
      message: e.message
    });
  }
});

app.get('/sync', { preHandler: authenticate }, async (request) => {
  const cursor = Number(request.query?.cursor || 0);
  if (!Number.isSafeInteger(cursor) || cursor < 0) {
    throw new Error('Cursor invalide.');
  }

  return withConnection(async conn => {
    const rows = await conn.query(
      `SELECT sync_cursor,entity,entity_id,operation,changed_at
       FROM sync_changes
       WHERE user_id=? AND sync_cursor>?
       ORDER BY sync_cursor ASC LIMIT 500`,
      [request.user.id, cursor]
    );

    const changes = [];
    for (const r of rows) {
      let data = null;

      if (r.entity === 'pain_category' || r.entity === 'activity_type') {
        const table = TABLE[r.entity];
        const x = await conn.query(
          `SELECT id,name,position,created_at,updated_at,deleted_at
           FROM ${table} WHERE id=? AND user_id=? LIMIT 1`,
          [r.entity_id, request.user.id]
        );
        if (x.length) {
          data = {
            id:x[0].id,name:x[0].name,position:x[0].position,
            createdAt:x[0].created_at,updatedAt:x[0].updated_at,deletedAt:x[0].deleted_at
          };
        }
      } else if (r.entity === 'day_entry') {
        const x = await conn.query(
          `SELECT id,entry_date,created_at,updated_at,deleted_at
           FROM day_entries WHERE id=? AND user_id=? LIMIT 1`,
          [r.entity_id, request.user.id]
        );
        if (x.length) data = {
          id:x[0].id, entryDate:x[0].entry_date,
          createdAt:x[0].created_at,updatedAt:x[0].updated_at,deletedAt:x[0].deleted_at
        };
      } else if (r.entity === 'day_pain_level') {
        const x = await conn.query(
          `SELECT p.id,p.day_entry_id,p.pain_category_id,p.level,
                  p.created_at,p.updated_at,p.deleted_at
           FROM day_pain_levels p
           JOIN day_entries d ON d.id=p.day_entry_id AND d.user_id=?
           WHERE p.id=? LIMIT 1`,
          [request.user.id, r.entity_id]
        );
        if (x.length) data = {
          id:x[0].id,dayEntryId:x[0].day_entry_id,
          painCategoryId:x[0].pain_category_id,level:x[0].level,
          createdAt:x[0].created_at,updatedAt:x[0].updated_at,deletedAt:x[0].deleted_at
        };
      } else if (r.entity === 'day_activity') {
        const x = await conn.query(
          `SELECT a.id,a.day_entry_id,a.activity_type_id,
                  a.created_at,a.updated_at,a.deleted_at
           FROM day_activities a
           JOIN day_entries d ON d.id=a.day_entry_id AND d.user_id=?
           WHERE a.id=? LIMIT 1`,
          [request.user.id, r.entity_id]
        );
        if (x.length) data = {
          id:x[0].id,dayEntryId:x[0].day_entry_id,
          activityTypeId:x[0].activity_type_id,
          createdAt:x[0].created_at,updatedAt:x[0].updated_at,deletedAt:x[0].deleted_at
        };
      }

      changes.push({
        cursor:Number(r.sync_cursor),
        entity:r.entity,
        entityId:r.entity_id,
        operation:r.operation,
        changedAt:r.changed_at,
        data
      });
    }

    const nextCursor = changes.length ? changes.at(-1).cursor : cursor;
    return { cursor, changes, nextCursor, hasMore: changes.length === 500 };
  });
});

async function pushOne(conn, userId, change) {
  const entity = change?.entity;
  const operation = change?.operation;
  const data = change?.data || {};
  const id = String(data.id || '');

  if (!['pain_category','activity_type','day_entry','day_pain_level','day_activity'].includes(entity))
    throw Object.assign(new Error('Entité non supportée.'), {code:'VALIDATION_ERROR'});
  if (!['INSERT','UPDATE','DELETE'].includes(operation))
    throw Object.assign(new Error('Opération invalide.'), {code:'VALIDATION_ERROR'});
  if (!id) throw Object.assign(new Error('Identifiant manquant.'), {code:'VALIDATION_ERROR'});

  if (entity === 'pain_category' || entity === 'activity_type') {
    const table = TABLE[entity];
    if (operation === 'DELETE') {
      const r = await conn.query(
        `UPDATE ${table} SET deleted_at=UTC_TIMESTAMP(6),updated_at=UTC_TIMESTAMP(6)
         WHERE id=? AND user_id=? AND deleted_at IS NULL`,
        [id,userId]
      );
      if (!r.affectedRows) throw Object.assign(new Error('Élément introuvable.'),{code:'NOT_FOUND'});
    } else {
      const name = cleanName(data.name);
      const position = Number.isInteger(data.position) ? data.position : 0;
      const existing = await conn.query(
        `SELECT id FROM ${table} WHERE id=? AND user_id=? LIMIT 1 FOR UPDATE`,
        [id,userId]
      );
      const duplicate = await conn.query(
        `SELECT id, deleted_at
         FROM ${table}
         WHERE user_id=? AND name=? AND id<>?
         LIMIT 1
         FOR UPDATE`,
        [userId,name,id]
      );

      if (duplicate.length) {
        const duplicateId = duplicate[0].id;

        // Même élément déjà présent sous un autre UUID :
        // on considère le changement comme déjà appliqué.
        //
        // IMPORTANT :
        // on ne crée surtout pas un deuxième catalogue avec le même nom.
        // Le client devra ensuite récupérer le catalogue serveur.
        return;
      }

      if (!existing.length) {
        await conn.query(
          `INSERT INTO ${table}
           (id,user_id,name,position,created_at,updated_at,deleted_at)
           VALUES (?,?,?,?,UTC_TIMESTAMP(6),UTC_TIMESTAMP(6),NULL)`,
          [id,userId,name,position]
        );
      } else {
        await conn.query(
          `UPDATE ${table} SET name=?,position=?,deleted_at=NULL,updated_at=UTC_TIMESTAMP(6)
           WHERE id=? AND user_id=?`,
          [name,position,id,userId]
        );
      }
    }
    await recordChange(conn,userId,entity,id,operation);
    return;
  }

  if (entity === 'day_entry') {
    if (operation === 'DELETE') {
      const r = await conn.query(
        `UPDATE day_entries SET deleted_at=UTC_TIMESTAMP(6),updated_at=UTC_TIMESTAMP(6)
         WHERE id=? AND user_id=? AND deleted_at IS NULL`,
        [id,userId]
      );
      if (!r.affectedRows) {
        const e=await conn.query(`SELECT id FROM day_entries WHERE id=? AND user_id=?`,[id,userId]);
        if (!e.length) throw Object.assign(new Error('Entrée introuvable.'),{code:'NOT_FOUND'});
      }
    } else {
      const entryDate=String(data.entryDate||'');
      if (!/^\d{4}-\d{2}-\d{2}$/.test(entryDate))
        throw Object.assign(new Error('Date invalide.'),{code:'VALIDATION_ERROR'});

      const existing=await conn.query(
        `SELECT id FROM day_entries WHERE id=? AND user_id=? LIMIT 1 FOR UPDATE`,
        [id,userId]
      );
      const sameDate=await conn.query(
        `SELECT id FROM day_entries WHERE user_id=? AND entry_date=? AND id<>? LIMIT 1 FOR UPDATE`,
        [userId,entryDate,id]
      );
      if (sameDate.length) {
        // Une seule entrée par date.
        // Le changement est déjà représenté côté serveur.
        // On ne crée pas de doublon.
        return;
      }
      if (!existing.length) {
        await conn.query(
          `INSERT INTO day_entries
           (id,user_id,entry_date,created_at,updated_at,deleted_at)
           VALUES (?,?,?,UTC_TIMESTAMP(6),UTC_TIMESTAMP(6),NULL)`,
          [id,userId,entryDate]
        );
      } else {
        await conn.query(
          `UPDATE day_entries SET entry_date=?,deleted_at=NULL,updated_at=UTC_TIMESTAMP(6)
           WHERE id=? AND user_id=?`,
          [entryDate,id,userId]
        );
      }
    }
    await recordChange(conn,userId,entity,id,operation);
    return;
  }

  if (entity === 'day_pain_level') {
    const dayEntryId=String(data.dayEntryId||'');
    const painCategoryId=String(data.painCategoryId||'');
    const level=Number(data.level);

    if (!dayEntryId || !painCategoryId || !Number.isInteger(level) || level<0 || level>3)
      throw Object.assign(new Error('Niveau ou références invalides.'),{code:'VALIDATION_ERROR'});

    const entry=await conn.query(
      `SELECT id FROM day_entries WHERE id=? AND user_id=? AND deleted_at IS NULL`,
      [dayEntryId,userId]
    );
    const cat=await conn.query(
      `SELECT id FROM pain_categories WHERE id=? AND user_id=? AND deleted_at IS NULL`,
      [painCategoryId,userId]
    );
    if (!entry.length) throw Object.assign(new Error('Entrée introuvable.'),{code:'NOT_FOUND'});
    if (!cat.length) throw Object.assign(new Error('Catégorie introuvable.'),{code:'NOT_FOUND'});

    if (operation === 'DELETE') {
      await conn.query(
        `UPDATE day_pain_levels SET deleted_at=UTC_TIMESTAMP(6),updated_at=UTC_TIMESTAMP(6) WHERE id=?`,
        [id]
      );
    } else {
      const existing=await conn.query(
        `SELECT id FROM day_pain_levels WHERE id=? LIMIT 1 FOR UPDATE`,
        [id]
      );
      if (!existing.length) {
        await conn.query(
          `INSERT INTO day_pain_levels
           (id,day_entry_id,pain_category_id,level,created_at,updated_at,deleted_at)
           VALUES (?,?,?,?,UTC_TIMESTAMP(6),UTC_TIMESTAMP(6),NULL)`,
          [id,dayEntryId,painCategoryId,level]
        );
      } else {
        await conn.query(
          `UPDATE day_pain_levels
           SET day_entry_id=?,pain_category_id=?,level=?,deleted_at=NULL,updated_at=UTC_TIMESTAMP(6)
           WHERE id=?`,
          [dayEntryId,painCategoryId,level,id]
        );
      }
    }
    await recordChange(conn,userId,entity,id,operation);
    return;
  }

  if (entity === 'day_activity') {
    const dayEntryId=String(data.dayEntryId||'');
    const activityTypeId=String(data.activityTypeId||'');
    if (!dayEntryId || !activityTypeId)
      throw Object.assign(new Error('Références activité invalides.'),{code:'VALIDATION_ERROR'});

    const entry=await conn.query(`SELECT id FROM day_entries WHERE id=? AND user_id=? AND deleted_at IS NULL`,[dayEntryId,userId]);
    const type=await conn.query(`SELECT id FROM activity_types WHERE id=? AND user_id=? AND deleted_at IS NULL`,[activityTypeId,userId]);
    if (!entry.length) throw Object.assign(new Error('Entrée introuvable.'),{code:'NOT_FOUND'});
    if (!type.length) throw Object.assign(new Error('Activité introuvable.'),{code:'NOT_FOUND'});

    if (operation === 'DELETE') {
      await conn.query(`UPDATE day_activities SET deleted_at=UTC_TIMESTAMP(6),updated_at=UTC_TIMESTAMP(6) WHERE id=?`,[id]);
    } else {
      const existing=await conn.query(`SELECT id FROM day_activities WHERE id=? LIMIT 1 FOR UPDATE`,[id]);
      if (!existing.length) {
        await conn.query(
          `INSERT INTO day_activities
           (id,day_entry_id,activity_type_id,created_at,updated_at,deleted_at)
           VALUES (?,?,?,UTC_TIMESTAMP(6),UTC_TIMESTAMP(6),NULL)`,
          [id,dayEntryId,activityTypeId]
        );
      } else {
        await conn.query(
          `UPDATE day_activities SET day_entry_id=?,activity_type_id=?,deleted_at=NULL,updated_at=UTC_TIMESTAMP(6) WHERE id=?`,
          [dayEntryId,activityTypeId,id]
        );
      }
    }
    await recordChange(conn,userId,entity,id,operation);
  }
}

app.post('/sync', { preHandler: authenticate }, async (request, reply) => {
  const changes = request.body?.changes;
  if (!Array.isArray(changes) || changes.length > 500)
    return reply.code(400).send({error:'VALIDATION_ERROR',message:'Maximum 500 changements.'});

  try {
    return await withConnection(async conn => {
      await conn.beginTransaction();
      try {
        let cursor = 0;

        for (const change of changes) {
          await pushOne(conn, request.user.id, change);

          const rows = await conn.query(
            `SELECT cursor_value
             FROM sync_cursor
             WHERE id=1`
          );

          if (rows.length) {
            cursor = Number(rows[0].cursor_value);
          }
        }

        await conn.commit();

        return {
          ok: true,
          applied: changes.length,
          cursor,
        };
      } catch(e) {
        await conn.rollback();
        throw e;
      }
    });
  } catch(e) {
    request.log.error(e);
    return reply.code(e.code === 'CONFLICT' ? 409 : 500).send({
      error:e.code || 'SERVER_ERROR',
      message:e.message
    });
  }
});

app.post('/import', { preHandler: authenticate }, async (request, reply) => {
  const body=request.body || {};
  const entries=Array.isArray(body.entries)?body.entries:[];
  const categories=Array.isArray(body.painCategories)?body.painCategories:[];
  const activities=Array.isArray(body.activityTypes)?body.activityTypes:[];

  try {
    return await withConnection(async conn => {
      await conn.beginTransaction();
      try {
        for (const c of categories) {
          const id=String(c.id||uuidv7());
          const name=cleanName(c.name);
          await conn.query(
            `INSERT INTO pain_categories
             (id,user_id,name,position,created_at,updated_at,deleted_at)
             VALUES (?,?,?,?,UTC_TIMESTAMP(6),UTC_TIMESTAMP(6),NULL)
             ON DUPLICATE KEY UPDATE name=VALUES(name),position=VALUES(position),deleted_at=NULL,updated_at=UTC_TIMESTAMP(6)`,
            [id,request.user.id,name,Number.isInteger(c.position)?c.position:0]
          );
        }
        for (const a of activities) {
          const id=String(a.id||uuidv7());
          const name=cleanName(a.name);
          await conn.query(
            `INSERT INTO activity_types
             (id,user_id,name,position,created_at,updated_at,deleted_at)
             VALUES (?,?,?,?,UTC_TIMESTAMP(6),UTC_TIMESTAMP(6),NULL)
             ON DUPLICATE KEY UPDATE name=VALUES(name),position=VALUES(position),deleted_at=NULL,updated_at=UTC_TIMESTAMP(6)`,
            [id,request.user.id,name,Number.isInteger(a.position)?a.position:0]
          );
        }
        for (const e of entries) {
          const id=String(e.id||uuidv7());
          const date=String(e.entryDate||'');
          if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) continue;
          await conn.query(
            `INSERT INTO day_entries
             (id,user_id,entry_date,created_at,updated_at,deleted_at)
             VALUES (?,?,?,UTC_TIMESTAMP(6),UTC_TIMESTAMP(6),NULL)
             ON DUPLICATE KEY UPDATE entry_date=VALUES(entry_date),deleted_at=NULL,updated_at=UTC_TIMESTAMP(6)`,
            [id,request.user.id,date]
          );
          for (const p of (e.painLevels||[])) {
            const level=Number(p.level);
            if (!Number.isInteger(level)||level<0||level>3) continue;
            await conn.query(
              `INSERT INTO day_pain_levels
               (id,day_entry_id,pain_category_id,level,created_at,updated_at,deleted_at)
               VALUES (?,?,?,?,UTC_TIMESTAMP(6),UTC_TIMESTAMP(6),NULL)
               ON DUPLICATE KEY UPDATE day_entry_id=VALUES(day_entry_id),pain_category_id=VALUES(pain_category_id),level=VALUES(level),deleted_at=NULL,updated_at=UTC_TIMESTAMP(6)`,
              [String(p.id||uuidv7()),id,String(p.painCategoryId),level]
            );
          }
          for (const a of (e.activities||[])) {
            await conn.query(
              `INSERT INTO day_activities
               (id,day_entry_id,activity_type_id,created_at,updated_at,deleted_at)
               VALUES (?,?,?,?,UTC_TIMESTAMP(6),NULL)
               ON DUPLICATE KEY UPDATE day_entry_id=VALUES(day_entry_id),activity_type_id=VALUES(activity_type_id),deleted_at=NULL,updated_at=UTC_TIMESTAMP(6)`,
              [String(a.id||uuidv7()),id,String(a.activityTypeId)]
            );
          }
        }
        await conn.commit();
        return {ok:true,entries:entries.length};
      } catch(e) {
        await conn.rollback(); throw e;
      }
    });
  } catch(e) {
    request.log.error(e);
    return reply.code(500).send({error:'IMPORT_ERROR',message:e.message});
  }
});

const port=Number(process.env.PORT||3080);
const host=process.env.HOST||'0.0.0.0';
await app.listen({port,host});

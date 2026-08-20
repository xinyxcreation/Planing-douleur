import Fastify from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';

import {
  registerUser,
  loginUser,
  createSession,
  getUserFromSessionToken,
  revokeSession,
} from './auth.js';

import {
  listCatalog,
  createCatalogItem,
  updateCatalogItem,
  deleteCatalogItem,
} from './catalog.js';

import { pool } from './db.js';
import {
  getSyncChanges,
  pushSyncChanges,
} from './sync.js';

import {
  getEntry,
  saveEntry,
  deleteEntry,
} from './entries.js';

function getBearerToken(request) {
  const header = request.headers.authorization;

  if (!header || !header.startsWith('Bearer ')) {
    return null;
  }

  return header.slice(7).trim();
}

async function requireAuth(request, reply) {
  const token = getBearerToken(request);

  if (!token) {
    return reply.code(401).send({
      error: 'AUTHENTICATION_ERROR',
      message: 'Authentification requise.',
    });
  }

  const session = await getUserFromSessionToken(token);

  if (!session) {
    return reply.code(401).send({
      error: 'AUTHENTICATION_ERROR',
      message: 'Session invalide ou expirée.',
    });
  }

  request.auth = {
    token,
    ...session,
  };
}

export async function buildApp() {
  const app = Fastify({
    logger: true,
  });

  await app.register(helmet);

  await app.register(cors, {
    origin: true,
  });

  app.get('/health', async () => {
    await pool.query('SELECT 1');

    return {
      ok: true,
      service: 'planning-douleur-api',
      version: '1.1.0',
      database: true,
      time: new Date().toISOString(),
    };
  });

  app.post('/auth/register', async (request, reply) => {
    try {
      const user = await registerUser(request.body || {});

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
      if (error.code === 'VALIDATION_ERROR') {
        return reply.code(400).send({
          error: error.code,
          message: error.message,
        });
      }

      if (error.code === 'CONFLICT') {
        return reply.code(409).send({
          error: error.code,
          message: error.message,
        });
      }

      request.log.error(error);
      return reply.code(500).send({
        error: 'INTERNAL_ERROR',
        message: 'Erreur interne.',
      });
    }
  });

  app.post('/auth/login', async (request, reply) => {
    try {
      const user = await loginUser(request.body || {});
      const session = await createSession(user.id);

      return {
        user,
        session: {
          id: session.id,
          token: session.token,
          expiresAt: session.expiresAt,
        },
      };
    } catch (error) {
      if (error.code === 'AUTHENTICATION_ERROR') {
        return reply.code(401).send({
          error: error.code,
          message: error.message,
        });
      }

      request.log.error(error);
      return reply.code(500).send({
        error: 'INTERNAL_ERROR',
        message: 'Erreur interne.',
      });
    }
  });

  async function catalogList(request, reply) {
    try {
      const items = await listCatalog(
        request.params.type,
        request.auth.user.id,
      );

      return { items };
    } catch (error) {
      if (error.code === 'VALIDATION_ERROR') {
        return reply.code(400).send({
          error: error.code,
          message: error.message,
        });
      }

      request.log.error(error);

      return reply.code(500).send({
        error: 'INTERNAL_ERROR',
        message: 'Erreur interne.',
      });
    }
  }

  async function catalogCreate(request, reply) {
    try {
      const item = await createCatalogItem(
        request.params.type,
        request.auth.user.id,
        request.body || {},
      );

      return reply.code(201).send({ item });
    } catch (error) {
      if (error.code === 'VALIDATION_ERROR') {
        return reply.code(400).send({
          error: error.code,
          message: error.message,
        });
      }

      if (error.code === 'CONFLICT') {
        return reply.code(409).send({
          error: error.code,
          message: error.message,
        });
      }

      request.log.error(error);

      return reply.code(500).send({
        error: 'INTERNAL_ERROR',
        message: 'Erreur interne.',
      });
    }
  }

  async function catalogUpdate(request, reply) {
    try {
      const item = await updateCatalogItem(
        request.params.type,
        request.auth.user.id,
        request.params.id,
        request.body || {},
      );

      return { item };
    } catch (error) {
      if (
        error.code === 'VALIDATION_ERROR' ||
        error.code === 'NOT_FOUND'
      ) {
        return reply.code(
          error.code === 'NOT_FOUND' ? 404 : 400,
        ).send({
          error: error.code,
          message: error.message,
        });
      }

      if (error.code === 'CONFLICT') {
        return reply.code(409).send({
          error: error.code,
          message: error.message,
        });
      }

      request.log.error(error);

      return reply.code(500).send({
        error: 'INTERNAL_ERROR',
        message: 'Erreur interne.',
      });
    }
  }

  async function catalogDelete(request, reply) {
    try {
      return await deleteCatalogItem(
        request.params.type,
        request.auth.user.id,
        request.params.id,
      );
    } catch (error) {
      if (error.code === 'NOT_FOUND') {
        return reply.code(404).send({
          error: error.code,
          message: error.message,
        });
      }

      request.log.error(error);

      return reply.code(500).send({
        error: 'INTERNAL_ERROR',
        message: 'Erreur interne.',
      });
    }
  }

  app.get('/catalog/:type', {
    preHandler: requireAuth,
  }, catalogList);

  app.post('/catalog/:type', {
    preHandler: requireAuth,
  }, catalogCreate);

  app.put('/catalog/:type/:id', {
    preHandler: requireAuth,
  }, catalogUpdate);

  app.delete('/catalog/:type/:id', {
    preHandler: requireAuth,
  }, catalogDelete);


  async function entryGet(request, reply) {
    try {
      const entry = await getEntry(
        request.auth.user.id,
        request.params.date,
      );

      if (!entry) {
        return reply.code(404).send({
          error: 'NOT_FOUND',
          message: 'Entrée introuvable.',
        });
      }

      return { entry };
    } catch (error) {
      if (error.code === 'VALIDATION_ERROR') {
        return reply.code(400).send({
          error: error.code,
          message: error.message,
        });
      }

      request.log.error(error);

      return reply.code(500).send({
        error: 'INTERNAL_ERROR',
        message: 'Erreur interne.',
      });
    }
  }

  async function entrySave(request, reply) {
    try {
      const entry = await saveEntry(
        request.auth.user.id,
        request.params.date,
        request.body || {},
      );

      return { entry };
    } catch (error) {
      if (
        error.code === 'VALIDATION_ERROR' ||
        error.code === 'NOT_FOUND'
      ) {
        return reply.code(
          error.code === 'NOT_FOUND' ? 404 : 400,
        ).send({
          error: error.code,
          message: error.message,
        });
      }

      request.log.error(error);

      return reply.code(500).send({
        error: 'INTERNAL_ERROR',
        message: 'Erreur interne.',
      });
    }
  }

  async function entryDelete(request, reply) {
    try {
      return await deleteEntry(
        request.auth.user.id,
        request.params.date,
      );
    } catch (error) {
      if (
        error.code === 'VALIDATION_ERROR' ||
        error.code === 'NOT_FOUND'
      ) {
        return reply.code(
          error.code === 'NOT_FOUND' ? 404 : 400,
        ).send({
          error: error.code,
          message: error.message,
        });
      }

      request.log.error(error);

      return reply.code(500).send({
        error: 'INTERNAL_ERROR',
        message: 'Erreur interne.',
      });
    }
  }

  app.get('/entries/:date', {
    preHandler: requireAuth,
  }, entryGet);

  app.put('/entries/:date', {
    preHandler: requireAuth,
  }, entrySave);

  app.delete('/entries/:date', {
    preHandler: requireAuth,
  }, entryDelete);

  app.post('/auth/logout', {
    preHandler: requireAuth,
  }, async (request) => {
    await revokeSession(request.auth.token);

    return {
      ok: true,
    };
  });

  app.get('/auth/me', {
    preHandler: requireAuth,
  }, async (request) => {
    return {
      user: request.auth.user,
      session: {
        id: request.auth.sessionId,
        expiresAt: request.auth.expiresAt,
      },
    };
  });


  app.post('/sync', {
    preHandler: requireAuth,
  }, async (request, reply) => {
    try {
      const result = await pushSyncChanges(
        request.auth.user.id,
        request.body?.changes ?? [],
      );

      return result;
    } catch (error) {
      if (
        error.code === 'VALIDATION_ERROR' ||
        error.code === 'NOT_FOUND'
      ) {
        return reply.code(
          error.code === 'NOT_FOUND' ? 404 : 400,
        ).send({
          error: error.code,
          message: error.message,
        });
      }

      request.log.error(error);

      return reply.code(500).send({
        error: 'INTERNAL_ERROR',
        message: 'Erreur interne.',
      });
    }
  });

  app.get('/sync', {
    preHandler: requireAuth,
  }, async (request, reply) => {
    try {
      const result = await getSyncChanges(
        request.auth.user.id,
        request.query?.cursor ?? '0',
      );

      return result;
    } catch (error) {
      if (error.code === 'VALIDATION_ERROR') {
        return reply.code(400).send({
          error: error.code,
          message: error.message,
        });
      }

      request.log.error(error);

      return reply.code(500).send({
        error: 'INTERNAL_ERROR',
        message: 'Erreur interne.',
      });
    }
  });

  app.addHook('onClose', async () => {
    await pool.end();
  });

  return app;
}

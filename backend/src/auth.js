import { randomBytes } from 'node:crypto';
import { v7 as uuidv7 } from 'uuid';

import {
  hashPassword,
  verifyPassword,
  hashSessionToken,
} from './security.js';

import { config } from './config.js';
import { withConnection } from './db.js';

function normalizeEmail(email) {
  return String(email || '').trim().toLowerCase();
}

function publicUser(user) {
  return {
    id: user.id,
    email: user.email,
    displayName: user.display_name,
    createdAt: user.created_at,
    updatedAt: user.updated_at,
  };
}

function sessionExpiry() {
  const date = new Date();
  date.setUTCDate(date.getUTCDate() + config.sessionDays);
  return date;
}

export async function registerUser({ email, password, displayName }) {
  const normalizedEmail = normalizeEmail(email);

  if (!normalizedEmail || !normalizedEmail.includes('@')) {
    const error = new Error('Adresse email invalide.');
    error.code = 'VALIDATION_ERROR';
    throw error;
  }

  const passwordHash = await hashPassword(password);
  const userId = uuidv7();
  const now = new Date();

  return withConnection(async (conn) => {
    try {
      await conn.query(
        `INSERT INTO users
          (id, email, password_hash, display_name, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?)`,
        [
          userId,
          normalizedEmail,
          passwordHash,
          displayName ? String(displayName).trim() : null,
          now,
          now,
        ],
      );
    } catch (error) {
      if (error.errno === 1062) {
        const conflict = new Error('Cette adresse email existe déjà.');
        conflict.code = 'CONFLICT';
        throw conflict;
      }

      throw error;
    }

    const rows = await conn.query(
      `SELECT id, email, display_name, created_at, updated_at
       FROM users
       WHERE id = ?`,
      [userId],
    );

    return publicUser(rows[0]);
  });
}

export async function loginUser({ email, password }) {
  const normalizedEmail = normalizeEmail(email);

  return withConnection(async (conn) => {
    const rows = await conn.query(
      `SELECT
         id,
         email,
         password_hash,
         display_name,
         created_at,
         updated_at
       FROM users
       WHERE email = ?
       LIMIT 1`,
      [normalizedEmail],
    );

    const user = rows[0];

    if (!user || !(await verifyPassword(password, user.password_hash))) {
      const error = new Error('Identifiants invalides.');
      error.code = 'AUTHENTICATION_ERROR';
      throw error;
    }

    return publicUser(user);
  });
}

export async function createSession(userId) {
  const sessionId = uuidv7();
  const token = randomBytes(32).toString('base64url');
  const tokenHash = hashSessionToken(token);
  const now = new Date();
  const expiresAt = sessionExpiry();

  await withConnection(async (conn) => {
    await conn.query(
      `INSERT INTO sessions
        (id, user_id, token_hash, expires_at, created_at)
       VALUES (?, ?, ?, ?, ?)`,
      [
        sessionId,
        userId,
        tokenHash,
        expiresAt,
        now,
      ],
    );
  });

  return {
    id: sessionId,
    token,
    expiresAt,
  };
}

export async function getUserFromSessionToken(token) {
  if (!token) {
    return null;
  }

  const tokenHash = hashSessionToken(token);

  return withConnection(async (conn) => {
    const rows = await conn.query(
      `SELECT
         u.id,
         u.email,
         u.display_name,
         u.created_at,
         u.updated_at,
         s.id AS session_id,
         s.expires_at
       FROM sessions s
       INNER JOIN users u ON u.id = s.user_id
       WHERE s.token_hash = ?
         AND s.revoked_at IS NULL
         AND s.expires_at > UTC_TIMESTAMP(6)
       LIMIT 1`,
      [tokenHash],
    );

    if (!rows[0]) {
      return null;
    }

    return {
      user: publicUser(rows[0]),
      sessionId: rows[0].session_id,
      expiresAt: rows[0].expires_at,
    };
  });
}

export async function revokeSession(token) {
  const tokenHash = hashSessionToken(token);

  await withConnection(async (conn) => {
    await conn.query(
      `UPDATE sessions
       SET revoked_at = UTC_TIMESTAMP(6)
       WHERE token_hash = ?
         AND revoked_at IS NULL`,
      [tokenHash],
    );
  });
}

import mariadb from 'mariadb';
import { config } from './config.js';

export const pool = mariadb.createPool({
  host: config.db.host,
  port: config.db.port,
  user: config.db.user,
  password: config.db.password,
  database: config.db.database,
  connectionLimit: config.db.connectionLimit,
  timezone: 'Z',
});

export async function withConnection(fn) {
  const conn = await pool.getConnection();

  try {
    return await fn(conn);
  } finally {
    conn.release();
  }
}

export async function closeDatabase() {
  await pool.end();
}

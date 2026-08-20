import 'dotenv/config';
import fs from 'node:fs/promises';
import path from 'node:path';
import mariadb from 'mariadb';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const migrationsDir = path.join(here, '..', 'migrations');

for (const key of ['DB_ADMIN_PASSWORD', 'DB_NAME']) {
  if (!process.env[key]) throw new Error(`Variable obligatoire absente: ${key}`);
}

const pool = mariadb.createPool({
  host: process.env.DB_HOST || '127.0.0.1',
  port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_ADMIN_USER || 'admin',
  password: process.env.DB_ADMIN_PASSWORD,
  database: process.env.DB_NAME,
  connectionLimit: 1,
});

const conn = await pool.getConnection();

try {
  const files = (await fs.readdir(migrationsDir))
    .filter((f) => /^\d+_.+\.sql$/.test(f))
    .sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));

  // Bootstrap/admin account has CREATE rights; the application account does not.
  await conn.query(`CREATE TABLE IF NOT EXISTS migration_history (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    migration_name VARCHAR(255) NOT NULL,
    applied_at DATETIME(6) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_migration_name (migration_name)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`);

  for (const file of files) {
    const rows = await conn.query(
      'SELECT id FROM migration_history WHERE migration_name = ? LIMIT 1',
      [file]
    );
    if (rows.length) {
      console.log(`SKIP ${file}`);
      continue;
    }

    const sql = await fs.readFile(path.join(migrationsDir, file), 'utf8');
    console.log(`APPLY ${file}`);
    await conn.beginTransaction();
    try {
      // Migration files in this project are DDL. MariaDB may implicitly commit
      // some DDL; history is recorded only after successful execution.
      await conn.query(sql);
      await conn.query(
        'INSERT INTO migration_history (migration_name, applied_at) VALUES (?, UTC_TIMESTAMP(6))',
        [file]
      );
      await conn.commit();
    } catch (error) {
      await conn.rollback();
      throw error;
    }
  }

  console.log('Migrations terminées.');
} finally {
  conn.release();
  await pool.end();
}

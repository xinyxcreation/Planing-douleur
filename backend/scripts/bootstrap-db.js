import 'dotenv/config';
import mariadb from 'mariadb';

const required = ['DB_ADMIN_PASSWORD', 'DB_NAME', 'DB_USER', 'DB_PASSWORD'];
for (const key of required) {
  if (!process.env[key]) throw new Error(`Variable obligatoire absente: ${key}`);
}

const host = process.env.DB_HOST || '127.0.0.1';
const port = Number(process.env.DB_PORT || 3306);
const adminUser = process.env.DB_ADMIN_USER || 'root';
const adminPassword = process.env.DB_ADMIN_PASSWORD;
const dbName = process.env.DB_NAME;
const appUser = process.env.DB_USER;
const appPassword = process.env.DB_PASSWORD;

const qi = (v) => '`' + String(v).replaceAll('`', '``') + '`';
const qu = (v) => "'" + String(v).replaceAll("'", "''") + "'";

const pool = mariadb.createPool({
  host, port, user: adminUser, password: adminPassword, connectionLimit: 2
});
const conn = await pool.getConnection();

try {
  await conn.query(
    `CREATE DATABASE IF NOT EXISTS ${qi(dbName)}
     CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`
  );

  for (const hostPart of ['localhost', '%']) {
    await conn.query(
      `CREATE USER IF NOT EXISTS 'admin'@'${hostPart}' IDENTIFIED BY ?`,
      [adminPassword]
    );
    await conn.query(
      `ALTER USER 'admin'@'${hostPart}' IDENTIFIED BY ?`,
      [adminPassword]
    );
    await conn.query(
      `GRANT ALL PRIVILEGES ON *.* TO 'admin'@'${hostPart}' WITH GRANT OPTION`
    );

    await conn.query(
      `CREATE USER IF NOT EXISTS ${qu(appUser)}@'${hostPart}' IDENTIFIED BY ?`,
      [appPassword]
    );
    await conn.query(
      `ALTER USER ${qu(appUser)}@'${hostPart}' IDENTIFIED BY ?`,
      [appPassword]
    );
    await conn.query(
      `REVOKE ALL PRIVILEGES, GRANT OPTION FROM ${qu(appUser)}@'${hostPart}'`
    );
    await conn.query(
      `GRANT SELECT, INSERT, UPDATE, DELETE ON ${qi(dbName)}.* TO ${qu(appUser)}@'${hostPart}'`
    );
  }

  await conn.query('FLUSH PRIVILEGES');
  console.log(`DB prête: ${dbName}`);
  console.log(`Admin: admin@localhost + admin@%`);
  console.log(`App: ${appUser}@localhost + ${appUser}@%`);
} finally {
  conn.release();
  await pool.end();
}

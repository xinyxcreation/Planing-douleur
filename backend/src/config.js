import 'dotenv/config';

function required(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Variable d'environnement manquante: ${name}`);
  }
  return value;
}

export const config = {
  host: process.env.API_HOST || '127.0.0.1',
  port: Number(process.env.API_PORT || 3000),

  db: {
    host: required('DB_HOST'),
    port: Number(process.env.DB_PORT || 3306),
    user: required('DB_USER'),
    password: required('DB_PASSWORD'),
    database: required('DB_NAME'),
    connectionLimit: Number(process.env.DB_CONNECTION_LIMIT || 10),
  },

  jwtSecret: required('JWT_SECRET'),

  sessionDays: Number(process.env.SESSION_DAYS || 30),
};

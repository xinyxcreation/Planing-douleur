const numberFromEnv = (name, fallback) => {
  const value = Number(process.env[name]);

  return Number.isFinite(value)
    ? value
    : fallback;
};

export const config = {
  port: numberFromEnv('PORT', 3000),

  host: process.env.HOST || '0.0.0.0',

  sessionDays: numberFromEnv(
    'SESSION_DAYS',
    30,
  ),

  db: {
    host: process.env.DB_HOST || '127.0.0.1',

    port: numberFromEnv(
      'DB_PORT',
      3306,
    ),

    user: process.env.DB_USER || 'planning_douleur_user',

    password: process.env.DB_PASSWORD || '',

    database:
      process.env.DB_DATABASE ||
      'pwa_planning_douleur',

    connectionLimit: numberFromEnv(
      'DB_CONNECTION_LIMIT',
      5,
    ),
  },
};

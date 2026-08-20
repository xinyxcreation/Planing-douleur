import { buildApp } from './app.js';
import { config } from './config.js';

const app = await buildApp();

try {
  await app.listen({
    host: config.host,
    port: config.port,
  });

  console.log(
    `Planning-douleur API écoute sur http://${config.host}:${config.port}`,
  );
} catch (error) {
  app.log.error(error);
  process.exit(1);
}

import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const run = (script) =>
  new Promise((resolve, reject) => {
    const scriptPath = fileURLToPath(
      new URL(`./${script}`, import.meta.url)
    );

    const child = spawn(process.execPath, [scriptPath], {
      stdio: 'inherit',
      env: process.env,
    });

    child.on('exit', (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`${script} exited ${code}`));
      }
    });

    child.on('error', reject);
  });

await run('bootstrap-db.js');
await run('migrate.js');

console.log('Planning-douleur DB setup terminé.');

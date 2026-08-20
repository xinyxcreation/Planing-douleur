import {
  randomBytes,
  scrypt as scryptCallback,
  timingSafeEqual,
  createHash,
} from 'node:crypto';

import { promisify } from 'node:util';

const scrypt = promisify(scryptCallback);

const KEY_LENGTH = 64;

export async function hashPassword(password) {
  if (typeof password !== 'string' || password.length < 8) {
    throw new Error('Le mot de passe doit contenir au moins 8 caractères.');
  }

  const salt = randomBytes(16);

  const derivedKey = await scrypt(
    password,
    salt,
    KEY_LENGTH,
    {
      N: 16384,
      r: 8,
      p: 1,
    },
  );

  return [
    'scrypt',
    salt.toString('hex'),
    Buffer.from(derivedKey).toString('hex'),
  ].join('$');
}

export async function verifyPassword(password, storedHash) {
  const parts = storedHash.split('$');

  if (parts.length !== 3 || parts[0] !== 'scrypt') {
    return false;
  }

  const salt = Buffer.from(parts[1], 'hex');
  const expected = Buffer.from(parts[2], 'hex');

  const derived = Buffer.from(
    await scrypt(
      password,
      salt,
      expected.length,
      {
        N: 16384,
        r: 8,
        p: 1,
      },
    ),
  );

  return (
    derived.length === expected.length &&
    timingSafeEqual(derived, expected)
  );
}

export function hashSessionToken(token) {
  return createHash('sha256')
    .update(token, 'utf8')
    .digest('hex');
}

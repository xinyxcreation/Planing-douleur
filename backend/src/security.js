import { createHash, randomBytes, scrypt as scryptCallback } from 'node:crypto';
import { promisify } from 'node:util';

const scrypt = promisify(scryptCallback);

const KEY_LENGTH = 64;
const SALT_LENGTH = 16;

export async function hashPassword(password) {
  const value = String(password ?? '');

  if (!value) {
    throw new Error('Mot de passe requis.');
  }

  const salt = randomBytes(SALT_LENGTH);

  const derivedKey = await scrypt(
    value,
    salt,
    KEY_LENGTH,
  );

  return [
    'scrypt',
    salt.toString('hex'),
    Buffer.from(derivedKey).toString('hex'),
  ].join('$');
}

export async function verifyPassword(password, storedHash) {
  try {
    const parts = String(storedHash ?? '').split('$');

    if (
      parts.length !== 3 ||
      parts[0] !== 'scrypt'
    ) {
      return false;
    }

    const salt = Buffer.from(parts[1], 'hex');
    const expected = Buffer.from(parts[2], 'hex');

    if (expected.length !== KEY_LENGTH) {
      return false;
    }

    const derivedKey = await scrypt(
      String(password ?? ''),
      salt,
      KEY_LENGTH,
    );

    return Buffer.from(derivedKey).equals(expected);
  } catch (_) {
    return false;
  }
}

export function hashSessionToken(token) {
  return createHash('sha256')
    .update(String(token ?? ''), 'utf8')
    .digest('hex');
}

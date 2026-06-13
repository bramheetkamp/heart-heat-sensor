import { createRemoteJWKSet, createLocalJWKSet, jwtVerify } from 'jose';
import type { JWTVerifyGetKey, JSONWebKeySet } from 'jose';

export type { JWTVerifyGetKey as AppleJWKS };
export { createLocalJWKSet } from 'jose';

const APPLE_JWKS_URI = 'https://appleid.apple.com/auth/keys';
const APPLE_ISSUER = 'https://appleid.apple.com';

export interface AppleTokenClaims {
  sub: string;
  email?: string;
}

/** Build a live Apple JWKS resolver (lazy-fetched on first use). */
export function makeAppleJWKS(uri = APPLE_JWKS_URI): JWTVerifyGetKey {
  return createRemoteJWKSet(new URL(uri));
}

/** Build an in-memory JWKS resolver from a static key set (used in tests). */
export function makeLocalJWKS(keySet: JSONWebKeySet): JWTVerifyGetKey {
  return createLocalJWKSet(keySet);
}

/**
 * Verify an Apple identity token against the provided JWKS.
 * Validates `iss` (must be Apple), `aud`, and `exp` claims.
 * Returns the `sub` and optional `email` on success.
 * Throws on any verification failure.
 */
export async function verifyAppleToken(
  identityToken: string,
  jwks: JWTVerifyGetKey,
  audience: string,
): Promise<AppleTokenClaims> {
  const { payload } = await jwtVerify(identityToken, jwks, {
    issuer: APPLE_ISSUER,
    audience,
  });

  const { sub, email } = payload;
  if (typeof sub !== 'string' || !sub) {
    throw new Error('Missing sub claim in Apple identity token');
  }

  return { sub, email: typeof email === 'string' ? email : undefined };
}

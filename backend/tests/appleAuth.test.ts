/**
 * Apple Sign-In JWKS verification tests.
 *
 * Generates a local RS256 key pair, builds an in-memory JWKS, and signs test
 * JWTs that are structurally identical to real Apple identity tokens. The
 * server is built with `appleJwks` injected so no network calls are made.
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { generateKeyPair, exportJWK, SignJWT } from 'jose';
import type { KeyLike, JSONWebKeySet } from 'jose';
import { buildServer } from '../src/server.js';
import { makeLocalJWKS } from '../src/services/appleAuth.js';
import type { FastifyInstance } from 'fastify';
import { mkdtempSync, rmSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';

const TEST_AUDIENCE = 'com.pulse.app';
const APPLE_ISSUER = 'https://appleid.apple.com';

// ── Key generation ────────────────────────────────────────────────────────────

let privateKey: KeyLike;
let app: FastifyInstance;
let tmpDir: string;

async function makeTestToken(
  signingKey: KeyLike,
  claims: { sub?: string; email?: string } = {},
  overrides: {
    issuer?: string;
    audience?: string;
    expiresIn?: string;
    sub?: string;
  } = {},
): Promise<string> {
  const sub = overrides.sub ?? claims.sub ?? 'apple.test.sub.001';
  return new SignJWT({ email: claims.email, ...claims })
    .setProtectedHeader({ alg: 'RS256', kid: 'test-key-001' })
    .setSubject(sub)
    .setIssuer(overrides.issuer ?? APPLE_ISSUER)
    .setAudience(overrides.audience ?? TEST_AUDIENCE)
    .setIssuedAt()
    .setExpirationTime(overrides.expiresIn ?? '1h')
    .sign(signingKey);
}

beforeAll(async () => {
  // Generate a fresh RS256 key pair for this test run
  const { privateKey: pk, publicKey } = await generateKeyPair('RS256');
  privateKey = pk;

  // Build a JWKS with the public key and a `kid` that matches the JWT header
  const jwk = await exportJWK(publicKey);
  jwk.kid = 'test-key-001';
  jwk.use = 'sig';
  const keySet: JSONWebKeySet = { keys: [jwk] };
  const testJwks = makeLocalJWKS(keySet);

  tmpDir = mkdtempSync(join(tmpdir(), 'pulse-apple-test-'));
  app = await buildServer({
    dbPath: join(tmpDir, 'test.db'),
    jwtSecret: 'test_apple_jwks_secret',
    // Tight rate limits so the rate-limit bucket doesn't interfere with these tests
    authRateLimit: { max: 100, timeWindow: '1 minute' },
    appleJwks: testJwks,
    appleAudience: TEST_AUDIENCE,
  });
  await app.ready();
});

afterAll(async () => {
  await app.close();
  rmSync(tmpDir, { recursive: true, force: true });
});

// ─── Valid token flows ────────────────────────────────────────────────────────

describe('POST /auth/apple — valid token', () => {
  it('creates a new user and returns a JWT when given a valid token with email', async () => {
    const identityToken = await makeTestToken(privateKey, {
      sub: 'apple.new.user.001',
      email: 'appleuser@example.com',
    });

    const res = await app.inject({
      method: 'POST',
      url: '/auth/apple',
      payload: { identityToken },
    });

    expect(res.statusCode).toBe(200);
    const body = res.json<{ token: string; userId: string }>();
    expect(typeof body.token).toBe('string');
    expect(body.token.length).toBeGreaterThan(10);
    expect(typeof body.userId).toBe('string');
  });

  it('returns the same userId on a second sign-in with the same sub', async () => {
    const identityToken1 = await makeTestToken(privateKey, { sub: 'apple.returning.user' });
    const res1 = await app.inject({
      method: 'POST',
      url: '/auth/apple',
      payload: { identityToken: identityToken1 },
    });
    expect(res1.statusCode).toBe(200);
    const { userId: uid1 } = res1.json<{ userId: string }>();

    const identityToken2 = await makeTestToken(privateKey, { sub: 'apple.returning.user' });
    const res2 = await app.inject({
      method: 'POST',
      url: '/auth/apple',
      payload: { identityToken: identityToken2 },
    });
    expect(res2.statusCode).toBe(200);
    const { userId: uid2 } = res2.json<{ userId: string }>();

    expect(uid1).toBe(uid2);
  });

  it('accepts a valid token without email and uses a placeholder address', async () => {
    const identityToken = await makeTestToken(privateKey, { sub: 'apple.no.email.sub' });

    const res = await app.inject({
      method: 'POST',
      url: '/auth/apple',
      payload: { identityToken },
    });

    expect(res.statusCode).toBe(200);
    expect(res.json<{ token: string }>().token).toBeTruthy();
  });

  it('links an Apple sub to an existing email/password account', async () => {
    // Register an email/password account first
    await app.inject({
      method: 'POST',
      url: '/auth/register',
      payload: { email: 'link@example.com', password: 'password123' },
    });

    // Sign in with Apple, using the same email — should link to the existing user
    const identityToken = await makeTestToken(privateKey, {
      sub: 'apple.link.sub.abc',
      email: 'link@example.com',
    });

    const appleRes = await app.inject({
      method: 'POST',
      url: '/auth/apple',
      payload: { identityToken },
    });

    expect(appleRes.statusCode).toBe(200);

    // Login with email/password should return the same user
    const loginRes = await app.inject({
      method: 'POST',
      url: '/auth/login',
      payload: { email: 'link@example.com', password: 'password123' },
    });
    expect(loginRes.statusCode).toBe(200);
    expect(loginRes.json<{ userId: string }>().userId).toBe(
      appleRes.json<{ userId: string }>().userId,
    );
  });
});

// ─── Invalid / tampered token flows ──────────────────────────────────────────

describe('POST /auth/apple — invalid token', () => {
  it('rejects an expired token', async () => {
    const identityToken = await makeTestToken(
      privateKey,
      { sub: 'apple.expired.sub' },
      { expiresIn: '-1s' },
    );

    const res = await app.inject({
      method: 'POST',
      url: '/auth/apple',
      payload: { identityToken },
    });

    expect(res.statusCode).toBe(401);
    expect(res.json<{ error: string }>().error).toBe('Invalid Apple identity token');
  });

  it('rejects a token with the wrong issuer', async () => {
    const identityToken = await makeTestToken(
      privateKey,
      { sub: 'apple.wrong.iss' },
      { issuer: 'https://evil.com' },
    );

    const res = await app.inject({
      method: 'POST',
      url: '/auth/apple',
      payload: { identityToken },
    });

    expect(res.statusCode).toBe(401);
  });

  it('rejects a token with the wrong audience', async () => {
    const identityToken = await makeTestToken(
      privateKey,
      { sub: 'apple.wrong.aud' },
      { audience: 'com.evil.app' },
    );

    const res = await app.inject({
      method: 'POST',
      url: '/auth/apple',
      payload: { identityToken },
    });

    expect(res.statusCode).toBe(401);
  });

  it('rejects a token signed with an unknown key', async () => {
    const { privateKey: unknownKey } = await generateKeyPair('RS256');
    const identityToken = await makeTestToken(unknownKey, { sub: 'apple.bad.sig' });

    const res = await app.inject({
      method: 'POST',
      url: '/auth/apple',
      payload: { identityToken },
    });

    expect(res.statusCode).toBe(401);
  });

  it('rejects a structurally malformed token', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/auth/apple',
      payload: { identityToken: 'not.a.real.jwt' },
    });

    expect(res.statusCode).toBe(401);
  });

  it('returns 400 when identityToken is missing from the request body', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/auth/apple',
      payload: {},
    });

    expect(res.statusCode).toBe(400);
  });
});

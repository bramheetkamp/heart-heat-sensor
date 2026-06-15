/**
 * Rate-limiting integration tests.
 *
 * Each describe block builds its own server with tight per-route limits so
 * the 429 threshold is reachable in a handful of inject() calls. Isolating
 * servers prevents shared in-memory rate-limit counters from interfering.
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildServer } from '../src/server.js';
import type { FastifyInstance } from 'fastify';
import { mkdtempSync, rmSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';

function makeTmpDb(prefix: string): { tmpDir: string; dbPath: string } {
  const tmpDir = mkdtempSync(join(tmpdir(), `pulse-rl-${prefix}-`));
  return { tmpDir, dbPath: join(tmpDir, 'test.db') };
}

// ─── Login rate limiting ──────────────────────────────────────────────────────

describe('POST /auth/login rate limit', () => {
  let app: FastifyInstance;
  let tmpDir: string;

  beforeAll(async () => {
    const tmp = makeTmpDb('login');
    tmpDir = tmp.tmpDir;
    app = await buildServer({
      dbPath: tmp.dbPath,
      jwtSecret: 'test_rl_secret',
      authRateLimit: { max: 3, timeWindow: '1 minute' },
    });
    await app.ready();
  });

  afterAll(async () => {
    await app.close();
    rmSync(tmpDir, { recursive: true, force: true });
  });

  it('allows up to max attempts then blocks with 429 and correct body', async () => {
    const payload = { email: 'probe@example.com', password: 'wrongpassword' };

    // Requests 1–3: allowed (return 401 — bad creds, not rate-limited)
    for (let i = 0; i < 3; i++) {
      const res = await app.inject({ method: 'POST', url: '/auth/login', payload });
      expect(res.statusCode).toBe(401);
      expect(res.headers['x-ratelimit-limit']).toBeTruthy();
      expect(Number(res.headers['x-ratelimit-remaining'])).toBeGreaterThanOrEqual(0);
    }

    // Request 4: rate-limited
    const blocked = await app.inject({ method: 'POST', url: '/auth/login', payload });
    expect(blocked.statusCode).toBe(429);
    const body = blocked.json<{ error: string; statusCode: number }>();
    expect(body.error).toBe('Too Many Requests');
    expect(body.statusCode).toBe(429);
  });

  it('register bucket stays independent — register still works after login is exhausted', async () => {
    // Login bucket is exhausted from the previous test.
    // Register has its own separate bucket and should not be affected.
    const res = await app.inject({
      method: 'POST',
      url: '/auth/register',
      payload: { email: 'independent@example.com', password: 'password123' },
    });
    expect(res.statusCode).toBe(201);
  });
});

// ─── Register rate limiting ───────────────────────────────────────────────────

describe('POST /auth/register rate limit', () => {
  let app: FastifyInstance;
  let tmpDir: string;

  beforeAll(async () => {
    const tmp = makeTmpDb('register');
    tmpDir = tmp.tmpDir;
    app = await buildServer({
      dbPath: tmp.dbPath,
      jwtSecret: 'test_rl_secret',
      authRateLimit: { max: 3, timeWindow: '1 minute' },
    });
    await app.ready();
  });

  afterAll(async () => {
    await app.close();
    rmSync(tmpDir, { recursive: true, force: true });
  });

  it('allows up to max registrations then blocks with 429', async () => {
    const payload = { email: 'newuser@example.com', password: 'password123' };

    // Request 1: creates account (201)
    const first = await app.inject({ method: 'POST', url: '/auth/register', payload });
    expect(first.statusCode).toBe(201);

    // Requests 2–3: duplicate email (409) but still not rate-limited
    for (let i = 1; i < 3; i++) {
      const res = await app.inject({ method: 'POST', url: '/auth/register', payload });
      expect(res.statusCode).toBe(409);
      expect(Number(res.headers['x-ratelimit-remaining'])).toBeGreaterThanOrEqual(0);
    }

    // Request 4: rate-limited
    const blocked = await app.inject({ method: 'POST', url: '/auth/register', payload });
    expect(blocked.statusCode).toBe(429);
  });
});

// ─── Readings batch rate limiting ────────────────────────────────────────────

describe('POST /readings/batch rate limit', () => {
  let app: FastifyInstance;
  let tmpDir: string;
  let token: string;

  beforeAll(async () => {
    const tmp = makeTmpDb('readings');
    tmpDir = tmp.tmpDir;
    app = await buildServer({
      dbPath: tmp.dbPath,
      jwtSecret: 'test_rl_secret',
      readingsRateLimit: { max: 3, timeWindow: '1 minute' },
    });
    await app.ready();

    // Obtain an auth token
    await app.inject({
      method: 'POST',
      url: '/auth/register',
      payload: { email: 'uploader@example.com', password: 'password123' },
    });
    const login = await app.inject({
      method: 'POST',
      url: '/auth/login',
      payload: { email: 'uploader@example.com', password: 'password123' },
    });
    token = login.json<{ token: string }>().token;
  });

  afterAll(async () => {
    await app.close();
    rmSync(tmpDir, { recursive: true, force: true });
  });

  it('allows up to max batch uploads then blocks with 429', async () => {
    const reading = {
      readings: [
        { device_id: 'dev-rl', timestamp: Date.now(), heart_rate: 70, rr_intervals: [], activity: 'rest' },
      ],
    };
    const headers = { authorization: `Bearer ${token}` };

    // Requests 1–3: succeed
    for (let i = 0; i < 3; i++) {
      const res = await app.inject({ method: 'POST', url: '/readings/batch', headers, payload: reading });
      expect(res.statusCode).toBe(201);
    }

    // Request 4: rate-limited
    const blocked = await app.inject({ method: 'POST', url: '/readings/batch', headers, payload: reading });
    expect(blocked.statusCode).toBe(429);
    expect(blocked.json<{ error: string }>().error).toBe('Too Many Requests');
  });
});

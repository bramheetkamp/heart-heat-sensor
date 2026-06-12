/**
 * Integration tests for heartrate-backend API.
 *
 * Uses Fastify's inject() — no real HTTP server or port required.
 * Each test suite gets a fresh in-memory SQLite database via a temp DATABASE_PATH.
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildServer } from '../src/server.js';
import type { FastifyInstance } from 'fastify';
import { mkdtempSync, rmSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';

// ─── shared server & temp DB ──────────────────────────────────────────────────
let app: FastifyInstance;
let tmpDir: string;
let authToken: string;
let userId: string;

beforeAll(async () => {
  // Point to a temp directory so tests don't touch the real DB
  tmpDir = mkdtempSync(join(tmpdir(), 'heartrate-test-'));
  process.env.DATABASE_PATH = join(tmpDir, 'test.db');
  process.env.JWT_SECRET = 'test_jwt_secret_for_vitest';

  // Dynamically re-import db so it picks up the new DATABASE_PATH
  // We build the server which registers all routes and plugins
  app = await buildServer();
  await app.ready();
});

afterAll(async () => {
  await app.close();
  rmSync(tmpDir, { recursive: true, force: true });
});

// ─── 1. POST /auth/register ───────────────────────────────────────────────────
describe('POST /auth/register', () => {
  it('creates a new user and returns a token', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/auth/register',
      payload: { email: 'alice@example.com', password: 'securepw!' },
    });

    expect(res.statusCode).toBe(201);
    const body = res.json<{ token: string; userId: string }>();
    expect(body.token).toBeTruthy();
    expect(body.userId).toBeTruthy();

    // Store for later tests
    authToken = body.token;
    userId = body.userId;
  });

  it('returns 409 when email already registered', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/auth/register',
      payload: { email: 'alice@example.com', password: 'anotherpassword' },
    });
    expect(res.statusCode).toBe(409);
  });

  it('returns 400 on invalid payload', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/auth/register',
      payload: { email: 'not-an-email', password: 'pw' },
    });
    expect(res.statusCode).toBe(400);
  });
});

// ─── 2. POST /auth/login ──────────────────────────────────────────────────────
describe('POST /auth/login', () => {
  it('returns a token for valid credentials', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/auth/login',
      payload: { email: 'alice@example.com', password: 'securepw!' },
    });

    expect(res.statusCode).toBe(200);
    const body = res.json<{ token: string; userId: string }>();
    expect(body.token).toBeTruthy();
    expect(body.userId).toBe(userId);
  });

  it('returns 401 on wrong password', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/auth/login',
      payload: { email: 'alice@example.com', password: 'wrongpassword' },
    });
    expect(res.statusCode).toBe(401);
  });

  it('returns 401 for unknown email', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/auth/login',
      payload: { email: 'unknown@example.com', password: 'anything' },
    });
    expect(res.statusCode).toBe(401);
  });
});

// ─── 3. POST /readings/batch ──────────────────────────────────────────────────
describe('POST /readings/batch', () => {
  it('inserts readings and returns count', async () => {
    const now = Date.now();
    const readings = [
      {
        device_id: 'dev-001',
        timestamp: now - 3600_000,
        heart_rate: 62,
        rr_intervals: [950, 960, 940, 970, 955],
        temp_site1: 36.6,
        temp_site2: 36.2,
        activity: 'rest',
      },
      {
        device_id: 'dev-001',
        timestamp: now - 1800_000,
        heart_rate: 130,
        rr_intervals: [460, 455, 470, 448, 462],
        temp_site1: 37.1,
        temp_site2: 36.8,
        activity: 'active',
      },
    ];

    const res = await app.inject({
      method: 'POST',
      url: '/readings/batch',
      headers: { authorization: `Bearer ${authToken}` },
      payload: { readings },
    });

    expect(res.statusCode).toBe(201);
    const body = res.json<{ inserted: number }>();
    expect(body.inserted).toBe(2);
  });

  it('returns 401 without a token', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/readings/batch',
      payload: { readings: [{ device_id: 'x', timestamp: Date.now(), heart_rate: 60, rr_intervals: [] }] },
    });
    expect(res.statusCode).toBe(401);
  });

  it('returns 400 on empty readings array', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/readings/batch',
      headers: { authorization: `Bearer ${authToken}` },
      payload: { readings: [] },
    });
    expect(res.statusCode).toBe(400);
  });
});

// ─── 4. GET /readings ─────────────────────────────────────────────────────────
describe('GET /readings', () => {
  it('returns the inserted readings for the authenticated user', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/readings',
      headers: { authorization: `Bearer ${authToken}` },
    });

    expect(res.statusCode).toBe(200);
    const body = res.json<{ readings: unknown[] }>();
    expect(Array.isArray(body.readings)).toBe(true);
    expect(body.readings.length).toBeGreaterThanOrEqual(2);
  });

  it('filters by from / to timestamps', async () => {
    const now = Date.now();
    const res = await app.inject({
      method: 'GET',
      url: `/readings?from=${now - 2 * 3600_000}&to=${now - 1000}`,
      headers: { authorization: `Bearer ${authToken}` },
    });

    expect(res.statusCode).toBe(200);
    const body = res.json<{ readings: Array<{ timestamp: number }> }>();
    for (const r of body.readings) {
      expect(r.timestamp).toBeGreaterThanOrEqual(now - 2 * 3600_000);
      expect(r.timestamp).toBeLessThanOrEqual(now - 1000);
    }
  });

  it('respects the limit param', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/readings?limit=1',
      headers: { authorization: `Bearer ${authToken}` },
    });

    expect(res.statusCode).toBe(200);
    const body = res.json<{ readings: unknown[] }>();
    expect(body.readings.length).toBeLessThanOrEqual(1);
  });

  it('returns 401 without a token', async () => {
    const res = await app.inject({ method: 'GET', url: '/readings' });
    expect(res.statusCode).toBe(401);
  });
});

// ─── 5. GET /warnings ────────────────────────────────────────────────────────
describe('GET /warnings', () => {
  it('returns an array (may be empty) for authenticated user', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/warnings',
      headers: { authorization: `Bearer ${authToken}` },
    });

    expect(res.statusCode).toBe(200);
    const body = res.json<{ warnings: unknown[] }>();
    expect(Array.isArray(body.warnings)).toBe(true);
  });

  it('returns 401 without a token', async () => {
    const res = await app.inject({ method: 'GET', url: '/warnings' });
    expect(res.statusCode).toBe(401);
  });
});

describe('GET /warnings/:id', () => {
  it('returns 404 for a non-existent warning id', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/warnings/non-existent-id',
      headers: { authorization: `Bearer ${authToken}` },
    });
    expect(res.statusCode).toBe(404);
  });
});

// ─── 6. GET /.well-known/apple-app-site-association ──────────────────────────
describe('GET /.well-known/apple-app-site-association', () => {
  it('returns valid JSON with applinks key', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/.well-known/apple-app-site-association',
    });

    expect(res.statusCode).toBe(200);
    const body = res.json<{ applinks: unknown; webcredentials: unknown }>();
    expect(body).toHaveProperty('applinks');
    expect(body).toHaveProperty('webcredentials');

    const applinks = body.applinks as { details: Array<{ appIDs: string[] }> };
    expect(applinks.details).toBeInstanceOf(Array);
    expect(applinks.details.length).toBeGreaterThan(0);
    expect(applinks.details[0].appIDs[0]).toContain('com.heartrate.app');
  });
});

// ─── 7. POST /warnings/recompute ─────────────────────────────────────────────
describe('POST /warnings/recompute', () => {
  it('runs the engine and returns result without crashing', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/warnings/recompute',
      headers: { authorization: `Bearer ${authToken}` },
    });

    expect(res.statusCode).toBe(200);
    const body = res.json<{ warnings: unknown[]; count: number }>();
    expect(Array.isArray(body.warnings)).toBe(true);
    expect(typeof body.count).toBe('number');
  });
});

// ─── 8. Health check ─────────────────────────────────────────────────────────
describe('GET /health', () => {
  it('returns status ok', async () => {
    const res = await app.inject({ method: 'GET', url: '/health' });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ status: string }>();
    expect(body.status).toBe('ok');
  });
});

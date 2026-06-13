/**
 * Unit tests for computeWarnings() and its three rules.
 *
 * Each test builds its own in-memory SQLite database, inserts controlled
 * readings, and asserts on the returned Warning[] directly — no HTTP layer.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { mkdtempSync, rmSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';
import { createDatabase } from '../src/db/index.js';
import { computeWarnings } from '../src/services/warningsEngine.js';
import { v4 as uuidv4 } from 'uuid';
import type Database from 'better-sqlite3';

// ─── helpers ──────────────────────────────────────────────────────────────────

const NOW = Date.now();
const H = 3_600_000; // 1 hour in ms
const D = 86_400_000; // 1 day in ms

function hoursAgo(n: number): number {
  return NOW - n * H;
}

function daysAgo(n: number): number {
  return NOW - n * D;
}

/** Generate `count` RR intervals with mean matching bpmTarget and approximate RMSSD. */
function makeRR(bpm: number, rmssdTarget: number, count = 20): number[] {
  const meanRR = (60 / bpm) * 1000;
  const rr: number[] = [meanRR];
  for (let i = 1; i < count; i++) {
    const diff = (Math.random() - 0.5) * 2 * rmssdTarget * 1.25;
    rr.push(Math.max(300, rr[i - 1] + diff));
  }
  return rr.map((v) => Math.round(v));
}

interface ReadingInput {
  timestamp: number;
  heart_rate?: number;
  rr_intervals?: number[];
  temp_site1?: number;
  temp_site2?: number;
  activity?: string;
}

function insertReadings(
  db: Database.Database,
  userId: string,
  readings: ReadingInput[]
): void {
  const stmt = db.prepare(`
    INSERT INTO readings (id, user_id, device_id, timestamp, heart_rate,
                          rr_intervals, temp_site1, temp_site2, activity, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);
  const insertMany = db.transaction(() => {
    for (const r of readings) {
      stmt.run(
        uuidv4(),
        userId,
        'test-device',
        r.timestamp,
        r.heart_rate ?? null,
        JSON.stringify(r.rr_intervals ?? []),
        r.temp_site1 ?? null,
        r.temp_site2 ?? null,
        r.activity ?? 'rest',
        NOW
      );
    }
  });
  insertMany();
}

// ─── fixture builders ──────────────────────────────────────────────────────────

/** 28 days of normal resting readings to establish a baseline. */
function normalBaseline(userId: string): ReadingInput[] {
  const out: ReadingInput[] = [];
  for (let d = 28; d >= 8; d--) {
    for (let h = 0; h < 4; h++) {
      out.push({
        timestamp: daysAgo(d) + h * H,
        heart_rate: 62,
        rr_intervals: makeRR(62, 60),
        temp_site1: 36.5,
        temp_site2: 36.1,
        activity: 'rest',
      });
    }
  }
  return out;
}

// ─── test scaffolding ──────────────────────────────────────────────────────────

let db: Database.Database;
let tmpDir: string;
let userId: string;

beforeEach(() => {
  tmpDir = mkdtempSync(join(tmpdir(), 'pulse-engine-test-'));
  db = createDatabase(join(tmpDir, 'test.db'));
  userId = uuidv4();
  db.prepare(
    `INSERT INTO users (id, email, password_hash, apple_sub, created_at)
     VALUES (?, ?, ?, NULL, ?)`
  ).run(userId, `u_${userId}@test.com`, 'hash', NOW);
});

afterEach(() => {
  db.close();
  rmSync(tmpDir, { recursive: true, force: true });
});

// ─── OVERHEATING ─────────────────────────────────────────────────────────────

describe('OVERHEATING rule', () => {
  it('fires when temp_site1 exceeds 38.5 °C within 48 h', () => {
    insertReadings(db, userId, [
      { timestamp: hoursAgo(10), heart_rate: 150, temp_site1: 39.1, activity: 'active' },
    ]);

    const warnings = computeWarnings(userId, db);
    expect(warnings).toHaveLength(1);
    expect(warnings[0].type).toBe('OVERHEATING');
    expect(warnings[0].data.triggerValues.temp_site1).toBeGreaterThan(38.5);
    expect(warnings[0].data.baselineValues.threshold).toBe(38.5);
  });

  it('fires for temp spike 37–38 h ago (48 h window)', () => {
    insertReadings(db, userId, [
      { timestamp: hoursAgo(37), heart_rate: 155, temp_site1: 39.2, activity: 'active' },
    ]);

    const warnings = computeWarnings(userId, db);
    expect(warnings.some((w) => w.type === 'OVERHEATING')).toBe(true);
  });

  it('does NOT fire when temp is below threshold', () => {
    insertReadings(db, userId, [
      { timestamp: hoursAgo(5), heart_rate: 130, temp_site1: 38.3, activity: 'active' },
    ]);

    const warnings = computeWarnings(userId, db);
    expect(warnings.every((w) => w.type !== 'OVERHEATING')).toBe(true);
  });

  it('does NOT fire for old readings outside 48 h window', () => {
    insertReadings(db, userId, [
      { timestamp: hoursAgo(60), heart_rate: 155, temp_site1: 39.5, activity: 'active' },
    ]);

    const warnings = computeWarnings(userId, db);
    expect(warnings.every((w) => w.type !== 'OVERHEATING')).toBe(true);
  });

  it('fires on rapid rise ≥1 °C in 30 min during active readings', () => {
    // Both readings stay below the 38.5 °C absolute threshold so only the
    // rapid-rise path can trigger.  Rise = 38.2 − 37.1 = 1.1 °C in 20 min.
    const base = hoursAgo(3);
    insertReadings(db, userId, [
      { timestamp: base, heart_rate: 140, temp_site1: 37.1, activity: 'active' },
      { timestamp: base + 20 * 60_000, heart_rate: 145, temp_site1: 38.2, activity: 'active' },
    ]);

    const warnings = computeWarnings(userId, db);
    expect(warnings.some((w) => w.type === 'OVERHEATING')).toBe(true);
    const w = warnings.find((w) => w.type === 'OVERHEATING')!;
    expect(w.data.triggerValues.rise).toBeGreaterThanOrEqual(1.0);
  });

  it('does NOT fire on rapid rise < 1 °C', () => {
    // Both readings below 38.5 °C (no absolute threshold) and rise only 0.8 °C.
    const base = hoursAgo(3);
    insertReadings(db, userId, [
      { timestamp: base, heart_rate: 140, temp_site1: 37.2, activity: 'active' },
      { timestamp: base + 20 * 60_000, heart_rate: 145, temp_site1: 38.0, activity: 'active' },
    ]);

    const warnings = computeWarnings(userId, db);
    expect(warnings.every((w) => w.type !== 'OVERHEATING')).toBe(true);
  });

  it('does not duplicate an existing unresolved OVERHEATING warning', () => {
    insertReadings(db, userId, [
      { timestamp: hoursAgo(5), heart_rate: 150, temp_site1: 39.1, activity: 'active' },
    ]);
    computeWarnings(userId, db); // first call inserts it

    insertReadings(db, userId, [
      { timestamp: hoursAgo(3), heart_rate: 152, temp_site1: 39.3, activity: 'active' },
    ]);
    const second = computeWarnings(userId, db);
    expect(second.every((w) => w.type !== 'OVERHEATING')).toBe(true);
  });
});

// ─── GETTING_SICK ─────────────────────────────────────────────────────────────

describe('GETTING_SICK rule', () => {
  it('fires when resting HR is elevated ≥5 bpm above baseline for 2+ consecutive days', () => {
    // Baseline: 28 days of readings ending 8 days ago (resting HR 62 bpm)
    insertReadings(db, userId, normalBaseline(userId));

    // Recent 7 days: elevated HR on last 3 consecutive days
    for (let d = 3; d >= 1; d--) {
      for (let h = 0; h < 3; h++) {
        insertReadings(db, userId, [
          {
            timestamp: daysAgo(d) + h * H,
            heart_rate: 70, // 62 + 8 = well above +5 threshold
            rr_intervals: makeRR(70, 45),
            temp_site1: 36.5,
            activity: 'rest',
          },
        ]);
      }
    }

    const warnings = computeWarnings(userId, db);
    expect(warnings.some((w) => w.type === 'GETTING_SICK')).toBe(true);
    const w = warnings.find((w) => w.type === 'GETTING_SICK')!;
    expect(w.data.baselineValues.restingHR).toBeCloseTo(62, 0);
    expect(w.data.triggerValues.restingHR).toBeGreaterThan(62 + 5);
  });

  it('fires when resting temp is elevated ≥0.3 °C above baseline for 2+ consecutive days', () => {
    insertReadings(db, userId, normalBaseline(userId));

    for (let d = 2; d >= 1; d--) {
      for (let h = 0; h < 3; h++) {
        insertReadings(db, userId, [
          {
            timestamp: daysAgo(d) + h * H,
            heart_rate: 62,
            rr_intervals: makeRR(62, 55),
            temp_site1: 36.9, // 36.5 + 0.4 = above +0.3 threshold
            activity: 'rest',
          },
        ]);
      }
    }

    const warnings = computeWarnings(userId, db);
    expect(warnings.some((w) => w.type === 'GETTING_SICK')).toBe(true);
  });

  it('does NOT fire when only 1 elevated day', () => {
    insertReadings(db, userId, normalBaseline(userId));

    // Three readings for the same calendar day (minute-level offsets avoid
    // accidentally crossing UTC midnight which would create a second day bucket).
    const base = daysAgo(2); // comfortably within the 7-day recent window
    for (let m = 0; m < 3; m++) {
      insertReadings(db, userId, [
        {
          timestamp: base + m * 60_000,
          heart_rate: 75,
          rr_intervals: makeRR(75, 40),
          temp_site1: 36.5,
          activity: 'rest',
        },
      ]);
    }

    const warnings = computeWarnings(userId, db);
    expect(warnings.every((w) => w.type !== 'GETTING_SICK')).toBe(true);
  });

  it('does NOT fire with insufficient baseline data', () => {
    // Only 2 baseline readings — below the 10-reading minimum
    insertReadings(db, userId, [
      { timestamp: daysAgo(20), heart_rate: 62, temp_site1: 36.5, activity: 'rest' },
      { timestamp: daysAgo(18), heart_rate: 63, temp_site1: 36.5, activity: 'rest' },
    ]);

    for (let d = 3; d >= 1; d--) {
      insertReadings(db, userId, [
        { timestamp: daysAgo(d), heart_rate: 75, temp_site1: 37.0, activity: 'rest' },
      ]);
    }

    const warnings = computeWarnings(userId, db);
    expect(warnings.every((w) => w.type !== 'GETTING_SICK')).toBe(true);
  });
});

// ─── FATIGUE_RECOVERY ──────────────────────────────────────────────────────────

describe('FATIGUE_RECOVERY rule', () => {
  it('fires when HR is ≥8% above baseline AND RMSSD ≤80% of baseline for 2+ consecutive days', () => {
    // Baseline: HR ~62, RMSSD ~60 ms
    insertReadings(db, userId, normalBaseline(userId));

    // Recent 2 days: elevated HR + very low HRV
    for (let d = 2; d >= 1; d--) {
      for (let h = 0; h < 3; h++) {
        insertReadings(db, userId, [
          {
            timestamp: daysAgo(d) + h * H,
            heart_rate: 70, // ~13% above 62 — above 8% threshold
            rr_intervals: makeRR(70, 12), // RMSSD ~12 — well below 80% of ~60
            temp_site1: 36.6,
            activity: 'rest',
          },
        ]);
      }
    }

    const warnings = computeWarnings(userId, db);
    expect(warnings.some((w) => w.type === 'FATIGUE_RECOVERY')).toBe(true);
    const w = warnings.find((w) => w.type === 'FATIGUE_RECOVERY')!;
    expect(w.data.triggerValues.restingHR).toBeGreaterThan(w.data.baselineValues.restingHR * 1.08);
    expect(w.data.triggerValues.hrv).toBeLessThanOrEqual(w.data.baselineValues.hrv * 0.8);
  });

  it('does NOT fire when only HR is elevated but HRV is normal', () => {
    insertReadings(db, userId, normalBaseline(userId));

    for (let d = 2; d >= 1; d--) {
      for (let h = 0; h < 3; h++) {
        insertReadings(db, userId, [
          {
            timestamp: daysAgo(d) + h * H,
            heart_rate: 70, // elevated HR
            rr_intervals: makeRR(70, 60), // but normal RMSSD
            temp_site1: 36.6,
            activity: 'rest',
          },
        ]);
      }
    }

    const warnings = computeWarnings(userId, db);
    expect(warnings.every((w) => w.type !== 'FATIGUE_RECOVERY')).toBe(true);
  });

  it('does NOT fire when only HRV is suppressed but HR is normal', () => {
    insertReadings(db, userId, normalBaseline(userId));

    for (let d = 2; d >= 1; d--) {
      for (let h = 0; h < 3; h++) {
        insertReadings(db, userId, [
          {
            timestamp: daysAgo(d) + h * H,
            heart_rate: 62, // normal HR
            rr_intervals: makeRR(62, 10), // suppressed HRV
            temp_site1: 36.5,
            activity: 'rest',
          },
        ]);
      }
    }

    const warnings = computeWarnings(userId, db);
    expect(warnings.every((w) => w.type !== 'FATIGUE_RECOVERY')).toBe(true);
  });

  it('does NOT fire with insufficient baseline data', () => {
    for (let d = 3; d >= 1; d--) {
      insertReadings(db, userId, [
        {
          timestamp: daysAgo(d),
          heart_rate: 75,
          rr_intervals: makeRR(75, 10),
          temp_site1: 36.6,
          activity: 'rest',
        },
      ]);
    }

    const warnings = computeWarnings(userId, db);
    expect(warnings.every((w) => w.type !== 'FATIGUE_RECOVERY')).toBe(true);
  });
});

// ─── computeWarnings: general behaviour ───────────────────────────────────────

describe('computeWarnings general', () => {
  it('returns [] gracefully when there are no readings', () => {
    const warnings = computeWarnings(userId, db);
    expect(warnings).toEqual([]);
  });

  it('persists warnings to the database', () => {
    insertReadings(db, userId, [
      { timestamp: hoursAgo(5), heart_rate: 150, temp_site1: 39.5, activity: 'active' },
    ]);

    const warnings = computeWarnings(userId, db);
    expect(warnings.length).toBeGreaterThan(0);

    const stored = db
      .prepare('SELECT * FROM warnings WHERE user_id = ?')
      .all(userId) as Array<{ type: string }>;
    expect(stored.some((w) => w.type === 'OVERHEATING')).toBe(true);
  });
});

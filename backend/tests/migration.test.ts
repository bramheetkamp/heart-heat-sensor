/**
 * Migration tests — createDatabase() must upgrade a database created before the
 * `eda` column existed, without losing data, and be safe to run repeatedly.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import Database from 'better-sqlite3';
import { createDatabase } from '../src/db/index.js';
import { mkdtempSync, rmSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';

let tmpDir: string;
let dbPath: string;

beforeEach(() => {
  tmpDir = mkdtempSync(join(tmpdir(), 'heartrate-migrate-'));
  dbPath = join(tmpDir, 'legacy.db');
});

afterEach(() => {
  rmSync(tmpDir, { recursive: true, force: true });
});

/** Build a pre-eda readings table and insert one legacy row. */
function seedLegacyDb(): void {
  const db = new Database(dbPath);
  db.exec(`
    CREATE TABLE readings (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      device_id TEXT NOT NULL,
      timestamp INTEGER NOT NULL,
      heart_rate INTEGER,
      rr_intervals TEXT NOT NULL DEFAULT '[]',
      temp_site1 REAL,
      temp_site2 REAL,
      activity TEXT,
      created_at INTEGER NOT NULL
    );
  `);
  db.prepare(
    `INSERT INTO readings (id, user_id, device_id, timestamp, heart_rate, rr_intervals, temp_site1, temp_site2, activity, created_at)
     VALUES ('r1', 'u1', 'dev', 1000, 60, '[]', 36.6, 36.2, 'rest', 1000)`
  ).run();
  db.close();
}

describe('createDatabase migration', () => {
  it('adds the eda column to a legacy readings table and preserves rows', () => {
    seedLegacyDb();
    const db = createDatabase(dbPath);

    const cols = db.prepare(`PRAGMA table_info(readings)`).all() as { name: string }[];
    expect(cols.some((c) => c.name === 'eda')).toBe(true);

    const row = db.prepare(`SELECT * FROM readings WHERE id = 'r1'`).get() as { eda: number | null; heart_rate: number };
    expect(row.heart_rate).toBe(60); // existing data intact
    expect(row.eda).toBeNull();      // new column defaults to NULL
    db.close();
  });

  it('is idempotent — running twice does not throw or duplicate the column', () => {
    seedLegacyDb();
    createDatabase(dbPath).close();
    const db = createDatabase(dbPath); // second run
    const edaCols = (db.prepare(`PRAGMA table_info(readings)`).all() as { name: string }[])
      .filter((c) => c.name === 'eda');
    expect(edaCols.length).toBe(1);
    db.close();
  });
});

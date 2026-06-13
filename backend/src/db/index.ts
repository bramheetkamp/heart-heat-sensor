import Database from 'better-sqlite3';
import { mkdirSync } from 'fs';
import { dirname } from 'path';

export type DB = Database.Database;

export function createDatabase(dbPath: string): DB {
  mkdirSync(dirname(dbPath), { recursive: true });

  const db = new Database(dbPath);
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');

  db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      email TEXT UNIQUE NOT NULL,
      password_hash TEXT,
      apple_sub TEXT UNIQUE,
      created_at INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS readings (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      device_id TEXT NOT NULL,
      timestamp INTEGER NOT NULL,
      heart_rate INTEGER,
      rr_intervals TEXT NOT NULL DEFAULT '[]',
      temp_site1 REAL,
      temp_site2 REAL,
      activity TEXT,
      created_at INTEGER NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_readings_user_timestamp ON readings(user_id, timestamp);

    CREATE TABLE IF NOT EXISTS warnings (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      type TEXT NOT NULL,
      fired_at INTEGER NOT NULL,
      resolved_at INTEGER,
      title TEXT NOT NULL,
      message TEXT NOT NULL,
      data TEXT NOT NULL,
      created_at INTEGER NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_warnings_user ON warnings(user_id, fired_at);
  `);

  return db;
}

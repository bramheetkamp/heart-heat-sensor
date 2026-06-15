/**
 * Seed script for heartrate-backend
 *
 * Generates 35 days of realistic sensor readings for a test user and runs
 * computeWarnings() to produce warning records.  Data is deterministic via a
 * simple seeded PRNG (mulberry32).
 *
 * Run with:  npm run seed
 */

import bcrypt from 'bcryptjs';
import { v4 as uuidv4 } from 'uuid';
import { createDatabase } from './src/db/index.js';
import { computeWarnings } from './src/services/warningsEngine.js';

// ─── PRNG (mulberry32) ────────────────────────────────────────────────────────
function mulberry32(seed: number) {
  return function (): number {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let z = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    z = (z ^ ((z + Math.imul(z ^ (z >>> 7), 61 | z)) >>> 3)) >>> 0;
    return (z ^ (z >>> 14)) / 4294967296;
  };
}

const rand = mulberry32(0xdeadbeef);

function randBetween(lo: number, hi: number): number {
  return lo + rand() * (hi - lo);
}

function randInt(lo: number, hi: number): number {
  return Math.round(randBetween(lo, hi));
}

// ─── RR-interval generation ───────────────────────────────────────────────────
/**
 * Generate `count` RR intervals (ms) with a given mean and a specified RMSSD.
 * We build the array so that successive differences have the right scale.
 */
function generateRR(meanHR: number, targetRmssd: number, count = 30): number[] {
  const meanRR = (60 / meanHR) * 1000; // ms per beat
  const rr: number[] = [meanRR + randBetween(-10, 10)];
  for (let i = 1; i < count; i++) {
    // Each successive difference is drawn from N(0, targetRmssd)
    const diff = (rand() - 0.5) * 2 * targetRmssd * 1.25;
    rr.push(Math.max(300, rr[i - 1] + diff));
  }
  return rr.map((v) => Math.round(v));
}

// ─── DB setup ─────────────────────────────────────────────────────────────────
const dbPath = process.env.DATABASE_PATH ?? './data/heartrate.db';
const db = createDatabase(dbPath);

// ─── Wipe old seed data ───────────────────────────────────────────────────────
const testEmail = 'test@example.com';
const existing = db.prepare('SELECT id FROM users WHERE email = ?').get(testEmail) as
  | { id: string }
  | undefined;

if (existing) {
  db.prepare('DELETE FROM readings WHERE user_id = ?').run(existing.id);
  db.prepare('DELETE FROM warnings WHERE user_id = ?').run(existing.id);
  db.prepare('DELETE FROM users WHERE id = ?').run(existing.id);
  console.log('Cleared existing test user data.');
}

// ─── Create test user ─────────────────────────────────────────────────────────
const userId = uuidv4();
const passwordHash = await bcrypt.hash('password123', 12);
const userCreatedAt = Date.now();

db.prepare(
  'INSERT INTO users (id, email, password_hash, apple_sub, created_at) VALUES (?, ?, ?, NULL, ?)'
).run(userId, testEmail, passwordHash, userCreatedAt);

console.log(`Created user: ${testEmail} (id: ${userId})`);

// ─── Generate readings ────────────────────────────────────────────────────────
const DEVICE_ID = 'seed-device-001';
const NOW = Date.now();
const TOTAL_DAYS = 35;
const READINGS_PER_DAY = 24; // one per hour

const insertReading = db.prepare(`
  INSERT INTO readings (id, user_id, device_id, timestamp, heart_rate, rr_intervals,
                        temp_site1, temp_site2, eda, activity, created_at)
  VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
`);

const insertAll = db.transaction(() => {
  let totalInserted = 0;

  for (let dayIndex = 0; dayIndex < TOTAL_DAYS; dayIndex++) {
    // dayIndex 0 = 35 days ago, dayIndex 34 = today
    const dayOffset = TOTAL_DAYS - 1 - dayIndex; // days ago
    const dayStart = NOW - dayOffset * 24 * 60 * 60 * 1000;

    for (let hour = 0; hour < READINGS_PER_DAY; hour++) {
      const timestamp = dayStart + hour * 60 * 60 * 1000;
      const created_at = NOW;

      // ── Circadian rhythm factor (lower at night, higher mid-day) ──────────
      const circadian = Math.sin(((hour - 6) / 24) * 2 * Math.PI); // peak ~noon

      let heartRate: number;
      let rrIntervals: number[];
      let tempSite1: number;
      let tempSite2: number;
      let activity: string;
      let rmssdTarget: number;

      if (dayIndex <= 27) {
        // ── Days 1–28: Normal ─────────────────────────────────────────────
        // Sleep hours (0-6, 22-23), workout windows at hours 7-8 and 17-18
        const isSleep = hour < 6 || hour >= 22;
        const isWorkout = hour === 7 || hour === 8 || hour === 17 || hour === 18;

        if (isWorkout && rand() < 0.6) {
          activity = 'active';
          heartRate = randInt(120, 160);
          rmssdTarget = randBetween(15, 30);
          tempSite1 = 36.8 + circadian * 0.3 + randBetween(0.0, 0.4);
          tempSite2 = tempSite1 - randBetween(0.2, 0.5);
        } else if (isSleep) {
          activity = 'sleep';
          heartRate = randInt(50, 62);
          rmssdTarget = randBetween(55, 90);
          tempSite1 = 36.4 + randBetween(-0.1, 0.1);
          tempSite2 = tempSite1 - randBetween(0.3, 0.5);
        } else {
          activity = 'rest';
          heartRate = randInt(55, 75) + Math.round(circadian * 5);
          rmssdTarget = randBetween(40, 70);
          tempSite1 = 36.5 + circadian * 0.2 + randBetween(-0.1, 0.1);
          tempSite2 = tempSite1 - randBetween(0.2, 0.4);
        }
      } else if (dayIndex <= 30) {
        // ── Days 29–31: Getting sick (rising HR +3 bpm/day, temp +0.15°C/day) ──
        const sickDay = dayIndex - 28; // 1, 2, 3
        const isSleep = hour < 6 || hour >= 22;

        activity = isSleep ? 'sleep' : 'rest';
        heartRate =
          randInt(58, 78) + Math.round(circadian * 5) + sickDay * 3;
        rmssdTarget = randBetween(35, 55);
        tempSite1 = 36.5 + circadian * 0.2 + sickDay * 0.15 + randBetween(-0.05, 0.05);
        tempSite2 = tempSite1 - randBetween(0.2, 0.4);
      } else if (dayIndex <= 32) {
        // ── Days 32–33: Overheating workout ──────────────────────────────
        const isOverheatHour = hour === 10 || hour === 11;
        const isSleep = hour < 6 || hour >= 22;

        if (isOverheatHour) {
          activity = 'active';
          heartRate = randInt(140, 165);
          rmssdTarget = randBetween(12, 20);
          tempSite1 = 39.1 + randBetween(-0.1, 0.1); // fever-level during workout
          tempSite2 = tempSite1 - randBetween(0.3, 0.6);
        } else if (isSleep) {
          activity = 'sleep';
          heartRate = randInt(50, 65);
          rmssdTarget = randBetween(50, 80);
          tempSite1 = 36.6 + randBetween(-0.1, 0.1);
          tempSite2 = tempSite1 - randBetween(0.3, 0.5);
        } else {
          activity = 'rest';
          heartRate = randInt(60, 78) + Math.round(circadian * 5);
          rmssdTarget = randBetween(38, 58);
          tempSite1 = 36.7 + circadian * 0.2 + randBetween(-0.1, 0.1);
          tempSite2 = tempSite1 - randBetween(0.2, 0.4);
        }
      } else {
        // ── Days 34–35: Poor recovery — elevated resting HR + very low HRV ──
        const isSleep = hour < 6 || hour >= 22;
        activity = isSleep ? 'sleep' : 'rest';
        // ~8-10% above the 30-day baseline of ~65 bpm
        heartRate = randInt(70, 80) + Math.round(circadian * 3);
        // Severely depressed HRV
        rmssdTarget = randBetween(10, 18);
        tempSite1 = 36.8 + circadian * 0.15 + randBetween(-0.05, 0.05);
        tempSite2 = tempSite1 - randBetween(0.2, 0.4);
      }

      rrIntervals = generateRR(heartRate, rmssdTarget);

      // EDA (skin conductance, µS): rises with sympathetic arousal — exertion,
      // early illness, and poor recovery all push it up.
      const edaBase = activity === 'active' ? randBetween(9, 14) : randBetween(4, 6.5);
      const edaIllnessBump = dayIndex > 27 && dayIndex <= 30 ? randBetween(1.5, 3) : 0;
      const edaFatigueBump = dayIndex >= 33 ? randBetween(2.5, 4) : 0;
      const eda = Math.round((edaBase + edaIllnessBump + edaFatigueBump) * 100) / 100;

      insertReading.run(
        uuidv4(),
        userId,
        DEVICE_ID,
        timestamp,
        heartRate,
        JSON.stringify(rrIntervals),
        Math.round(tempSite1 * 100) / 100,
        Math.round(tempSite2 * 100) / 100,
        eda,
        activity,
        created_at
      );

      totalInserted++;
    }
  }

  return totalInserted;
});

const inserted = insertAll();
console.log(`Inserted ${inserted} readings across ${TOTAL_DAYS} days.`);

// ─── Run warnings engine ──────────────────────────────────────────────────────
console.log('\nRunning warnings engine...');
const warnings = computeWarnings(userId, db);

if (warnings.length === 0) {
  console.log('No new warnings generated (rules may not have found enough data or thresholds not crossed).');
} else {
  console.log(`Generated ${warnings.length} warning(s):`);
  for (const w of warnings) {
    const date = new Date(w.fired_at).toISOString();
    console.log(`  [${w.type}] "${w.title}" — fired at ${date}`);
  }
}

// ─── Summary ─────────────────────────────────────────────────────────────────
const readingCount = (
  db.prepare('SELECT COUNT(*) as c FROM readings WHERE user_id = ?').get(userId) as { c: number }
).c;

const warningCount = (
  db.prepare('SELECT COUNT(*) as c FROM warnings WHERE user_id = ?').get(userId) as { c: number }
).c;

console.log('\n── Seed summary ──────────────────────────────────────────────');
console.log(`  User       : ${testEmail} / password123`);
console.log(`  User ID    : ${userId}`);
console.log(`  Readings   : ${readingCount}`);
console.log(`  Warnings   : ${warningCount}`);
console.log(`  DB path    : ${dbPath}`);
console.log('──────────────────────────────────────────────────────────────\n');

db.close();

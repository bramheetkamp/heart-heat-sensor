import type Database from 'better-sqlite3';
import { v4 as uuidv4 } from 'uuid';
import type { Warning, WarningType, WarningData } from '../types.js';

// ─── helpers ─────────────────────────────────────────────────────────────────

/** Compute RMSSD (root mean square of successive differences) from RR intervals (ms). */
function rmssd(rr: number[]): number {
  if (rr.length < 2) return 0;
  let sumSq = 0;
  for (let i = 1; i < rr.length; i++) {
    const diff = rr[i] - rr[i - 1];
    sumSq += diff * diff;
  }
  return Math.sqrt(sumSq / (rr.length - 1));
}

function mean(values: number[]): number {
  if (values.length === 0) return 0;
  return values.reduce((a, b) => a + b, 0) / values.length;
}

/** Group readings into UTC calendar days (ms buckets). Returns Map<dayKey, readings[]>. */
function groupByDay(readings: DbReading[]): Map<string, DbReading[]> {
  const map = new Map<string, DbReading[]>();
  for (const r of readings) {
    const d = new Date(r.timestamp);
    const key = `${d.getUTCFullYear()}-${d.getUTCMonth()}-${d.getUTCDate()}`;
    const bucket = map.get(key) ?? [];
    bucket.push(r);
    map.set(key, bucket);
  }
  return map;
}

// ─── DB row type ─────────────────────────────────────────────────────────────

interface DbReading {
  id: string;
  user_id: string;
  device_id: string;
  timestamp: number;
  heart_rate: number | null;
  rr_intervals: string; // JSON
  temp_site1: number | null;
  temp_site2: number | null;
  eda: number | null;
  activity: string | null;
  created_at: number;
}

/** Mean of a column over rows where it is present and positive; null if none. */
function meanEda(rows: DbReading[]): number | null {
  const vals = rows.map((r) => r.eda).filter((v): v is number => v != null && v > 0);
  return vals.length === 0 ? null : mean(vals);
}

interface DbWarning {
  id: string;
  user_id: string;
  type: string;
  fired_at: number | null;
  resolved_at: number | null;
  title: string;
  message: string;
  data: string;
  created_at: number;
}

// ─── insert helper ────────────────────────────────────────────────────────────

function insertWarning(
  db: Database.Database,
  userId: string,
  type: WarningType,
  title: string,
  message: string,
  data: WarningData,
  firedAt: number
): Warning {
  const id = uuidv4();
  const now = Date.now();
  db.prepare(`
    INSERT INTO warnings (id, user_id, type, fired_at, resolved_at, title, message, data, created_at)
    VALUES (?, ?, ?, ?, NULL, ?, ?, ?, ?)
  `).run(id, userId, type, firedAt, title, message, JSON.stringify(data), now);

  return {
    id,
    user_id: userId,
    type,
    fired_at: firedAt,
    resolved_at: null,
    title,
    message,
    data,
    created_at: now,
  };
}

/** Return true if an unresolved warning of this type already exists for the user. */
function hasUnresolved(db: Database.Database, userId: string, type: WarningType): boolean {
  const row = db
    .prepare('SELECT id FROM warnings WHERE user_id = ? AND type = ? AND resolved_at IS NULL')
    .get(userId, type);
  return row !== undefined;
}

// ─── Rule 1: OVERHEATING ──────────────────────────────────────────────────────

function checkOverheating(
  db: Database.Database,
  userId: string,
  readings: DbReading[]
): Warning | null {
  if (hasUnresolved(db, userId, 'OVERHEATING')) return null;

  const now = Date.now();
  // 48 h window: catches yesterday's overheating workout without triggering on
  // distant historical events; aligns with the seed data (overheat readings
  // land ~37 h in the past).
  const cutoff = now - 48 * 60 * 60 * 1000;
  const recent = readings.filter((r) => r.timestamp >= cutoff && r.temp_site1 !== null);

  if (recent.length === 0) return null;

  // Check absolute threshold
  const hotReading = recent.find((r) => (r.temp_site1 ?? 0) > 38.5);
  if (hotReading) {
    return insertWarning(
      db,
      userId,
      'OVERHEATING',
      'Overheating Detected',
      `Core temperature reached ${hotReading.temp_site1?.toFixed(1)}°C, exceeding the safe threshold of 38.5°C.`,
      {
        triggerValues: { temp_site1: hotReading.temp_site1! },
        baselineValues: { threshold: 38.5 },
        trend: recent.map((r) => r.temp_site1 ?? 0),
      },
      hotReading.timestamp
    );
  }

  // Check 1°C rise in a 30-minute window during active readings
  const WINDOW_MS = 30 * 60 * 1000;
  const active = recent
    .filter((r) => r.activity === 'active' && r.temp_site1 !== null)
    .sort((a, b) => a.timestamp - b.timestamp);

  for (let i = 0; i < active.length; i++) {
    const base = active[i].temp_site1!;
    for (let j = i + 1; j < active.length; j++) {
      if (active[j].timestamp - active[i].timestamp > WINDOW_MS) break;
      const rise = active[j].temp_site1! - base;
      if (rise >= 1.0) {
        return insertWarning(
          db,
          userId,
          'OVERHEATING',
          'Rapid Temperature Rise During Activity',
          `Core temperature rose ${rise.toFixed(1)}°C in under 30 minutes during active use.`,
          {
            triggerValues: {
              temp_start: base,
              temp_end: active[j].temp_site1!,
              rise,
            },
            baselineValues: { maxRiseIn30min: 1.0 },
            trend: active
              .filter(
                (r) =>
                  r.timestamp >= active[i].timestamp &&
                  r.timestamp <= active[j].timestamp
              )
              .map((r) => r.temp_site1 ?? 0),
          },
          active[j].timestamp
        );
      }
    }
  }

  return null;
}

// ─── Rule 2: GETTING_SICK ─────────────────────────────────────────────────────

function checkGettingSick(
  db: Database.Database,
  userId: string,
  readings: DbReading[]
): Warning | null {
  if (hasUnresolved(db, userId, 'GETTING_SICK')) return null;

  const now = Date.now();
  const day7cutoff = now - 7 * 24 * 60 * 60 * 1000;
  const day30cutoff = now - 30 * 24 * 60 * 60 * 1000;

  const baseline30 = readings.filter(
    (r) => r.timestamp >= day30cutoff && r.timestamp < day7cutoff && r.activity === 'rest'
  );
  if (baseline30.length < 10) return null;

  const baselineHR = mean(baseline30.map((r) => r.heart_rate ?? 0).filter((v) => v > 0));
  const baselineTemp = mean(
    baseline30.map((r) => r.temp_site1 ?? 0).filter((v) => v > 0)
  );
  if (baselineHR === 0 || baselineTemp === 0) return null;

  // Compare daily resting values over the last 7 days
  const recent7 = readings.filter((r) => r.timestamp >= day7cutoff && r.activity === 'rest');
  if (recent7.length === 0) return null;

  const byDay = groupByDay(recent7);
  const sortedDays = Array.from(byDay.keys()).sort();

  let consecutiveDaysElevated = 0;
  let lastDayHR = 0;
  let lastDayTemp = 0;
  let triggerDay: string | null = null;

  for (const day of sortedDays) {
    const dayReadings = byDay.get(day)!;
    const dayHR = mean(dayReadings.map((r) => r.heart_rate ?? 0).filter((v) => v > 0));
    const dayTemp = mean(
      dayReadings.map((r) => r.temp_site1 ?? 0).filter((v) => v > 0)
    );

    const hrElevated = dayHR > 0 && dayHR >= baselineHR + 5;
    const tempElevated = dayTemp > 0 && dayTemp >= baselineTemp + 0.3;

    if (hrElevated || tempElevated) {
      consecutiveDaysElevated++;
      lastDayHR = dayHR;
      lastDayTemp = dayTemp;
      if (consecutiveDaysElevated >= 2 && triggerDay === null) {
        triggerDay = day;
      }
    } else {
      consecutiveDaysElevated = 0;
    }
  }

  if (triggerDay === null) return null;

  // EDA is a corroborating signal when present (BodyTempSensor); HR-only
  // devices leave it absent and behave exactly as before.
  const triggerValues: Record<string, number> = { restingHR: lastDayHR, temp_site1: lastDayTemp };
  const baselineValues: Record<string, number> = { restingHR: baselineHR, temp_site1: baselineTemp };
  const baselineEda = meanEda(baseline30);
  const recentEda = meanEda(recent7);
  if (baselineEda !== null && recentEda !== null) {
    triggerValues.eda = recentEda;
    baselineValues.eda = baselineEda;
  }

  return insertWarning(
    db,
    userId,
    'GETTING_SICK',
    'Possible Illness Developing',
    `Your resting heart rate (${lastDayHR.toFixed(0)} bpm) and/or temperature (${lastDayTemp.toFixed(2)}°C) have been elevated above your personal baseline for 2+ consecutive days.`,
    {
      triggerValues,
      baselineValues,
      trend: sortedDays.map((d) => {
        const dr = byDay.get(d)!;
        return mean(dr.map((r) => r.heart_rate ?? 0).filter((v) => v > 0));
      }),
    },
    now
  );
}

// ─── Rule 3: FATIGUE_RECOVERY ─────────────────────────────────────────────────

function checkFatigueRecovery(
  db: Database.Database,
  userId: string,
  readings: DbReading[]
): Warning | null {
  if (hasUnresolved(db, userId, 'FATIGUE_RECOVERY')) return null;

  const now = Date.now();
  const day7cutoff = now - 7 * 24 * 60 * 60 * 1000;
  const day30cutoff = now - 30 * 24 * 60 * 60 * 1000;

  // Build 30-day baseline (resting, excluding last 7 days)
  const baseline30 = readings.filter(
    (r) => r.timestamp >= day30cutoff && r.timestamp < day7cutoff && r.activity === 'rest'
  );
  if (baseline30.length < 10) return null;

  const baselineHR = mean(baseline30.map((r) => r.heart_rate ?? 0).filter((v) => v > 0));

  const baselineHRVs = baseline30
    .map((r) => {
      const rr = JSON.parse(r.rr_intervals) as number[];
      return rmssd(rr);
    })
    .filter((v) => v > 0);
  const baselineHRV = mean(baselineHRVs);

  if (baselineHR === 0 || baselineHRV === 0) return null;

  // Evaluate recent 7-day daily values
  const recent7 = readings.filter((r) => r.timestamp >= day7cutoff && r.activity === 'rest');
  if (recent7.length === 0) return null;

  const byDay = groupByDay(recent7);
  const sortedDays = Array.from(byDay.keys()).sort();

  let consecutiveDaysFatigued = 0;
  let lastDayHR = 0;
  let lastDayHRV = 0;
  let triggerDay: string | null = null;

  for (const day of sortedDays) {
    const dayReadings = byDay.get(day)!;
    const dayHR = mean(dayReadings.map((r) => r.heart_rate ?? 0).filter((v) => v > 0));
    const dayHRVs = dayReadings
      .map((r) => {
        const rr = JSON.parse(r.rr_intervals) as number[];
        return rmssd(rr);
      })
      .filter((v) => v > 0);
    const dayHRV = mean(dayHRVs);

    const hrElevated = dayHR > 0 && dayHR >= baselineHR * 1.08;
    const hrvDepressed = dayHRV > 0 && dayHRV <= baselineHRV * 0.8;

    if (hrElevated && hrvDepressed) {
      consecutiveDaysFatigued++;
      lastDayHR = dayHR;
      lastDayHRV = dayHRV;
      if (consecutiveDaysFatigued >= 2 && triggerDay === null) {
        triggerDay = day;
      }
    } else {
      consecutiveDaysFatigued = 0;
    }
  }

  if (triggerDay === null) return null;

  const triggerValues: Record<string, number> = { restingHR: lastDayHR, hrv: lastDayHRV };
  const baselineValues: Record<string, number> = { restingHR: baselineHR, hrv: baselineHRV };
  const baselineEda = meanEda(baseline30);
  const recentEda = meanEda(recent7);
  if (baselineEda !== null && recentEda !== null) {
    triggerValues.eda = recentEda;
    baselineValues.eda = baselineEda;
  }

  return insertWarning(
    db,
    userId,
    'FATIGUE_RECOVERY',
    'Poor Recovery / Fatigue Detected',
    `Your resting heart rate is elevated (${lastDayHR.toFixed(0)} bpm, +8% above baseline) and HRV is suppressed (${lastDayHRV.toFixed(1)} ms, ≤80% of baseline) for 2+ consecutive days. Consider extra rest.`,
    {
      triggerValues,
      baselineValues,
      trend: sortedDays.map((d) => {
        const dr = byDay.get(d)!;
        return mean(dr.map((r) => r.heart_rate ?? 0).filter((v) => v > 0));
      }),
    },
    now
  );
}

// ─── public API ───────────────────────────────────────────────────────────────

/**
 * Compute all applicable warnings for a user and persist them.
 * Returns only the newly inserted warnings.
 * Gracefully returns [] if there is insufficient data.
 */
export function computeWarnings(userId: string, db: Database.Database): Warning[] {
  try {
    // Load all readings for the user (up to 60 days is sufficient)
    const cutoff = Date.now() - 60 * 24 * 60 * 60 * 1000;
    const readings = db
      .prepare(
        'SELECT * FROM readings WHERE user_id = ? AND timestamp >= ? ORDER BY timestamp ASC'
      )
      .all(userId, cutoff) as DbReading[];

    if (readings.length === 0) return [];

    const results: Warning[] = [];

    const overheating = checkOverheating(db, userId, readings);
    if (overheating) results.push(overheating);

    const gettingSick = checkGettingSick(db, userId, readings);
    if (gettingSick) results.push(gettingSick);

    const fatigue = checkFatigueRecovery(db, userId, readings);
    if (fatigue) results.push(fatigue);

    return results;
  } catch (err) {
    // Never crash the request; log and return empty
    console.error('[warningsEngine] Error computing warnings:', err);
    return [];
  }
}

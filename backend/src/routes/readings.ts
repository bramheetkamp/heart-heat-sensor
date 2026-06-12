import { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { v4 as uuidv4 } from 'uuid';
import type { Reading } from '../types.js';

const readingSchema = z.object({
  id: z.string().uuid().optional(),
  device_id: z.string().min(1),
  timestamp: z.number().int().positive(),
  heart_rate: z.number().int().positive().nullable().optional(),
  rr_intervals: z.array(z.number().positive()).optional().default([]),
  temp_site1: z.number().nullable().optional(),
  temp_site2: z.number().nullable().optional(),
  activity: z.enum(['rest', 'active', 'sleep']).nullable().optional(),
});

const batchSchema = z.object({
  readings: z.array(readingSchema).min(1).max(1000),
});

const querySchema = z.object({
  from: z.coerce.number().int().optional(),
  to: z.coerce.number().int().optional(),
  limit: z.coerce.number().int().min(1).max(5000).optional().default(500),
});

interface DbReading {
  id: string;
  user_id: string;
  device_id: string;
  timestamp: number;
  heart_rate: number | null;
  rr_intervals: string;
  temp_site1: number | null;
  temp_site2: number | null;
  activity: string | null;
  created_at: number;
}

function dbRowToReading(row: DbReading): Reading {
  return {
    id: row.id,
    user_id: row.user_id,
    device_id: row.device_id,
    timestamp: row.timestamp,
    heart_rate: row.heart_rate,
    rr_intervals: JSON.parse(row.rr_intervals) as number[],
    temp_site1: row.temp_site1,
    temp_site2: row.temp_site2,
    activity: row.activity,
    created_at: row.created_at,
  };
}

const readingsRoutes: FastifyPluginAsync = async (fastify) => {
  const db = fastify.db;

  fastify.addHook('preHandler', async (request, reply) => {
    try {
      await request.jwtVerify();
    } catch {
      return reply.status(401).send({ error: 'Unauthorized' });
    }
  });

  fastify.post('/batch', async (request, reply) => {
    const parsed = batchSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'Validation failed', details: parsed.error.flatten() });
    }

    const userId = (request.user as { userId: string }).userId;
    const now = Date.now();

    const upsert = db.prepare(`
      INSERT INTO readings (id, user_id, device_id, timestamp, heart_rate, rr_intervals, temp_site1, temp_site2, activity, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        device_id = excluded.device_id,
        timestamp = excluded.timestamp,
        heart_rate = excluded.heart_rate,
        rr_intervals = excluded.rr_intervals,
        temp_site1 = excluded.temp_site1,
        temp_site2 = excluded.temp_site2,
        activity = excluded.activity
    `);

    const insertMany = db.transaction((readings: z.infer<typeof batchSchema>['readings']) => {
      let count = 0;
      for (const r of readings) {
        const id = r.id ?? uuidv4();
        upsert.run(
          id, userId, r.device_id, r.timestamp,
          r.heart_rate ?? null,
          JSON.stringify(r.rr_intervals ?? []),
          r.temp_site1 ?? null,
          r.temp_site2 ?? null,
          r.activity ?? null,
          now
        );
        count++;
      }
      return count;
    });

    const inserted = insertMany(parsed.data.readings);
    return reply.status(201).send({ inserted });
  });

  fastify.get('/', async (request, reply) => {
    const parsed = querySchema.safeParse(request.query);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'Invalid query params', details: parsed.error.flatten() });
    }

    const userId = (request.user as { userId: string }).userId;
    const { from, to, limit } = parsed.data;

    let sql = 'SELECT * FROM readings WHERE user_id = ?';
    const params: (string | number)[] = [userId];

    if (from !== undefined) { sql += ' AND timestamp >= ?'; params.push(from); }
    if (to !== undefined)   { sql += ' AND timestamp <= ?'; params.push(to); }
    sql += ' ORDER BY timestamp ASC LIMIT ?';
    params.push(limit);

    const rows = db.prepare(sql).all(...params) as DbReading[];
    return reply.send({ readings: rows.map(dbRowToReading) });
  });
};

export default readingsRoutes;

import { FastifyPluginAsync } from 'fastify';
import { computeWarnings } from '../services/warningsEngine.js';
import type { Warning } from '../types.js';

interface DbWarning {
  id: string;
  user_id: string;
  type: string;
  fired_at: number;
  resolved_at: number | null;
  title: string;
  message: string;
  data: string;
  created_at: number;
}

function dbRowToWarning(row: DbWarning): Warning {
  return {
    id: row.id,
    user_id: row.user_id,
    type: row.type as Warning['type'],
    fired_at: row.fired_at,
    resolved_at: row.resolved_at,
    title: row.title,
    message: row.message,
    data: JSON.parse(row.data) as Warning['data'],
    created_at: row.created_at,
  };
}

const warningsRoutes: FastifyPluginAsync = async (fastify) => {
  const db = fastify.db;

  fastify.addHook('preHandler', async (request, reply) => {
    try {
      await request.jwtVerify();
    } catch {
      return reply.status(401).send({ error: 'Unauthorized' });
    }
  });

  fastify.get('/', async (request, reply) => {
    const userId = (request.user as { userId: string }).userId;
    const rows = db
      .prepare('SELECT * FROM warnings WHERE user_id = ? ORDER BY fired_at DESC')
      .all(userId) as DbWarning[];
    return reply.send({ warnings: rows.map(dbRowToWarning) });
  });

  fastify.get('/:id', async (request, reply) => {
    const userId = (request.user as { userId: string }).userId;
    const { id } = request.params as { id: string };
    const row = db
      .prepare('SELECT * FROM warnings WHERE id = ? AND user_id = ?')
      .get(id, userId) as DbWarning | undefined;
    if (!row) return reply.status(404).send({ error: 'Warning not found' });
    return reply.send({ warning: dbRowToWarning(row) });
  });

  fastify.post('/recompute', async (request, reply) => {
    const userId = (request.user as { userId: string }).userId;
    const newWarnings = computeWarnings(userId, db);
    return reply.send({ warnings: newWarnings, count: newWarnings.length });
  });
};

export default warningsRoutes;

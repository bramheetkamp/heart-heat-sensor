import Fastify, { FastifyInstance } from 'fastify';
import cors from '@fastify/cors';
import jwt from '@fastify/jwt';
import rateLimit from '@fastify/rate-limit';
import { createDatabase, type DB } from './db/index.js';
import authRoutes from './routes/auth.js';
import readingsRoutes from './routes/readings.js';
import warningsRoutes from './routes/warnings.js';
import wellknownRoutes from './routes/wellknown.js';

// Augment FastifyInstance so routes can access `fastify.db`
declare module 'fastify' {
  interface FastifyInstance {
    db: DB;
  }
}

const PORT = parseInt(process.env.PORT ?? '3000', 10);

export interface RateLimitConfig {
  max: number;
  timeWindow: string | number;
}

export interface BuildServerOptions {
  dbPath?: string;
  jwtSecret?: string;
  /** Override auth route rate limits (login/register/apple). Useful in tests. */
  authRateLimit?: RateLimitConfig;
  /** Override readings/batch rate limit. Useful in tests. */
  readingsRateLimit?: RateLimitConfig;
}

export const buildServer = async (opts?: BuildServerOptions): Promise<FastifyInstance> => {
  const dbPath = opts?.dbPath ?? process.env.DATABASE_PATH ?? './data/heartrate.db';
  const jwtSecret = opts?.jwtSecret ?? process.env.JWT_SECRET ?? 'dev_secret_change_me';

  const fastify = Fastify({
    logger: { level: process.env.NODE_ENV === 'test' ? 'silent' : 'info' },
  });

  // ── Database ─────────────────────────────────────────────────────────────────
  const db = createDatabase(dbPath);
  fastify.decorate('db', db);

  // ── CORS ─────────────────────────────────────────────────────────────────────
  await fastify.register(cors, { origin: true, credentials: true });

  // ── JWT ──────────────────────────────────────────────────────────────────────
  await fastify.register(jwt, { secret: jwtSecret });

  // ── Rate limiting ─────────────────────────────────────────────────────────────
  // Global backstop (200 req / min). Auth and readings routes apply tighter
  // per-route limits via config.rateLimit overrides in their plugin files.
  await fastify.register(rateLimit, {
    global: true,
    max: 200,
    timeWindow: '1 minute',
    errorResponseBuilder: (_request, context) => ({
      error: 'Too Many Requests',
      message: `Rate limit exceeded. Retry after ${context.after}.`,
      statusCode: 429,
    }),
  });

  // ── Routes ───────────────────────────────────────────────────────────────────
  await fastify.register(authRoutes, { prefix: '/auth', authRateLimit: opts?.authRateLimit });
  await fastify.register(readingsRoutes, { prefix: '/readings', readingsRateLimit: opts?.readingsRateLimit });
  await fastify.register(warningsRoutes, { prefix: '/warnings' });
  await fastify.register(wellknownRoutes, { prefix: '/.well-known' });

  // ── Health check ─────────────────────────────────────────────────────────────
  fastify.get('/health', async (_request, reply) => {
    return reply.send({ status: 'ok', timestamp: Date.now() });
  });

  return fastify;
};

// ── Start server when run directly ───────────────────────────────────────────
const isMain =
  process.argv[1] != null &&
  (process.argv[1].endsWith('server.ts') || process.argv[1].endsWith('server.js'));

if (isMain) {
  const fastify = await buildServer();
  try {
    await fastify.listen({ port: PORT, host: '0.0.0.0' });
    console.log(`Server listening on port ${PORT}`);
  } catch (err) {
    fastify.log.error(err);
    process.exit(1);
  }
}

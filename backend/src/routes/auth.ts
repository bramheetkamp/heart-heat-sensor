import { FastifyPluginAsync } from 'fastify';
import bcrypt from 'bcryptjs';
import { v4 as uuidv4 } from 'uuid';
import { z } from 'zod';
import type { User } from '../types.js';

const registerSchema = z.object({
  email: z.string().email(),
  password: z.string().min(6),
});

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

const appleSchema = z.object({
  identityToken: z.string().min(1),
  email: z.string().email().optional(),
});

const authRoutes: FastifyPluginAsync = async (fastify) => {
  const db = fastify.db;

  fastify.post('/register', async (request, reply) => {
    const parsed = registerSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'Validation failed', details: parsed.error.flatten() });
    }

    const { email, password } = parsed.data;

    const existing = db.prepare('SELECT id FROM users WHERE email = ?').get(email);
    if (existing) {
      return reply.status(409).send({ error: 'Email already registered' });
    }

    const password_hash = await bcrypt.hash(password, 12);
    const id = uuidv4();
    const created_at = Date.now();

    db.prepare(
      'INSERT INTO users (id, email, password_hash, apple_sub, created_at) VALUES (?, ?, ?, NULL, ?)'
    ).run(id, email, password_hash, created_at);

    const token = fastify.jwt.sign({ userId: id });
    return reply.status(201).send({ token, userId: id });
  });

  fastify.post('/login', async (request, reply) => {
    const parsed = loginSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'Validation failed', details: parsed.error.flatten() });
    }

    const { email, password } = parsed.data;

    const user = db.prepare('SELECT * FROM users WHERE email = ?').get(email) as User | undefined;
    if (!user || !user.password_hash) {
      return reply.status(401).send({ error: 'Invalid credentials' });
    }

    const valid = await bcrypt.compare(password, user.password_hash);
    if (!valid) {
      return reply.status(401).send({ error: 'Invalid credentials' });
    }

    const token = fastify.jwt.sign({ userId: user.id });
    return reply.send({ token, userId: user.id });
  });

  fastify.post('/apple', async (request, reply) => {
    const parsed = appleSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'Validation failed', details: parsed.error.flatten() });
    }

    const { identityToken, email } = parsed.data;

    // PRODUCTION NOTE: verify identityToken against Apple's public keys
    // (https://appleid.apple.com/auth/keys) and validate iss, aud, exp claims.
    // For development, we decode without verification.
    let appleSub: string;
    let appleEmail: string | undefined = email;

    try {
      const parts = identityToken.split('.');
      if (parts.length !== 3) {
        return reply.status(400).send({ error: 'Invalid identity token format' });
      }
      const payloadJson = Buffer.from(parts[1], 'base64url').toString('utf-8');
      const payload = JSON.parse(payloadJson) as { sub?: string; email?: string };

      if (!payload.sub) {
        return reply.status(400).send({ error: 'Identity token missing sub claim' });
      }
      appleSub = payload.sub;
      if (!appleEmail && payload.email) appleEmail = payload.email;
    } catch {
      return reply.status(400).send({ error: 'Failed to decode identity token' });
    }

    let user = db.prepare('SELECT * FROM users WHERE apple_sub = ?').get(appleSub) as User | undefined;

    if (!user) {
      if (appleEmail) {
        user = db.prepare('SELECT * FROM users WHERE email = ?').get(appleEmail) as User | undefined;
        if (user) {
          db.prepare('UPDATE users SET apple_sub = ? WHERE id = ?').run(appleSub, user.id);
        }
      }
      if (!user) {
        const id = uuidv4();
        const created_at = Date.now();
        const newEmail = appleEmail ?? `apple_${appleSub}@placeholder.local`;
        db.prepare(
          'INSERT INTO users (id, email, password_hash, apple_sub, created_at) VALUES (?, ?, NULL, ?, ?)'
        ).run(id, newEmail, appleSub, created_at);
        user = { id, email: newEmail, password_hash: null, apple_sub: appleSub, created_at };
      }
    }

    const token = fastify.jwt.sign({ userId: user.id });
    return reply.send({ token, userId: user.id });
  });
};

export default authRoutes;

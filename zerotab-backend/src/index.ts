import Fastify from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import multipart from '@fastify/multipart';
import dotenv from 'dotenv';

dotenv.config();

import { aaRoutes } from './routes/aa.js';
import { transactionRoutes } from './routes/transactions.js';
import { insightRoutes } from './routes/insights.js';
import { accountRoutes } from './routes/accounts.js';
import { mfRoutes } from './routes/mf.js';
import { stockRoutes } from './routes/stocks.js';
import { userRoutes } from './routes/users.js';
import { demoRoutes } from './routes/demo.js';
import { startWorkers } from './jobs/index.js';

const server = Fastify({
  logger: {
    level: process.env.NODE_ENV === 'production' ? 'info' : 'debug',
    transport: process.env.NODE_ENV !== 'production'
      ? { target: 'pino-pretty', options: { colorize: true } }
      : undefined,
  },
});

// ── Plugins ──────────────────────────────────────────────
await server.register(cors, {
  origin: true,
  credentials: true,
});

await server.register(helmet, { global: true });

await server.register(rateLimit, {
  max: 100,
  timeWindow: '1 minute',
  keyGenerator: (req) => (req as any).user?.id ?? req.ip,
});

await server.register(multipart, {
  limits: { fileSize: 10 * 1024 * 1024 }, // 10 MB
});

// ── Routes ────────────────────────────────────────────────
await server.register(aaRoutes,          { prefix: '/aa' });
await server.register(transactionRoutes, { prefix: '/transactions' });
await server.register(insightRoutes,     { prefix: '/insights' });
await server.register(accountRoutes,     { prefix: '/accounts' });
await server.register(mfRoutes,          { prefix: '/mf' });
await server.register(stockRoutes,       { prefix: '/stocks' });
await server.register(userRoutes,        { prefix: '/users' });
await server.register(demoRoutes,        { prefix: '/demo' });

// ── Health check ──────────────────────────────────────────
server.get('/', async () => ({
  name: 'ZeroTab backend',
  status: 'ok',
  health: '/health',
}));

server.get('/health', async () => ({ status: 'ok', ts: new Date().toISOString() }));

// ── Start ─────────────────────────────────────────────────
const PORT = parseInt(process.env.PORT ?? '3000', 10);

try {
  // Start BullMQ workers
  await startWorkers();

  await server.listen({ port: PORT, host: '0.0.0.0' });
  server.log.info(`ZeroTab backend running on port ${PORT}`);
} catch (err) {
  server.log.error(err);
  process.exit(1);
}

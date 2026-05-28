import { Queue } from 'bullmq';
import dotenv from 'dotenv';
dotenv.config();

// Upstash Redis uses port 6380 with TLS in prod; local Redis uses 6379 without TLS
const isUpstash = (process.env.UPSTASH_REDIS_URL ?? '').includes('upstash.io');

function getRedisConnection() {
  if (isUpstash) {
    const url = new URL(process.env.UPSTASH_REDIS_URL!);
    return {
      host:     url.hostname,
      port:     6380,
      password: process.env.UPSTASH_REDIS_TOKEN,
      tls:      {},
    };
  }
  // Local Redis (development)
  return {
    host: process.env.REDIS_HOST ?? 'localhost',
    port: parseInt(process.env.REDIS_PORT ?? '6379'),
  };
}

export const redisConnection = getRedisConnection();

// ── Queues ────────────────────────────────────────────────
export const aaFetchQueue    = new Queue('aa-fetch',          { connection: redisConnection });
export const insightQueue    = new Queue('insight-gen',       { connection: redisConnection });
export const navUpdateQueue  = new Queue('nav-update',        { connection: redisConnection });
export const archetypeQueue  = new Queue('archetype-compute', { connection: redisConnection });

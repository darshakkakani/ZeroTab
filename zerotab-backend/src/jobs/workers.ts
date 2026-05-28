import { Worker, Job } from 'bullmq';
import { redisConnection } from './queues.js';
import { fetchAAData } from '../services/aaService.js';
import { generateWeeklyInsight, generateInsightsForAllUsers } from '../services/insightService.js';
import { updateAllNavs } from '../services/mfService.js';
import { computeAndStoreArchetype, recomputeAllArchetypes } from '../services/archetypeEngine.js';
import { supabaseAdmin } from '../lib/supabase.js';

// ── AA Data Fetch Worker ─────────────────────────────────
const aaWorker = new Worker(
  'aa-fetch',
  async (job: Job) => {
    const { consentHandle } = job.data as { consentHandle: string; userId?: string };

    // Look up userId from consentHandle if not provided (e.g. from callback)
    let userId = job.data.userId as string | undefined;
    if (!userId) {
      const { data: consent } = await supabaseAdmin
        .from('consents')
        .select('user_id')
        .eq('consent_handle', consentHandle)
        .single();
      userId = consent?.user_id;
    }
    if (!userId) throw new Error(`Cannot resolve userId for consentHandle ${consentHandle}`);

    console.log(`[AA Worker] Fetching data for user ${userId}`);
    await fetchAAData(userId, consentHandle);
    console.log(`[AA Worker] Done for user ${userId}`);
  },
  { connection: redisConnection, concurrency: 10 }
);

// ── AI Insight Generation Worker ─────────────────────────
// When job.data.userId is provided → generate for that user only
// When job.data is empty (cron) → generate for ALL active users
const insightWorker = new Worker(
  'insight-gen',
  async (job: Job) => {
    const { userId } = job.data as { userId?: string };
    if (userId) {
      console.log(`[Insight Worker] Generating insight for user ${userId}`);
      await generateWeeklyInsight(userId);
    } else {
      console.log('[Insight Worker] Generating insights for ALL users (weekly cron)');
      await generateInsightsForAllUsers();
    }
  },
  { connection: redisConnection, concurrency: 5 }
);

// ── NAV Update Worker ─────────────────────────────────────
const navWorker = new Worker(
  'nav-update',
  async (_job: Job) => {
    console.log('[NAV Worker] Updating all MF NAVs');
    await updateAllNavs();
    console.log('[NAV Worker] NAV update complete');
  },
  { connection: redisConnection, concurrency: 1 }
);

// ── Archetype Compute Worker ──────────────────────────────
// When job.data.userId provided → compute for that user
// When job.data is empty (cron) → recompute for ALL users
const archetypeWorker = new Worker(
  'archetype-compute',
  async (job: Job) => {
    const { userId } = job.data as { userId?: string };
    if (userId) {
      console.log(`[Archetype Worker] Computing archetype for user ${userId}`);
      await computeAndStoreArchetype(userId);
    } else {
      console.log('[Archetype Worker] Recomputing archetypes for ALL users (weekly cron)');
      await recomputeAllArchetypes();
    }
  },
  { connection: redisConnection, concurrency: 20 }
);

// Error handlers
for (const w of [aaWorker, insightWorker, navWorker, archetypeWorker]) {
  w.on('failed', (job, err) => {
    console.error(`[Worker] Job ${job?.id} failed: ${err.message}`);
  });
  w.on('error', (err) => {
    console.error(`[Worker] Worker error: ${err.message}`);
  });
}

export { aaWorker, insightWorker, navWorker, archetypeWorker };

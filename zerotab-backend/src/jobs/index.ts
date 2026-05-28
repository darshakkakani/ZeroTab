// Start all BullMQ workers and register recurring crons
export async function startWorkers() {
  if (process.env.SKIP_WORKERS === 'true') {
    console.log('[Jobs] Skipping BullMQ workers because SKIP_WORKERS=true');
    return;
  }

  const { insightQueue, navUpdateQueue, archetypeQueue } = await import('./queues.js');

  // Import workers (side-effect: registers them with BullMQ)
  await import('./workers.js');

  // ── Weekly insight generation: Monday 9 AM IST (3:30 AM UTC) ──
  await insightQueue.upsertJobScheduler(
    'weekly-insights-monday',
    { pattern: '30 3 * * 1' }, // 9:00 AM IST = 3:30 AM UTC
    { name: 'weekly-insights-all-users', data: {} }
  );

  // ── Daily NAV update: 10:30 PM IST (5:00 PM UTC) ─────────────
  await navUpdateQueue.upsertJobScheduler(
    'daily-nav-update',
    { pattern: '0 17 * * *' },
    { name: 'update-all-navs', data: {} }
  );

  // ── Weekly archetype recompute: Sunday midnight IST ───────────
  await archetypeQueue.upsertJobScheduler(
    'weekly-archetype-recompute',
    { pattern: '30 18 * * 0' }, // 12:00 AM IST Sunday = 6:30 PM UTC Saturday
    { name: 'recompute-all-archetypes', data: {} }
  );

  console.log('[Jobs] BullMQ workers started, crons registered');
}

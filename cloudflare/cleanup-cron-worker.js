/**
 * WellScreen 90-day data retention, run once a day.
 *
 * Deploy as its own Scheduled Cloudflare Worker (see wrangler.example.toml).
 * Calls the backend's private POST /internal/maintenance/cleanup with the
 * token from the Worker secret CLEANUP_TOKEN. The backend decides what is
 * deleted (WELLSCREEN_CLEANUP_APPLY=true deletes, otherwise dry run).
 * Never put the token in this file or the repo.
 */
async function runCleanup(env) {
  if (!env.MONITORING_API_URL || !env.CLEANUP_TOKEN) {
    console.error('Missing cleanup scheduler configuration');
    return { ok: false, status: 0 };
  }
  const endpoint = new URL('/internal/maintenance/cleanup', env.MONITORING_API_URL);
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: { 'X-WellScreen-Cleanup-Token': env.CLEANUP_TOKEN },
  });
  const text = await response.text();
  if (!response.ok) {
    console.error('Cleanup returned HTTP ' + response.status);
    return { ok: false, status: response.status };
  }
  // The report only holds counts, so it is safe to log.
  console.log('Cleanup report: ' + text.slice(0, 2000));
  return { ok: true, status: response.status };
}

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(runCleanup(env));
  },
};

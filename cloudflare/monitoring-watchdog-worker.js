/** Deploy separately as a Scheduled Cloudflare Worker, not as the FCM limit notifier. */
export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil((async () => {
      if (!env.MONITORING_API_URL || !env.MONITORING_CRON_SECRET) {
        console.error('Missing monitoring scheduler configuration');
        return;
      }
      const endpoint = new URL('/internal/monitoring/sweep', env.MONITORING_API_URL);
      const response = await fetch(endpoint, {
        method: 'POST',
        headers: {'x-monitoring-secret': env.MONITORING_CRON_SECRET},
      });
      if (!response.ok) console.error('Monitoring sweep returned HTTP ' + response.status);
    })());
  },
};

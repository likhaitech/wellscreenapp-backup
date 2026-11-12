// Separate Cloudflare Cron Worker; does not replace any existing Worker.
// Bind MONITORING_API_URL and CHAT_CRON_SECRET as Worker secrets.
export default {
  async scheduled(controller, env, ctx) {
    ctx.waitUntil(fetch(`${env.MONITORING_API_URL.replace(/\/$/, '')}/internal/chat/notifications/sweep`, {
      method: 'POST',
      headers: { 'X-Chat-Cron-Secret': env.CHAT_CRON_SECRET },
    }));
  },
};

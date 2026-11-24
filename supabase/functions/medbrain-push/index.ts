import { createClient } from 'npm:@supabase/supabase-js@2.57.4';
import webPush from 'npm:web-push@3.6.7';

const notices: Record<string, string> = {
  message: 'لديك رسالة جديدة.',
  chat_request: 'لديك طلب مراسلة جديد.',
  friend_request: 'لديك طلب صداقة جديد.',
  friend_accepted: 'تم قبول طلب الصداقة.',
};

Deno.serve(async (req) => {
  if (req.method !== 'POST' || !req.headers.get('x-medbrain-dispatch')) {
    return new Response(null, { status: 403 });
  }
  try {
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const { user, kind } = await req.json();
    if (!/^[0-9a-f-]{36}$/i.test(user) || !Object.hasOwn(notices, kind)) {
      return new Response(null, { status: 400 });
    }
    const { data, error } = await admin.rpc('medbrain_push_delivery', {
      p_token: req.headers.get('x-medbrain-dispatch'), p_user: user,
    });
    if (error || !data) return new Response(null, { status: 403 });
    const payload = JSON.stringify({ body: notices[kind], tag: 'medbrain-' + kind });
    const results = await Promise.allSettled(data.subscriptions.map(async (sub) => {
      try {
        await webPush.sendNotification(sub, payload, {
          vapidDetails: { subject: 'https://haider1381.github.io/al-marja3/', publicKey: data.public_key, privateKey: data.private_key },
          TTL: 3600,
          timeout: 5000,
        });
      } catch (error) {
        if (error.statusCode === 404 || error.statusCode === 410) {
          await admin.rpc('medbrain_push_prune', { p_endpoint: sub.endpoint });
          return;
        }
        throw error;
      }
    }));
    return new Response(null, { status: results.some(result => result.status === 'rejected') ? 502 : 204 });
  } catch {
    return new Response(null, { status: 500 });
  }
});

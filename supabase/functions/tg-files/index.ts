// Owner-only helper for lecture files stored in the private Telegram channel «ملفات midbrain» (no R2 space used).
// check: confirms the bot token and channel access. sync: reads new channel posts the bot received and records each
// document (file_id) in private.tg_files. insert: creates library rows whose file_path is "tg:<file_id>".
// Protected by a one-time import token; switch it off (410) when an import batch is done.
import { createClient } from 'npm:@supabase/supabase-js@2.57.4';

const IMPORT_TOKEN = '29c2dba30a16c119f1d6efc5457f5775ec8623efa937c871';
const CHANNEL = -1003997891065;
const env = (k: string) => Deno.env.get(k) ?? '';

Deno.serve(async (req) => {
  const json = (status: number, data: unknown) => new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } });
  if (req.method !== 'POST') return json(405, { error: 'method' });
  if (req.headers.get('x-import-token') !== IMPORT_TOKEN) return json(401, { error: 'token' });
  const bot = env('TELEGRAM_BOT_TOKEN');
  if (!bot) return json(503, { error: 'no_bot_token' });
  const tg = async (method: string, params: Record<string, unknown> = {}) => {
    const r = await fetch('https://api.telegram.org/bot' + bot + '/' + method, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(params) });
    return await r.json();
  };
  const pub = createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), { auth: { persistSession: false } });
  const body = await req.json().catch(() => ({}));
  try {
    if (body.action === 'check') {
      const me = await tg('getMe');
      const chat = await tg('getChat', { chat_id: CHANNEL });
      const member = me.ok ? await tg('getChatMember', { chat_id: CHANNEL, user_id: me.result.id }) : null;
      return json(200, { bot: me.ok ? me.result.username : me.description, chat: chat.ok ? chat.result.title : chat.description, status: member?.result?.status ?? member?.description });
    }
    if (body.action === 'sync') {
      const { data: off } = await pub.rpc('tg_offset');
      let offset = Number(off || 0), added = 0, seen = 0;
      for (let round = 0; round < 30; round++) {
        const up = await tg('getUpdates', { offset, limit: 100, timeout: 0, allowed_updates: ['channel_post', 'edited_channel_post'] });
        if (!up.ok) return json(502, { error: up.description });
        if (!up.result.length) break;
        const rows = [];
        for (const u of up.result) {
          offset = u.update_id + 1; seen++;
          const m = u.channel_post || u.edited_channel_post;
          if (!m || m.chat?.id !== CHANNEL || !m.document) continue;
          rows.push({ message_id: m.message_id, chat_id: CHANNEL, file_id: m.document.file_id, file_unique_id: m.document.file_unique_id,
            file_name: m.document.file_name ?? null, mime_type: m.document.mime_type ?? null, file_size: m.document.file_size ?? null,
            caption: m.caption ?? null, forward_from: m.forward_origin?.chat?.username ?? m.forward_origin?.chat?.title ?? m.forward_from_chat?.username ?? null });
        }
        const { data: n, error } = await pub.rpc('tg_files_put', { p_rows: rows, p_offset: offset }); if (error) throw error; added += Number(n || 0);
      }
      return json(200, { seen, added, offset });
    }
    if (body.action === 'list') {
      const from = Number(body.from || 0), to = Number(body.to || 1e12);
      const { data, error } = await pub.rpc('tg_files_get', { p_from: from, p_to: to });
      if (error) throw error;
      return json(200, { files: data });
    }
    if (body.action === 'insert') {
      const items = Array.isArray(body.rows) ? body.rows : [];
      if (!items.length || items.length > 300) return json(400, { error: 'rows' });
      const ids = items.map((r: { message_id: number }) => r.message_id);
      const { data: all, error } = await pub.rpc('tg_files_get', { p_from: Math.min(...ids), p_to: Math.max(...ids) });
      if (error) throw error;
      const files = (all || []).filter((f: { message_id: number }) => ids.includes(Number(f.message_id)));
      const byMsg = new Map(files.map((f: { message_id: number; file_id: string }) => [Number(f.message_id), f.file_id]));
      const out = [];
      for (const r of items) {
        const fid = byMsg.get(Number(r.message_id));
        if (!fid) continue;
        out.push({ title: r.title, source: r.source, category: r.category, topic: r.topic, type: r.type || 'محاضرة', stage: r.stage ?? null,
          doctor: r.doctor ?? null, topic_id: r.topic_id ?? null, notes: r.notes ?? null, file_path: 'tg:' + fid, questions: [] });
      }
      if (!out.length) return json(400, { error: 'no_files' });
      const { data: ins, error: e2 } = await pub.from('lectures').insert(out).select('id');
      if (e2) throw e2;
      return json(200, { inserted: ins.length });
    }
    return json(400, { error: 'action' });
  } catch (e) {
    return json(500, { error: String((e as Error)?.message || e) });
  }
});

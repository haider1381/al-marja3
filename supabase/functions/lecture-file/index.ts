// Lecture PDFs live in a private Cloudflare R2 bucket (zero egress cost).
// open:   any signed-in reader allowed by RLS on public.lectures gets a 5-minute presigned GET URL.
// upload: editors send the PDF body; it is stored in R2 and the new file_path is returned.
import { createClient } from 'npm:@supabase/supabase-js@2.57.4';
import { AwsClient } from 'npm:aws4fetch@1.0.20';

const ORIGINS = new Set(['https://haider1381.github.io', 'https://localhost', 'capacitor://localhost', 'http://localhost:5173']);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_PDF = 50 * 1024 * 1024;
const URL_TTL = 300;

const env = (name: string) => Deno.env.get(name) ?? '';
const r2 = new AwsClient({ accessKeyId: env('R2_ACCESS_KEY_ID'), secretAccessKey: env('R2_SECRET_ACCESS_KEY'), service: 's3', region: 'auto' });
const objectUrl = (key: string) => `https://${env('R2_ACCOUNT_ID')}.r2.cloudflarestorage.com/${env('R2_BUCKET')}/${key.split('/').map(encodeURIComponent).join('/')}`;

Deno.serve(async (req) => {
  const origin = req.headers.get('origin');
  const cors = {
    'Access-Control-Allow-Origin': origin && ORIGINS.has(origin) ? origin : 'https://haider1381.github.io',
    'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  };
  const reply = (status: number, data: unknown) => new Response(JSON.stringify(data), { status, headers: { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
  if (origin && !ORIGINS.has(origin)) return reply(403, { error: 'origin_not_allowed' });
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
  if (req.method !== 'POST') return reply(405, { error: 'method_not_allowed' });

  const auth = req.headers.get('authorization') || '';
  if (!/^Bearer\s+\S+$/i.test(auth)) return reply(401, { error: 'sign_in_required' });
  const anon = env('SUPABASE_ANON_KEY') || JSON.parse(env('SUPABASE_PUBLISHABLE_KEYS') || '{}').default;
  const user = createClient(env('SUPABASE_URL'), anon, { global: { headers: { Authorization: auth } }, auth: { persistSession: false, autoRefreshToken: false } });
  const { data: who, error: whoError } = await user.auth.getUser(auth.replace(/^Bearer\s+/i, ''));
  if (whoError || !who?.user || who.user.is_anonymous) return reply(401, { error: 'sign_in_required' });

  const action = new URL(req.url).searchParams.get('action');
  try {
    if (action === 'open') {
      const body = await req.json().catch(() => null);
      if (!body || typeof body.lecture_id !== 'string' || !UUID.test(body.lecture_id)) return reply(400, { error: 'invalid_lecture' });
      // RLS decides whether this reader may see the lecture at all.
      const { data: row, error } = await user.from('lectures').select('file_path,title').eq('id', body.lecture_id).maybeSingle();
      if (error) throw error;
      if (!row?.file_path) return reply(404, { error: 'no_file' });
      const head = await r2.fetch(objectUrl(row.file_path), { method: 'HEAD' });
      if (head.ok) {
        const url = new URL(objectUrl(row.file_path));
        url.searchParams.set('X-Amz-Expires', String(URL_TTL));
        // inline shows the PDF in the browser/viewer; attachment saves it under the lecture title.
        const name = (String(row.title || 'lecture').replace(/[\\/:*?"<>|\r\n]+/g, ' ').trim().slice(0, 120) || 'lecture') + '.pdf';
        const disposition = body.download === true ? 'attachment' : 'inline';
        url.searchParams.set('response-content-disposition', `${disposition}; filename*=UTF-8''${encodeURIComponent(name)}`);
        url.searchParams.set('response-content-type', 'application/pdf');
        const signed = await r2.sign(url.toString(), { method: 'GET', aws: { signQuery: true } });
        return reply(200, { url: signed.url, expires_in: URL_TTL });
      }
      // Files not yet copied to R2 still open from Supabase Storage.
      const legacy = await user.storage.from('lecture-files').createSignedUrl(row.file_path, URL_TTL);
      if (legacy.error || !legacy.data?.signedUrl) return reply(404, { error: 'file_missing' });
      return reply(200, { url: legacy.data.signedUrl, expires_in: URL_TTL });
    }

    if (action === 'upload') {
      const { data: editor, error } = await user.rpc('is_editor');
      if (error) throw error;
      if (editor !== true) return reply(403, { error: 'editor_required' });
      if (Number(req.headers.get('content-length') || 0) > MAX_PDF) return reply(413, { error: 'too_large' });
      const bytes = new Uint8Array(await req.arrayBuffer());
      if (bytes.length < 5 || bytes.length > MAX_PDF) return reply(413, { error: 'too_large' });
      if (new TextDecoder().decode(bytes.slice(0, 5)) !== '%PDF-') return reply(400, { error: 'not_pdf' });
      const path = `pdf/${crypto.randomUUID()}.pdf`;
      const put = await r2.fetch(objectUrl(path), { method: 'PUT', body: bytes, headers: { 'Content-Type': 'application/pdf' } });
      if (!put.ok) return reply(502, { error: 'storage_failed' });
      return reply(200, { path });
    }

    return reply(400, { error: 'invalid_action' });
  } catch (_) {
    return reply(500, { error: 'server_error' });
  }
});

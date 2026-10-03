# Ask Midbrain AI — Groq integration

The top bar, personal menu and lecture reader open the same memory-only chat. A signed-in user can ask a general study question or select an available text lecture. PDF extraction is not implemented; PDF-only materials are excluded from the context selector.

## Server configuration

- Project: `wuvzteosknrzddsaexez`; Edge Function: `medbrain-ai`.
- Keep `verify_jwt = true`. The handler additionally validates the user using Auth `getUser()` and rejects anonymous users.
- Store `GROQ_API_KEY` in [Edge Function secrets](https://supabase.com/dashboard/project/wuvzteosknrzddsaexez/functions/secrets). Never put its value in this repository or browser code.
- Provider endpoint: `https://api.groq.com/openai/v1/chat/completions`; model: `openai/gpt-oss-20b`.
- The implementation uses the existing Supabase runtime credentials only on the server. The browser sends a user JWT and the project's publishable key, never the Groq key.
- This integration does not upgrade the Groq plan or enable paid billing. Keep the provider account on Free Plan. Groq limits and free availability may change: [official limits](https://console.groq.com/docs/rate-limits).

## Data and limits

Only the question, recent conversation and selected lecture excerpts are sent to Groq. Profile details, schedules, favorites, storage credentials and attachments are not sent. Auth-scoped lecture queries respect existing RLS. Long lectures are represented by limited excerpts selected using question terms; the UI indicates partial context. These excerpts are not a substitute for reviewing the full lecture.

Conversations remain in browser memory, clear on account changes, and are never saved in the application's database. Provider handling of requests follows [Groq's data policy](https://console.groq.com/docs/your-data). Responses are rendered using `textContent`, with no HTML execution.

`supabase/medbrain-ai-quota.sql` records the additive database setup. Apply it once to a new environment. It creates:
- Private, RLS-enabled `private.medbrain_ai_usage` counters accessible only to `service_role`, storing a user UUID or global scope, UTC date, count and last request time.
- A `SECURITY INVOKER` RPC callable only by `service_role`. The authenticated user ID comes from server-verified Auth, never request JSON.
- Transaction-serialized reservations: 15 attempts/user/day, 40/site/day, 20-second global and 10-second user cooldowns. Old counters expire after seven days during reservations. Provider failures still consume the reserved attempt.
- Groq can enforce additional minute/token limits. A 429 response shows a retry message; the app does not retry automatically or switch to a paid provider.

Requests are bounded (24 KB body, 1200-character question, six recent messages, 4500-character lecture excerpt). Output is limited to 1600 completion tokens, including reasoning tokens. The model is instructed to assist medical study, state uncertainty, and avoid patient-specific prescribing. Users are reminded to verify answers and avoid patient-identifying data.

Existing lecture records, storage policies, editor/owner roles and personal tools are unchanged.

## Validation — 2026-10-03

- A live server-side probe using the saved key returned HTTP 200 and an Arabic model answer. The temporary probe route was removed immediately; the final function has JWT verification enabled and its source matches the committed implementation.
- Live unauthenticated requests return 401; the site's CORS preflight returns 204 with the correct origin.
- Backend tests cover authentication, allowed origin, input bounds, history roles, RLS-scoped context, quota rejection, provider errors and secret non-exposure.
- Transactional SQL tests verify cooldown and both daily quotas, then roll back. No test counter rows remain.
- Browser tests at widths 320, 390, 768 and 1440 in light/dark verify all entry points, chat/history, lecture selection, error recovery, 429 cooldown, cancellation, safe output, and Escape returning to the reader. Existing profile, schedule sharing, favorites and settings regression checks pass.
- Security advisors report no findings for the new table/function; pre-existing notices were not changed.
- A user-authenticated production conversation still needs the account holder's own login to test. No existing user sessions were accessed or impersonated.

To verify on the live site, refresh, sign in, open the stars icon or Ask Midbrain AI in the menu, and submit a short question. In a text lecture, use the reader's AI button to select that lecture automatically.

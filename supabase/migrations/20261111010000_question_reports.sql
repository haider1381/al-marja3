-- Students report a wrong answer, wrong/incomplete question or weak explanation; editors review and close reports.
begin;
create table if not exists public.question_reports (
  id uuid primary key default gen_random_uuid(),
  lecture_id uuid not null references public.lectures(id) on delete cascade,
  question_index integer not null check (question_index >= 0),
  question_prompt text not null check (char_length(question_prompt) between 1 and 4000),
  reason text not null check (reason in ('wrong_answer', 'wrong_question', 'incomplete', 'explanation', 'other')),
  note text check (note is null or char_length(note) <= 1000),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  status text not null default 'open' check (status in ('open', 'resolved', 'dismissed')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);
-- One open report per student per question, so a single student cannot flood the inbox.
create unique index if not exists question_reports_one_open
  on public.question_reports (user_id, lecture_id, question_prompt) where status = 'open';
create index if not exists question_reports_open_idx on public.question_reports (created_at desc) where status = 'open';
create index if not exists question_reports_lecture_idx on public.question_reports (lecture_id);

alter table public.question_reports enable row level security;
revoke all on public.question_reports from public, anon;
grant select, insert, update, delete on public.question_reports to authenticated;

drop policy if exists "reports insert own" on public.question_reports;
create policy "reports insert own" on public.question_reports for insert to authenticated
  with check (user_id = (select auth.uid()) and status = 'open' and resolved_at is null);
drop policy if exists "reports read own or editor" on public.question_reports;
create policy "reports read own or editor" on public.question_reports for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_editor()));
drop policy if exists "reports editor update" on public.question_reports;
create policy "reports editor update" on public.question_reports for update to authenticated
  using ((select public.is_editor())) with check ((select public.is_editor()));
drop policy if exists "reports editor delete" on public.question_reports;
create policy "reports editor delete" on public.question_reports for delete to authenticated
  using ((select public.is_editor()));
commit;

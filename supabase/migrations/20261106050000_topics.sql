-- A topic is the hub of the study guide: every material (lectures, summaries, mind maps, questions…) from every source links to one.
create table if not exists public.topics (
  id uuid primary key default gen_random_uuid(),
  category text not null,
  branch text not null,
  name text not null,
  key text not null,
  sort integer not null default 0,
  created_at timestamptz not null default now(),
  unique (category, branch, key)
);
alter table public.topics enable row level security;
create policy topics_read on public.topics for select to authenticated using (true);
create policy topics_write on public.topics for all to authenticated
  using ((select public.is_editor())) with check ((select public.is_editor()));

alter table public.lectures add column if not exists topic_id uuid references public.topics(id) on delete set null;
create index if not exists lectures_topic_id on public.lectures (topic_id);

-- Each student's own notes on study material (PDF ink, summary ink, question highlights, flashcard progress), synced to the account.
create table if not exists public.user_annotations (
  user_id uuid not null references auth.users(id) on delete cascade,
  item_key text not null check (char_length(item_key) between 3 and 120),
  data jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, item_key),
  constraint user_annotations_size check (pg_column_size(data) <= 400000)
);
alter table public.user_annotations enable row level security;
revoke all on public.user_annotations from anon;
grant select, insert, update, delete on public.user_annotations to authenticated;
create policy "annotations_own_select" on public.user_annotations for select to authenticated using (user_id = (select auth.uid()));
create policy "annotations_own_insert" on public.user_annotations for insert to authenticated with check (user_id = (select auth.uid()));
create policy "annotations_own_update" on public.user_annotations for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "annotations_own_delete" on public.user_annotations for delete to authenticated using (user_id = (select auth.uid()));

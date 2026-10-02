-- Review and back up existing policies before applying in Supabase SQL Editor.
-- This transaction preserves all lecture/access-code rows; replaces lecture policies.
begin;
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create table if not exists private.editors (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table private.editors enable row level security;
revoke all on private.editors from public, anon, authenticated;

create or replace function public.is_editor()
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (select 1 from private.editors where user_id = (select auth.uid()));
$$;
revoke all on function public.is_editor() from public, anon;
grant execute on function public.is_editor() to authenticated;

-- Do not recreate lectures or change its IDs/columns/data.
alter table public.lectures enable row level security;
-- Existing permissive policies combine with OR: remove them before installing restrictions.
do $$
declare p record;
begin
  for p in select policyname from pg_policies
    where schemaname = 'public' and tablename = 'lectures'
  loop
    execute format('drop policy %I on public.lectures', p.policyname);
  end loop;
end $$;
revoke all on public.lectures from public, anon, authenticated;
grant select, insert, update, delete on public.lectures to authenticated;
-- Support existing serial/identity IDs without assuming their type.
do $$
declare seq text;
begin
  seq := pg_get_serial_sequence('public.lectures', 'id');
  if seq is not null then
    execute format('grant usage, select on sequence %s to authenticated', seq);
  end if;
end $$;
create policy lectures_read on public.lectures
  for select to authenticated using (true);
create policy lectures_insert on public.lectures
  for insert to authenticated with check ((select public.is_editor()));
create policy lectures_update on public.lectures
  for update to authenticated using ((select public.is_editor()))
  with check ((select public.is_editor()));
create policy lectures_delete on public.lectures
  for delete to authenticated using ((select public.is_editor()));

-- Keep legacy data for rollback, but deny all browser access.
do $$
declare p record;
begin
  if to_regclass('public.access_codes') is not null then
    alter table public.access_codes enable row level security;
    revoke all on public.access_codes from public, anon, authenticated;
    for p in select policyname from pg_policies
      where schemaname = 'public' and tablename = 'access_codes'
    loop
      execute format('drop policy %I on public.access_codes', p.policyname);
    end loop;
  end if;
end $$;
commit;

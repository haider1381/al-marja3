-- Apply after 202610020001_auth_rls.sql. No lecture rows or files are deleted.
begin;
alter table public.lectures add column if not exists file_path text;
alter table public.lectures add column if not exists questions jsonb not null default '[]'::jsonb;

create or replace function public.valid_lecture_questions(payload jsonb)
returns boolean language plpgsql immutable set search_path = ''
as $$
declare q jsonb; o jsonb;
begin
  if payload is null or jsonb_typeof(payload) <> 'array' then return false; end if;
  if jsonb_array_length(payload) > 100 then return false; end if;
  for q in select value from jsonb_array_elements(payload) loop
    if jsonb_typeof(q) <> 'object'
      or jsonb_typeof(q->'prompt') is distinct from 'string'
      or length(btrim(q->>'prompt')) = 0 or length(q->>'prompt') > 10000
      or jsonb_typeof(q->'options') is distinct from 'array'
      or jsonb_typeof(q->'correctIndex') is distinct from 'number'
      or (q->>'correctIndex') !~ '^[0-3]$' then return false; end if;
    if jsonb_array_length(q->'options') <> 4 then return false; end if;
    for o in select value from jsonb_array_elements(q->'options') loop
      if jsonb_typeof(o) <> 'object'
        or jsonb_typeof(o->'text') is distinct from 'string'
        or length(btrim(o->>'text')) = 0 or length(o->>'text') > 5000
        or jsonb_typeof(o->'explanation') is distinct from 'string'
        or length(btrim(o->>'explanation')) = 0 or length(o->>'explanation') > 10000
        then return false; end if;
    end loop;
  end loop;
  return true;
end $$;
revoke all on function public.valid_lecture_questions(jsonb) from public, anon;
grant execute on function public.valid_lecture_questions(jsonb) to authenticated;
do $$
begin
  if not exists (select 1 from pg_constraint
    where conrelid = 'public.lectures'::regclass and conname = 'lectures_questions_valid') then
    alter table public.lectures add constraint lectures_questions_valid
      check (public.valid_lecture_questions(questions));
  end if;
end $$;

-- Dedicated private PDF bucket: do not change an existing bucket silently.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('lecture-files', 'lecture-files', false, 26214400, array['application/pdf'])
on conflict (id) do nothing;
do $$
begin
  if not exists (select 1 from storage.buckets where id = 'lecture-files'
    and public = false and file_size_limit = 26214400
    and allowed_mime_types = array['application/pdf']) then
    raise exception 'Existing lecture-files bucket settings differ. Review before continuing.';
  end if;
end $$;

drop policy if exists lecture_files_anon_guard on storage.objects;
create policy lecture_files_anon_guard on storage.objects as restrictive for all to anon
using (bucket_id <> 'lecture-files') with check (bucket_id <> 'lecture-files');

-- Restrictive guards ensure older permissive policies cannot open this bucket.
-- They do not change access to other buckets.
drop policy if exists lecture_files_read_guard on storage.objects;
drop policy if exists lecture_files_insert_guard on storage.objects;
drop policy if exists lecture_files_update_guard on storage.objects;
drop policy if exists lecture_files_delete_guard on storage.objects;
create policy lecture_files_read_guard on storage.objects as restrictive for select to authenticated
using (bucket_id <> 'lecture-files' or (
  (select auth.uid()) is not null and (
    (select public.is_editor()) or exists (
      select 1 from public.lectures l where l.file_path = storage.objects.name
    )
  )
));
create policy lecture_files_insert_guard on storage.objects as restrictive for insert to authenticated
with check (bucket_id <> 'lecture-files' or (
  (select auth.uid()) is not null and (select public.is_editor())
));
create policy lecture_files_update_guard on storage.objects as restrictive for update to authenticated
using (bucket_id <> 'lecture-files' or ((select auth.uid()) is not null and (select public.is_editor())))
with check (bucket_id <> 'lecture-files' or ((select auth.uid()) is not null and (select public.is_editor())));
create policy lecture_files_delete_guard on storage.objects as restrictive for delete to authenticated
using (bucket_id <> 'lecture-files' or ((select auth.uid()) is not null and (select public.is_editor())));

drop policy if exists lecture_files_read on storage.objects;
drop policy if exists lecture_files_insert on storage.objects;
drop policy if exists lecture_files_update on storage.objects;
drop policy if exists lecture_files_delete on storage.objects;
create policy lecture_files_read on storage.objects for select to authenticated
using (bucket_id = 'lecture-files' and (
  (select public.is_editor()) or exists (
    select 1 from public.lectures l where l.file_path = storage.objects.name
  )
));
create policy lecture_files_insert on storage.objects for insert to authenticated
with check (bucket_id = 'lecture-files' and (select public.is_editor()));
create policy lecture_files_update on storage.objects for update to authenticated
using (bucket_id = 'lecture-files' and (select public.is_editor()))
with check (bucket_id = 'lecture-files' and (select public.is_editor()));
create policy lecture_files_delete on storage.objects for delete to authenticated
using (bucket_id = 'lecture-files' and (select public.is_editor()));
commit;

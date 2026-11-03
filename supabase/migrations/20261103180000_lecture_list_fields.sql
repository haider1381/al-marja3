-- Lightweight list fields so the library can load without downloading every lecture text and question set.
-- PostgREST exposes these as computed columns: select=...,has_text,question_count
create or replace function public.has_text(l public.lectures)
returns boolean language sql stable set search_path = '' as $$
  select coalesce(length(btrim(l.lecture_text)), 0) > 0
$$;

create or replace function public.question_count(l public.lectures)
returns integer language sql stable set search_path = '' as $$
  select coalesce(jsonb_array_length(l.questions), 0)
$$;

revoke all on function public.has_text(public.lectures) from public, anon;
revoke all on function public.question_count(public.lectures) from public, anon;
grant execute on function public.has_text(public.lectures) to authenticated;
grant execute on function public.question_count(public.lectures) to authenticated;

notify pgrst, 'reload schema';

begin;

alter table public.question_reports
  add column flashcard_id uuid references public.library_flashcards(id) on delete cascade,
  alter column lecture_id drop not null,
  add constraint question_reports_one_target
    check ((lecture_id is null) <> (flashcard_id is null));

create unique index question_reports_one_open_flashcard
  on public.question_reports (user_id, flashcard_id)
  where status = 'open' and flashcard_id is not null;

create or replace function private.award_resolved_question_report()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_owner() then return new; end if;
  insert into public.study_xp_events (user_id, event_key, activity, points)
  values (
    new.user_id,
    case when new.flashcard_id is not null then 'flashcard-report:' || new.flashcard_id::text
         else 'question-report:' || new.lecture_id::text || ':' || pg_catalog.md5(new.question_prompt) end,
    'helpful_report', 2
  )
  on conflict (user_id, event_key) do nothing;
  return new;
end;
$$;

commit;

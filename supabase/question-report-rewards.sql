begin;

create or replace function private.award_resolved_question_report()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_owner() then return new; end if;
  insert into public.study_xp_events (user_id, event_key, activity, points)
  values (new.user_id,
          'question-report:' || new.lecture_id::text || ':' || md5(new.question_prompt),
          'helpful_report', 2)
  on conflict (user_id, event_key) do nothing;
  return new;
end;
$$;

revoke all on function private.award_resolved_question_report() from public, anon, authenticated;
drop trigger if exists award_resolved_question_report on public.question_reports;
create trigger award_resolved_question_report
after update of status on public.question_reports
for each row when (old.status = 'open' and new.status = 'resolved')
execute function private.award_resolved_question_report();

commit;

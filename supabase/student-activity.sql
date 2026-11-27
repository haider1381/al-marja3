create table if not exists private.student_activity_days (
  user_id uuid not null references auth.users(id) on delete cascade,
  activity_day date not null,
  kind text not null check (kind in ('lecture', 'quiz')),
  primary key (activity_day, user_id, kind)
);
alter table private.student_activity_days enable row level security;
revoke all on private.student_activity_days from public, anon, authenticated;

create or replace function public.record_student_activity(p_kind text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null or p_kind is null or p_kind not in ('lecture', 'quiz') then return; end if;
  if not exists (
    select 1 from auth.users
    where id = uid and not coalesce(is_anonymous, false) and deleted_at is null
  ) or public.is_owner() is true then return; end if;
  insert into private.student_activity_days (user_id, activity_day, kind)
  values (uid, (now() at time zone 'Asia/Baghdad')::date, p_kind)
  on conflict do nothing;
end;
$$;

create or replace function public.owner_student_activity()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare today_baghdad date := (now() at time zone 'Asia/Baghdad')::date;
begin
  if auth.uid() is null or public.is_owner() is distinct from true then
    raise exception 'not_owner' using errcode = '42501';
  end if;
  return (
    with per_student as (
      select activity.user_id, count(distinct activity_day) as days,
        bool_or(kind = 'lecture') as read_lecture, bool_or(kind = 'quiz') as finished_quiz,
        bool_or(activity_day = today_baghdad) as active_today,
        bool_or(activity_day = today_baghdad and kind = 'lecture') as read_today,
        bool_or(activity_day = today_baghdad and kind = 'quiz') as quiz_today
      from private.student_activity_days activity
      join auth.users account on account.id = activity.user_id and account.deleted_at is null
      where activity_day between today_baghdad - 6 and today_baghdad
      group by activity.user_id
    )
    select jsonb_build_object(
      'active', count(*),
      'returning', count(*) filter (where days >= 2),
      'lectures', count(*) filter (where read_lecture),
      'quizzes', count(*) filter (where finished_quiz),
      'today', jsonb_build_object(
        'active', count(*) filter (where active_today),
        'lectures', count(*) filter (where read_today),
        'quizzes', count(*) filter (where quiz_today)
      )
    )
    from per_student
  );
end;
$$;

revoke all on function public.record_student_activity(text), public.owner_student_activity()
  from public, anon, authenticated;
grant execute on function public.record_student_activity(text), public.owner_student_activity()
  to authenticated;

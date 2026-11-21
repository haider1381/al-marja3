CREATE OR REPLACE FUNCTION public.record_study_xp(p_user uuid, p_key text, p_activity text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  balance integer;
  delta integer;
  daily_count integer;
  today date := (now() at time zone 'Asia/Baghdad')::date;
begin
  if p_user is null or p_key is null or length(p_key) not between 1 and 240 then
    raise exception 'Invalid XP activity';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user::text, 0));
  select 15 + coalesce(sum(points), 0)::integer into balance
  from public.study_xp_events where user_id = p_user;
  if exists (select 1 from public.study_xp_events where user_id = p_user and event_key = p_key) then
    if p_activity in ('ai_hint', 'ai_answer') then raise exception 'duplicate_ai_request'; end if;
    return balance;
  end if;
  delta := case p_activity when 'study' then 10 when 'quiz' then 8 when 'deck' then 6
    when 'ai_hint' then -1 when 'ai_answer' then -5 end;
  if delta is null then raise exception 'Unknown XP activity'; end if;
  if delta > 0 then
    select count(*) into daily_count from public.study_xp_events
      where user_id = p_user and activity = p_activity
      and (created_at at time zone 'Asia/Baghdad')::date = today;
    if daily_count >= 5 then return balance; end if;
  elsif balance + delta < 0 then
    raise exception 'insufficient_xp';
  end if;
  insert into public.study_xp_events (user_id, event_key, activity, points)
    values (p_user, p_key, p_activity, delta);
  return balance + delta;
end
$function$;

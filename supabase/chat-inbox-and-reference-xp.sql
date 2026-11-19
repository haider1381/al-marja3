begin;

create function public.friend_chat_inbox_previews()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_object_agg(peer, jsonb_build_object('body', body, 'sent_at', created_at)), '{}'::jsonb)
  from (
    select distinct on (f.user_low, f.user_high)
      case when f.user_low = auth.uid() then f.user_high else f.user_low end as peer,
      m.body, m.created_at
    from private.friend_requests f
    join private.friend_chat_requests c using (user_low, user_high)
    join private.friend_chat_messages m using (user_low, user_high)
    where f.accepted and auth.uid() in (f.user_low, f.user_high)
      and (c.status = 'accepted' or (c.status = 'pending' and m.sender = c.sender))
      and private.can_chat_with(f.user_low, f.user_high)
      and private.can_chat_with(f.user_high, f.user_low)
    order by f.user_low, f.user_high, m.id desc
  ) recent;
$$;

create function public.spend_reference_xp(p_request uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null or p_request is null then raise exception 'not_authenticated'; end if;
  perform pg_advisory_xact_lock(hashtextextended(uid::text, 0));
  if exists (select 1 from public.study_xp_events
      where user_id = uid and event_key = 'reference:' || p_request::text) then return; end if;
  if (select 15 + coalesce(sum(points), 0) from public.study_xp_events where user_id = uid) < 1 then
    raise exception 'insufficient_xp';
  end if;
  insert into public.study_xp_events (user_id, event_key, activity, points)
  values (uid, 'reference:' || p_request::text, 'reference_values', -1);
end;
$$;

revoke all on function public.friend_chat_inbox_previews(), public.spend_reference_xp(uuid) from public, anon, authenticated;
grant execute on function public.friend_chat_inbox_previews(), public.spend_reference_xp(uuid) to authenticated;

commit;

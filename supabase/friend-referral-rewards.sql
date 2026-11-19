begin;

alter table private.friend_invite_claims
  add column reward_invited boolean not null default false;
alter table private.friend_invite_claims
  alter column reward_invited set default true;

create or replace function public.friend_invite_xp()
returns bigint language sql stable security definer set search_path = '' as $$
  select count(*) * 10
  from private.friend_invite_claims
  where inviter = auth.uid() or (reward_invited and invited_user = auth.uid());
$$;

create function public.friend_claim_signup_code(p_code text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  code uuid;
begin
  if auth.uid() is null or p_code is null or p_code !~ '^[A-F0-9]{10}$' then
    return false;
  end if;
  select invite_code into code
  from private.friend_profiles where friend_code = p_code;
  if code is null then return false; end if;
  return public.friend_claim_invite(code);
end;
$$;

revoke all on function public.friend_claim_signup_code(text) from public, anon, authenticated;
grant execute on function public.friend_claim_signup_code(text) to authenticated;

create or replace function public.friend_state()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  own jsonb;
  peers jsonb;
begin
  if uid is null then return null; end if;
  while not exists (select 1 from private.friend_profiles where user_id = uid) loop
    insert into private.friend_profiles (user_id, friend_code)
    values (uid, upper(left(replace(gen_random_uuid()::text, '-', ''), 10)))
    on conflict do nothing;
  end loop;
  select jsonb_build_object('friend_code', friend_code, 'invite_code', invite_code, 'share_progress', share_progress,
    'points', greatest(0, coalesce((select sum(event.points)
      from public.study_xp_events event where event.user_id = uid), 0)) + public.friend_invite_xp())
  into own from private.friend_profiles where user_id = uid;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', profile.user_id, 'friend_code', profile.friend_code, 'name', student.display_name,
    'avatar_url', student.avatar_url,
    'status', case when request.accepted then 'friend' when request.requested_by = uid then 'sent' else 'received' end,
    'points', case when request.accepted and profile.share_progress then
      greatest(0, coalesce((select sum(event.points) from public.study_xp_events event where event.user_id = profile.user_id), 0)) +
      (select count(*) * 10 from private.friend_invite_claims where inviter = profile.user_id or (reward_invited and invited_user = profile.user_id))
    end
  ) order by profile.friend_code), '[]'::jsonb)
  into peers
  from (
    select requests.*, user_high as peer from private.friend_requests requests where user_low = uid
    union all
    select requests.*, user_low as peer from private.friend_requests requests where user_high = uid
  ) request
  join private.friend_profiles profile on profile.user_id = request.peer
  left join public.profiles student on student.id = request.peer;
  return jsonb_build_object('profile', own, 'peers', peers);
end $$;

commit;

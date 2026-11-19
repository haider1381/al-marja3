begin;

-- Requires the existing XP ledger and its user_id and points columns.
do $$
begin
  perform event.user_id, event.points from public.study_xp_events event limit 0;
end $$;

create table private.friend_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  friend_code text not null unique check (friend_code ~ '^[A-F0-9]{10}$'),
  share_progress boolean not null default false,
  invite_code uuid not null default gen_random_uuid() unique
);

create table private.friend_requests (
  user_low uuid references auth.users(id) on delete cascade,
  user_high uuid references auth.users(id) on delete cascade,
  requested_by uuid not null,
  accepted boolean not null default false,
  primary key (user_low, user_high),
  check (user_low < user_high and requested_by in (user_low, user_high))
);
create index friend_requests_high_idx on private.friend_requests(user_high);

create table private.friend_invite_claims (
  invited_user uuid primary key references auth.users(id) on delete cascade,
  inviter uuid not null references auth.users(id) on delete cascade,
  check (invited_user <> inviter)
);
create index friend_invite_claims_inviter_idx on private.friend_invite_claims(inviter);

alter table private.friend_profiles enable row level security;
alter table private.friend_requests enable row level security;
alter table private.friend_invite_claims enable row level security;
revoke all on private.friend_profiles, private.friend_requests, private.friend_invite_claims from public, anon, authenticated;

create function public.friend_set_privacy(p_share boolean)
returns void language sql security definer set search_path = '' as $$
  update private.friend_profiles set share_progress = coalesce(p_share, false) where user_id = auth.uid();
$$;

create function public.friend_request(p_friend_code text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  peer uuid;
begin
  if uid is null or not exists (select 1 from private.friend_profiles where user_id = uid) then
    raise exception 'Friend profile unavailable';
  end if;
  select user_id into peer from private.friend_profiles where friend_code = upper(trim(p_friend_code));
  if peer is null or peer = uid then raise exception 'Friend ID unavailable'; end if;
  insert into private.friend_requests (user_low, user_high, requested_by)
  values (least(uid, peer), greatest(uid, peer), uid)
  on conflict (user_low, user_high) do nothing;
end $$;

create function public.friend_respond(p_peer uuid, p_accept boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null or p_peer is null then return; end if;
  if p_accept is true then
    update private.friend_requests set accepted = true
    where user_low = least(uid, p_peer) and user_high = greatest(uid, p_peer)
      and not accepted and requested_by = p_peer;
  else
    delete from private.friend_requests
    where user_low = least(uid, p_peer) and user_high = greatest(uid, p_peer);
  end if;
end $$;

create function public.friend_claim_invite(p_code uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  inviter_id uuid;
begin
  if uid is null then return false; end if;
  select user_id into inviter_id from private.friend_profiles where invite_code = p_code;
  if inviter_id is null or inviter_id = uid then return false; end if;
  if not exists (select 1 from auth.users where id = uid and created_at >= now() - interval '7 days'
                 and (email_confirmed_at is not null or phone_confirmed_at is not null)
                 and not coalesce(is_anonymous, false)) then return false; end if;
  insert into private.friend_invite_claims (invited_user, inviter)
  values (uid, inviter_id) on conflict (invited_user) do nothing;
  return found;
end $$;

create function public.friend_invite_xp()
returns bigint language sql stable security definer set search_path = '' as $$
  select count(*) * 10 from private.friend_invite_claims where inviter = auth.uid();
$$;

create function public.friend_state()
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
  select jsonb_build_object('friend_code', friend_code, 'invite_code', invite_code, 'share_progress', share_progress)
  into own from private.friend_profiles where user_id = uid;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', profile.user_id, 'friend_code', profile.friend_code, 'name', student.display_name,
    'status', case when request.accepted then 'friend' when request.requested_by = uid then 'sent' else 'received' end,
    'points', case when request.accepted and profile.share_progress then
      greatest(0, coalesce((select sum(event.points) from public.study_xp_events event where event.user_id = profile.user_id), 0)) +
      (select count(*) * 10 from private.friend_invite_claims where inviter = profile.user_id)
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

revoke all on function public.friend_set_privacy(boolean),
  public.friend_request(text), public.friend_respond(uuid,boolean), public.friend_claim_invite(uuid),
  public.friend_invite_xp(), public.friend_state() from public, anon;
grant execute on function public.friend_set_privacy(boolean),
  public.friend_request(text), public.friend_respond(uuid,boolean), public.friend_claim_invite(uuid),
  public.friend_invite_xp(), public.friend_state() to authenticated;

commit;

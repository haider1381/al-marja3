begin;

create or replace function public.friend_chat(p_peer uuid, p_action text default 'read', p_body text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
  lo uuid := least(uid, p_peer);
  hi uuid := greatest(uid, p_peer);
  thread private.friend_chat_requests%rowtype;
  allowed boolean;
begin
  if uid is null or p_peer is null or uid = p_peer then raise exception 'not_friends'; end if;
  perform 1 from private.friend_requests where user_low = lo and user_high = hi and accepted for share;
  if not found then raise exception 'not_friends'; end if;
  select * into thread from private.friend_chat_requests where user_low = lo and user_high = hi for update;
  allowed := private.can_chat_with(uid, p_peer) and private.can_chat_with(p_peer, uid);
  case p_action
    when 'read' then null;
    when 'request' then
      if not allowed then raise exception 'chat_disabled'; end if;
      insert into private.friend_chat_requests values (lo, hi, uid, 'pending')
        on conflict (user_low, user_high) do nothing;
      if found and nullif(trim(p_body), '') is not null then
        insert into private.friend_chat_messages (user_low, user_high, sender, body)
        values (lo, hi, uid, trim(p_body));
      end if;
    when 'accept', 'decline' then
      if not allowed and p_action = 'accept' then raise exception 'chat_disabled'; end if;
      update private.friend_chat_requests set status = case p_action when 'accept' then 'accepted' else 'declined' end
        where user_low = lo and user_high = hi and sender = p_peer and status = 'pending';
    when 'send' then
      if not allowed or thread.status is distinct from 'accepted' then raise exception 'chat_not_approved'; end if;
      insert into private.friend_chat_messages (user_low, user_high, sender, body) values (lo, hi, uid, trim(p_body));
    else raise exception 'invalid_action';
  end case;
  select * into thread from private.friend_chat_requests where user_low = lo and user_high = hi;
  return jsonb_build_object('status', thread.status, 'incoming', thread.sender = p_peer, 'allowed', allowed,
    'first_message_supported', true,
    'request_preview', case when thread.status = 'pending' and thread.sender = p_peer then (
      select body from private.friend_chat_messages
      where user_low = lo and user_high = hi and sender = p_peer order by id asc limit 1
    ) end,
    'messages', case when thread.status = 'accepted' and allowed then coalesce((
      select jsonb_agg(jsonb_build_object('mine', sender = uid, 'body', body, 'created_at', created_at) order by id)
      from (select id, sender, body, created_at from private.friend_chat_messages
            where user_low = lo and user_high = hi order by id desc limit 100) recent), '[]'::jsonb)
      else '[]'::jsonb end);
end;
$$;

create table private.friend_blocks (
  blocker uuid references auth.users(id) on delete cascade,
  blocked uuid references auth.users(id) on delete cascade,
  primary key (blocker, blocked),
  check (blocker <> blocked)
);
create table private.friend_presence (
  user_id uuid primary key references auth.users(id) on delete cascade,
  seen_at timestamptz not null
);
alter table private.friend_blocks enable row level security;
alter table private.friend_presence enable row level security;
revoke all on private.friend_blocks, private.friend_presence from public, anon, authenticated;

create or replace function public.friend_request(p_friend_code text)
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
  perform pg_advisory_xact_lock(hashtextextended(least(uid, peer)::text || greatest(uid, peer)::text, 0));
  if exists (select 1 from private.friend_blocks where (blocker, blocked) in ((uid, peer), (peer, uid))) then
    raise exception 'Friend ID unavailable';
  end if;
  insert into private.friend_requests (user_low, user_high, requested_by)
  values (least(uid, peer), greatest(uid, peer), uid)
  on conflict (user_low, user_high) do nothing;
end $$;

create function public.friend_block(p_peer uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null or p_peer is null or uid = p_peer then raise exception 'invalid_peer'; end if;
  perform pg_advisory_xact_lock(hashtextextended(least(uid, p_peer)::text || greatest(uid, p_peer)::text, 0));
  if not exists (select 1 from private.friend_requests
      where user_low = least(uid, p_peer) and user_high = greatest(uid, p_peer)) then
    raise exception 'invalid_peer';
  end if;
  insert into private.friend_blocks values (uid, p_peer) on conflict do nothing;
  delete from private.friend_requests where user_low = least(uid, p_peer) and user_high = greatest(uid, p_peer);
end;
$$;

create function public.friend_presence(p_active boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if p_active then
    insert into private.friend_presence values (uid, now())
    on conflict (user_id) do update set seen_at = excluded.seen_at
    where private.friend_presence.seen_at < now() - interval '20 seconds';
  end if;
  return coalesce((select jsonb_object_agg(p.user_id, p.seen_at)
    from private.friend_requests f join private.friend_presence p
      on p.user_id = case when f.user_low = uid then f.user_high else f.user_low end
    where uid in (f.user_low, f.user_high) and f.accepted), '{}'::jsonb);
end;
$$;

revoke all on function public.friend_block(uuid), public.friend_presence(boolean) from public, anon, authenticated;
grant execute on function public.friend_block(uuid), public.friend_presence(boolean) to authenticated;

commit;

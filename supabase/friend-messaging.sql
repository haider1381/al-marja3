begin;

create table private.friend_chat_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  mode text not null check (mode in ('off', 'friends', 'selected'))
);
create table private.friend_chat_allowed (
  user_id uuid references auth.users(id) on delete cascade,
  peer_id uuid references auth.users(id) on delete cascade,
  primary key (user_id, peer_id)
);
create table private.friend_chat_requests (
  user_low uuid references auth.users(id) on delete cascade,
  user_high uuid references auth.users(id) on delete cascade,
  sender uuid not null,
  status text not null check (status in ('pending', 'accepted', 'declined')),
  primary key (user_low, user_high)
);
create table private.friend_chat_messages (
  id bigint generated always as identity primary key,
  user_low uuid not null,
  user_high uuid not null,
  sender uuid not null,
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now(),
  foreign key (user_low, user_high) references private.friend_chat_requests on delete cascade
);
create index friend_chat_thread on private.friend_chat_messages(user_low, user_high, id desc);

alter table private.friend_chat_settings enable row level security;
alter table private.friend_chat_allowed enable row level security;
alter table private.friend_chat_requests enable row level security;
alter table private.friend_chat_messages enable row level security;
revoke all on private.friend_chat_settings, private.friend_chat_allowed,
  private.friend_chat_requests, private.friend_chat_messages from public, anon, authenticated;

create function private.can_chat_with(p_recipient uuid, p_peer uuid)
returns boolean language sql stable set search_path = '' as $$
  select case coalesce((select mode from private.friend_chat_settings where user_id = p_recipient), 'off')
    when 'friends' then true
    when 'selected' then exists (select 1 from private.friend_chat_allowed where user_id = p_recipient and peer_id = p_peer)
    else false end;
$$;

create function public.friend_chat_preferences(p_mode text default null, p_peers uuid[] default '{}')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if p_mode is not null then
    if cardinality(p_peers) > 200 then raise exception 'too_many_friends'; end if;
    insert into private.friend_chat_settings values (uid, p_mode)
      on conflict (user_id) do update set mode = excluded.mode;
    delete from private.friend_chat_allowed where user_id = uid;
    insert into private.friend_chat_allowed
      select uid, peer from unnest(p_peers) peers(peer)
      join private.friend_requests f on f.user_low = least(uid, peer) and f.user_high = greatest(uid, peer)
      where f.accepted on conflict do nothing;
  end if;
  return jsonb_build_object('mode', coalesce((select mode from private.friend_chat_settings where user_id = uid), 'off'),
    'peers', coalesce((select jsonb_agg(peer_id) from private.friend_chat_allowed where user_id = uid), '[]'::jsonb));
end;
$$;

create function public.friend_chat(p_peer uuid, p_action text default 'read', p_body text default null)
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
    'messages', case when thread.status = 'accepted' and allowed then coalesce((
      select jsonb_agg(jsonb_build_object('mine', sender = uid, 'body', body, 'created_at', created_at) order by id)
      from (select id, sender, body, created_at from private.friend_chat_messages
            where user_low = lo and user_high = hi order by id desc limit 100) recent), '[]'::jsonb)
      else '[]'::jsonb end);
end;
$$;

create function public.friend_chat_incoming()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(request.sender order by request.sender), '[]'::jsonb)
  from private.friend_chat_requests request
  join private.friend_requests friendship using (user_low, user_high)
  where auth.uid() in (request.user_low, request.user_high)
    and request.sender <> auth.uid() and request.status = 'pending' and friendship.accepted;
$$;

revoke all on function public.friend_chat_incoming() from public, anon, authenticated;
grant execute on function public.friend_chat_incoming() to authenticated;

create function private.clear_chat_on_unfriend()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  delete from private.friend_chat_requests where user_low = old.user_low and user_high = old.user_high;
  delete from private.friend_chat_allowed
    where (user_id, peer_id) in ((old.user_low, old.user_high), (old.user_high, old.user_low));
  return old;
end;
$$;
create trigger clear_chat_on_unfriend after delete on private.friend_requests
for each row execute function private.clear_chat_on_unfriend();

revoke all on function private.can_chat_with(uuid, uuid), private.clear_chat_on_unfriend(),
  public.friend_chat_preferences(text, uuid[]), public.friend_chat(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.friend_chat_preferences(text, uuid[]), public.friend_chat(uuid, text, text)
  to authenticated;

commit;

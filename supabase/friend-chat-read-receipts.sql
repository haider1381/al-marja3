alter table private.friend_chat_messages add column if not exists seen_at timestamptz;

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
    'messages', case when allowed and (thread.status = 'accepted' or (thread.status = 'pending' and thread.sender = uid)) then coalesce((
      select jsonb_agg(jsonb_build_object('id', id::text, 'mine', sender = uid, 'body', body, 'created_at', created_at,
        'seen', sender = uid and seen_at is not null) order by id)
      from (select id, sender, body, created_at, seen_at from private.friend_chat_messages
            where user_low = lo and user_high = hi
              and (thread.status = 'accepted' or sender = uid) order by id desc limit 100) recent), '[]'::jsonb)
      else '[]'::jsonb end);
end;
$$;

create or replace function public.friend_chat_mark_seen(p_peer uuid, p_ids bigint[])
returns void language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  lo uuid := least(uid, p_peer);
  hi uuid := greatest(uid, p_peer);
begin
  if uid is null or p_peer is null or uid = p_peer or coalesce(cardinality(p_ids), 0) not between 1 and 100 then
    return;
  end if;
  perform 1 from private.friend_requests
    where user_low = lo and user_high = hi and accepted for share;
  if not found then return; end if;
  if not (private.can_chat_with(uid, p_peer) and private.can_chat_with(p_peer, uid)) then return; end if;
  if not exists (select 1 from private.friend_chat_requests
    where user_low = lo and user_high = hi and status = 'accepted') then return; end if;

  update private.friend_chat_messages set seen_at = now()
    where id = any(p_ids) and user_low = lo and user_high = hi
      and sender = p_peer and seen_at is null;
end;
$$;

revoke all on function public.friend_chat_mark_seen(uuid, bigint[]) from public, anon, authenticated;
grant execute on function public.friend_chat_mark_seen(uuid, bigint[]) to authenticated;

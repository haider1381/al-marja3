begin;

create function public.friend_message_notices()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('peer', peer, 'message_id', latest::text)), '[]'::jsonb)
  from (
    select m.sender as peer, max(m.id) as latest
    from private.friend_chat_messages m
    join private.friend_chat_requests c using (user_low, user_high)
    join private.friend_requests f using (user_low, user_high)
    where auth.uid() in (m.user_low, m.user_high)
      and m.sender <> auth.uid() and c.status = 'accepted' and f.accepted
      and private.can_chat_with(auth.uid(), m.sender)
      and private.can_chat_with(m.sender, auth.uid())
    group by m.sender
  ) messages;
$$;

revoke all on function public.friend_message_notices() from public, anon, authenticated;
grant execute on function public.friend_message_notices() to authenticated;

commit;

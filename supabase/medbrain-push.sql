begin;
create extension if not exists pg_net;
revoke usage on schema net from public, anon, authenticated;
revoke all on net.http_request_queue, net._http_response from public, anon, authenticated;

create table private.medbrain_push_subscriptions (
  endpoint text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  p256dh text not null,
  auth_key text not null,
  updated_at timestamptz not null default now()
);
create index on private.medbrain_push_subscriptions (user_id);
alter table private.medbrain_push_subscriptions enable row level security;
revoke all on private.medbrain_push_subscriptions from public, anon, authenticated;

create function public.medbrain_push_key()
returns text language sql stable security definer set search_path = '' as $$
  select decrypted_secret from vault.decrypted_secrets
  where name = 'medbrain_push_public' and auth.uid() is not null;
$$;

create function public.medbrain_push_subscription(p_endpoint text, p_p256dh text default null, p_auth text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if p_p256dh is null and p_auth is null then
    delete from private.medbrain_push_subscriptions where endpoint = p_endpoint and user_id = uid;
    return;
  end if;
  if not coalesce(char_length(p_endpoint) <= 2048
     and p_endpoint ~ '^https://(fcm[.]googleapis[.]com|updates[.]push[.]services[.]mozilla[.]com|web[.]push[.]apple[.]com|[a-z0-9.-]+[.]notify[.]windows[.]com)/[^[:space:]#]+$'
     and p_p256dh ~ '^[A-Za-z0-9_-]{87}$' and p_auth ~ '^[A-Za-z0-9_-]{22}$', false) then
    raise exception 'unsupported_push_subscription';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(uid::text, 91));
  insert into private.medbrain_push_subscriptions (endpoint,user_id,p256dh,auth_key)
    values (p_endpoint,uid,p_p256dh,p_auth)
    on conflict (endpoint) do update set user_id=excluded.user_id, p256dh=excluded.p256dh, auth_key=excluded.auth_key, updated_at=now();
  delete from private.medbrain_push_subscriptions where endpoint in (
    select endpoint from private.medbrain_push_subscriptions where user_id=uid order by updated_at desc,endpoint offset 8
  );
end;
$$;

create function public.medbrain_push_delivery(p_token text,p_user uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare token text;
begin
  select decrypted_secret into token from vault.decrypted_secrets where name='medbrain_push_dispatch';
  if token is null or p_token is distinct from token then return null; end if;
  return jsonb_build_object(
    'public_key',(select decrypted_secret from vault.decrypted_secrets where name='medbrain_push_public'),
    'private_key',(select decrypted_secret from vault.decrypted_secrets where name='medbrain_push_private'),
    'subscriptions',coalesce((select jsonb_agg(jsonb_build_object(
      'endpoint',endpoint,'keys',jsonb_build_object('auth',auth_key,'p256dh',p256dh)
    )) from private.medbrain_push_subscriptions where user_id=p_user),'[]'::jsonb)
  );
end;
$$;

create function public.medbrain_push_prune(p_endpoint text)
returns void language sql security definer set search_path = '' as $$
  delete from private.medbrain_push_subscriptions where endpoint=p_endpoint;
$$;

create function private.medbrain_queue_push(p_user uuid,p_kind text)
returns void language plpgsql security definer set search_path = '' as $$
declare token text;
begin
  if not exists (select 1 from private.medbrain_push_subscriptions where user_id=p_user) then return; end if;
  select decrypted_secret into token from vault.decrypted_secrets where name='medbrain_push_dispatch';
  if token is null then return; end if;
  perform net.http_post(
    url := 'https://wuvzteosknrzddsaexez.supabase.co/functions/v1/medbrain-push',
    headers := jsonb_build_object('Content-Type','application/json','x-medbrain-dispatch',token),
    body := jsonb_build_object('user',p_user,'kind',p_kind),
    timeout_milliseconds := 10000
  );
exception when others then
  raise warning 'Could not queue Medbrain push (%)', sqlstate;
end;
$$;

create function private.medbrain_friend_push()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' and not new.accepted then
    perform private.medbrain_queue_push(case when new.requested_by=new.user_low then new.user_high else new.user_low end,'friend_request');
  elsif tg_op = 'UPDATE' and new.accepted and not old.accepted then
    perform private.medbrain_queue_push(new.requested_by,'friend_accepted');
  end if;
  return new;
end;
$$;

create function private.medbrain_chat_push()
returns trigger language plpgsql security definer set search_path = '' as $$
declare state text;
begin
  select status into state from private.friend_chat_requests
  where user_low=new.user_low and user_high=new.user_high;
  if state in ('accepted','pending') then
    perform private.medbrain_queue_push(case when new.sender=new.user_low then new.user_high else new.user_low end,
      case when state='pending' then 'chat_request' else 'message' end);
  end if;
  return new;
end;
$$;

create trigger medbrain_friend_push after insert or update of accepted on private.friend_requests
for each row execute function private.medbrain_friend_push();
create trigger medbrain_chat_push after insert on private.friend_chat_messages
for each row execute function private.medbrain_chat_push();

revoke all on function public.medbrain_push_key(), public.medbrain_push_subscription(text,text,text), public.medbrain_push_delivery(text,uuid), public.medbrain_push_prune(text) from public, anon, authenticated;
revoke all on function private.medbrain_queue_push(uuid,text), private.medbrain_friend_push(), private.medbrain_chat_push() from public, anon, authenticated;
grant execute on function public.medbrain_push_key(), public.medbrain_push_subscription(text,text,text) to authenticated;
grant execute on function public.medbrain_push_delivery(text,uuid), public.medbrain_push_prune(text) to service_role;
commit;

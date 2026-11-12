-- A code belongs forever to the first account that redeems it. Deleting that account used to null
-- redeemed_by and free the code for someone else; now redeemed_at (never cleared) marks it as spent,
-- and the redeeming email is kept for the owner's list. Also: a public support contact for every visitor.
begin;

alter table private.subscription_codes add column if not exists redeemed_email text;
update private.subscription_codes c set redeemed_email = u.email
  from auth.users u where u.id = c.redeemed_by and c.redeemed_email is null;

create or replace function public.redeem_code(p_code text)
returns timestamptz language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  c private.subscription_codes;
  start_at timestamptz;
begin
  if uid is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  select * into c from private.subscription_codes
   where code = upper(regexp_replace(coalesce(p_code, ''), '\s', '', 'g')) for update;
  if not found or c.revoked then raise exception 'invalid_code' using errcode = 'P0001'; end if;
  if c.redeemed_at is not null then
    if c.redeemed_by = uid then return c.expires_at; end if;
    raise exception 'code_used' using errcode = 'P0001';
  end if;
  start_at := greatest(now(), coalesce(public.my_subscription_end(), now()));
  update private.subscription_codes
     set redeemed_by = uid, redeemed_at = now(), expires_at = start_at + make_interval(days => c.days),
         redeemed_email = (select email from auth.users where id = uid)
   where id = c.id
  returning expires_at into c.expires_at;
  return c.expires_at;
end;
$$;

drop function if exists public.admin_list_codes();
create function public.admin_list_codes()
returns table(id uuid, code text, plan text, note text, created_at timestamptz, redeemed_email text,
              redeemed_at timestamptz, expires_at timestamptz, revoked boolean)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_owner() then raise exception 'Only the owner' using errcode = '42501'; end if;
  return query
    select c.id, c.code, c.plan, c.note, c.created_at, coalesce(u.email::text, c.redeemed_email), c.redeemed_at, c.expires_at, c.revoked
      from private.subscription_codes c left join auth.users u on u.id = c.redeemed_by
     order by c.created_at desc limit 500;
end;
$$;
revoke all on function public.admin_list_codes() from public, anon;
grant execute on function public.admin_list_codes() to authenticated;

-- The support Telegram handle is not secret: anyone (even signed out) may read it.
create or replace function public.support_contact()
returns text language sql stable security definer set search_path = ''
as $$ select coalesce((select value->>'telegram' from private.app_settings where key = 'paywall'), ''); $$;
revoke all on function public.support_contact() from public;
grant execute on function public.support_contact() to anon, authenticated;

update private.app_settings set value = jsonb_set(value, '{telegram}', '"ha_hayder"')
 where key = 'paywall' and coalesce(value->>'telegram', '') = '';
commit;

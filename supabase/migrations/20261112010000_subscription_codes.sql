-- Subscription codes: the owner generates one code per student (monthly, yearly, ...).
-- A student redeems a code once; access lasts until it expires. A paywall switch (off by default)
-- decides whether library content needs an active subscription. Owner/editors always have access.
begin;

create table if not exists private.app_settings (
  key text primary key,
  value jsonb not null
);
alter table private.app_settings enable row level security;
revoke all on private.app_settings from public, anon, authenticated;
insert into private.app_settings(key, value) values ('paywall', '{"enabled": false, "telegram": ""}')
on conflict (key) do nothing;

create table if not exists private.subscription_codes (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  plan text not null check (plan in ('month', 'quarter', 'half', 'year')),
  days integer not null check (days > 0),
  note text check (note is null or char_length(note) <= 200),
  created_at timestamptz not null default now(),
  redeemed_by uuid references auth.users(id) on delete set null,
  redeemed_at timestamptz,
  expires_at timestamptz,
  revoked boolean not null default false
);
create index if not exists subscription_codes_user_idx on private.subscription_codes (redeemed_by, expires_at desc);
alter table private.subscription_codes enable row level security;
revoke all on private.subscription_codes from public, anon, authenticated;

-- Current subscription end for the calling user (null when none).
create or replace function public.my_subscription_end()
returns timestamptz language sql stable security definer set search_path = ''
as $$
  select max(expires_at) from private.subscription_codes
  where redeemed_by = (select auth.uid()) and not revoked;
$$;

create or replace function public.has_access()
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce((select (value->>'enabled')::boolean from private.app_settings where key = 'paywall'), false) = false
      or public.is_editor()
      or coalesce(public.my_subscription_end() > now(), false);
$$;

-- What the app needs to decide whether to ask for a code or show the expiry message.
create or replace function public.my_access()
returns jsonb language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'paywall', coalesce((select (value->>'enabled')::boolean from private.app_settings where key = 'paywall'), false),
    'telegram', coalesce((select value->>'telegram' from private.app_settings where key = 'paywall'), ''),
    'staff', public.is_editor(),
    'owner', public.is_owner(),
    'expires_at', public.my_subscription_end(),
    'ever_subscribed', exists(select 1 from private.subscription_codes where redeemed_by = (select auth.uid())),
    'active', public.has_access()
  );
$$;

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
  if c.redeemed_by is not null then
    if c.redeemed_by = uid then return c.expires_at; end if;
    raise exception 'code_used' using errcode = 'P0001';
  end if;
  -- A renewal before expiry extends the current subscription instead of overlapping it.
  start_at := greatest(now(), coalesce(public.my_subscription_end(), now()));
  update private.subscription_codes
     set redeemed_by = uid, redeemed_at = now(), expires_at = start_at + make_interval(days => c.days)
   where id = c.id
  returning expires_at into c.expires_at;
  return c.expires_at;
end;
$$;

create or replace function public.admin_create_code(p_plan text, p_note text default null)
returns text language plpgsql security definer set search_path = ''
as $$
declare
  d integer;
  new_code text;
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  i integer;
begin
  if not public.is_owner() then raise exception 'Only the owner can create codes' using errcode = '42501'; end if;
  d := case p_plan when 'month' then 30 when 'quarter' then 90 when 'half' then 180 when 'year' then 365 end;
  if d is null then raise exception 'Unknown plan' using errcode = '22023'; end if;
  loop
    new_code := 'MB-';
    for i in 1..10 loop
      new_code := new_code || substr(alphabet, 1 + (get_byte(extensions.gen_random_bytes(1), 0) % 32), 1);
      if i = 5 then new_code := new_code || '-'; end if;
    end loop;
    exit when not exists (select 1 from private.subscription_codes where code = new_code);
  end loop;
  insert into private.subscription_codes(code, plan, days, note) values (new_code, p_plan, d, nullif(trim(p_note), ''));
  return new_code;
end;
$$;

create or replace function public.admin_list_codes()
returns table(id uuid, code text, plan text, note text, created_at timestamptz, redeemed_email text,
              redeemed_at timestamptz, expires_at timestamptz, revoked boolean)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_owner() then raise exception 'Only the owner' using errcode = '42501'; end if;
  return query
    select c.id, c.code, c.plan, c.note, c.created_at, u.email::text, c.redeemed_at, c.expires_at, c.revoked
      from private.subscription_codes c left join auth.users u on u.id = c.redeemed_by
     order by c.created_at desc limit 500;
end;
$$;

create or replace function public.admin_revoke_code(p_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_owner() then raise exception 'Only the owner' using errcode = '42501'; end if;
  update private.subscription_codes set revoked = true where id = p_id;
end;
$$;

create or replace function public.admin_set_paywall(p_enabled boolean, p_telegram text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_owner() then raise exception 'Only the owner' using errcode = '42501'; end if;
  insert into private.app_settings(key, value)
  values ('paywall', jsonb_build_object('enabled', coalesce(p_enabled, false), 'telegram', left(coalesce(trim(p_telegram), ''), 100)))
  on conflict (key) do update set value = excluded.value;
end;
$$;

revoke all on function public.my_subscription_end(), public.has_access(), public.my_access(), public.redeem_code(text),
  public.admin_create_code(text, text), public.admin_list_codes(), public.admin_revoke_code(uuid),
  public.admin_set_paywall(boolean, text) from public, anon;
grant execute on function public.my_subscription_end(), public.has_access(), public.my_access(), public.redeem_code(text),
  public.admin_create_code(text, text), public.admin_list_codes(), public.admin_revoke_code(uuid),
  public.admin_set_paywall(boolean, text) to authenticated;

-- Library content is readable only with access (always true while the paywall is off).
drop policy if exists lectures_read on public.lectures;
create policy lectures_read on public.lectures for select to authenticated using ((select public.has_access()));
drop policy if exists library_flashcards_read on public.library_flashcards;
create policy library_flashcards_read on public.library_flashcards for select to authenticated using ((select public.has_access()));
drop policy if exists flashcard_decks_read on public.flashcard_decks;
create policy flashcard_decks_read on public.flashcard_decks for select to authenticated using ((select public.has_access()));
commit;

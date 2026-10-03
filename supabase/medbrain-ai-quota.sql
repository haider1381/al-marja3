-- Additive, server-only counters. No lecture, profile or permission changes.
create table private.medbrain_ai_usage (
  scope text not null,
  usage_day date not null,
  requests integer not null default 0 check (requests >= 0),
  last_request_at timestamptz,
  primary key(scope, usage_day)
);
alter table private.medbrain_ai_usage enable row level security;
revoke all on private.medbrain_ai_usage from public, anon, authenticated;
grant usage on schema private to service_role;
grant select, insert, update, delete on private.medbrain_ai_usage to service_role;
create policy medbrain_ai_server_only on private.medbrain_ai_usage for all to service_role using (true) with check (true);

create function public.medbrain_ai_reserve(request_user uuid)
returns jsonb language plpgsql security invoker
set search_path = '' as $$
declare
  today date := (now() at time zone 'UTC')::date;
  global_row private.medbrain_ai_usage%rowtype;
  user_row private.medbrain_ai_usage%rowtype;
  wait_seconds integer;
begin
  if request_user is null then raise exception 'User required'; end if;
  perform pg_catalog.pg_advisory_xact_lock(741829360);
  delete from private.medbrain_ai_usage where usage_day < today - 7;
  insert into private.medbrain_ai_usage(scope, usage_day) values ('global',today), (request_user::text,today) on conflict do nothing;
  select * into global_row from private.medbrain_ai_usage where scope='global' and usage_day=today;
  select * into user_row from private.medbrain_ai_usage where scope=request_user::text and usage_day=today;
  if global_row.requests >= 40 or user_row.requests >= 15 then
    return jsonb_build_object('allowed',false,'code','daily_limit','retry_seconds', greatest(1,ceil(extract(epoch from ((today+1)::timestamp at time zone 'UTC')-now()))::integer));
  end if;
  wait_seconds := greatest(0,ceil(20-extract(epoch from now()-global_row.last_request_at))::integer,ceil(10-extract(epoch from now()-user_row.last_request_at))::integer);
  if wait_seconds > 0 then return jsonb_build_object('allowed',false,'code','slow_down','retry_seconds',wait_seconds); end if;
  update private.medbrain_ai_usage set requests=requests+1,last_request_at=now() where usage_day=today and scope in ('global',request_user::text);
  return jsonb_build_object('allowed',true,'remaining',15-user_row.requests-1);
end;
$$;
revoke all on function public.medbrain_ai_reserve(uuid) from public, anon, authenticated;
grant execute on function public.medbrain_ai_reserve(uuid) to service_role;

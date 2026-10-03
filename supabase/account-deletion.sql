-- Read-only preflight and narrow quota cleanup for the authenticated Edge Function.
-- Browser roles never execute these functions or choose a deletion target.
begin;
-- Column-limited reads required by SECURITY INVOKER; only the trusted server role.
grant select(id,user_id,not_after) on auth.sessions to service_role;
grant select(id) on auth.users to service_role;
grant select(user_id) on private.owners to service_role;
create or replace function public.account_deletion_context(target_user uuid,target_session uuid)
returns jsonb language sql security invoker set search_path='' as $$
 select jsonb_build_object(
 'session_active',exists(select 1 from auth.sessions where id=target_session and user_id=target_user and (not_after is null or not_after>now())),
 'is_owner',exists(select 1 from private.owners where user_id=target_user),
 'objects',coalesce((select jsonb_agg(jsonb_build_object('bucket',bucket_id,'name',name)) from storage.objects where owner_id=target_user::text or owner=target_user),'[]'::jsonb));
$$;
revoke all on function public.account_deletion_context(uuid,uuid) from public,anon,authenticated;
grant execute on function public.account_deletion_context(uuid,uuid) to service_role;
create or replace function public.account_deletion_clear_usage(target_user uuid)
returns void language sql security invoker set search_path='' as $$
 delete from private.medbrain_ai_usage where scope=target_user::text and not exists(select 1 from auth.users where id=target_user);
$$;
revoke all on function public.account_deletion_clear_usage(uuid) from public,anon,authenticated;
grant execute on function public.account_deletion_clear_usage(uuid) to service_role;
commit;
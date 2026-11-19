begin;

create function public.owner_registered_user_count()
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or public.is_owner() is distinct from true then
    raise exception 'not_owner' using errcode = '42501';
  end if;
  return (
    select count(*) from auth.users
    where not coalesce(is_anonymous, false) and deleted_at is null
  );
end;
$$;

revoke all on function public.owner_registered_user_count() from public, anon, authenticated;
grant execute on function public.owner_registered_user_count() to authenticated;

commit;

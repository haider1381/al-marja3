-- Owner can manage editor membership; preserve all content and existing editors.
begin;
create table if not exists private.owners (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table private.owners enable row level security;
revoke all on private.owners from public, anon, authenticated;

create or replace function public.is_owner()
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (select 1 from private.owners where user_id = (select auth.uid()));
$$;
revoke all on function public.is_owner() from public, anon, authenticated;
grant execute on function public.is_owner() to authenticated;

create or replace function public.is_editor()
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (select 1 from private.editors where user_id = (select auth.uid()))
      or exists (select 1 from private.owners where user_id = (select auth.uid()));
$$;
revoke all on function public.is_editor() from public, anon, authenticated;
grant execute on function public.is_editor() to authenticated;

create or replace function public.set_editor(target_user_id uuid, enabled boolean)
returns void language plpgsql security definer
set search_path = ''
as $$
begin
  if not public.is_owner() then
    raise exception 'Only the owner can manage editors' using errcode = '42501';
  end if;
  if target_user_id is null or enabled is null then
    raise exception 'User and enabled are required' using errcode = '22023';
  end if;
  if enabled then
    insert into private.editors(user_id) values (target_user_id) on conflict do nothing;
  else
    delete from private.editors where user_id = target_user_id;
  end if;
end;
$$;
revoke all on function public.set_editor(uuid, boolean) from public, anon, authenticated;
grant execute on function public.set_editor(uuid, boolean) to authenticated;
commit;

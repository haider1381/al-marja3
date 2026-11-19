begin;

alter table private.friend_profiles add column share_leaderboard boolean not null default false;

create function public.medbrain_leaderboard(p_share boolean default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if p_share is not null then
    perform public.friend_state();
    update private.friend_profiles set share_leaderboard = p_share where user_id = uid;
  end if;
  return jsonb_build_object(
    'sharing', coalesce((select share_leaderboard from private.friend_profiles where user_id = uid), false),
    'top', coalesce((
      select jsonb_agg(jsonb_build_object('name', name, 'points', points) order by points desc, name)
      from (
        select coalesce(nullif(trim(student.display_name), ''), 'طالب') as name,
          greatest(0, coalesce((select sum(event.points) from public.study_xp_events event where event.user_id = f.user_id), 0)) +
          (select count(*) * 10 from private.friend_invite_claims c
           where c.inviter = f.user_id or (c.reward_invited and c.invited_user = f.user_id)) as points
        from private.friend_profiles f
        left join public.profiles student on student.id = f.user_id
        where f.share_leaderboard
        order by points desc, name, f.user_id
        limit 10
      ) ranked
    ), '[]'::jsonb));
end;
$$;

create table private.medbrain_support_suggestions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 200),
  details text not null check (char_length(trim(details)) between 1 and 1000),
  status text not null default 'open' check (status in ('open', 'approved', 'dismissed')),
  created_at timestamptz not null default now()
);
alter table private.medbrain_support_suggestions enable row level security;
revoke all on private.medbrain_support_suggestions from public, anon, authenticated;
create unique index medbrain_support_one_open
  on private.medbrain_support_suggestions (user_id, lower(trim(title))) where status = 'open';

create function public.medbrain_submit_suggestion(p_title text, p_details text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  insert into private.medbrain_support_suggestions (user_id, title, details)
  values (auth.uid(), trim(p_title), trim(p_details));
end;
$$;

create function public.medbrain_review_suggestions(p_id uuid default null, p_approve boolean default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare suggestion private.medbrain_support_suggestions%rowtype;
begin
  if not public.is_owner() then raise exception 'not_owner'; end if;
  if p_id is not null and p_approve is not null then
    update private.medbrain_support_suggestions set status = case when p_approve then 'approved' else 'dismissed' end
    where id = p_id and status = 'open' returning * into suggestion;
    if found and p_approve then
      insert into public.study_xp_events (user_id, event_key, activity, points)
      values (suggestion.user_id, 'support-suggestion:' || md5(lower(trim(suggestion.title))), 'helpful_report', 2)
      on conflict (user_id, event_key) do nothing;
    end if;
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', id, 'title', title, 'details', details) order by created_at)
    from (select * from private.medbrain_support_suggestions where status = 'open' order by created_at limit 50) pending
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.medbrain_leaderboard(boolean), public.medbrain_submit_suggestion(text, text),
  public.medbrain_review_suggestions(uuid, boolean) from public, anon, authenticated;
grant execute on function public.medbrain_leaderboard(boolean), public.medbrain_submit_suggestion(text, text),
  public.medbrain_review_suggestions(uuid, boolean) to authenticated;

commit;

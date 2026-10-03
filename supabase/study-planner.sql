begin;
-- Snapshot existing tasks before additive changes; no existing tasks are rewritten.
create table setup_backup.study_schedule_before_planner_20261003 as select * from public.study_schedule;
alter table setup_backup.study_schedule_before_planner_20261003 enable row level security;
revoke all on setup_backup.study_schedule_before_planner_20261003 from public,anon,authenticated;

create table public.study_chapter_plans (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 category text not null check(category in ('Medicine','Surgery','Pediatrics','OB/GYN')),
 chapter text not null check(char_length(chapter) between 1 and 160),
 planned_days integer not null default 7 check(planned_days between 1 and 365),
 start_date date not null default current_date,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(user_id,category,chapter),unique(id,user_id)
);
create table public.study_plan_topics (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 plan_id uuid not null,
 lecture_id uuid references public.lectures(id) on delete set null,
 title text not null check(char_length(title) between 1 and 200),
 completed boolean not null default false,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 foreign key(plan_id,user_id) references public.study_chapter_plans(id,user_id),
 unique(plan_id,lecture_id),unique(id,user_id),unique(id,plan_id,user_id)
);
create index study_plan_topics_user_plan_idx on public.study_plan_topics(user_id,plan_id);
create index study_plan_topics_lecture_idx on public.study_plan_topics(lecture_id);
create table public.study_session_groups (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 plan_id uuid not null,
 plan_topic_id uuid,
 title text not null check(char_length(title) between 1 and 160),
 config jsonb not null check(jsonb_typeof(config)='object' and octet_length(config::text)<=6000),
 created_at timestamptz not null default now(),
 foreign key(plan_id,user_id) references public.study_chapter_plans(id,user_id),
 foreign key(plan_topic_id,plan_id,user_id) references public.study_plan_topics(id,plan_id,user_id),
 unique(id,user_id)
);
create index study_session_groups_user_plan_idx on public.study_session_groups(user_id,plan_id);
create index study_session_groups_topic_idx on public.study_session_groups(plan_topic_id,plan_id,user_id);

alter table public.study_schedule
 add column session_group_id uuid,
 add column session_order integer,
 add column kind text not null default 'task' check(kind in ('task','study','break')),
 add column duration_minutes integer check(duration_minutes between 1 and 1440),
 add column scheduled_date date,
 add constraint study_schedule_group_owner_fk foreign key(session_group_id,user_id) references public.study_session_groups(id,user_id) on delete cascade,
 add constraint study_schedule_session_shape check(session_group_id is null or (session_order is not null and session_order>=0 and start_time is not null and kind in ('study','break') and duration_minutes is not null and scheduled_date is not null)),
 add constraint study_schedule_session_order_unique unique(session_group_id,session_order);

do $$ declare t text; begin
 foreach t in array array['study_chapter_plans','study_plan_topics','study_session_groups'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select,insert,update,delete on public.%I to authenticated',t);
  execute format('create policy %I on public.%I for select to authenticated using ((select auth.uid())=user_id)',t||'_select_own',t);
  execute format('create policy %I on public.%I for insert to authenticated with check ((select auth.uid())=user_id)',t||'_insert_own',t);
  execute format('create policy %I on public.%I for update to authenticated using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id)',t||'_update_own',t);
  execute format('create policy %I on public.%I for delete to authenticated using ((select auth.uid())=user_id)',t||'_delete_own',t);
 end loop;
end $$;

-- One transaction saves a group and its sessions. Retries with the same ID are idempotent.
create function public.save_study_session_group(group_data jsonb,session_data jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare uid uuid := auth.uid(); gid uuid; existing public.study_session_groups%rowtype; inserted integer;
begin
 if uid is null then raise exception 'Sign in required'; end if;
 if jsonb_typeof(group_data)<>'object' or jsonb_typeof(session_data)<>'array' or jsonb_array_length(session_data) not between 1 and 400 then raise exception 'Invalid session data'; end if;
 gid := (group_data->>'id')::uuid;
 insert into public.study_session_groups(id,user_id,plan_id,plan_topic_id,title,config)
 values(gid,uid,(group_data->>'plan_id')::uuid,(group_data->>'plan_topic_id')::uuid,group_data->>'title',group_data->'config')
 on conflict(id) do nothing;
 get diagnostics inserted = row_count;
 if inserted=0 then
  select * into existing from public.study_session_groups where id=gid and user_id=uid;
  if not found or existing.config is distinct from group_data->'config' or existing.title is distinct from group_data->>'title' or existing.plan_id is distinct from (group_data->>'plan_id')::uuid or existing.plan_topic_id is distinct from (group_data->>'plan_topic_id')::uuid then raise exception 'Conflicting plan ID'; end if;
  return jsonb_build_object('id',gid,'reused',true);
 end if;
 insert into public.study_schedule(user_id,session_group_id,session_order,day_of_week,start_time,title,kind,duration_minutes,scheduled_date)
 select uid,gid,s.session_order,s.day_of_week,s.start_time,s.title,s.kind,s.duration_minutes,s.scheduled_date
 from jsonb_to_recordset(session_data) as s(session_order integer,day_of_week smallint,start_time time,title text,kind text,duration_minutes integer,scheduled_date date);
 return jsonb_build_object('id',gid,'reused',false);
end;
$$;
revoke all on function public.save_study_session_group(jsonb,jsonb) from public,anon;
grant execute on function public.save_study_session_group(jsonb,jsonb) to authenticated;
create index if not exists study_plan_topics_plan_owner_idx on public.study_plan_topics(plan_id,user_id);
create index if not exists study_session_groups_plan_owner_idx on public.study_session_groups(plan_id,user_id);
create index if not exists study_schedule_group_owner_idx on public.study_schedule(session_group_id,user_id);
create index if not exists study_schedule_user_idx on public.study_schedule(user_id);
commit;

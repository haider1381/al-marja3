begin;

-- Report ownership is fixed when the student submits it.
revoke update on public.question_reports from authenticated;
grant update (status, resolved_at) on public.question_reports to authenticated;

create table if not exists private.medbrain_report_messages (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.question_reports(id) on delete cascade,
  from_owner boolean not null,
  body text not null check (char_length(btrim(body)) between 1 and 1000),
  created_at timestamptz not null default now()
);

alter table private.medbrain_report_messages enable row level security;
revoke all on private.medbrain_report_messages from public, anon, authenticated;
create index if not exists medbrain_report_messages_thread_idx
  on private.medbrain_report_messages (report_id, created_at desc, id);

create or replace function public.medbrain_report_support(
  p_report_id uuid default null, p_body text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  staff boolean := public.is_owner() is true;
  report public.question_reports%rowtype;
begin
  if uid is null then raise exception 'not_authenticated' using errcode = '42501'; end if;

  if p_report_id is null then
    if p_body is not null then raise exception 'report_required'; end if;
    return coalesce((
      select jsonb_agg(to_jsonb(thread) order by thread.created_at desc, thread.id)
      from (
        select r.id, left(r.question_prompt, 200) as question, r.created_at,
          case when staff then r.user_id end as reporter_id,
          case when staff then coalesce(nullif(btrim(p.display_name), ''), 'طالب') end as reporter_name,
          exists (select 1 from private.medbrain_report_messages m where m.report_id = r.id) as has_messages
        from public.question_reports r
        left join public.profiles p on staff and p.id = r.user_id
        where (staff and r.status = 'open')
           or ((staff or r.user_id = uid) and exists (
             select 1 from private.medbrain_report_messages m where m.report_id = r.id
           ))
        order by r.created_at desc, r.id
        limit 200
      ) thread
    ), '[]'::jsonb);
  end if;

  select * into report from public.question_reports r
  where r.id = p_report_id and (staff or r.user_id = uid)
  for update;
  if not found then raise exception 'report_unavailable' using errcode = '42501'; end if;

  if not staff and not exists (
    select 1 from private.medbrain_report_messages m
    where m.report_id = report.id and m.from_owner
  ) then raise exception 'report_unavailable' using errcode = '42501'; end if;

  if p_body is not null then
    insert into private.medbrain_report_messages (report_id, from_owner, body)
    values (report.id, staff, btrim(p_body));
  end if;

  return coalesce((
    select jsonb_agg(to_jsonb(message) order by message.created_at, message.id)
    from (
      select m.id, m.from_owner, m.body, m.created_at
      from private.medbrain_report_messages m
      where m.report_id = report.id
      order by m.created_at desc, m.id desc limit 100
    ) message
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.medbrain_report_support(uuid, text) from public, anon, authenticated;
grant execute on function public.medbrain_report_support(uuid, text) to authenticated;

commit;

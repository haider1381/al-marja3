create table if not exists private.medbrain_first_quiz_reminders (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table private.medbrain_first_quiz_reminders enable row level security;
revoke all on private.medbrain_first_quiz_reminders from public, anon, authenticated;

create or replace function private.medbrain_new_content_push()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  recipient uuid;
  notice_kind text;
begin
  if new.type = 'أسئلة' and jsonb_array_length(new.questions) > 0 then
    notice_kind := 'new_quiz:';
  elsif new.type in ('محاضرة', 'ملف PDF', 'ملخص') then
    notice_kind := 'new_lecture:';
  else
    return new;
  end if;
  notice_kind := notice_kind || left(trim(coalesce(new.source, '')), 100);
  for recipient in
    select distinct subscription.user_id
    from private.medbrain_push_subscriptions subscription
    join auth.users account on account.id = subscription.user_id
    where account.deleted_at is null and not coalesce(account.is_anonymous, false)
      and subscription.user_id is distinct from auth.uid()
  loop
    perform private.medbrain_queue_push(recipient, notice_kind);
  end loop;
  return new;
exception when others then
  raise warning 'Could not queue MedBrain material notices (%)', sqlstate;
  return new;
end;
$$;

create or replace function private.medbrain_first_quiz_push()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from private.medbrain_first_quiz_reminders where user_id = new.user_id)
     or exists (select 1 from private.student_activity_days where user_id = new.user_id and kind = 'quiz')
     or not exists (select 1 from public.lectures where type = 'أسئلة' and jsonb_array_length(questions) > 0)
  then
    return new;
  end if;
  insert into private.medbrain_first_quiz_reminders (user_id)
    values (new.user_id) on conflict do nothing;
  if found then
    perform private.medbrain_queue_push(new.user_id, 'first_quiz');
  end if;
  return new;
exception when others then
  raise warning 'Could not queue MedBrain first quiz notice (%)', sqlstate;
  return new;
end;
$$;

create or replace trigger medbrain_new_content_push
after insert on public.lectures
for each row execute function private.medbrain_new_content_push();

create or replace trigger medbrain_first_quiz_push
after insert or update on private.medbrain_push_subscriptions
for each row execute function private.medbrain_first_quiz_push();

revoke all on function private.medbrain_new_content_push(), private.medbrain_first_quiz_push()
  from public, anon, authenticated;

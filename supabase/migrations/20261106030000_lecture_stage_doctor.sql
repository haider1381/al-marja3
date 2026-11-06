-- University sources are browsed as stage → specialty (or subject) → doctor → lectures.
alter table public.lectures add column if not exists stage smallint check (stage between 1 and 6);
alter table public.lectures add column if not exists doctor text;
create index if not exists lectures_source_stage on public.lectures (source, stage);

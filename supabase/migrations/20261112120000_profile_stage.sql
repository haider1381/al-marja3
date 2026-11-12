-- Study stage of the medical student (1–6), 7 = graduate / resident.
alter table public.profiles add column if not exists stage smallint;
alter table public.profiles drop constraint if exists profiles_stage_check;
alter table public.profiles add constraint profiles_stage_check check (stage is null or stage between 1 and 7);

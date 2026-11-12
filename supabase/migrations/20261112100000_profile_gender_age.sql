-- Students give their gender (for the «أهلاً دكتور / دكتورة» greeting) and age when they create the account.
alter table public.profiles
  add column if not exists gender text,
  add column if not exists age smallint;
alter table public.profiles drop constraint if exists profiles_gender_check;
alter table public.profiles add constraint profiles_gender_check check (gender is null or gender in ('male','female'));
alter table public.profiles drop constraint if exists profiles_age_check;
alter table public.profiles add constraint profiles_age_check check (age is null or age between 13 and 100);

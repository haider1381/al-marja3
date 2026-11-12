-- Ministerial questions carry a label line such as «[وزاري جراحة 2025 – دور ثاني]» or «[وزاري باطنية 2026 تجريبي]».
-- These helpers let students filter by year, round and main/mock paper. SECURITY INVOKER: lectures RLS (has_access) still applies.
create or replace function public.exam_tag_parts(p_prompt text)
returns table(tag text, year int, round int, mock boolean)
language sql immutable set search_path = '' as $$
  select t, nullif(substring(t from '(20[0-9][0-9])'), '')::int,
         case when t ~ 'دور\s*(ثاني|ثان|2)' then 2 else 1 end,
         t ~ 'تجريبي'
  from (select substring(p_prompt from '^\s*\[([^\]\n]{1,80})\]') as t) s
  where t is not null and t ~ '^وزاري';
$$;

create or replace function public.exam_papers()
returns table(category text, year int, round int, mock boolean)
language sql stable security invoker set search_path = '' as $$
  select distinct l.category, p.year, p.round, p.mock
  from public.lectures l, jsonb_array_elements(coalesce(l.questions, '[]'::jsonb)) q,
       lateral public.exam_tag_parts(q->>'prompt') p
  where l.type = 'أسئلة' and p.year is not null
  order by 2 desc, 1, 3, 4;
$$;

create or replace function public.exam_questions(p_category text default null, p_year int default null, p_round int default null, p_mock boolean default null, p_limit int default 200)
returns table(lecture_id uuid, idx int, question jsonb)
language sql stable security invoker set search_path = '' as $$
  select l.id, (q.ord - 1)::int, q.val
  from public.lectures l, jsonb_array_elements(coalesce(l.questions, '[]'::jsonb)) with ordinality q(val, ord),
       lateral public.exam_tag_parts(q.val->>'prompt') p
  where l.type = 'أسئلة'
    and (p_category is null or l.category = p_category)
    and (p_year is null or p.year = p_year)
    and (p_round is null or p.round = p_round)
    and (p_mock is null or p.mock = p_mock)
  order by random()
  limit least(greatest(coalesce(p_limit, 200), 1), 300);
$$;

revoke all on function public.exam_papers() from public, anon;
revoke all on function public.exam_questions(text, int, int, boolean, int) from public, anon;
grant execute on function public.exam_papers() to authenticated;
grant execute on function public.exam_questions(text, int, int, boolean, int) to authenticated;
grant execute on function public.exam_tag_parts(text) to authenticated;

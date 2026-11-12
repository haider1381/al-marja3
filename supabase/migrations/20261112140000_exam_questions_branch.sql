-- Ministerial questions can also be filtered by branch (lectures.topic, e.g. Cardiology, GIT).
drop function if exists public.exam_questions(text, int, int, boolean, int);
create or replace function public.exam_questions(p_category text default null, p_year int default null, p_round int default null, p_mock boolean default null, p_limit int default 200, p_topic text default null)
returns table(lecture_id uuid, idx int, question jsonb)
language sql stable security invoker set search_path = '' as $$
  select l.id, (q.ord - 1)::int, q.val
  from public.lectures l, jsonb_array_elements(coalesce(l.questions, '[]'::jsonb)) with ordinality q(val, ord),
       lateral public.exam_tag_parts(q.val->>'prompt') p
  where l.type = 'أسئلة'
    and (p_category is null or l.category = p_category)
    and (p_topic is null or l.topic = p_topic)
    and (p_year is null or p.year = p_year)
    and (p_round is null or p.round = p_round)
    and (p_mock is null or p.mock = p_mock)
  order by random()
  limit least(greatest(coalesce(p_limit, 200), 1), 300);
$$;
revoke all on function public.exam_questions(text, int, int, boolean, int, text) from public, anon;
grant execute on function public.exam_questions(text, int, int, boolean, int, text) to authenticated;

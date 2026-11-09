-- Ministerial exam MCQs have five options (a–e). Allow 4 or 5 options; correctIndex must point at one of them.
create or replace function public.valid_lecture_questions(payload jsonb)
returns boolean language plpgsql immutable set search_path = ''
as $$
declare q jsonb; o jsonb; n int;
begin
  if payload is null or jsonb_typeof(payload) <> 'array' then return false; end if;
  if jsonb_array_length(payload) > 100 then return false; end if;
  for q in select value from jsonb_array_elements(payload) loop
    if jsonb_typeof(q) <> 'object'
      or jsonb_typeof(q->'prompt') is distinct from 'string'
      or length(btrim(q->>'prompt')) = 0 or length(q->>'prompt') > 10000
      or jsonb_typeof(q->'options') is distinct from 'array'
      or jsonb_typeof(q->'correctIndex') is distinct from 'number'
      or (q->>'correctIndex') !~ '^[0-4]$' then return false; end if;
    n := jsonb_array_length(q->'options');
    if n < 4 or n > 5 or (q->>'correctIndex')::int >= n then return false; end if;
    for o in select value from jsonb_array_elements(q->'options') loop
      if jsonb_typeof(o) <> 'object'
        or jsonb_typeof(o->'text') is distinct from 'string'
        or length(btrim(o->>'text')) = 0 or length(o->>'text') > 5000
        or jsonb_typeof(o->'explanation') is distinct from 'string'
        or length(btrim(o->>'explanation')) = 0 or length(o->>'explanation') > 10000
        then return false; end if;
    end loop;
  end loop;
  return true;
end $$;

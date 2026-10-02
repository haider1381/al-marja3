"""Validate a Claude v1 export and generate a non-destructive SQL import.
Usage: python scripts/prepare_claude_import.py /private/export.json > /private/import.sql
Apply the bookkeeping schema in docs/claude-import-2026-10-02.md first.
Review SQL and execute with an administrative connection. Do not commit exported data.
"""
import json
import sys
from pathlib import Path

TEMPLATE = """
begin;
lock table public.lectures in share row exclusive mode;
lock table private.claude_lecture_import in share row exclusive mode;
do $import$
declare r jsonb; existing_map private.claude_lecture_import%rowtype;
matched_ids uuid[]; target_id uuid; action text;
begin
for r in select value from jsonb_array_elements($records$__RECORDS_JSON__$records$::jsonb)
loop
 select * into existing_map from private.claude_lecture_import where legacy_id=r->>'id';
 if found then
  if existing_map.original_record<>r then raise exception 'Legacy record conflict: %',r->>'id'; end if;
  continue;
 end if;
 select array_agg(id) into matched_ids from public.lectures
 where title=r->>'title' and source=r->>'source' and category=r->>'category'
 and topic=r->>'topic' and type=r->>'type'
 and coalesce(link,'')=r->>'link' and coalesce(lecture_text,'')=r->>'text'
 and coalesce(notes,'')=r->>'notes'
 and (length(r->>'text')>0 or length(r->>'link')>0);
 if coalesce(cardinality(matched_ids),0)>1 then raise exception 'Ambiguous complete match: %',r->>'id'; end if;
 if cardinality(matched_ids)=1 then target_id:=matched_ids[1]; action:='matched_existing';
 else
  insert into public.lectures(title,source,category,topic,type,link,lecture_text,notes,created_at)
  values(r->>'title',r->>'source',r->>'category',r->>'topic',r->>'type',r->>'link',r->>'text',r->>'notes',
    to_timestamp((r->>'createdAt')::numeric/1000))
  returning id into target_id;
  action:='inserted';
 end if;
 insert into private.claude_lecture_import(legacy_id,lecture_id,original_record,disposition)
 values(r->>'id',target_id,r,action);
end loop;
end $import$;
commit;
select disposition,count(*) from private.claude_lecture_import group by disposition;
"""

def prepare(path):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    records = data["records"]
    if not isinstance(records, list) or len(records) != data["totalRecords"]:
        raise ValueError("Export record count mismatch")
    fields = {"id","title","source","category","topic","type","link","text","notes","createdAt"}
    if len({r["id"] for r in records}) != len(records):
        raise ValueError("Duplicate legacy IDs")
    for record in records:
        if set(record) != fields:
            raise ValueError("Unexpected or missing fields; review before import")
        if any(not isinstance(record[k], str) for k in fields - {"createdAt"}):
            raise ValueError("String field required")
        if isinstance(record["createdAt"], bool) or not isinstance(record["createdAt"], int):
            raise ValueError("createdAt must be an integer millisecond timestamp")
        if not record["id"] or not record["title"]:
            raise ValueError("ID and title required")
    payload = json.dumps(records, ensure_ascii=False, separators=(",",":"))
    if "$records$" in payload or "$import$" in payload:
        raise ValueError("SQL delimiter collision; review before import")
    return TEMPLATE.replace("__RECORDS_JSON__", payload)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: prepare_claude_import.py EXPORT.json")
    print(prepare(sys.argv[1]))

-- Library flashcards linked to the topics they mention, so a lecture can show "flashcards on this topic".
create table if not exists public.library_flashcard_topics (
  card_id uuid not null references public.library_flashcards(id) on delete cascade,
  topic_id uuid not null references public.topics(id) on delete cascade,
  primary key (topic_id, card_id)
);
alter table public.library_flashcard_topics enable row level security;
create policy library_flashcard_topics_read on public.library_flashcard_topics for select to authenticated using (true);
create policy library_flashcard_topics_write on public.library_flashcard_topics for all to authenticated
  using ((select public.is_editor())) with check ((select public.is_editor()));

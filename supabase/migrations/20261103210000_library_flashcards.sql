-- Shared flashcard decks imported from Anki. Every signed-in user can read; only editors can change them.
create table if not exists public.flashcard_decks (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  source text,
  category text,
  topic text,
  card_count integer not null default 0,
  sort integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.library_flashcards (
  id uuid primary key default gen_random_uuid(),
  deck_id uuid not null references public.flashcard_decks(id) on delete cascade,
  ord integer not null,
  kind text not null default 'basic' check (kind in ('basic', 'cloze')),
  front text not null,
  back text not null,
  extra text not null default '',
  created_at timestamptz not null default now(),
  unique (deck_id, ord)
);
create index if not exists library_flashcards_deck_ord on public.library_flashcards (deck_id, ord);

alter table public.flashcard_decks enable row level security;
alter table public.library_flashcards enable row level security;

create policy flashcard_decks_read on public.flashcard_decks for select to authenticated using (true);
create policy flashcard_decks_write on public.flashcard_decks for all to authenticated
  using ((select public.is_editor())) with check ((select public.is_editor()));
create policy library_flashcards_read on public.library_flashcards for select to authenticated using (true);
create policy library_flashcards_write on public.library_flashcards for all to authenticated
  using ((select public.is_editor())) with check ((select public.is_editor()));

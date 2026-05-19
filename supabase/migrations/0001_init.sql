-- hushly schema
create extension if not exists "pgcrypto";

create table if not exists public.transcripts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  raw_text text not null,
  cleaned_text text not null,
  duration_ms integer,
  context_id uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.contexts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  label text not null,
  body text not null default '',
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.vocab (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  term text not null,
  definition text,
  created_at timestamptz not null default now(),
  unique (user_id, term)
);

alter table public.transcripts
  add constraint transcripts_context_fk
  foreign key (context_id) references public.contexts(id) on delete set null
  not valid;

create index if not exists transcripts_user_id_idx on public.transcripts (user_id, created_at desc);
create index if not exists contexts_user_id_idx on public.contexts (user_id);
create index if not exists vocab_user_id_idx on public.vocab (user_id);

alter table public.transcripts enable row level security;
alter table public.contexts enable row level security;
alter table public.vocab enable row level security;

drop policy if exists "own transcripts read" on public.transcripts;
drop policy if exists "own transcripts write" on public.transcripts;
drop policy if exists "own contexts read" on public.contexts;
drop policy if exists "own contexts write" on public.contexts;
drop policy if exists "own vocab read" on public.vocab;
drop policy if exists "own vocab write" on public.vocab;

create policy "own transcripts read" on public.transcripts for select using (auth.uid() = user_id);
create policy "own transcripts write" on public.transcripts for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own contexts read" on public.contexts for select using (auth.uid() = user_id);
create policy "own contexts write" on public.contexts for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own vocab read" on public.vocab for select using (auth.uid() = user_id);
create policy "own vocab write" on public.vocab for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

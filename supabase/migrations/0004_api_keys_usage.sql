-- hushly: API-key access and server-side usage metering
-- Desktop users authenticate with app_api_keys. Signed-in web users continue
-- to authenticate with Supabase JWTs. Usage rows are written by API routes.

create table if not exists public.app_api_keys (
  id uuid primary key default gen_random_uuid(),
  label text not null,
  tag text,
  user_id uuid references auth.users(id) on delete set null,
  key_hash text not null unique,
  key_prefix text not null,
  status text not null default 'active' check (status in ('active', 'revoked')),
  created_at timestamptz not null default now(),
  last_used_at timestamptz
);

create table if not exists public.api_usage_events (
  id uuid primary key default gen_random_uuid(),
  api_key_id uuid references public.app_api_keys(id) on delete set null,
  user_id uuid references auth.users(id) on delete set null,
  route text not null,
  status integer not null,
  duration_ms integer,
  audio_bytes integer,
  input_chars integer,
  output_chars integer,
  error text,
  created_at timestamptz not null default now()
);

create index if not exists app_api_keys_status_idx on public.app_api_keys (status, created_at desc);
create index if not exists app_api_keys_user_idx on public.app_api_keys (user_id, created_at desc);
create index if not exists api_usage_events_key_idx on public.api_usage_events (api_key_id, created_at desc);
create index if not exists api_usage_events_user_idx on public.api_usage_events (user_id, created_at desc);
create index if not exists api_usage_events_route_idx on public.api_usage_events (route, created_at desc);

alter table public.app_api_keys enable row level security;
alter table public.api_usage_events enable row level security;

drop policy if exists "own api keys read" on public.app_api_keys;
drop policy if exists "own api usage read" on public.api_usage_events;

create policy "own api keys read" on public.app_api_keys
  for select using (auth.uid() = user_id);

create policy "own api usage read" on public.api_usage_events
  for select using (auth.uid() = user_id);

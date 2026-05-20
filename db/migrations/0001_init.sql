create extension if not exists pgcrypto;

create table if not exists app_users (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  password_hash text not null,
  password_salt text not null,
  created_at timestamptz not null default now()
);

create table if not exists auth_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app_users(id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create index if not exists auth_sessions_user_id_idx on auth_sessions(user_id);
create index if not exists auth_sessions_expires_at_idx on auth_sessions(expires_at);

create table if not exists app_api_keys (
  id uuid primary key default gen_random_uuid(),
  label text not null,
  tag text,
  user_id uuid references app_users(id) on delete set null,
  key_hash text not null unique,
  key_prefix text not null,
  status text not null default 'active' check (status in ('active', 'revoked')),
  created_at timestamptz not null default now(),
  last_used_at timestamptz
);

create index if not exists app_api_keys_status_idx on app_api_keys(status);
create index if not exists app_api_keys_user_id_idx on app_api_keys(user_id);

create table if not exists api_usage_events (
  id uuid primary key default gen_random_uuid(),
  api_key_id uuid references app_api_keys(id) on delete set null,
  api_key_label text,
  api_key_tag text,
  api_key_prefix text,
  user_id uuid references app_users(id) on delete set null,
  route text not null,
  status integer not null,
  duration_ms integer,
  audio_bytes integer,
  input_chars integer,
  output_chars integer,
  error text,
  created_at timestamptz not null default now()
);

create index if not exists api_usage_events_created_at_idx on api_usage_events(created_at desc);
create index if not exists api_usage_events_api_key_id_idx on api_usage_events(api_key_id);
create index if not exists api_usage_events_user_id_idx on api_usage_events(user_id);

create table if not exists transcripts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app_users(id) on delete cascade,
  raw_text text not null default '',
  cleaned_text text not null default '',
  duration_ms integer,
  audio_path text,
  audio_mime text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists transcripts_user_id_created_at_idx on transcripts(user_id, created_at desc);

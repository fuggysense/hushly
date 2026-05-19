-- hushly: SaaS-ready additions
-- (1) profiles table — billing/plan home for each tenant
-- (2) usage_events — for future rate-limiting and billing
-- (3) auto-provision: new auth.users → profile row + default context

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text,
  plan text not null default 'free' check (plan in ('free', 'pro', 'team')),
  monthly_seconds_used integer not null default 0,
  monthly_window_start timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table if not exists public.usage_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null,
  duration_ms integer,
  meta jsonb,
  created_at timestamptz not null default now()
);

create index if not exists usage_events_user_idx on public.usage_events (user_id, created_at desc);

alter table public.profiles enable row level security;
alter table public.usage_events enable row level security;

drop policy if exists "own profile read" on public.profiles;
drop policy if exists "own profile update" on public.profiles;
drop policy if exists "own usage read" on public.usage_events;

create policy "own profile read" on public.profiles for select using (auth.uid() = id);
create policy "own profile update" on public.profiles for update using (auth.uid() = id) with check (auth.uid() = id);
create policy "own usage read" on public.usage_events for select using (auth.uid() = user_id);

-- Auto-create profile + default context on new auth user
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email)
  on conflict (id) do nothing;

  insert into public.contexts (user_id, label, body, is_default)
  values (new.id, 'General', '', true)
  on conflict do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Backfill any users created before this migration
insert into public.profiles (id, email)
select id, email from auth.users
on conflict (id) do nothing;

insert into public.contexts (user_id, label, body, is_default)
select u.id, 'General', '', true from auth.users u
where not exists (select 1 from public.contexts c where c.user_id = u.id);

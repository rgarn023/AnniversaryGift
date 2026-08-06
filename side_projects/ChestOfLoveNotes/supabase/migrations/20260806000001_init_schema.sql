-- Chest of Love Notes — initial schema
-- Profile setup is CLIENT-DRIVEN via upsert after auth signup.
-- There is intentionally NO trigger that auto-creates a full profile row;
-- the client calls an upsert with username / display_name / friend_code.

create extension if not exists pgcrypto with schema extensions;
create extension if not exists citext with schema extensions;

-- Ensure extension types are reachable without forcing every caller to
-- schema-qualify (Supabase installs citext into `extensions`).
do $$
begin
  execute 'alter database ' || quote_ident(current_database())
    || ' set search_path to public, extensions';
exception
  when insufficient_privilege then
    -- Fallback for roles that cannot alter database settings.
    null;
end $$;
set search_path to public, extensions;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.friend_request_status as enum (
    'pending',
    'accepted',
    'declined',
    'cancelled'
  );
exception
  when duplicate_object then null;
end $$;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Normalize usernames: trim, lowercase, strip surrounding whitespace.
create or replace function public.normalize_username(raw text)
returns extensions.citext
language sql
immutable
as $$
  select nullif(lower(trim(raw)), '')::extensions.citext;
$$;

-- Generate a short human-shareable friend code (e.g. CHEST-AB12CD).
create or replace function public.generate_friend_code()
returns text
language plpgsql
volatile
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  chunk text := '';
  i int;
  candidate text;
  attempts int := 0;
begin
  loop
    chunk := '';
    for i in 1..6 loop
      chunk := chunk || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    candidate := 'CHEST-' || chunk;
    exit when not exists (
      select 1 from public.profiles p where p.friend_code = candidate
    );
    attempts := attempts + 1;
    if attempts > 25 then
      raise exception 'could not generate unique friend_code';
    end if;
  end loop;
  return candidate;
end;
$$;

-- Generic updated_at touch trigger.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username extensions.citext not null,
  display_name text not null default '',
  friend_code text not null,
  avatar_url text,
  bio text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint profiles_username_len check (char_length(username::text) between 3 and 32),
  constraint profiles_username_format check (username::text ~ '^[a-z0-9][a-z0-9._-]*$'),
  constraint profiles_friend_code_format check (friend_code ~ '^CHEST-[A-Z0-9]{6}$')
);

create unique index if not exists profiles_username_unique on public.profiles (username);
create unique index if not exists profiles_friend_code_unique on public.profiles (friend_code);
create index if not exists profiles_display_name_idx on public.profiles (display_name);

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

comment on table public.profiles is
  'Public profile stub. Created/updated by the client via upsert after auth; no auto-create trigger.';

-- ---------------------------------------------------------------------------
-- friend_requests
-- ---------------------------------------------------------------------------
create table if not exists public.friend_requests (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles (id) on delete cascade,
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  status public.friend_request_status not null default 'pending',
  message text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  responded_at timestamptz,
  constraint friend_requests_no_self check (sender_id <> recipient_id)
);

-- At most one pending request per directed pair.
create unique index if not exists friend_requests_unique_pending
  on public.friend_requests (sender_id, recipient_id)
  where status = 'pending';

create index if not exists friend_requests_recipient_pending_idx
  on public.friend_requests (recipient_id, created_at desc)
  where status = 'pending';

create index if not exists friend_requests_sender_idx
  on public.friend_requests (sender_id, created_at desc);

create trigger friend_requests_set_updated_at
  before update on public.friend_requests
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- friendships (normalized: user_one_id < user_two_id)
-- ---------------------------------------------------------------------------
create table if not exists public.friendships (
  id uuid primary key default gen_random_uuid(),
  user_one_id uuid not null references public.profiles (id) on delete cascade,
  user_two_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default timezone('utc', now()),
  constraint friendships_ordered check (user_one_id < user_two_id),
  constraint friendships_unique_pair unique (user_one_id, user_two_id)
);

create index if not exists friendships_user_one_idx on public.friendships (user_one_id);
create index if not exists friendships_user_two_idx on public.friendships (user_two_id);

-- ---------------------------------------------------------------------------
-- blocks
-- ---------------------------------------------------------------------------
create table if not exists public.blocks (
  id uuid primary key default gen_random_uuid(),
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default timezone('utc', now()),
  constraint blocks_no_self check (blocker_id <> blocked_id),
  constraint blocks_unique_pair unique (blocker_id, blocked_id)
);

create index if not exists blocks_blocker_idx on public.blocks (blocker_id);
create index if not exists blocks_blocked_idx on public.blocks (blocked_id);

-- ---------------------------------------------------------------------------
-- scrolls (metadata only — ciphertext lives in scroll_contents)
-- ---------------------------------------------------------------------------
create table if not exists public.scrolls (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles (id) on delete cascade,
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  title text not null default 'A Love Note',
  unlock_at timestamptz not null default timezone('utc', now()),
  has_password boolean not null default false,
  is_opened boolean not null default false,
  opened_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint scrolls_no_self check (sender_id <> recipient_id),
  constraint scrolls_title_len check (char_length(title) between 1 and 120)
);

create index if not exists scrolls_recipient_unlock_idx
  on public.scrolls (recipient_id, unlock_at desc)
  where deleted_at is null;

create index if not exists scrolls_sender_created_idx
  on public.scrolls (sender_id, created_at desc)
  where deleted_at is null;

create index if not exists scrolls_recipient_unopened_idx
  on public.scrolls (recipient_id, created_at desc)
  where deleted_at is null and is_opened = false;

create trigger scrolls_set_updated_at
  before update on public.scrolls
  for each row execute function public.set_updated_at();

comment on table public.scrolls is
  'Scroll metadata visible to sender/recipient. Message body is NEVER stored here.';

-- ---------------------------------------------------------------------------
-- scroll_contents (service-role only; no client RLS grants)
-- ---------------------------------------------------------------------------
create table if not exists public.scroll_contents (
  scroll_id uuid primary key references public.scrolls (id) on delete cascade,
  ciphertext text not null,
  nonce text not null,
  password_hash text,
  encryption_version smallint not null default 1,
  created_at timestamptz not null default timezone('utc', now())
);

comment on table public.scroll_contents is
  'Encrypted message payloads. Accessible only via service role / edge functions. No client SELECT/INSERT/UPDATE/DELETE.';

-- ---------------------------------------------------------------------------
-- scroll_open_attempts (password rate limiting)
-- ---------------------------------------------------------------------------
create table if not exists public.scroll_open_attempts (
  id uuid primary key default gen_random_uuid(),
  scroll_id uuid not null references public.scrolls (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  success boolean not null default false,
  attempted_at timestamptz not null default timezone('utc', now()),
  ip_hash text
);

create index if not exists scroll_open_attempts_rate_idx
  on public.scroll_open_attempts (scroll_id, user_id, attempted_at desc);

create index if not exists scroll_open_attempts_user_recent_idx
  on public.scroll_open_attempts (user_id, attempted_at desc);

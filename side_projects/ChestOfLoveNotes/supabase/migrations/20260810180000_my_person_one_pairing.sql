-- My Person: strict one-active pairing + public connection tokens for QR.
-- Keeps existing friendships / friend_requests tables (UI terminology is "My Person").
-- Does NOT put raw UUIDs in QR payloads.

set search_path to public, extensions;

-- ---------------------------------------------------------------------------
-- Public connection token (safe to share / encode in QR)
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists public_connection_token text;

comment on column public.profiles.public_connection_token is
  'Cryptographically random public pairing token for QR / deep-link connect. Not a UUID.';

create or replace function public.generate_public_connection_token()
returns text
language plpgsql
volatile
as $$
declare
  candidate text;
  attempts int := 0;
begin
  loop
    -- 32 hex chars from 16 random bytes (~128 bits)
    candidate := encode(gen_random_bytes(16), 'hex');
    exit when not exists (
      select 1 from public.profiles p where p.public_connection_token = candidate
    );
    attempts := attempts + 1;
    if attempts > 25 then
      raise exception 'could not generate unique public_connection_token';
    end if;
  end loop;
  return candidate;
end;
$$;

-- Backfill missing tokens
update public.profiles
set public_connection_token = public.generate_public_connection_token()
where public_connection_token is null or public_connection_token = '';

alter table public.profiles
  alter column public_connection_token set default public.generate_public_connection_token();

alter table public.profiles
  alter column public_connection_token set not null;

create unique index if not exists profiles_public_connection_token_unique
  on public.profiles (public_connection_token);

-- ---------------------------------------------------------------------------
-- Collapse multi-friendships to at most one active pairing per user
-- (private invite app — keep earliest friendship involving each user).
-- ---------------------------------------------------------------------------
with ranked as (
  select
    id,
    row_number() over (
      partition by least(user_one_id, user_two_id), greatest(user_one_id, user_two_id)
      order by created_at asc nulls last, id
    ) as pair_rn
  from public.friendships
),
dup_pairs as (
  select id from ranked where pair_rn > 1
)
delete from public.friendships f using dup_pairs d where f.id = d.id;

-- Users in multiple distinct pairings: keep earliest by created_at, drop others.
with user_rows as (
  select f.id, f.created_at, u.uid
  from public.friendships f
  cross join lateral (values (f.user_one_id), (f.user_two_id)) as u(uid)
),
keep as (
  select distinct on (uid) id
  from user_rows
  order by uid, created_at asc nulls last, id
),
drop_ids as (
  select distinct ur.id
  from user_rows ur
  where ur.id not in (select id from keep)
)
delete from public.friendships f using drop_ids d where f.id = d.id;

-- ---------------------------------------------------------------------------
-- Enforce: each user appears in at most one friendship row
-- ---------------------------------------------------------------------------
create or replace function public.enforce_one_active_person()
returns trigger
language plpgsql
as $$
begin
  if exists (
    select 1 from public.friendships f
    where f.id is distinct from NEW.id
      and (
        f.user_one_id = NEW.user_one_id
        or f.user_two_id = NEW.user_one_id
        or f.user_one_id = NEW.user_two_id
        or f.user_two_id = NEW.user_two_id
      )
  ) then
    raise exception 'already_has_person' using errcode = 'P0001';
  end if;
  return NEW;
end;
$$;

drop trigger if exists friendships_one_person on public.friendships;
create trigger friendships_one_person
  before insert or update on public.friendships
  for each row execute function public.enforce_one_active_person();

-- Unique partial indexes also protect concurrent inserts per ordered slot.
create unique index if not exists friendships_user_one_unique
  on public.friendships (user_one_id);
create unique index if not exists friendships_user_two_unique
  on public.friendships (user_two_id);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function public.has_active_person(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.friendships f
    where f.user_one_id = p_user or f.user_two_id = p_user
  );
$$;

create or replace function public.get_active_person_id(p_user uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select case
    when f.user_one_id = p_user then f.user_two_id
    else f.user_one_id
  end
  from public.friendships f
  where f.user_one_id = p_user or f.user_two_id = p_user
  limit 1;
$$;

revoke all on function public.has_active_person(uuid) from public;
revoke all on function public.get_active_person_id(uuid) from public;
grant execute on function public.has_active_person(uuid) to authenticated, service_role;
grant execute on function public.get_active_person_id(uuid) to authenticated, service_role;

-- Resolve connection token → safe public profile (no email / no enumeration dump).
create or replace function public.resolve_connection_token(p_token text)
returns table (
  id uuid,
  username extensions.citext,
  display_name text
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  tok text := lower(trim(coalesce(p_token, '')));
begin
  if tok = '' or char_length(tok) < 16 then
    return;
  end if;
  return query
    select p.id, p.username, p.display_name
    from public.profiles p
    where p.public_connection_token = tok
    limit 1;
end;
$$;

revoke all on function public.resolve_connection_token(text) from public;
grant execute on function public.resolve_connection_token(text) to authenticated, service_role;

-- Regenerate own token (does not end active pairing).
create or replace function public.regenerate_my_connection_token()
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  uid uuid := auth.uid();
  tok text;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  tok := public.generate_public_connection_token();
  update public.profiles
  set public_connection_token = tok
  where id = uid;
  return tok;
end;
$$;

revoke all on function public.regenerate_my_connection_token() from public;
grant execute on function public.regenerate_my_connection_token() to authenticated;

-- Ensure new profiles get a token (client upsert may omit it).
create or replace function public.profiles_ensure_connection_token()
returns trigger
language plpgsql
as $$
begin
  if NEW.public_connection_token is null or NEW.public_connection_token = '' then
    NEW.public_connection_token := public.generate_public_connection_token();
  end if;
  return NEW;
end;
$$;

drop trigger if exists profiles_ensure_connection_token on public.profiles;
create trigger profiles_ensure_connection_token
  before insert or update on public.profiles
  for each row execute function public.profiles_ensure_connection_token();

-- Private online allowlist for Chest of Love Notes.
-- Additive only: does not drop tables, reset data, or delete the database.
--
-- Flow:
-- 1) An admin/service inserts an email into private_app_allowlist.
-- 2) After signup/sign-in, claim-private-membership (or service seed) links
--    auth.users.id into private_app_members when the email matches.
-- 3) Edge Functions reject non-members.

-- ---------------------------------------------------------------------------
-- Email allowlist (pre-signup / invite list)
-- ---------------------------------------------------------------------------
create table if not exists public.private_app_allowlist (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  label text not null default '',
  created_at timestamptz not null default timezone('utc', now()),
  created_by uuid null references auth.users (id) on delete set null,
  consumed_at timestamptz null,
  consumed_user_id uuid null references auth.users (id) on delete set null,
  constraint private_app_allowlist_email_lower check (email = lower(email)),
  constraint private_app_allowlist_email_nonempty check (char_length(email) >= 3)
);

create unique index if not exists private_app_allowlist_email_unique
  on public.private_app_allowlist (email);

create index if not exists private_app_allowlist_unconsumed_idx
  on public.private_app_allowlist (email)
  where consumed_at is null;

-- ---------------------------------------------------------------------------
-- Active / revoked members (post-auth)
-- ---------------------------------------------------------------------------
create table if not exists public.private_app_members (
  user_id uuid primary key references auth.users (id) on delete cascade,
  role text not null default 'member'
    check (role in ('member', 'admin')),
  status text not null default 'active'
    check (status in ('active', 'revoked')),
  allowlist_id uuid null references public.private_app_allowlist (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  revoked_at timestamptz null
);

create index if not exists private_app_members_active_idx
  on public.private_app_members (user_id)
  where status = 'active';

drop trigger if exists private_app_members_set_updated_at on public.private_app_members;
create trigger private_app_members_set_updated_at
  before update on public.private_app_members
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function public.is_active_private_app_member(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.private_app_members m
    where m.user_id = p_user_id
      and m.status = 'active'
  );
$$;

revoke all on function public.is_active_private_app_member(uuid) from public;
grant execute on function public.is_active_private_app_member(uuid) to authenticated, service_role;

-- Atomically claim allowlist entry for the caller's email and create membership.
-- Intended for Edge Function use with JWT-authenticated caller.
create or replace function public.claim_private_app_membership(p_user_id uuid, p_email text)
returns public.private_app_members
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized text := lower(trim(p_email));
  allow_row public.private_app_allowlist%rowtype;
  member_row public.private_app_members%rowtype;
begin
  if p_user_id is null or normalized is null or normalized = '' then
    raise exception 'invalid claim arguments' using errcode = '22023';
  end if;

  -- Already an active member?
  select * into member_row
  from public.private_app_members
  where user_id = p_user_id;

  if found and member_row.status = 'active' then
    return member_row;
  end if;

  select * into allow_row
  from public.private_app_allowlist
  where email = normalized
    and (consumed_at is null or consumed_user_id = p_user_id)
  for update;

  if not found then
    raise exception 'email is not on the private allowlist' using errcode = '42501';
  end if;

  update public.private_app_allowlist
  set consumed_at = timezone('utc', now()),
      consumed_user_id = p_user_id
  where id = allow_row.id;

  insert into public.private_app_members as m (user_id, role, status, allowlist_id)
  values (p_user_id, 'member', 'active', allow_row.id)
  on conflict (user_id) do update
    set status = 'active',
        revoked_at = null,
        allowlist_id = excluded.allowlist_id,
        updated_at = timezone('utc', now())
  returning * into member_row;

  return member_row;
end;
$$;

revoke all on function public.claim_private_app_membership(uuid, text) from public;
grant execute on function public.claim_private_app_membership(uuid, text) to service_role;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.private_app_allowlist enable row level security;
alter table public.private_app_members enable row level security;
alter table public.private_app_allowlist force row level security;
alter table public.private_app_members force row level security;

-- Users may see only their own membership row.
create policy private_app_members_select_own
  on public.private_app_members
  for select
  to authenticated
  using (user_id = auth.uid());

-- No client INSERT/UPDATE/DELETE on members or allowlist.
-- Management is via service role / SQL dashboard / Edge Functions.
-- (intentionally no write policies for authenticated on these tables)

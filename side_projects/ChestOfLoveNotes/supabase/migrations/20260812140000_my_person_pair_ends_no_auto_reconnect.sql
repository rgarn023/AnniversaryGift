-- Permanent disconnect / no auto-reconnect.
--
-- Root cause (confirmed): get-friends reconcileAcceptedPairing + SQL
-- reconcile_my_person_pairing recreated friendships from historical
-- friend_requests.status='accepted' after disconnect deleted friendships.
--
-- Fix:
-- 1) Durable tombstone table my_person_pair_ends (survives request cancellation races).
-- 2) Block friendship INSERT for tombstoned pairs (DB trigger).
-- 3) Neutralize reconcile_my_person_pairing — NEVER insert from history.
-- 4) Tombstone orphaned accepted requests that have no friendship.
-- Does not delete scrolls.

set search_path to public, extensions;

-- ---------------------------------------------------------------------------
-- Durable deliberate-disconnect tombstone (unordered pair)
-- ---------------------------------------------------------------------------
create table if not exists public.my_person_pair_ends (
  user_one_id uuid not null references public.profiles (id) on delete cascade,
  user_two_id uuid not null references public.profiles (id) on delete cascade,
  disconnected_at timestamptz not null default timezone('utc', now()),
  ended_by uuid null references public.profiles (id) on delete set null,
  constraint my_person_pair_ends_ordered check (user_one_id < user_two_id),
  primary key (user_one_id, user_two_id)
);

comment on table public.my_person_pair_ends is
  'Deliberate My Person disconnect tombstone. Blocks auto-rehydrate from historical accepted requests. Cleared only by a NEW explicit accept.';

alter table public.my_person_pair_ends enable row level security;
alter table public.my_person_pair_ends force row level security;

-- Participants may read their own end records (diagnostics). Writes via service role only.
drop policy if exists my_person_pair_ends_select_parties on public.my_person_pair_ends;
create policy my_person_pair_ends_select_parties
  on public.my_person_pair_ends
  for select
  to authenticated
  using (user_one_id = auth.uid() or user_two_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Block friendship recreation for tombstoned pairs
-- ---------------------------------------------------------------------------
create or replace function public.enforce_pair_not_ended()
returns trigger
language plpgsql
as $$
declare
  u1 uuid;
  u2 uuid;
begin
  u1 := least(NEW.user_one_id, NEW.user_two_id);
  u2 := greatest(NEW.user_one_id, NEW.user_two_id);
  if exists (
    select 1 from public.my_person_pair_ends e
    where e.user_one_id = u1 and e.user_two_id = u2
  ) then
    raise exception 'pair_disconnected'
      using errcode = 'P0001',
            hint = 'This pair was deliberately disconnected. A NEW accepted connection request is required.';
  end if;
  return NEW;
end;
$$;

drop trigger if exists friendships_pair_not_ended on public.friendships;
create trigger friendships_pair_not_ended
  before insert on public.friendships
  for each row execute function public.enforce_pair_not_ended();

-- ---------------------------------------------------------------------------
-- Helpers used by edge functions
-- ---------------------------------------------------------------------------
create or replace function public.record_my_person_pair_end(p_a uuid, p_b uuid, p_ended_by uuid default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  u1 uuid := least(p_a, p_b);
  u2 uuid := greatest(p_a, p_b);
begin
  if p_a is null or p_b is null or p_a = p_b then
    return;
  end if;
  insert into public.my_person_pair_ends (user_one_id, user_two_id, ended_by, disconnected_at)
  values (u1, u2, p_ended_by, timezone('utc', now()))
  on conflict (user_one_id, user_two_id) do update
    set disconnected_at = excluded.disconnected_at,
        ended_by = coalesce(excluded.ended_by, public.my_person_pair_ends.ended_by);
end;
$$;

create or replace function public.clear_my_person_pair_end(p_a uuid, p_b uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  u1 uuid := least(p_a, p_b);
  u2 uuid := greatest(p_a, p_b);
begin
  if p_a is null or p_b is null or p_a = p_b then
    return;
  end if;
  delete from public.my_person_pair_ends
  where user_one_id = u1 and user_two_id = u2;
end;
$$;

create or replace function public.pair_is_ended(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.my_person_pair_ends e
    where e.user_one_id = least(p_a, p_b)
      and e.user_two_id = greatest(p_a, p_b)
  );
$$;

revoke all on function public.record_my_person_pair_end(uuid, uuid, uuid) from public;
revoke all on function public.clear_my_person_pair_end(uuid, uuid) from public;
revoke all on function public.pair_is_ended(uuid, uuid) from public;
grant execute on function public.record_my_person_pair_end(uuid, uuid, uuid) to service_role;
grant execute on function public.clear_my_person_pair_end(uuid, uuid) to service_role;
grant execute on function public.pair_is_ended(uuid, uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Neutralize reconcile — NEVER recreate from historical accepted requests
-- ---------------------------------------------------------------------------
create or replace function public.reconcile_my_person_pairing()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  existing uuid;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  -- Read-only: return current active friendship if any.
  -- Deliberate disconnect + historical accepted requests must NOT insert rows.
  select f.id into existing
  from public.friendships f
  where f.user_one_id = uid or f.user_two_id = uid
  limit 1;

  return existing;
end;
$$;

revoke all on function public.reconcile_my_person_pairing() from public;
grant execute on function public.reconcile_my_person_pairing() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Data repair: cancel orphaned accepted requests + tombstone those pairs
-- ---------------------------------------------------------------------------
update public.friend_requests fr
set
  status = 'cancelled',
  responded_at = coalesce(fr.responded_at, timezone('utc', now()))
where fr.status = 'accepted'
  and fr.sender_id is distinct from fr.recipient_id
  and not exists (
    select 1
    from public.friendships f
    where f.user_one_id = least(fr.sender_id, fr.recipient_id)
      and f.user_two_id = greatest(fr.sender_id, fr.recipient_id)
  );

-- Tombstone every unordered pair that has a cancelled request and no friendship
-- (covers deliberate disconnects that left cancelled or newly-cancelled orphans).
insert into public.my_person_pair_ends (user_one_id, user_two_id, disconnected_at)
select distinct
  least(fr.sender_id, fr.recipient_id),
  greatest(fr.sender_id, fr.recipient_id),
  coalesce(fr.responded_at, timezone('utc', now()))
from public.friend_requests fr
where fr.status = 'cancelled'
  and fr.sender_id is distinct from fr.recipient_id
  and not exists (
    select 1 from public.friendships f
    where f.user_one_id = least(fr.sender_id, fr.recipient_id)
      and f.user_two_id = greatest(fr.sender_id, fr.recipient_id)
  )
on conflict do nothing;

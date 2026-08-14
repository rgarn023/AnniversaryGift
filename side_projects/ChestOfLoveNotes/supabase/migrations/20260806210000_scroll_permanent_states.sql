-- Chest of Love Notes — permanent scroll recipient/sender state tables
-- Additive only: does not drop scrolls columns, reset data, or delete the database.
--
-- Purpose:
-- - Opening a received scroll marks that existing row read + saved (no duplicate scroll).
-- - Saved / favorites are filtered views over recipient state.
-- - Recipient or sender soft-delete hides only that party's copy.
-- - Opening never expires a scroll.

-- ---------------------------------------------------------------------------
-- scroll_recipient_states
-- ---------------------------------------------------------------------------
create table if not exists public.scroll_recipient_states (
  scroll_id uuid not null references public.scrolls (id) on delete cascade,
  recipient_id uuid not null references auth.users (id) on delete cascade,
  is_read boolean not null default false,
  is_saved boolean not null default false,
  is_favorite boolean not null default false,
  first_opened_at timestamptz null,
  last_opened_at timestamptz null,
  opened_count integer not null default 0,
  deleted_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint scroll_recipient_states_pkey primary key (scroll_id, recipient_id),
  constraint scroll_recipient_states_opened_count_nonnegative check (opened_count >= 0)
);

create index if not exists scroll_recipient_states_recipient_deleted_idx
  on public.scroll_recipient_states (recipient_id, deleted_at);

create index if not exists scroll_recipient_states_recipient_saved_idx
  on public.scroll_recipient_states (recipient_id, is_saved)
  where deleted_at is null and is_saved = true;

create index if not exists scroll_recipient_states_recipient_favorite_idx
  on public.scroll_recipient_states (recipient_id, is_favorite)
  where deleted_at is null and is_favorite = true;

create index if not exists scroll_recipient_states_last_opened_idx
  on public.scroll_recipient_states (recipient_id, last_opened_at desc nulls last)
  where deleted_at is null;

drop trigger if exists scroll_recipient_states_set_updated_at
  on public.scroll_recipient_states;
create trigger scroll_recipient_states_set_updated_at
  before update on public.scroll_recipient_states
  for each row execute function public.set_updated_at();

comment on table public.scroll_recipient_states is
  'Per-recipient permanent scroll view state (read/saved/favorite/soft-delete). Does not duplicate scroll content.';

-- ---------------------------------------------------------------------------
-- scroll_sender_states
-- ---------------------------------------------------------------------------
create table if not exists public.scroll_sender_states (
  scroll_id uuid not null references public.scrolls (id) on delete cascade,
  sender_id uuid not null references auth.users (id) on delete cascade,
  deleted_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint scroll_sender_states_pkey primary key (scroll_id, sender_id)
);

create index if not exists scroll_sender_states_sender_deleted_idx
  on public.scroll_sender_states (sender_id, deleted_at);

drop trigger if exists scroll_sender_states_set_updated_at
  on public.scroll_sender_states;
create trigger scroll_sender_states_set_updated_at
  before update on public.scroll_sender_states
  for each row execute function public.set_updated_at();

comment on table public.scroll_sender_states is
  'Per-sender Sent Scrolls visibility state. Soft-delete hides only the sender copy.';

-- ---------------------------------------------------------------------------
-- Prevent identity column reassignment on state rows
-- ---------------------------------------------------------------------------
create or replace function public.prevent_scroll_state_identity_change()
returns trigger
language plpgsql
as $$
begin
  if tg_table_name = 'scroll_recipient_states' then
    if new.scroll_id is distinct from old.scroll_id
       or new.recipient_id is distinct from old.recipient_id then
      raise exception 'scroll_recipient_states identity columns are immutable'
        using errcode = '42501';
    end if;
  elsif tg_table_name = 'scroll_sender_states' then
    if new.scroll_id is distinct from old.scroll_id
       or new.sender_id is distinct from old.sender_id then
      raise exception 'scroll_sender_states identity columns are immutable'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists scroll_recipient_states_immutable_identity
  on public.scroll_recipient_states;
create trigger scroll_recipient_states_immutable_identity
  before update on public.scroll_recipient_states
  for each row execute function public.prevent_scroll_state_identity_change();

drop trigger if exists scroll_sender_states_immutable_identity
  on public.scroll_sender_states;
create trigger scroll_sender_states_immutable_identity
  before update on public.scroll_sender_states
  for each row execute function public.prevent_scroll_state_identity_change();

-- ---------------------------------------------------------------------------
-- Backfill from existing scrolls (safe / idempotent)
-- Obsolete fields kept on public.scrolls for a later cleanup migration:
--   is_opened, opened_at, deleted_at
-- ---------------------------------------------------------------------------
insert into public.scroll_recipient_states as srs (
  scroll_id,
  recipient_id,
  is_read,
  is_saved,
  is_favorite,
  first_opened_at,
  last_opened_at,
  opened_count,
  deleted_at,
  created_at,
  updated_at
)
select
  s.id,
  s.recipient_id,
  coalesce(s.is_opened, false),
  -- Opening a scroll marks it saved; preserve that for already-opened rows.
  coalesce(s.is_opened, false),
  false,
  s.opened_at,
  s.opened_at,
  case when coalesce(s.is_opened, false) then 1 else 0 end,
  -- Old model used one scrolls.deleted_at for both parties; preserve hide behavior.
  s.deleted_at,
  s.created_at,
  s.updated_at
from public.scrolls s
on conflict (scroll_id, recipient_id) do nothing;

insert into public.scroll_sender_states as sss (
  scroll_id,
  sender_id,
  deleted_at,
  created_at,
  updated_at
)
select
  s.id,
  s.sender_id,
  s.deleted_at,
  s.created_at,
  s.updated_at
from public.scrolls s
on conflict (scroll_id, sender_id) do nothing;

-- ---------------------------------------------------------------------------
-- Secure helpers for permanent-scroll mutations (edge / authenticated RPC)
-- Existing DB had NO SQL functions for open/save/favorite/soft-delete state.
-- Edge function open-scroll currently writes scrolls.is_opened / opened_at only.
-- ---------------------------------------------------------------------------

create or replace function public.ensure_scroll_party_states(p_scroll_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.scrolls%rowtype;
begin
  select * into s from public.scrolls where id = p_scroll_id;
  if not found then
    raise exception 'scroll not found' using errcode = 'P0002';
  end if;

  insert into public.scroll_recipient_states (scroll_id, recipient_id)
  values (s.id, s.recipient_id)
  on conflict (scroll_id, recipient_id) do nothing;

  insert into public.scroll_sender_states (scroll_id, sender_id)
  values (s.id, s.sender_id)
  on conflict (scroll_id, sender_id) do nothing;
end;
$$;

create or replace function public.mark_recipient_scroll_opened(p_scroll_id uuid)
returns public.scroll_recipient_states
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  s public.scrolls%rowtype;
  row public.scroll_recipient_states%rowtype;
  ts timestamptz := timezone('utc', now());
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if not public.is_active_private_app_member(uid) then
    raise exception 'private membership required' using errcode = '42501';
  end if;

  select * into s from public.scrolls where id = p_scroll_id;
  if not found then
    raise exception 'scroll not found' using errcode = 'P0002';
  end if;
  if s.recipient_id <> uid then
    raise exception 'only the recipient can open this scroll' using errcode = '42501';
  end if;

  perform public.ensure_scroll_party_states(p_scroll_id);

  update public.scroll_recipient_states
  set
    is_read = true,
    is_saved = true,
    first_opened_at = coalesce(first_opened_at, ts),
    last_opened_at = ts,
    opened_count = opened_count + 1,
    updated_at = ts
  where scroll_id = p_scroll_id
    and recipient_id = uid
    and deleted_at is null
  returning * into row;

  if not found then
    raise exception 'recipient scroll is deleted or unavailable' using errcode = 'P0002';
  end if;

  -- Keep legacy scrolls.* fields in sync until a later cleanup migration.
  update public.scrolls
  set
    is_opened = true,
    opened_at = coalesce(opened_at, ts),
    updated_at = ts
  where id = p_scroll_id;

  return row;
end;
$$;

create or replace function public.set_recipient_scroll_saved(
  p_scroll_id uuid,
  p_saved boolean
)
returns public.scroll_recipient_states
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  row public.scroll_recipient_states%rowtype;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if not public.is_active_private_app_member(uid) then
    raise exception 'private membership required' using errcode = '42501';
  end if;
  if p_saved is null then
    raise exception 'p_saved is required' using errcode = '22023';
  end if;

  perform public.ensure_scroll_party_states(p_scroll_id);

  update public.scroll_recipient_states
  set
    is_saved = p_saved,
    updated_at = timezone('utc', now())
  where scroll_id = p_scroll_id
    and recipient_id = uid
    and deleted_at is null
  returning * into row;

  if not found then
    raise exception 'recipient scroll is deleted or unavailable' using errcode = 'P0002';
  end if;

  return row;
end;
$$;

create or replace function public.set_recipient_scroll_favorite(
  p_scroll_id uuid,
  p_favorite boolean
)
returns public.scroll_recipient_states
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  row public.scroll_recipient_states%rowtype;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if not public.is_active_private_app_member(uid) then
    raise exception 'private membership required' using errcode = '42501';
  end if;
  if p_favorite is null then
    raise exception 'p_favorite is required' using errcode = '22023';
  end if;

  perform public.ensure_scroll_party_states(p_scroll_id);

  update public.scroll_recipient_states
  set
    is_favorite = p_favorite,
    updated_at = timezone('utc', now())
  where scroll_id = p_scroll_id
    and recipient_id = uid
    and deleted_at is null
  returning * into row;

  if not found then
    raise exception 'recipient scroll is deleted or unavailable' using errcode = 'P0002';
  end if;

  return row;
end;
$$;

create or replace function public.soft_delete_recipient_scroll(p_scroll_id uuid)
returns public.scroll_recipient_states
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  row public.scroll_recipient_states%rowtype;
  ts timestamptz := timezone('utc', now());
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if not public.is_active_private_app_member(uid) then
    raise exception 'private membership required' using errcode = '42501';
  end if;

  perform public.ensure_scroll_party_states(p_scroll_id);

  update public.scroll_recipient_states
  set
    deleted_at = coalesce(deleted_at, ts),
    updated_at = ts
  where scroll_id = p_scroll_id
    and recipient_id = uid
  returning * into row;

  if not found then
    raise exception 'recipient scroll not found' using errcode = 'P0002';
  end if;

  return row;
end;
$$;

create or replace function public.soft_delete_sender_scroll(p_scroll_id uuid)
returns public.scroll_sender_states
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  row public.scroll_sender_states%rowtype;
  ts timestamptz := timezone('utc', now());
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if not public.is_active_private_app_member(uid) then
    raise exception 'private membership required' using errcode = '42501';
  end if;

  perform public.ensure_scroll_party_states(p_scroll_id);

  update public.scroll_sender_states
  set
    deleted_at = coalesce(deleted_at, ts),
    updated_at = ts
  where scroll_id = p_scroll_id
    and sender_id = uid
  returning * into row;

  if not found then
    raise exception 'sender scroll not found' using errcode = 'P0002';
  end if;

  return row;
end;
$$;

revoke all on function public.ensure_scroll_party_states(uuid) from public;
revoke all on function public.mark_recipient_scroll_opened(uuid) from public;
revoke all on function public.set_recipient_scroll_saved(uuid, boolean) from public;
revoke all on function public.set_recipient_scroll_favorite(uuid, boolean) from public;
revoke all on function public.soft_delete_recipient_scroll(uuid) from public;
revoke all on function public.soft_delete_sender_scroll(uuid) from public;

grant execute on function public.ensure_scroll_party_states(uuid)
  to service_role;
grant execute on function public.mark_recipient_scroll_opened(uuid)
  to authenticated, service_role;
grant execute on function public.set_recipient_scroll_saved(uuid, boolean)
  to authenticated, service_role;
grant execute on function public.set_recipient_scroll_favorite(uuid, boolean)
  to authenticated, service_role;
grant execute on function public.soft_delete_recipient_scroll(uuid)
  to authenticated, service_role;
grant execute on function public.soft_delete_sender_scroll(uuid)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.scroll_recipient_states enable row level security;
alter table public.scroll_sender_states enable row level security;
alter table public.scroll_recipient_states force row level security;
alter table public.scroll_sender_states force row level security;

-- Recipients may view only their own recipient-state rows (private members only).
create policy scroll_recipient_states_select_own
  on public.scroll_recipient_states
  for select
  to authenticated
  using (
    recipient_id = auth.uid()
    and public.is_active_private_app_member(auth.uid())
  );

-- Senders may view only their own sender-state rows (private members only).
create policy scroll_sender_states_select_own
  on public.scroll_sender_states
  for select
  to authenticated
  using (
    sender_id = auth.uid()
    and public.is_active_private_app_member(auth.uid())
  );

-- No anon policies.
-- No authenticated INSERT/UPDATE/DELETE policies:
--   state rows are created by service role / ensure_scroll_party_states,
--   and mutations go through the secured functions above.
-- scroll_contents remains service-role only (unchanged; no grants added).

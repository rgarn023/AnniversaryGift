-- Chest of Love Notes — per-user Hide vs permanent Delete
-- Additive: extends scroll_*_states with hidden_at; preserves historic soft-deletes as Hidden.
--
-- Semantics:
--   hidden_at  = reversible Hide (own list only; other party unaffected)
--   deleted_at = permanent Delete for that user (not restorable; other party unaffected)
-- When BOTH parties have deleted_at set, underlying content is eligible for cleanup.

-- ---------------------------------------------------------------------------
-- Columns
-- ---------------------------------------------------------------------------
alter table public.scroll_recipient_states
  add column if not exists hidden_at timestamptz null;

alter table public.scroll_sender_states
  add column if not exists hidden_at timestamptz null;

create index if not exists scroll_recipient_states_recipient_hidden_idx
  on public.scroll_recipient_states (recipient_id, hidden_at)
  where deleted_at is null;

create index if not exists scroll_sender_states_sender_hidden_idx
  on public.scroll_sender_states (sender_id, hidden_at)
  where deleted_at is null;

comment on column public.scroll_recipient_states.hidden_at is
  'Recipient Hide (recoverable). Distinct from deleted_at (permanent for recipient).';
comment on column public.scroll_sender_states.hidden_at is
  'Sender Hide (recoverable). Distinct from deleted_at (permanent for sender).';

-- Historic soft-deletes were product "Hide" (UI labeled Hide / soft_delete).
-- Preserve them as Hidden, NOT permanent deletion (AT — do not erase recoverable history).
update public.scroll_recipient_states
set
  hidden_at = coalesce(hidden_at, deleted_at),
  deleted_at = null,
  updated_at = timezone('utc', now())
where deleted_at is not null
  and hidden_at is null;

update public.scroll_sender_states
set
  hidden_at = coalesce(hidden_at, deleted_at),
  deleted_at = null,
  updated_at = timezone('utc', now())
where deleted_at is not null
  and hidden_at is null;

-- ---------------------------------------------------------------------------
-- Hide / Unhide (recoverable)
-- ---------------------------------------------------------------------------
create or replace function public.hide_recipient_scroll(p_scroll_id uuid)
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
    hidden_at = coalesce(hidden_at, ts),
    updated_at = ts
  where scroll_id = p_scroll_id
    and recipient_id = uid
    and deleted_at is null
  returning * into row;

  if not found then
    raise exception 'recipient scroll not found or deleted' using errcode = 'P0002';
  end if;
  return row;
end;
$$;

create or replace function public.unhide_recipient_scroll(p_scroll_id uuid)
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

  update public.scroll_recipient_states
  set
    hidden_at = null,
    updated_at = ts
  where scroll_id = p_scroll_id
    and recipient_id = uid
    and deleted_at is null
  returning * into row;

  if not found then
    raise exception 'recipient scroll not found or deleted' using errcode = 'P0002';
  end if;
  return row;
end;
$$;

create or replace function public.hide_sender_scroll(p_scroll_id uuid)
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
    hidden_at = coalesce(hidden_at, ts),
    updated_at = ts
  where scroll_id = p_scroll_id
    and sender_id = uid
    and deleted_at is null
  returning * into row;

  if not found then
    raise exception 'sender scroll not found or deleted' using errcode = 'P0002';
  end if;
  return row;
end;
$$;

create or replace function public.unhide_sender_scroll(p_scroll_id uuid)
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

  update public.scroll_sender_states
  set
    hidden_at = null,
    updated_at = ts
  where scroll_id = p_scroll_id
    and sender_id = uid
    and deleted_at is null
  returning * into row;

  if not found then
    raise exception 'sender scroll not found or deleted' using errcode = 'P0002';
  end if;
  return row;
end;
$$;

-- ---------------------------------------------------------------------------
-- Permanent Delete (per-user) + both-deleted cleanup eligibility
-- ---------------------------------------------------------------------------
create or replace function public.maybe_purge_scroll_if_both_deleted(p_scroll_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  recip_del timestamptz;
  send_del timestamptz;
begin
  select deleted_at into recip_del
  from public.scroll_recipient_states
  where scroll_id = p_scroll_id
  limit 1;

  select deleted_at into send_del
  from public.scroll_sender_states
  where scroll_id = p_scroll_id
  limit 1;

  if recip_del is null or send_del is null then
    return false;
  end if;

  -- Both parties permanently deleted → remove content + scroll row (cascade states).
  delete from public.scroll_contents where scroll_id = p_scroll_id;
  delete from public.scrolls where id = p_scroll_id;
  return true;
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
    hidden_at = null,
    updated_at = ts
  where scroll_id = p_scroll_id
    and recipient_id = uid
  returning * into row;

  if not found then
    raise exception 'recipient scroll not found' using errcode = 'P0002';
  end if;

  perform public.maybe_purge_scroll_if_both_deleted(p_scroll_id);
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
    hidden_at = null,
    updated_at = ts
  where scroll_id = p_scroll_id
    and sender_id = uid
  returning * into row;

  if not found then
    raise exception 'sender scroll not found' using errcode = 'P0002';
  end if;

  perform public.maybe_purge_scroll_if_both_deleted(p_scroll_id);
  return row;
end;
$$;

-- Open / saved / favorite must refuse permanently deleted rows (hidden OK for open path).
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

  update public.scrolls
  set
    is_opened = true,
    opened_at = coalesce(opened_at, ts),
    updated_at = ts
  where id = p_scroll_id;

  return row;
end;
$$;

revoke all on function public.hide_recipient_scroll(uuid) from public;
revoke all on function public.unhide_recipient_scroll(uuid) from public;
revoke all on function public.hide_sender_scroll(uuid) from public;
revoke all on function public.unhide_sender_scroll(uuid) from public;
revoke all on function public.maybe_purge_scroll_if_both_deleted(uuid) from public;
revoke all on function public.soft_delete_recipient_scroll(uuid) from public;
revoke all on function public.soft_delete_sender_scroll(uuid) from public;

grant execute on function public.hide_recipient_scroll(uuid) to authenticated, service_role;
grant execute on function public.unhide_recipient_scroll(uuid) to authenticated, service_role;
grant execute on function public.hide_sender_scroll(uuid) to authenticated, service_role;
grant execute on function public.unhide_sender_scroll(uuid) to authenticated, service_role;
grant execute on function public.maybe_purge_scroll_if_both_deleted(uuid) to authenticated, service_role;
grant execute on function public.soft_delete_recipient_scroll(uuid) to authenticated, service_role;
grant execute on function public.soft_delete_sender_scroll(uuid) to authenticated, service_role;
grant execute on function public.mark_recipient_scroll_opened(uuid) to authenticated, service_role;

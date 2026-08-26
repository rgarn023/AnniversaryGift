-- Pet Store + gift delivery pipeline (Free Parrot validation path).
-- Tables: pet_catalog, pet_deliveries, user_pet_ownership
-- RPCs: send_pet_gift, list_pending_pet_gifts, claim_pet_gift
-- Idempotent / migration-safe. Does not touch My Person disconnect tables.

set search_path to public, extensions;

-- ---------------------------------------------------------------------------
-- Catalog (metadata only — no artwork blobs)
-- ---------------------------------------------------------------------------
create table if not exists public.pet_catalog (
  pet_id text primary key,
  display_name text not null,
  price_type text not null default 'FREE'
    check (price_type in ('FREE', 'PAID')),
  enabled boolean not null default true,
  available_in_store boolean not null default true,
  description text not null default '',
  created_at timestamptz not null default timezone('utc', now())
);

insert into public.pet_catalog (pet_id, display_name, price_type, enabled, available_in_store, description)
values (
  'parrot',
  'Parrot',
  'FREE',
  true,
  true,
  'A cheerful beach companion ready to hop beside your chest.'
)
on conflict (pet_id) do update
  set display_name = excluded.display_name,
      price_type = excluded.price_type,
      enabled = excluded.enabled,
      available_in_store = excluded.available_in_store,
      description = excluded.description;

alter table public.pet_catalog enable row level security;
alter table public.pet_catalog force row level security;

drop policy if exists pet_catalog_select_authenticated on public.pet_catalog;
create policy pet_catalog_select_authenticated
  on public.pet_catalog
  for select
  to authenticated
  using (enabled = true);

-- ---------------------------------------------------------------------------
-- Deliveries / gifts
-- ---------------------------------------------------------------------------
create table if not exists public.pet_deliveries (
  id uuid primary key default gen_random_uuid(),
  pet_id text not null references public.pet_catalog (pet_id),
  sender_user_id uuid not null references public.profiles (id) on delete cascade,
  recipient_user_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'claimed', 'cancelled')),
  created_at timestamptz not null default timezone('utc', now()),
  claimed_at timestamptz null
);

create index if not exists pet_deliveries_recipient_pending_idx
  on public.pet_deliveries (recipient_user_id, status, created_at desc);

create index if not exists pet_deliveries_sender_idx
  on public.pet_deliveries (sender_user_id, created_at desc);

-- One pending gift per (sender, recipient, pet) — spam protection.
create unique index if not exists pet_deliveries_unique_pending
  on public.pet_deliveries (sender_user_id, recipient_user_id, pet_id)
  where status = 'pending';

alter table public.pet_deliveries enable row level security;
alter table public.pet_deliveries force row level security;

-- Recipient may read their own gifts; sender may read gifts they created.
drop policy if exists pet_deliveries_select_parties on public.pet_deliveries;
create policy pet_deliveries_select_parties
  on public.pet_deliveries
  for select
  to authenticated
  using (
    recipient_user_id = auth.uid()
    or sender_user_id = auth.uid()
  );

-- Direct inserts blocked — use send_pet_gift RPC.
drop policy if exists pet_deliveries_no_direct_insert on public.pet_deliveries;
-- (no insert/update/delete policies for authenticated → blocked by default under FORCE RLS)

-- ---------------------------------------------------------------------------
-- Ownership (unique per user+pet)
-- ---------------------------------------------------------------------------
create table if not exists public.user_pet_ownership (
  user_id uuid not null references public.profiles (id) on delete cascade,
  pet_id text not null references public.pet_catalog (pet_id),
  granted_at timestamptz not null default timezone('utc', now()),
  source_delivery_id uuid null references public.pet_deliveries (id) on delete set null,
  primary key (user_id, pet_id)
);

create index if not exists user_pet_ownership_user_idx
  on public.user_pet_ownership (user_id);

alter table public.user_pet_ownership enable row level security;
alter table public.user_pet_ownership force row level security;

drop policy if exists user_pet_ownership_select_own on public.user_pet_ownership;
create policy user_pet_ownership_select_own
  on public.user_pet_ownership
  for select
  to authenticated
  using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function public._pet_users_are_paired(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.friendships f
    where f.user_one_id = least(p_a, p_b)
      and f.user_two_id = greatest(p_a, p_b)
  );
$$;

revoke all on function public._pet_users_are_paired(uuid, uuid) from public;
grant execute on function public._pet_users_are_paired(uuid, uuid) to service_role;

-- ---------------------------------------------------------------------------
-- send_pet_gift(p_pet_id, p_recipient_user_id)
-- Self-send allowed. My Person must be an active friendship pair.
-- ---------------------------------------------------------------------------
create or replace function public.send_pet_gift(p_pet_id text, p_recipient_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  pet_row public.pet_catalog%rowtype;
  existing_id uuid;
  new_id uuid;
  now_ts timestamptz := timezone('utc', now());
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'code', 'not_authenticated');
  end if;
  if p_pet_id is null or length(trim(p_pet_id)) = 0 then
    return jsonb_build_object('ok', false, 'code', 'invalid_pet');
  end if;
  if p_recipient_user_id is null then
    return jsonb_build_object('ok', false, 'code', 'invalid_recipient');
  end if;

  select * into pet_row
  from public.pet_catalog c
  where c.pet_id = p_pet_id and c.enabled = true and c.available_in_store = true;

  if not found then
    return jsonb_build_object('ok', false, 'code', 'pet_unavailable');
  end if;

  if pet_row.price_type <> 'FREE' then
    -- Paid pets require a future Play entitlement step before this RPC.
    return jsonb_build_object('ok', false, 'code', 'paid_not_supported');
  end if;

  -- Recipient must be self OR currently paired My Person.
  if p_recipient_user_id <> uid then
    if not public._pet_users_are_paired(uid, p_recipient_user_id) then
      return jsonb_build_object('ok', false, 'code', 'not_my_person');
    end if;
  end if;

  -- Spam protection: reuse existing pending gift.
  select d.id into existing_id
  from public.pet_deliveries d
  where d.sender_user_id = uid
    and d.recipient_user_id = p_recipient_user_id
    and d.pet_id = p_pet_id
    and d.status = 'pending'
  limit 1;

  if existing_id is not null then
    return jsonb_build_object(
      'ok', true,
      'code', 'already_pending',
      'delivery_id', existing_id,
      'pet_id', p_pet_id,
      'sender_user_id', uid,
      'recipient_user_id', p_recipient_user_id,
      'status', 'pending',
      'duplicate', true
    );
  end if;

  insert into public.pet_deliveries (
    pet_id, sender_user_id, recipient_user_id, status, created_at
  ) values (
    p_pet_id, uid, p_recipient_user_id, 'pending', now_ts
  )
  returning id into new_id;

  return jsonb_build_object(
    'ok', true,
    'code', 'created',
    'delivery_id', new_id,
    'pet_id', p_pet_id,
    'sender_user_id', uid,
    'recipient_user_id', p_recipient_user_id,
    'status', 'pending',
    'duplicate', false,
    'created_at', now_ts
  );
exception
  when unique_violation then
    select d.id into existing_id
    from public.pet_deliveries d
    where d.sender_user_id = uid
      and d.recipient_user_id = p_recipient_user_id
      and d.pet_id = p_pet_id
      and d.status = 'pending'
    limit 1;
    return jsonb_build_object(
      'ok', true,
      'code', 'already_pending',
      'delivery_id', existing_id,
      'pet_id', p_pet_id,
      'sender_user_id', uid,
      'recipient_user_id', p_recipient_user_id,
      'status', 'pending',
      'duplicate', true
    );
end;
$$;

-- ---------------------------------------------------------------------------
-- list_pending_pet_gifts — recipient inbox only
-- ---------------------------------------------------------------------------
create or replace function public.list_pending_pet_gifts()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  rows jsonb;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'code', 'not_authenticated', 'gifts', '[]'::jsonb);
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
  into rows
  from (
    select
      d.id as delivery_id,
      d.pet_id,
      c.display_name as pet_display_name,
      c.price_type,
      d.sender_user_id,
      d.recipient_user_id,
      d.status,
      d.created_at,
      'PET_GIFT'::text as reward_type
    from public.pet_deliveries d
    join public.pet_catalog c on c.pet_id = d.pet_id
    where d.recipient_user_id = uid
      and d.status = 'pending'
  ) x;

  return jsonb_build_object('ok', true, 'gifts', rows);
end;
$$;

-- ---------------------------------------------------------------------------
-- claim_pet_gift — recipient only; grants ownership once; idempotent
-- ---------------------------------------------------------------------------
create or replace function public.claim_pet_gift(p_delivery_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  d public.pet_deliveries%rowtype;
  now_ts timestamptz := timezone('utc', now());
  already_owned boolean := false;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'code', 'not_authenticated');
  end if;
  if p_delivery_id is null then
    return jsonb_build_object('ok', false, 'code', 'invalid_delivery');
  end if;

  select * into d
  from public.pet_deliveries
  where id = p_delivery_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'code', 'not_found');
  end if;

  -- Only the recipient may claim.
  if d.recipient_user_id <> uid then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;

  -- Idempotent: already claimed → still report ownership.
  if d.status = 'claimed' then
    select exists (
      select 1 from public.user_pet_ownership o
      where o.user_id = uid and o.pet_id = d.pet_id
    ) into already_owned;
    return jsonb_build_object(
      'ok', true,
      'code', 'already_claimed',
      'delivery_id', d.id,
      'pet_id', d.pet_id,
      'status', 'claimed',
      'owned', already_owned,
      'idempotent', true
    );
  end if;

  if d.status <> 'pending' then
    return jsonb_build_object('ok', false, 'code', 'not_claimable', 'status', d.status);
  end if;

  -- Grant ownership first (unique), then mark claimed.
  insert into public.user_pet_ownership (user_id, pet_id, granted_at, source_delivery_id)
  values (uid, d.pet_id, now_ts, d.id)
  on conflict (user_id, pet_id) do update
    set source_delivery_id = coalesce(public.user_pet_ownership.source_delivery_id, excluded.source_delivery_id);

  update public.pet_deliveries
  set status = 'claimed', claimed_at = now_ts
  where id = d.id;

  return jsonb_build_object(
    'ok', true,
    'code', 'claimed',
    'delivery_id', d.id,
    'pet_id', d.pet_id,
    'status', 'claimed',
    'owned', true,
    'idempotent', false,
    'claimed_at', now_ts
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- list_owned_pets — optional sync helper
-- ---------------------------------------------------------------------------
create or replace function public.list_owned_pets()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  rows jsonb;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'code', 'not_authenticated', 'pets', '[]'::jsonb);
  end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.granted_at asc), '[]'::jsonb)
  into rows
  from (
    select o.pet_id, c.display_name, c.price_type, o.granted_at
    from public.user_pet_ownership o
    join public.pet_catalog c on c.pet_id = o.pet_id
    where o.user_id = uid
  ) x;
  return jsonb_build_object('ok', true, 'pets', rows);
end;
$$;

revoke all on function public.send_pet_gift(text, uuid) from public;
revoke all on function public.list_pending_pet_gifts() from public;
revoke all on function public.claim_pet_gift(uuid) from public;
revoke all on function public.list_owned_pets() from public;

grant execute on function public.send_pet_gift(text, uuid) to authenticated;
grant execute on function public.list_pending_pet_gifts() to authenticated;
grant execute on function public.claim_pet_gift(uuid) to authenticated;
grant execute on function public.list_owned_pets() to authenticated;

comment on table public.pet_catalog is
  'Pet store catalog metadata. Artwork stays in the app; FREE parrot validates gift pipeline.';
comment on table public.pet_deliveries is
  'Pending/claimed pet gifts. Self-send uses same path as My Person delivery.';
comment on table public.user_pet_ownership is
  'Unique ownership per user+pet. Granted only via claim_pet_gift.';
comment on function public.send_pet_gift(text, uuid) is
  'Create a pending FREE pet delivery to self or current My Person. Duplicate pending returns already_pending.';
comment on function public.claim_pet_gift(uuid) is
  'Recipient-only claim: upsert ownership then mark delivery claimed. Idempotent.';

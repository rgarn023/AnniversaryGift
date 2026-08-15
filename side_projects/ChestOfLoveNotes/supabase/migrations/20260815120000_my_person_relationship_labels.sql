-- Per-user My Person relationship labels (private to the owner).
-- Independent of the other participant's label. Non-destructive for existing friendships.

set search_path to public, extensions;

create table if not exists public.my_person_relationship_labels (
  id uuid primary key default gen_random_uuid(),
  friendship_id uuid not null references public.friendships (id) on delete cascade,
  owner_user_id uuid not null references public.profiles (id) on delete cascade,
  relationship_key text not null default 'not_set',
  custom_label text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint my_person_rel_labels_owner_pair unique (friendship_id, owner_user_id),
  constraint my_person_rel_labels_key_check check (
    relationship_key in (
      'not_set',
      'wife',
      'husband',
      'spouse',
      'partner',
      'boyfriend',
      'girlfriend',
      'fiance',
      'fiancee',
      'significant_other',
      'best_friend',
      'friend',
      'family',
      'other'
    )
  ),
  constraint my_person_rel_labels_custom_len check (
    custom_label is null or char_length(custom_label) <= 40
  ),
  constraint my_person_rel_labels_other_requires_custom check (
    (
      relationship_key = 'other'
      and custom_label is not null
      and char_length(trim(custom_label)) between 1 and 40
    )
    or (
      relationship_key <> 'other'
      and (custom_label is null or btrim(custom_label) = '')
    )
  )
);

comment on table public.my_person_relationship_labels is
  'Private per-owner relationship label for an active My Person friendship. One row per (friendship, owner).';

create index if not exists my_person_rel_labels_owner_idx
  on public.my_person_relationship_labels (owner_user_id);

create index if not exists my_person_rel_labels_friendship_idx
  on public.my_person_relationship_labels (friendship_id);

drop trigger if exists my_person_rel_labels_set_updated_at on public.my_person_relationship_labels;
create trigger my_person_rel_labels_set_updated_at
  before update on public.my_person_relationship_labels
  for each row execute function public.set_updated_at();

alter table public.my_person_relationship_labels enable row level security;
alter table public.my_person_relationship_labels force row level security;

-- Owners may only read/write their own label rows.
drop policy if exists my_person_rel_labels_select_own on public.my_person_relationship_labels;
create policy my_person_rel_labels_select_own
  on public.my_person_relationship_labels
  for select
  to authenticated
  using (owner_user_id = auth.uid());

drop policy if exists my_person_rel_labels_insert_own on public.my_person_relationship_labels;
create policy my_person_rel_labels_insert_own
  on public.my_person_relationship_labels
  for insert
  to authenticated
  with check (
    owner_user_id = auth.uid()
    and exists (
      select 1
      from public.friendships f
      where f.id = friendship_id
        and (f.user_one_id = auth.uid() or f.user_two_id = auth.uid())
    )
  );

drop policy if exists my_person_rel_labels_update_own on public.my_person_relationship_labels;
create policy my_person_rel_labels_update_own
  on public.my_person_relationship_labels
  for update
  to authenticated
  using (owner_user_id = auth.uid())
  with check (
    owner_user_id = auth.uid()
    and exists (
      select 1
      from public.friendships f
      where f.id = friendship_id
        and (f.user_one_id = auth.uid() or f.user_two_id = auth.uid())
    )
  );

drop policy if exists my_person_rel_labels_delete_own on public.my_person_relationship_labels;
create policy my_person_rel_labels_delete_own
  on public.my_person_relationship_labels
  for delete
  to authenticated
  using (owner_user_id = auth.uid());

-- Sanitize + upsert own label. Clearing uses key 'not_set' (deletes the row).
create or replace function public.upsert_my_person_relationship_label(
  p_friendship_id uuid,
  p_relationship_key text,
  p_custom_label text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  key text := lower(trim(coalesce(p_relationship_key, 'not_set')));
  custom text := nullif(trim(coalesce(p_custom_label, '')), '');
  row_out public.my_person_relationship_labels%rowtype;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  if p_friendship_id is null then
    raise exception 'friendship_id required';
  end if;
  if not exists (
    select 1 from public.friendships f
    where f.id = p_friendship_id
      and (f.user_one_id = uid or f.user_two_id = uid)
  ) then
    raise exception 'not a participant of this friendship'
      using errcode = '42501';
  end if;

  -- Normalize accented fiancé/fiancée aliases from clients.
  if key like 'fianc%' and char_length(key) <= 8 then
    if right(key, 1) = 'e' and key <> 'fiance' then
      key := 'fiancee';
    else
      key := 'fiance';
    end if;
  end if;

  if key = 'not_set' or key = '' then
    delete from public.my_person_relationship_labels
    where friendship_id = p_friendship_id
      and owner_user_id = uid;
    return jsonb_build_object(
      'ok', true,
      'cleared', true,
      'friendship_id', p_friendship_id,
      'relationship_key', 'not_set',
      'custom_label', null,
      'display_label', 'Not set'
    );
  end if;

  if key = 'other' then
    if custom is null or char_length(custom) < 1 or char_length(custom) > 40 then
      raise exception 'custom_label required for other (1-40 chars)';
    end if;
    -- Basic sanitation: strip control chars / angle brackets.
    custom := regexp_replace(custom, '[[:cntrl:]]+', '', 'g');
    custom := replace(replace(custom, '<', ''), '>', '');
    custom := left(trim(custom), 40);
    if custom is null or custom = '' then
      raise exception 'custom_label required for other (1-40 chars)';
    end if;
  else
    custom := null;
  end if;

  if key not in (
    'wife','husband','spouse','partner','boyfriend','girlfriend',
    'fiance','fiancee','significant_other','best_friend','friend','family','other'
  ) then
    raise exception 'invalid relationship_key';
  end if;

  insert into public.my_person_relationship_labels as t (
    friendship_id, owner_user_id, relationship_key, custom_label
  ) values (
    p_friendship_id, uid, key, custom
  )
  on conflict (friendship_id, owner_user_id) do update
    set relationship_key = excluded.relationship_key,
        custom_label = excluded.custom_label,
        updated_at = timezone('utc', now())
  returning * into row_out;

  return jsonb_build_object(
    'ok', true,
    'cleared', false,
    'id', row_out.id,
    'friendship_id', row_out.friendship_id,
    'owner_user_id', row_out.owner_user_id,
    'relationship_key', row_out.relationship_key,
    'custom_label', row_out.custom_label,
    'display_label', case
      when row_out.relationship_key = 'other' then coalesce(row_out.custom_label, 'Other')
      when row_out.relationship_key = 'fiance' then 'Fiancé'
      when row_out.relationship_key = 'fiancee' then 'Fiancée'
      when row_out.relationship_key = 'significant_other' then 'Significant Other'
      when row_out.relationship_key = 'best_friend' then 'Best Friend'
      else initcap(replace(row_out.relationship_key, '_', ' '))
    end,
    'updated_at', row_out.updated_at
  );
end;
$$;

create or replace function public.clear_my_person_relationship_label(p_friendship_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.upsert_my_person_relationship_label(p_friendship_id, 'not_set', null);
end;
$$;

revoke all on function public.upsert_my_person_relationship_label(uuid, text, text) from public;
revoke all on function public.clear_my_person_relationship_label(uuid) from public;
grant execute on function public.upsert_my_person_relationship_label(uuid, text, text) to authenticated, service_role;
grant execute on function public.clear_my_person_relationship_label(uuid) to authenticated, service_role;

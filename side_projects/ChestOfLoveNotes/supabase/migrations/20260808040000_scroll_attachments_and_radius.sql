-- Attachments metadata + private storage + allow 1 m – 10 km Location Lock radii.
-- Run in Supabase SQL Editor after reviewing. Client never writes storage/DB directly
-- for attachments without going through edge functions / signed URLs.

set search_path to public, extensions;

-- 1) Allow flexible Location Lock radii (1 m minimum, 10 km maximum).
alter table public.scrolls
  drop constraint if exists scrolls_location_radius_range;

alter table public.scrolls
  add constraint scrolls_location_radius_range
  check (location_radius_m between 1 and 10000);

comment on column public.scrolls.location_radius_m is
  'Unlock radius in meters (1–10000). Very small radii may be hard to verify with phone GPS.';

-- 2) Attachment metadata (binaries live in Storage, never in this table).
create table if not exists public.scroll_attachments (
  id uuid primary key default gen_random_uuid(),
  scroll_id uuid not null references public.scrolls (id) on delete cascade,
  storage_path text not null,
  mime_type text not null default 'image/jpeg',
  width integer,
  height integer,
  byte_size integer,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  constraint scroll_attachments_mime_ok check (
    mime_type in ('image/jpeg', 'image/png', 'image/webp')
  ),
  constraint scroll_attachments_sort_nonneg check (sort_order >= 0),
  constraint scroll_attachments_path_nonempty check (char_length(storage_path) > 0)
);

create index if not exists scroll_attachments_scroll_id_idx
  on public.scroll_attachments (scroll_id, sort_order);

comment on table public.scroll_attachments is
  'Image attachment metadata for scrolls. Files stored in private scroll-attachments bucket.';

alter table public.scroll_attachments enable row level security;

-- Recipients/senders can read metadata for scrolls they can see via recipient/sender state.
drop policy if exists scroll_attachments_select_participants on public.scroll_attachments;
create policy scroll_attachments_select_participants
  on public.scroll_attachments
  for select
  to authenticated
  using (
    exists (
      select 1 from public.scrolls s
      where s.id = scroll_attachments.scroll_id
        and (s.sender_id = auth.uid() or s.recipient_id = auth.uid())
    )
  );

-- Inserts/updates/deletes go through service role in edge functions only.
drop policy if exists scroll_attachments_no_client_write on public.scroll_attachments;
create policy scroll_attachments_no_client_write
  on public.scroll_attachments
  for all
  to authenticated
  using (false)
  with check (false);

-- 3) Private storage bucket for scroll images.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'scroll-attachments',
  'scroll-attachments',
  false,
  5242880, -- 5 MB compressed per object
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Storage object paths: {sender_id}/{scroll_id}/{filename}
-- Authenticated users may only read objects for scrolls they participate in.
-- Uploads use service-role or signed upload URLs issued by edge functions.

drop policy if exists scroll_attachments_storage_select on storage.objects;
create policy scroll_attachments_storage_select
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'scroll-attachments'
    and exists (
      select 1
      from public.scrolls s
      where s.id::text = (storage.foldername(name))[2]
        and (s.sender_id = auth.uid() or s.recipient_id = auth.uid())
    )
  );

-- No direct client inserts into storage; signed URLs / service role only.
drop policy if exists scroll_attachments_storage_no_client_write on storage.objects;
create policy scroll_attachments_storage_no_client_write
  on storage.objects
  for insert
  to authenticated
  with check (false);

drop policy if exists scroll_attachments_storage_no_client_update on storage.objects;
create policy scroll_attachments_storage_no_client_update
  on storage.objects
  for update
  to authenticated
  using (false);

drop policy if exists scroll_attachments_storage_no_client_delete on storage.objects;
create policy scroll_attachments_storage_no_client_delete
  on storage.objects
  for delete
  to authenticated
  using (false);

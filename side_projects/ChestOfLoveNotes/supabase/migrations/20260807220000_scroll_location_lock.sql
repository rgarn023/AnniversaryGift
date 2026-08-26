-- Location Lock metadata for scrolls (optional geofenced unlock).
-- Client never writes these columns directly — only via send-scroll Edge Function.
-- open-scroll verifies recipient proximity when has_location_lock is true.

set search_path to public, extensions;

alter table public.scrolls
  add column if not exists has_location_lock boolean not null default false;

alter table public.scrolls
  add column if not exists location_name text not null default '';

alter table public.scrolls
  add column if not exists location_lat double precision;

alter table public.scrolls
  add column if not exists location_lng double precision;

alter table public.scrolls
  add column if not exists location_radius_m integer not null default 500;

alter table public.scrolls
  drop constraint if exists scrolls_location_radius_range;

alter table public.scrolls
  add constraint scrolls_location_radius_range
  check (location_radius_m between 50 and 50000);

alter table public.scrolls
  drop constraint if exists scrolls_location_coords_pair;

alter table public.scrolls
  add constraint scrolls_location_coords_pair
  check (
    (location_lat is null and location_lng is null)
    or (location_lat is not null and location_lng is not null
        and location_lat between -90 and 90
        and location_lng between -180 and 180)
  );

comment on column public.scrolls.has_location_lock is
  'When true, recipient must be near location_lat/lng within location_radius_m to open.';
comment on column public.scrolls.location_name is
  'Human-readable place label shown in UI (never required to be unique).';

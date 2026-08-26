-- Optional formatted address for Location Lock display (sender-selected place).
set search_path to public, extensions;

alter table public.scrolls
  add column if not exists location_address text not null default '';

comment on column public.scrolls.location_address is
  'Optional formatted address/place description for Location Lock UI (never exact unlock coords in UI).';

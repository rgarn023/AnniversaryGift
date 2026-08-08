-- Activity Lock + Focus Lock configuration on scrolls.
-- Recipient challenge progress is stored on scroll_recipient_states (minimal fields).
-- Missing/null columns mean feature disabled (older scrolls remain compatible).

alter table public.scrolls
  add column if not exists activity_lock_enabled boolean not null default false,
  add column if not exists activity_target_km numeric(6,2) not null default 0,
  add column if not exists focus_lock_enabled boolean not null default false,
  add column if not exists focus_duration_hours integer not null default 0;

alter table public.scrolls
  drop constraint if exists scrolls_activity_target_km_range;
alter table public.scrolls
  add constraint scrolls_activity_target_km_range
  check (
    (not activity_lock_enabled and activity_target_km = 0)
    or (activity_lock_enabled and activity_target_km >= 1 and activity_target_km <= 100)
  );

alter table public.scrolls
  drop constraint if exists scrolls_focus_duration_hours_range;
alter table public.scrolls
  add constraint scrolls_focus_duration_hours_range
  check (
    (not focus_lock_enabled and focus_duration_hours = 0)
    or (focus_lock_enabled and focus_duration_hours >= 1 and focus_duration_hours <= 24)
  );

comment on column public.scrolls.activity_lock_enabled is
  'When true, recipient must travel activity_target_km after starting the challenge.';
comment on column public.scrolls.focus_lock_enabled is
  'When true, recipient must complete an uninterrupted focus period.';

-- Minimal recipient challenge state (no breadcrumb trail, no app-usage history).
alter table public.scroll_recipient_states
  add column if not exists activity_started_at timestamptz,
  add column if not exists activity_distance_km numeric(8,3) not null default 0,
  add column if not exists activity_last_lat double precision,
  add column if not exists activity_last_lng double precision,
  add column if not exists activity_completed_at timestamptz,
  add column if not exists focus_started_at timestamptz,
  add column if not exists focus_completed_at timestamptz,
  add column if not exists focus_interrupted_at timestamptz;

comment on column public.scroll_recipient_states.activity_distance_km is
  'Cumulative verified travel distance in km for Activity Lock (not a GPS trail).';
comment on column public.scroll_recipient_states.focus_completed_at is
  'Set when Focus Lock completes; usage verification remains on-device.';

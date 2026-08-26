-- Device push tokens + notification dedupe events for My Person / scrolls.
-- FCM credentials stay server-side (Edge Function secrets). Clients only register tokens.

set search_path to public, extensions;

create table if not exists public.device_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  token text not null,
  platform text not null default 'android',
  device_label text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint device_push_tokens_platform_check check (platform in ('android', 'ios', 'web')),
  constraint device_push_tokens_token_len check (char_length(token) between 8 and 512)
);

create unique index if not exists device_push_tokens_token_unique
  on public.device_push_tokens (token);

create index if not exists device_push_tokens_user_active_idx
  on public.device_push_tokens (user_id)
  where active = true;

create trigger device_push_tokens_set_updated_at
  before update on public.device_push_tokens
  for each row execute function public.set_updated_at();

alter table public.device_push_tokens enable row level security;

-- Users may only manage their own tokens (never read others').
drop policy if exists device_push_tokens_select_own on public.device_push_tokens;
create policy device_push_tokens_select_own
  on public.device_push_tokens for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists device_push_tokens_insert_own on public.device_push_tokens;
create policy device_push_tokens_insert_own
  on public.device_push_tokens for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists device_push_tokens_update_own on public.device_push_tokens;
create policy device_push_tokens_update_own
  on public.device_push_tokens for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists device_push_tokens_delete_own on public.device_push_tokens;
create policy device_push_tokens_delete_own
  on public.device_push_tokens for delete
  to authenticated
  using (auth.uid() = user_id);

-- Deduplicate requirement / lifecycle notifications (false→true once).
create table if not exists public.notification_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  scroll_id uuid references public.scrolls (id) on delete cascade,
  event_key text not null,
  created_at timestamptz not null default timezone('utc', now()),
  constraint notification_events_key_len check (char_length(event_key) between 3 and 120)
);

create unique index if not exists notification_events_user_scroll_key_unique
  on public.notification_events (
    user_id,
    (coalesce(scroll_id, '00000000-0000-0000-0000-000000000000'::uuid)),
    event_key
  );

create index if not exists notification_events_user_idx
  on public.notification_events (user_id, created_at desc);

alter table public.notification_events enable row level security;

-- Recipients can insert/select their own dedupe rows; service role bypasses RLS for push.
drop policy if exists notification_events_select_own on public.notification_events;
create policy notification_events_select_own
  on public.notification_events for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists notification_events_insert_own on public.notification_events;
create policy notification_events_insert_own
  on public.notification_events for insert
  to authenticated
  with check (auth.uid() = user_id);

-- Claim a notification event once (returns true if newly claimed).
create or replace function public.claim_notification_event(
  p_scroll_id uuid,
  p_event_key text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  if p_event_key is null or length(trim(p_event_key)) < 3 then
    return false;
  end if;
  begin
    insert into public.notification_events (user_id, scroll_id, event_key)
    values (uid, p_scroll_id, trim(p_event_key));
    return true;
  exception
    when unique_violation then
      return false;
  end;
end;
$$;

revoke all on function public.claim_notification_event(uuid, text) from public;
grant execute on function public.claim_notification_event(uuid, text) to authenticated, service_role;

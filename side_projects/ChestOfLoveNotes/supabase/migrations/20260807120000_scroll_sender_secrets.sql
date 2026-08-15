-- Sender-recoverable Magic Password secrets for Chest of Love Notes.
-- Additive only: does not drop tables, reset data, or delete the database.
--
-- Design:
--   password_hash (on scroll_contents) remains the recipient verification path.
--   scroll_sender_secrets holds an AES-256-GCM encrypted copy for the sender only.
--   Access is service-role / Edge Function only — no client policies.
--
-- Encryption key (MAGIC_PASSWORD_RECOVERY_KEY) is an Edge secret, never stored here.

create table if not exists public.scroll_sender_secrets (
  scroll_id uuid primary key references public.scrolls (id) on delete cascade,
  sender_id uuid not null references auth.users (id) on delete cascade,
  encrypted_magic_password text not null,
  encryption_iv text not null,
  encryption_version text not null default '1',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint scroll_sender_secrets_ciphertext_nonempty
    check (char_length(encrypted_magic_password) >= 8),
  constraint scroll_sender_secrets_iv_nonempty
    check (char_length(encryption_iv) >= 8)
);

create index if not exists scroll_sender_secrets_sender_id_idx
  on public.scroll_sender_secrets (sender_id);

drop trigger if exists scroll_sender_secrets_set_updated_at on public.scroll_sender_secrets;
create trigger scroll_sender_secrets_set_updated_at
  before update on public.scroll_sender_secrets
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS: force enabled; intentionally NO policies for anon/authenticated.
-- Only service_role (Edge Functions) may access this table.
-- ---------------------------------------------------------------------------
alter table public.scroll_sender_secrets enable row level security;
alter table public.scroll_sender_secrets force row level security;

revoke all on table public.scroll_sender_secrets from anon, authenticated, public;
grant all on table public.scroll_sender_secrets to service_role;

-- No SELECT/INSERT/UPDATE/DELETE policies for authenticated or anon.
-- (service_role bypasses RLS)

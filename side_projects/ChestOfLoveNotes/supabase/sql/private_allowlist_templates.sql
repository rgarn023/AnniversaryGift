-- Chest of Love Notes — private allowlist templates (PLACEHOLDERS ONLY)
-- Paste into Supabase SQL Editor after replacing placeholders.
-- Do NOT commit real email addresses into git.
--
-- Schema notes (verified):
--   public.private_app_allowlist(
--     id uuid PK default gen_random_uuid(),
--     email text NOT NULL CHECK (email = lower(email)) CHECK (char_length(email) >= 3),
--     label text NOT NULL default '',
--     created_at timestamptz NOT NULL,
--     created_by uuid NULL REFERENCES auth.users,
--     consumed_at timestamptz NULL,
--     consumed_user_id uuid NULL REFERENCES auth.users
--   )
--   UNIQUE (email)
--   No enabled/disabled column: presence of an unconsumed (or same-user) row is the invite.
--   To disable an invite before claim: DELETE the allowlist row (do not leave a foreign consumed_user_id).
--   Roles live on public.private_app_members.role CHECK (role IN ('member','admin')).
--   There is no 'owner' role; Robert is promoted to 'admin' after a successful claim.
--   claim_private_app_membership always creates role='member'; admin is assigned after claim.
--   This template does NOT create Auth users and does NOT bypass claim-private-membership.
--   Emails are not exposed by public profile queries (allowlist has no SELECT policy for clients).

-- ---------------------------------------------------------------------------
-- 1) Invite Robert + Mandy (replace placeholders; emails must be lowercase)
-- ---------------------------------------------------------------------------
insert into public.private_app_allowlist (email, label)
values
  (lower(trim('ROBERT_EMAIL_PLACEHOLDER')), 'Robert'),
  (lower(trim('MANDY_EMAIL_PLACEHOLDER')), 'Mandy')
on conflict (email) do update
set label = excluded.label;

-- ---------------------------------------------------------------------------
-- 2) After Robert has signed up, confirmed email, signed in, and successfully
--    called claim-private-membership, promote Robert to admin (schema has no
--    'owner' role; supported roles are 'member' and 'admin').
-- ---------------------------------------------------------------------------
update public.private_app_members m
set role = 'admin',
    updated_at = timezone('utc', now())
from public.private_app_allowlist a
where a.email = lower(trim('ROBERT_EMAIL_PLACEHOLDER'))
  and m.user_id = a.consumed_user_id
  and m.status = 'active';

-- Mandy remains the default claim role: 'member' (no update required).

-- ---------------------------------------------------------------------------
-- 3) Read-only verification (scoped to the two placeholder emails only)
-- ---------------------------------------------------------------------------
select
  a.email,
  a.label,
  true as allowlist_enabled, -- invite exists; schema has no separate enabled flag
  (a.consumed_at is null) as awaiting_claim,
  (a.consumed_at is not null) as claimed_allowlist_slot,
  a.consumed_at,
  m.user_id is not null as membership_row_exists,
  m.role as member_role,
  m.status as member_status,
  public.is_active_private_app_member(m.user_id) as is_active_member
from public.private_app_allowlist a
left join public.private_app_members m
  on m.user_id = a.consumed_user_id
where a.email in (
  lower(trim('ROBERT_EMAIL_PLACEHOLDER')),
  lower(trim('MANDY_EMAIL_PLACEHOLDER'))
)
order by a.label;

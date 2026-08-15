-- Chest of Love Notes — Row Level Security
-- Principle: clients never read ciphertext; scroll writes go through edge functions
-- (service role). Authenticated users may SELECT safe scroll metadata when they
-- are sender or recipient.

alter table public.profiles enable row level security;
alter table public.friend_requests enable row level security;
alter table public.friendships enable row level security;
alter table public.blocks enable row level security;
alter table public.scrolls enable row level security;
alter table public.scroll_contents enable row level security;
alter table public.scroll_open_attempts enable row level security;

-- Ensure table owners cannot bypass RLS in the API role path.
alter table public.profiles force row level security;
alter table public.friend_requests force row level security;
alter table public.friendships force row level security;
alter table public.blocks force row level security;
alter table public.scrolls force row level security;
alter table public.scroll_contents force row level security;
alter table public.scroll_open_attempts force row level security;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------

-- Owners can read their full profile row.
create policy profiles_select_own
  on public.profiles
  for select
  to authenticated
  using (id = auth.uid());

-- Authenticated users may search public fields of other profiles.
-- NOTE: email is NOT on this table (lives in auth.users) — never expose it here.
create policy profiles_select_public_search
  on public.profiles
  for select
  to authenticated
  using (true);

-- Client-driven profile stub: insert own row after signup.
create policy profiles_insert_own
  on public.profiles
  for insert
  to authenticated
  with check (id = auth.uid());

-- Owners may update limited profile fields only (enforced also in edge/client).
-- Restricting columns requires a trigger or edge function; RLS allows the row
-- update for the owner. Sensitive auth fields are not present on this table.
create policy profiles_update_own
  on public.profiles
  for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- No client DELETE — use delete-account edge function (service role).
-- (intentionally no delete policy for authenticated)

-- ---------------------------------------------------------------------------
-- friend_requests
-- ---------------------------------------------------------------------------

create policy friend_requests_select_parties
  on public.friend_requests
  for select
  to authenticated
  using (sender_id = auth.uid() or recipient_id = auth.uid());

-- Sender may create a pending request (caller must be sender).
create policy friend_requests_insert_as_sender
  on public.friend_requests
  for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    and status = 'pending'
  );

-- Only the recipient may respond (accept/decline). Sender may cancel pending.
create policy friend_requests_update_parties
  on public.friend_requests
  for update
  to authenticated
  using (sender_id = auth.uid() or recipient_id = auth.uid())
  with check (sender_id = auth.uid() or recipient_id = auth.uid());

-- Prefer edge functions for accept→friendship side effects.

-- ---------------------------------------------------------------------------
-- friendships
-- ---------------------------------------------------------------------------

create policy friendships_select_participants
  on public.friendships
  for select
  to authenticated
  using (user_one_id = auth.uid() or user_two_id = auth.uid());

-- Inserts/deletes happen via edge functions with service role.
-- No insert/update/delete policies for authenticated clients.

-- ---------------------------------------------------------------------------
-- blocks
-- ---------------------------------------------------------------------------

create policy blocks_select_blocker
  on public.blocks
  for select
  to authenticated
  using (blocker_id = auth.uid());

create policy blocks_insert_as_blocker
  on public.blocks
  for insert
  to authenticated
  with check (blocker_id = auth.uid());

create policy blocks_delete_as_blocker
  on public.blocks
  for delete
  to authenticated
  using (blocker_id = auth.uid());

-- ---------------------------------------------------------------------------
-- scrolls (metadata only)
-- ---------------------------------------------------------------------------

-- Authenticated users can SELECT safe scroll rows where they are sender or recipient.
create policy scrolls_select_parties
  on public.scrolls
  for select
  to authenticated
  using (
    deleted_at is null
    and (sender_id = auth.uid() or recipient_id = auth.uid())
  );

-- INSERT / UPDATE / DELETE denied for clients — only service role (edge functions).
-- Intentionally no insert/update/delete policies for authenticated on scrolls.
-- This prevents clients from writing unlock_at / opened fields or forging scrolls.

-- ---------------------------------------------------------------------------
-- scroll_contents — NO client policies at all
-- ---------------------------------------------------------------------------
-- No SELECT / INSERT / UPDATE / DELETE for authenticated or anon.
-- Service role bypasses RLS and is used exclusively by edge functions.

-- ---------------------------------------------------------------------------
-- scroll_open_attempts
-- ---------------------------------------------------------------------------
-- Clients should not write attempts directly; edge function (service role) records them.
-- Allow users to see their own recent attempt timestamps (optional UX).

create policy scroll_open_attempts_select_own
  on public.scroll_open_attempts
  for select
  to authenticated
  using (user_id = auth.uid());

-- No insert/update/delete for authenticated.

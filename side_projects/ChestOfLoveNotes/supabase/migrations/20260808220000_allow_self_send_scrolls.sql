-- Allow self-send for end-to-end lock testing (sender_id may equal recipient_id).
-- Locks remain enforced; this only removes the DB prohibition on self-addressed scrolls.

alter table public.scrolls
  drop constraint if exists scrolls_no_self;

comment on table public.scrolls is
  'Love Notes scrolls. Self-send (sender_id = recipient_id) is allowed for testing; locks still apply.';

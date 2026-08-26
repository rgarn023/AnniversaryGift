-- Durable disconnect: prevent get-friends / reconcile from resurrecting a
-- deliberately ended My Person pairing via leftover friend_requests.status='accepted'.
--
-- Root cause: disconnect-person deleted friendships but left accepted requests;
-- reconcileAcceptedPairing / reconcile_my_person_pairing then re-inserted the pair.
--
-- Fix:
-- 1) Tombstone orphaned accepted requests that have no friendship row (past disconnects).
-- 2) Replace reconcile_my_person_pairing so it never recreates from cancelled history.
-- Does not delete scrolls or profiles.

set search_path to public, extensions;

-- Past disconnects / failed cleanups: accepted request exists, mutual friendship does not.
-- Cancelling these stops automatic rehydration. Reconnect requires a NEW request+accept.
update public.friend_requests fr
set
  status = 'cancelled',
  responded_at = coalesce(fr.responded_at, timezone('utc', now()))
where fr.status = 'accepted'
  and fr.sender_id is distinct from fr.recipient_id
  and not exists (
    select 1
    from public.friendships f
    where f.user_one_id = least(fr.sender_id, fr.recipient_id)
      and f.user_two_id = greatest(fr.sender_id, fr.recipient_id)
  );

-- Reconcile remains a one-shot repair for true missed-accepts only (status still accepted
-- AND friendship missing). After disconnect, requests are cancelled so they never match.
create or replace function public.reconcile_my_person_pairing()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  existing uuid;
  fr record;
  u1 uuid;
  u2 uuid;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  select f.id into existing
  from public.friendships f
  where f.user_one_id = uid or f.user_two_id = uid
  limit 1;

  if existing is not null then
    return existing;
  end if;

  -- Only live accepted requests. Cancelled / declined / pending never recreate a Person.
  for fr in
    select *
    from public.friend_requests r
    where r.status = 'accepted'
      and (r.sender_id = uid or r.recipient_id = uid)
    order by r.responded_at asc nulls last, r.created_at asc nulls last, r.id
  loop
    u1 := least(fr.sender_id, fr.recipient_id);
    u2 := greatest(fr.sender_id, fr.recipient_id);

    if exists (
      select 1 from public.friendships f
      where f.user_one_id = fr.sender_id
         or f.user_two_id = fr.sender_id
         or f.user_one_id = fr.recipient_id
         or f.user_two_id = fr.recipient_id
    ) then
      continue;
    end if;

    insert into public.friendships (user_one_id, user_two_id)
    values (u1, u2)
    on conflict do nothing
    returning id into existing;

    if existing is null then
      select f.id into existing
      from public.friendships f
      where f.user_one_id = u1 and f.user_two_id = u2
      limit 1;
    end if;

    if existing is not null then
      return existing;
    end if;
  end loop;

  return null;
end;
$$;

revoke all on function public.reconcile_my_person_pairing() from public;
grant execute on function public.reconcile_my_person_pairing() to authenticated, service_role;

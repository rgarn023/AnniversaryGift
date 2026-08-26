-- Reconcile legacy accepted friend_requests into one mutual friendships row.
-- Safe / idempotent. Does not delete scrolls or create duplicates.
-- Does not hard-code any user identities.

set search_path to public, extensions;

-- Insert missing friendships for accepted requests when neither party already has a Person.
insert into public.friendships (user_one_id, user_two_id)
select
  least(fr.sender_id, fr.recipient_id) as user_one_id,
  greatest(fr.sender_id, fr.recipient_id) as user_two_id
from public.friend_requests fr
where fr.status = 'accepted'
  and fr.sender_id is distinct from fr.recipient_id
  and not exists (
    select 1
    from public.friendships f
    where f.user_one_id = least(fr.sender_id, fr.recipient_id)
      and f.user_two_id = greatest(fr.sender_id, fr.recipient_id)
  )
  and not exists (
    select 1
    from public.friendships f
    where f.user_one_id = fr.sender_id
       or f.user_two_id = fr.sender_id
       or f.user_one_id = fr.recipient_id
       or f.user_two_id = fr.recipient_id
  )
-- One row per unordered pair (prefer earliest accepted).
and fr.id = (
  select fr2.id
  from public.friend_requests fr2
  where fr2.status = 'accepted'
    and least(fr2.sender_id, fr2.recipient_id) = least(fr.sender_id, fr.recipient_id)
    and greatest(fr2.sender_id, fr2.recipient_id) = greatest(fr.sender_id, fr.recipient_id)
  order by fr2.responded_at asc nulls last, fr2.created_at asc nulls last, fr2.id
  limit 1
)
on conflict do nothing;

-- Helper RPC used by get-friends edge function (and clients) to repair on read.
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

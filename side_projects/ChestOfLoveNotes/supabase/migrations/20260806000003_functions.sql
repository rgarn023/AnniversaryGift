-- Chest of Love Notes — SQL helpers for RLS / edge functions

-- Ordered pair helper for friendship normalization.
create or replace function public.ordered_pair(a uuid, b uuid)
returns table (user_one_id uuid, user_two_id uuid)
language sql
immutable
as $$
  select least(a, b), greatest(a, b);
$$;

create or replace function public.friendship_exists(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.friendships f
    where f.user_one_id = least(a, b)
      and f.user_two_id = greatest(a, b)
  );
$$;

create or replace function public.are_friends(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.friendship_exists(a, b);
$$;

-- True if either user has blocked the other (directional either way).
create or replace function public.is_blocked(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.blocks bl
    where (bl.blocker_id = a and bl.blocked_id = b)
       or (bl.blocker_id = b and bl.blocked_id = a)
  );
$$;

create or replace function public.has_blocked(blocker uuid, blocked uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.blocks bl
    where bl.blocker_id = blocker
      and bl.blocked_id = blocked
  );
$$;

create or replace function public.pending_friend_request_exists(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.friend_requests fr
    where fr.status = 'pending'
      and (
        (fr.sender_id = a and fr.recipient_id = b)
        or (fr.sender_id = b and fr.recipient_id = a)
      )
  );
$$;

-- Count failed open attempts in the last N minutes for rate limiting.
create or replace function public.count_recent_failed_open_attempts(
  p_scroll_id uuid,
  p_user_id uuid,
  p_window_minutes int default 15
)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int
  from public.scroll_open_attempts soa
  where soa.scroll_id = p_scroll_id
    and soa.user_id = p_user_id
    and soa.success = false
    and soa.attempted_at >= timezone('utc', now()) - make_interval(mins => p_window_minutes);
$$;

-- Search profiles by username prefix or friend_code (public fields only).
create or replace function public.search_profiles(query text, result_limit int default 20)
returns table (
  id uuid,
  username extensions.citext,
  display_name text,
  friend_code text,
  avatar_url text
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with q as (
    select trim(query) as raw,
           public.normalize_username(query) as uname
  )
  select p.id, p.username, p.display_name, p.friend_code, p.avatar_url
  from public.profiles p, q
  where q.raw <> ''
    and (
      p.username like (coalesce(q.uname::text, '') || '%')::extensions.citext
      or upper(p.friend_code) = upper(q.raw)
      or p.display_name ilike ('%' || q.raw || '%')
    )
    and p.id <> auth.uid()
  order by
    case when upper(p.friend_code) = upper(q.raw) then 0 else 1 end,
    p.username
  limit greatest(1, least(result_limit, 50));
$$;

revoke all on function public.search_profiles(text, int) from public;
grant execute on function public.search_profiles(text, int) to authenticated;

grant execute on function public.are_friends(uuid, uuid) to authenticated;
grant execute on function public.friendship_exists(uuid, uuid) to authenticated;
grant execute on function public.is_blocked(uuid, uuid) to authenticated;
grant execute on function public.has_blocked(uuid, uuid) to authenticated;
grant execute on function public.pending_friend_request_exists(uuid, uuid) to authenticated;
grant execute on function public.count_recent_failed_open_attempts(uuid, uuid, int) to authenticated;
grant execute on function public.normalize_username(text) to authenticated;
grant execute on function public.generate_friend_code() to authenticated;

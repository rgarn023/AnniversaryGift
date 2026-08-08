-- Server-side Activity / Focus completion RPCs + open enforcement support.
-- Does NOT store travel breadcrumbs or per-app UsageStats history.

create or replace function public.mark_activity_lock_progress(
  p_scroll_id uuid,
  p_distance_km numeric,
  p_completed boolean default false
)
returns public.scroll_recipient_states
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  row public.scroll_recipient_states;
  target numeric;
  enabled boolean;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  select s.activity_lock_enabled, s.activity_target_km
    into enabled, target
  from public.scrolls s
  where s.id = p_scroll_id and s.recipient_id = uid;
  if not found then
    raise exception 'scroll not found';
  end if;
  if not coalesce(enabled, false) then
    raise exception 'activity lock not enabled';
  end if;

  perform public.ensure_scroll_party_states(p_scroll_id);

  update public.scroll_recipient_states r
  set
    activity_started_at = coalesce(r.activity_started_at, now()),
    activity_distance_km = greatest(coalesce(r.activity_distance_km, 0), greatest(coalesce(p_distance_km, 0), 0)),
    activity_completed_at = case
      when p_completed or greatest(coalesce(r.activity_distance_km, 0), greatest(coalesce(p_distance_km, 0), 0)) + 0.001 >= coalesce(target, 0)
        then coalesce(r.activity_completed_at, now())
      else r.activity_completed_at
    end
  where r.scroll_id = p_scroll_id and r.recipient_id = uid
  returning * into row;
  return row;
end;
$$;

create or replace function public.mark_focus_lock_started(p_scroll_id uuid)
returns public.scroll_recipient_states
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  row public.scroll_recipient_states;
  enabled boolean;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  select s.focus_lock_enabled into enabled
  from public.scrolls s
  where s.id = p_scroll_id and s.recipient_id = uid;
  if not found then
    raise exception 'scroll not found';
  end if;
  if not coalesce(enabled, false) then
    raise exception 'focus lock not enabled';
  end if;
  perform public.ensure_scroll_party_states(p_scroll_id);
  update public.scroll_recipient_states r
  set
    focus_started_at = coalesce(r.focus_started_at, now()),
    focus_interrupted_at = null,
    focus_completed_at = null
  where r.scroll_id = p_scroll_id and r.recipient_id = uid
  returning * into row;
  return row;
end;
$$;

create or replace function public.mark_focus_lock_complete(p_scroll_id uuid)
returns public.scroll_recipient_states
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  row public.scroll_recipient_states;
  enabled boolean;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  select s.focus_lock_enabled into enabled
  from public.scrolls s
  where s.id = p_scroll_id and s.recipient_id = uid;
  if not found then
    raise exception 'scroll not found';
  end if;
  if not coalesce(enabled, false) then
    raise exception 'focus lock not enabled';
  end if;
  perform public.ensure_scroll_party_states(p_scroll_id);
  update public.scroll_recipient_states r
  set
    focus_started_at = coalesce(r.focus_started_at, now()),
    focus_completed_at = coalesce(r.focus_completed_at, now()),
    focus_interrupted_at = null
  where r.scroll_id = p_scroll_id and r.recipient_id = uid
  returning * into row;
  return row;
end;
$$;

create or replace function public.mark_focus_lock_interrupted(p_scroll_id uuid)
returns public.scroll_recipient_states
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  row public.scroll_recipient_states;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  perform public.ensure_scroll_party_states(p_scroll_id);
  update public.scroll_recipient_states r
  set
    focus_interrupted_at = now(),
    focus_completed_at = null,
    focus_started_at = null
  where r.scroll_id = p_scroll_id and r.recipient_id = uid
  returning * into row;
  return row;
end;
$$;

grant execute on function public.mark_activity_lock_progress(uuid, numeric, boolean) to authenticated;
grant execute on function public.mark_focus_lock_started(uuid) to authenticated;
grant execute on function public.mark_focus_lock_complete(uuid) to authenticated;
grant execute on function public.mark_focus_lock_interrupted(uuid) to authenticated;

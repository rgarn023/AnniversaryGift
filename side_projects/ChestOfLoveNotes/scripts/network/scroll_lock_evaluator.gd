extends RefCounted
class_name ScrollLockEvaluator
## Central AND of all unlock requirements for a received scroll.


static func evaluate(item: Dictionary, now_unix: int = -1, fix: Dictionary = {}) -> Dictionary:
	if now_unix < 0:
		now_unix = int(Time.get_unix_time_from_system())
	var checks: Array = []
	var blockers: PackedStringArray = PackedStringArray()

	## Schedule
	var unlock_unix := int(item.get("unlock_at_unix", item.get("unlock_unix", 0)))
	if unlock_unix <= 0:
		var unlock_at := str(item.get("unlock_at", ""))
		if not unlock_at.is_empty():
			unlock_unix = int(Time.get_unix_time_from_datetime_string(unlock_at))
	var schedule_ok := unlock_unix <= now_unix
	checks.append({"id": "schedule", "label": "Available time reached", "ok": schedule_ok, "active": true})
	if not schedule_ok:
		blockers.append("Available time has not arrived yet")

	## Location
	var loc_on := bool(item.get("has_location_lock", false))
	var loc_ok := true
	var loc_detail := ""
	if loc_on:
		var loc_eval := LocationHelper.evaluate_unlock_requirements({
			"unlock_at_unix": 0,
			"has_location_lock": true,
			"location_lat": item.get("location_lat"),
			"location_lng": item.get("location_lng"),
			"location_radius_m": item.get("location_radius_m", LocationHelper.DEFAULT_RADIUS_M),
			"has_password": false,
		}, now_unix, fix)
		loc_ok = bool(loc_eval.get("ok", false))
		loc_detail = str(loc_eval.get("message", ""))
		if not loc_ok:
			blockers.append(loc_detail if not loc_detail.is_empty() else "Location Lock not satisfied")
	checks.append({
		"id": "location",
		"label": "Location Lock — within %s" % LocationHelper.format_radius(int(item.get("location_radius_m", 500))),
		"ok": (not loc_on) or loc_ok,
		"active": loc_on,
		"detail": loc_detail,
	})

	## Activity
	var act_on := bool(item.get("activity_lock_enabled", false)) or bool(item.get("has_activity_lock", false))
	var act_target := float(item.get("activity_target_km", 0.0))
	var act_ok := true
	var act_detail := ""
	if act_on:
		var sid := str(item.get("id", item.get("scroll_id", "")))
		var prog := ActivityLockHelper.get_progress(sid)
		act_ok = ActivityLockHelper.is_complete(sid, act_target)
		act_detail = "%.1f / %s" % [float(prog.get("distance_km", 0.0)), ActivityLockHelper.format_km(act_target)]
		if not act_ok:
			blockers.append("Activity Lock — travel %s" % ActivityLockHelper.format_km(act_target))
	checks.append({
		"id": "activity",
		"label": "Activity Lock — %s" % ActivityLockHelper.format_km(act_target if act_target > 0.0 else ActivityLockHelper.DEFAULT_KM),
		"ok": (not act_on) or act_ok,
		"active": act_on,
		"detail": act_detail,
	})

	## Focus
	var focus_on := bool(item.get("focus_lock_enabled", false)) or bool(item.get("has_focus_lock", false))
	var focus_hours := int(item.get("focus_duration_hours", 0))
	var focus_ok := true
	var focus_detail := ""
	if focus_on:
		var sid2 := str(item.get("id", item.get("scroll_id", "")))
		var fr := FocusLockHelper.evaluate(sid2)
		focus_ok = bool(fr.get("ok", false)) and str(fr.get("status", "")) == "complete"
		focus_detail = str(fr.get("message", FocusLockHelper.format_hours(focus_hours)))
		if not focus_ok:
			blockers.append("Focus Lock — %s uninterrupted" % FocusLockHelper.format_hours(focus_hours if focus_hours > 0 else FocusLockHelper.DEFAULT_HOURS))
	checks.append({
		"id": "focus",
		"label": "Focus Lock — %s" % FocusLockHelper.format_hours(focus_hours if focus_hours > 0 else FocusLockHelper.DEFAULT_HOURS),
		"ok": (not focus_on) or focus_ok,
		"active": focus_on,
		"detail": focus_detail,
	})

	## Password (open-time; mark password_ok when dialog succeeds)
	var pw_on := bool(item.get("has_password", false)) or bool(item.get("has_magic_password", false))
	var pw_ok := (not pw_on) or bool(item.get("password_ok", false))
	checks.append({
		"id": "password",
		"label": "Magic Password",
		"ok": pw_ok,
		"active": pw_on,
	})
	if pw_on and not pw_ok:
		blockers.append("Magic Password required")

	var active_count := 0
	var passed_count := 0
	for c in checks:
		if bool(c.get("active", false)) or str(c.get("id")) == "schedule":
			active_count += 1
			if bool(c.get("ok", false)):
				passed_count += 1
	var all_ok := blockers.is_empty()
	return {
		"ok": all_ok,
		"checks": checks,
		"blockers": blockers,
		"active_count": active_count,
		"passed_count": passed_count,
	}


static func preview_lock_lines(draft_or_item: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var immediate := bool(draft_or_item.get("open_immediately", false))
	if immediate:
		lines.append("Available immediately")
	else:
		var label := str(draft_or_item.get("schedule_label", ""))
		if label.is_empty():
			var u := int(draft_or_item.get("unlock_unix", draft_or_item.get("unlock_at_unix", 0)))
			if u > 0:
				var dt := Time.get_datetime_dict_from_unix_time(u)
				label = "%s %d at %02d:%02d" % [
					["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"][clampi(int(dt.month), 1, 12) - 1],
					int(dt.day), int(dt.hour), int(dt.minute)
				]
		if not label.is_empty():
			lines.append("Available %s" % label)
	if bool(draft_or_item.get("has_location_lock", false)):
		lines.append("Location Lock · %s" % LocationHelper.format_radius(int(draft_or_item.get("location_radius_m", 500))))
	if bool(draft_or_item.get("activity_lock_enabled", false)) or bool(draft_or_item.get("has_activity_lock", false)):
		lines.append("Activity Lock · %s" % ActivityLockHelper.format_km(float(draft_or_item.get("activity_target_km", 5.0))))
	if bool(draft_or_item.get("focus_lock_enabled", false)) or bool(draft_or_item.get("has_focus_lock", false)):
		lines.append("Focus Lock · %s" % FocusLockHelper.format_hours(int(draft_or_item.get("focus_duration_hours", 3))))
	if bool(draft_or_item.get("has_password", false)) or bool(draft_or_item.get("has_magic_password", false)):
		lines.append("Magic Password required")
	return lines

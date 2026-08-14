class_name DateService
extends RefCounted

## Provides device calendar dates and optional developer overrides.
## Developer overrides never update normal-mode progress dates.

const START_DATE := "2026-08-06"
const END_DATE := "2026-08-13"
const ALL_DATES: PackedStringArray = [
	"2026-08-06",
	"2026-08-07",
	"2026-08-08",
	"2026-08-09",
	"2026-08-10",
	"2026-08-11",
	"2026-08-12",
	"2026-08-13",
]

var _developer_active: bool = false
var _simulated_date: String = ""


func get_device_date() -> String:
	var now: Dictionary = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [int(now.year), int(now.month), int(now.day)]


func is_developer_active() -> bool:
	return _developer_active


func set_developer_active(active: bool) -> void:
	_developer_active = active
	if not active:
		_simulated_date = ""


func set_simulated_date(iso_date: String) -> void:
	if iso_date.is_empty():
		_simulated_date = ""
		return
	if _is_valid_iso_date(iso_date):
		_simulated_date = iso_date


func get_simulated_date() -> String:
	return _simulated_date


func get_effective_date() -> String:
	if _developer_active and not _simulated_date.is_empty():
		return _simulated_date
	return get_device_date()


func shift_simulated_date(days: int) -> String:
	var base: String = get_effective_date()
	var shifted: String = add_days(base, days)
	set_simulated_date(shifted)
	return shifted


func clear_simulated_date() -> void:
	_simulated_date = ""


static func _is_valid_iso_date(iso_date: String) -> bool:
	var parts: PackedStringArray = iso_date.split("-")
	if parts.size() != 3:
		return false
	if parts[0].length() != 4 or parts[1].length() != 2 or parts[2].length() != 2:
		return false
	if not parts[0].is_valid_int() or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return false
	var month: int = int(parts[1])
	var day: int = int(parts[2])
	return month >= 1 and month <= 12 and day >= 1 and day <= 31


static func compare_dates(a: String, b: String) -> int:
	if a == b:
		return 0
	return -1 if a < b else 1


static func max_date(a: String, b: String) -> String:
	if a.is_empty():
		return b
	if b.is_empty():
		return a
	return a if a > b else b


static func date_to_unix_day(iso_date: String) -> int:
	var parts: PackedStringArray = iso_date.split("-")
	if parts.size() != 3:
		return 0
	var dict := {
		"year": int(parts[0]),
		"month": int(parts[1]),
		"day": int(parts[2]),
		"hour": 12,
		"minute": 0,
		"second": 0,
	}
	return int(Time.get_unix_time_from_datetime_dict(dict) / 86400.0)


static func unix_day_to_date(day_index: int) -> String:
	var unix: int = day_index * 86400 + 12 * 3600
	var dict: Dictionary = Time.get_datetime_dict_from_unix_time(unix)
	return "%04d-%02d-%02d" % [int(dict.year), int(dict.month), int(dict.day)]


static func add_days(iso_date: String, days: int) -> String:
	return unix_day_to_date(date_to_unix_day(iso_date) + days)


static func format_display_date(iso_date: String) -> String:
	var parts: PackedStringArray = iso_date.split("-")
	if parts.size() != 3:
		return iso_date
	var month_names: PackedStringArray = [
		"", "January", "February", "March", "April", "May", "June",
		"July", "August", "September", "October", "November", "December"
	]
	var month: int = int(parts[1])
	var day: int = int(parts[2])
	if month < 1 or month > 12:
		return iso_date
	return "%s %d" % [month_names[month], day]


static func short_display_date(iso_date: String) -> String:
	var parts: PackedStringArray = iso_date.split("-")
	if parts.size() != 3:
		return iso_date
	return "%s/%s" % [parts[1], parts[2]]

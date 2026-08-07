extends RefCounted
class_name LocationSearchService
## Place autocomplete / reverse geocode abstraction.
## Prefers authenticated Edge Function proxy; falls back to Photon (no key) when offline/demo.

const DEBOUNCE_MS := 350
const MIN_QUERY_LEN := 3
const PHOTON_SEARCH := "https://photon.komoot.io/api/"
const PHOTON_REVERSE := "https://photon.komoot.io/reverse"
const USER_AGENT := "ChestOfLoveNotes/1.0 (Charoite Games; location-lock)"

var api: ApiClient = null
var _request_token: int = 0


func _init(p_api: ApiClient = null) -> void:
	api = p_api


func next_token() -> int:
	_request_token += 1
	return _request_token


func is_current(token: int) -> bool:
	return token == _request_token


func search_places(query: String, token: int = -1) -> Dictionary:
	var q := query.strip_edges()
	if q.length() < MIN_QUERY_LEN:
		return {"ok": true, "results": [], "token": token}
	if api != null and api.config != null and api.config.is_configured() and api.tokens != null and api.tokens.has_session():
		var edge: Dictionary = await api.call_edge_function("search-places", {
			"action": "autocomplete",
			"query": q,
			"limit": 8,
		})
		if bool(edge.get("ok", false)):
			var data: Dictionary = edge.get("data", {}) if typeof(edge.get("data")) == TYPE_DICTIONARY else {}
			var results: Array = data.get("results", []) if typeof(data.get("results")) == TYPE_ARRAY else []
			return {"ok": true, "results": results, "token": token, "provider": "edge"}
		## Soft-fail to public geocoder so Compose still works if function undeployed.
	return await _photon_search(q, token)


func reverse_geocode(lat: float, lng: float, token: int = -1) -> Dictionary:
	if api != null and api.config != null and api.config.is_configured() and api.tokens != null and api.tokens.has_session():
		var edge: Dictionary = await api.call_edge_function("search-places", {
			"action": "reverse",
			"lat": lat,
			"lng": lng,
		})
		if bool(edge.get("ok", false)):
			var data: Dictionary = edge.get("data", {}) if typeof(edge.get("data")) == TYPE_DICTIONARY else {}
			return {
				"ok": true,
				"place": data.get("place", {}),
				"token": token,
				"provider": "edge",
			}
	return await _photon_reverse(lat, lng, token)


func _photon_search(query: String, token: int) -> Dictionary:
	var url := "%s?q=%s&limit=8&lang=en" % [PHOTON_SEARCH, query.uri_encode()]
	var raw: Dictionary = await _http_get_json(url)
	if not bool(raw.get("ok", false)):
		return {"ok": false, "error": "Couldn't search locations. Try again.", "token": token}
	var features: Array = []
	var data: Variant = raw.get("data")
	if typeof(data) == TYPE_DICTIONARY:
		features = (data as Dictionary).get("features", []) if typeof((data as Dictionary).get("features")) == TYPE_ARRAY else []
	var results: Array = []
	for f in features:
		if typeof(f) != TYPE_DICTIONARY:
			continue
		var place := _feature_to_place(f)
		if not place.is_empty():
			results.append(place)
	return {"ok": true, "results": results, "token": token, "provider": "photon"}


func _photon_reverse(lat: float, lng: float, token: int) -> Dictionary:
	var url := "%s?lat=%s&lon=%s&lang=en" % [PHOTON_REVERSE, str(lat), str(lng)]
	var raw: Dictionary = await _http_get_json(url)
	if not bool(raw.get("ok", false)):
		return {
			"ok": true,
			"place": {
				"name": "Selected place",
				"address": "%.4f, %.4f" % [lat, lng],
				"lat": lat,
				"lng": lng,
				"display": "Selected place",
			},
			"token": token,
			"provider": "fallback",
		}
	var data: Variant = raw.get("data")
	var features: Array = []
	if typeof(data) == TYPE_DICTIONARY:
		features = (data as Dictionary).get("features", []) if typeof((data as Dictionary).get("features")) == TYPE_ARRAY else []
	if features.is_empty():
		return {
			"ok": true,
			"place": {
				"name": "Current place",
				"address": "",
				"lat": lat,
				"lng": lng,
				"display": "Current place",
			},
			"token": token,
		}
	var place := _feature_to_place(features[0])
	place["lat"] = lat
	place["lng"] = lng
	return {"ok": true, "place": place, "token": token, "provider": "photon"}


func _feature_to_place(feature: Dictionary) -> Dictionary:
	var props: Dictionary = feature.get("properties", {}) if typeof(feature.get("properties")) == TYPE_DICTIONARY else {}
	var geom: Dictionary = feature.get("geometry", {}) if typeof(feature.get("geometry")) == TYPE_DICTIONARY else {}
	var coords: Array = geom.get("coordinates", []) if typeof(geom.get("coordinates")) == TYPE_ARRAY else []
	if coords.size() < 2:
		return {}
	var lng := float(coords[0])
	var lat := float(coords[1])
	var name := str(props.get("name", "")).strip_edges()
	var city := str(props.get("city", props.get("town", props.get("village", "")))).strip_edges()
	var state := str(props.get("state", "")).strip_edges()
	var country := str(props.get("country", "")).strip_edges()
	var street := str(props.get("street", "")).strip_edges()
	var housenumber := str(props.get("housenumber", "")).strip_edges()
	if name.is_empty():
		if not street.is_empty():
			name = ("%s %s" % [housenumber, street]).strip_edges()
		elif not city.is_empty():
			name = city
		else:
			name = "Selected place"
	var address_parts: PackedStringArray = PackedStringArray()
	if not street.is_empty():
		var line := ("%s %s" % [housenumber, street]).strip_edges()
		if line != name:
			address_parts.append(line)
	var locality := city
	if not state.is_empty():
		locality = locality + (", %s" % state) if not locality.is_empty() else state
	if not locality.is_empty() and locality != name:
		address_parts.append(locality)
	elif not country.is_empty() and country != name:
		address_parts.append(country)
	var address := ", ".join(address_parts)
	var display := name if address.is_empty() else "%s — %s" % [name, address]
	return {
		"name": name,
		"address": address,
		"lat": lat,
		"lng": lng,
		"display": display,
		"city": city,
		"state": state,
		"country": country,
	}


func _http_get_json(url: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 12.0
	Engine.get_main_loop().root.add_child(http)
	var headers := PackedStringArray([
		"Accept: application/json",
		"User-Agent: %s" % USER_AGENT,
	])
	var err := http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "network"}
	var completed: Array = await http.request_completed
	http.queue_free()
	if completed.size() < 4:
		return {"ok": false, "error": "network"}
	var result: int = int(completed[0])
	var status: int = int(completed[1])
	var body: PackedByteArray = completed[3]
	if result != HTTPRequest.RESULT_SUCCESS or status < 200 or status >= 300:
		return {"ok": false, "error": "http_%d" % status}
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY and typeof(parsed) != TYPE_ARRAY:
		return {"ok": false, "error": "parse"}
	return {"ok": true, "data": parsed}

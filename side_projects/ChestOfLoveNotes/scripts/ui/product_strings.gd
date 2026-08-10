extends RefCounted
class_name ProductStrings
## Central user-facing terminology for the one-to-one My Person model.
## Change strings here — avoid scattering "Friend"/"Friends" in UI.

const MY_PERSON := "My Person"
const PERSON := "Person"
const CONNECT := "Connect"
const CONNECTION_REQUEST := "Connection Request"
const CONNECTION_CODE := "Connection Code"
const DISCONNECT := "Disconnect"
const SCAN_PERSON_CODE := "Scan Person Code"
const SHOW_MY_CODE := "Show My Code"
const ENTER_CODE := "Enter Connection Code / Username"
const REGENERATE_CODE := "Regenerate Connection Code"
const GO_TO_MY_PERSON := "Go to My Person"

const EMPTY_HEADLINE := "Connect with your Person"
const EMPTY_SUPPORT := "Choose the one person you'd like to exchange scrolls with."
const COMPOSE_NEED_PERSON := "Connect with your Person before sending a scroll."
const ALREADY_CONNECTED_FMT := "You're already connected with %s."
const DISCONNECT_FIRST := "Disconnect first if you want to connect with someone else."
const OWN_CODE := "That's your own connection code."
const INVALID_QR := "This isn't a valid Chest of Love Notes connection code."
const CAMERA_RATIONALE := "Camera access lets you scan your Person's connection code."
const CAMERA_NEEDED := "Camera permission is needed to scan a connection code."
const NOTIFY_RATIONALE := "Allow notifications so Chest of Love Notes can tell you when a new scroll arrives or when a scroll requirement is completed."
const LOCATION_RATIONALE := "Location access lets you unlock scrolls that require being near a place, and optionally get a nudge when you're close enough."
const CONNECTION_REQUEST_ACCEPTED := "Connection request accepted"
const PERMISSIONS_SETUP_WHY := "A few optional permissions help Chest of Love Notes work smoothly. You can change these anytime in Profile."
const PERMISSIONS_SECTION := "PERMISSIONS"


static func sending_to(display_name: String) -> String:
	var n := display_name.strip_edges()
	if n.is_empty():
		n = PERSON
	return "Sending to %s" % n


static func to_label(display_name: String) -> String:
	var n := display_name.strip_edges()
	if n.is_empty():
		n = PERSON
	return "To %s" % n


static func connected_since(iso_or_label: String) -> String:
	var s := iso_or_label.strip_edges()
	if s.is_empty():
		return "Connected"
	return "Connected since %s" % s


static func disconnect_confirm(display_name: String) -> String:
	var n := display_name.strip_edges()
	if n.is_empty():
		n = PERSON
	return "Disconnect from %s?\n\nYou won't be able to exchange new scrolls until you connect with someone again. Existing scroll history will remain." % n


static func wants_to_connect(display_name: String) -> String:
	var n := display_name.strip_edges()
	if n.is_empty():
		n = "Someone"
	return "%s wants to connect with you on Chest of Love Notes." % n


static func connect_with_confirm(display_name: String) -> String:
	var n := display_name.strip_edges()
	if n.is_empty():
		n = PERSON
	return "Connect with %s?" % n

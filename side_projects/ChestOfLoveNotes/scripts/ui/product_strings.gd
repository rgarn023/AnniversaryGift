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
const SHOW_MY_CODE_HELP := "Have your Person scan this code to send you a connection request."
const SCAN_AGAIN := "Scan Again"
const ENTER_CODE := "Enter Connection Code / Username"
const REGENERATE_CODE := "Regenerate Connection Code"
const GO_TO_MY_PERSON := "Go to My Person"

const PET_STORE := "Pet Store"
const PET_STORE_GET_FREE := "Get Free"
const PET_SEND_TO_SELF := "Myself"
const PET_SEND_TO_PERSON := "My Person"
const PET_CONNECT_PERSON_FIRST := "Connect your person first"
const PET_NO_PETS_YET := "No pets yet"
const PET_VISIT_STORE := "Visit Pet Store"
const PET_JOINED_FMT := "%s joined you!"
const PET_ALREADY_PENDING := "A Parrot gift is already on the way."
const PET_SENT_SELF := "Parrot gift sent to your chest."
const PET_SENT_PERSON := "Parrot gift sent to your Person."

const EMPTY_HEADLINE := "Connect with your Person"
const EMPTY_SUPPORT := "Choose the one person you'd like to exchange scrolls with."
const COMPOSE_NEED_PERSON := "Connect with your Person before sending a scroll."
const ALREADY_CONNECTED_FMT := "You're already connected with %s."
const DISCONNECT_FIRST := "Disconnect first if you want to connect with someone else."
const OWN_CODE := "That's your own connection code."
const INVALID_QR := "This isn't a valid Chest of Love Notes connection code."
const CAMERA_RATIONALE := "Camera access lets you scan your Person's connection code."
const CAMERA_NEEDED := "Camera permission is needed to scan a connection code."
const NOTIFY_RATIONALE := "Get notified when your Person sends a scroll or when a scroll becomes ready."
const LOCATION_RATIONALE := "Use your current location for Location Locks and verify location-based scrolls."
const CAMERA_SETUP_RATIONALE := "Scan your Person's QR connection code."
const GEOFENCE_RATIONALE := "Allow background location so Chest of Love Notes can notify you when you enter this scroll's unlock area."
const CONNECTION_REQUEST_ACCEPTED := "Connection request accepted"
const PERMISSIONS_SETUP_WHY := "A few optional permissions help Chest of Love Notes work smoothly. You can change these anytime in Profile."
const PERMISSIONS_SECTION := "PERMISSIONS"
const RELATIONSHIP_SECTION := "Relationship"
const EDIT_RELATIONSHIP := "Edit relationship"
const RELATIONSHIP_SAVE := "Save"
const RELATIONSHIP_SKIP := "Skip for now"
const RELATIONSHIP_NOT_SET := "Not set"
const RELATIONSHIP_OTHER := "Other"
const RELATIONSHIP_CUSTOM_HINT := "Custom label (e.g. Soulmate)"
const RELATIONSHIP_SAVE_FAILED := "Connected, but relationship could not be saved. You can set it anytime."


static func relationship_prompt_title(display_name: String) -> String:
	var n := display_name.strip_edges()
	if n.is_empty():
		n = PERSON
	return "What is %s to you?" % n


static func relationship_line(display_label: String) -> String:
	var d := display_label.strip_edges()
	if d.is_empty():
		d = RELATIONSHIP_NOT_SET
	return "Relationship: %s" % d


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

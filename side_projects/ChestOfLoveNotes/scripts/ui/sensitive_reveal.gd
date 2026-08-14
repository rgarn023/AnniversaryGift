extends RefCounted
class_name SensitiveReveal
## Isolates sensitive reveal actions so Android biometrics can be inserted later.
## Current pass: confirmation callback only (no biometric gate).


static func request_sensitive_reveal(on_confirmed: Callable, on_cancelled: Callable = Callable()) -> void:
	## Future: require biometric confirmation before invoking on_confirmed.
	if on_confirmed.is_valid():
		on_confirmed.call()
	elif on_cancelled.is_valid():
		on_cancelled.call()

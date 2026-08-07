extends RefCounted
class_name BuildFlags
## Compile-time style flags for Chest of Love Notes builds.
##
## PRIVATE_ONBOARDING_BUILD:
##   true  → Sign Up + Sign In + Check Your Email (temporary private invite build)
##   false → Sign In only (later private release; existing members still work)
##
## Never put real emails, passwords, or server secrets in this file.

const PRIVATE_ONBOARDING_BUILD := true
const APP_VERSION_NAME := "0.1.8-mobile-correction-complete"
const APP_VERSION_CODE := 9

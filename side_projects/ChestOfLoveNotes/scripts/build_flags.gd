extends RefCounted
class_name BuildFlags
## Compile-time style flags for Chest of Love Notes builds.
##
## PRIVATE_ONBOARDING_BUILD:
##   true  → Sign Up + Sign In + Check Your Email (temporary private invite build)
##   false → Sign In only (later private release; existing members still work)
##
## SHOW_ONBOARDING_BANNER:
##   Never show "Private Onboarding Build" / demo watermarks in normal APK testing.
##   Keep false for debug and release test builds.
##
## Never put real emails, passwords, or server secrets in this file.

const PRIVATE_ONBOARDING_BUILD := true
## Visible watermark/banner must stay off for phone test APKs.
const SHOW_ONBOARDING_BANNER := false
## Debug-only chest preview path (never enable in production content path).
const DEV_CHEST_SCROLL_PREVIEW := false
## Debug/test builds may offer "Send to Myself (Test)" using the real send path.
const DEBUG_SELF_SEND := true
const APP_VERSION_NAME := "0.1.49-chest-scroll-polish"
const APP_VERSION_CODE := 49

class_name AdsBackend
extends RefCounted
## What AdsGate needs from an ad SDK. AdMobBackend wraps the Poing AdMob plugin (Android);
## FakeAdsBackend stands in on desktop and in tests. Every method that waits is a coroutine.

enum Consent { UNKNOWN, NOT_REQUIRED, REQUIRED, OBTAINED }


## Refreshes the consent status (UMP's update). Returns the Consent after it.
func update_consent() -> Consent:
	return Consent.NOT_REQUIRED


## Shows the consent form if one is available; returns when it's dismissed.
func show_consent_form() -> void:
	pass


func privacy_options_required() -> bool:
	return false


func show_privacy_options() -> void:
	pass


## Starts the ad SDK (only after consent allows requests).
func initialize() -> void:
	pass


## Loads an ad; true when one filled.
func load_rewarded() -> bool:
	return false


func load_interstitial() -> bool:
	return false


## Shows the loaded rewarded ad; returns true only if the earned-reward callback fired.
func show_rewarded() -> bool:
	return false


## Shows the loaded interstitial; returns when it's closed (or failed to show).
func show_interstitial() -> void:
	pass

class_name FakeAdsBackend
extends AdsBackend
## Desktop and test stand-in for AdMob. Fill, consent and the reward are switches; every load
## is recorded with whether consent allowed it at the time (the "no request before consent"
## check reads `requests`).

var consent := AdsBackend.Consent.NOT_REQUIRED
var consent_after_form := AdsBackend.Consent.OBTAINED
var fill := true
var earn := true  # whether a shown rewarded ad calls back with the reward
var privacy_required := false
var load_frames := 0  # frames a load takes (tests use it for the 3 s wait)
var consent_frames := 0  # frames a consent update takes (one that never answers: huge)
var show_frames := 0  # frames a full-screen ad stays up
var initialized := false
var forms_shown := 0
var requests: Array[String] = []  # "rewarded" / "interstitial", in order
var shown: Array[String] = []

var _tree: SceneTree


func _init(tree: SceneTree = null) -> void:
	_tree = tree


func update_consent() -> AdsBackend.Consent:
	for i in consent_frames:
		await _tree.process_frame
	return consent


func show_consent_form() -> void:
	forms_shown += 1
	consent = consent_after_form


func privacy_options_required() -> bool:
	return privacy_required


func show_privacy_options() -> void:
	forms_shown += 1


func initialize() -> void:
	initialized = true


func load_rewarded() -> bool:
	return await _load("rewarded")


func load_interstitial() -> bool:
	return await _load("interstitial")


func show_rewarded() -> bool:
	shown.append("rewarded")
	for i in show_frames:
		await _tree.process_frame
	return earn


func show_interstitial() -> void:
	shown.append("interstitial")
	for i in show_frames:
		await _tree.process_frame


func _load(kind: String) -> bool:
	requests.append(kind)
	print("[ads] (fake) load %s: %s" % [kind, "filled" if fill else "no fill"])
	for i in load_frames:
		await _tree.process_frame
	return fill

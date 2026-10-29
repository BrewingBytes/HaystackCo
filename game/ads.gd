class_name AdsGate
extends Node
## Ads for the game (design D6/D17, eng D3/D7; G8): consent first, then the SDK, then ads.
## Nothing loads before consent allows requests, and nothing at all when it doesn't. One
## rewarded and one interstitial are kept loaded; a failed load retries a minute later in the
## background. A reward is granted only when the earned-reward callback fired. AdPolicy decides
## whether an interstitial may show; this only shows it.

signal offers_changed  # consent resolved or the rewarded ad's readiness changed

enum Consent { PENDING, CAN_REQUEST, CANNOT_REQUEST }
enum Load { NONE, LOADING, READY }

const RETRY_S := 60.0
const INTERSTITIAL_WAIT_MS := 3000  # "Next pile" shows "Loading…" at most this long

var consent := Consent.PENDING
var backend: AdsBackend
## How long boot waits for a consent update before going on without ads.
var consent_timeout_ms := 10_000

var _rewarded := Load.NONE
var _interstitial := Load.NONE
var _showing := false


## Picks the AdMob backend on a device with the plugin, else the fake (desktop, tests).
func _init(p_backend: AdsBackend = null) -> void:
	backend = p_backend
	if backend == null:
		backend = AdMobBackend.new() if AdMobBackend.available() else FakeAdsBackend.new()


func _ready() -> void:
	if backend is FakeAdsBackend and backend._tree == null:
		backend._tree = get_tree()


## Boot (design D6): refresh consent and show the form where it's required, before the yard.
## Then, if requests are allowed, start the SDK and load in the background.
## A consent update that doesn't answer within consent_timeout_ms counts as unknown: the yard
## opens without ads this session rather than waiting on the boot screen.
func resolve_consent() -> void:
	var status: AdsBackend.Consent = await _within(backend.update_consent, consent_timeout_ms, AdsBackend.Consent.UNKNOWN)
	if status == AdsBackend.Consent.REQUIRED:
		await backend.show_consent_form()
		status = await _within(backend.update_consent, consent_timeout_ms, AdsBackend.Consent.UNKNOWN)
	_set_consent(status)


func offers_visible() -> bool:
	return consent == Consent.CAN_REQUEST and _rewarded == Load.READY and not _showing


func privacy_options_required() -> bool:
	return consent != Consent.PENDING and backend.privacy_options_required()


## Settings "Privacy options": reopens the form; the answer can turn ads on or off.
func show_privacy_options() -> void:
	await backend.show_privacy_options()
	_set_consent(await backend.update_consent())


## Shows the rewarded ad. True only if the earned-reward callback fired.
func show_rewarded() -> bool:
	if not offers_visible():
		return false
	_showing = true
	_rewarded = Load.NONE
	offers_changed.emit()
	print("[ads] show rewarded")
	var earned := await backend.show_rewarded()
	print("[ads] rewarded closed: %s" % ("earned" if earned else "no reward"))
	_showing = false
	_load_rewarded()
	return earned


## The pile-complete break, after AdPolicy said yes: shows the interstitial if one is loaded
## or arrives within INTERSTITIAL_WAIT_MS; otherwise skips (never retried into gameplay).
## True if it showed.
func show_interstitial() -> bool:
	if consent != Consent.CAN_REQUEST or _showing:
		return false
	if _interstitial == Load.NONE:
		_load_interstitial()
	var waited_from := Time.get_ticks_msec()
	while _interstitial == Load.LOADING and Time.get_ticks_msec() - waited_from < INTERSTITIAL_WAIT_MS:
		await get_tree().process_frame
	if _interstitial != Load.READY:
		print("[ads] interstitial skipped: none ready within %d ms" % INTERSTITIAL_WAIT_MS)
		return false
	_showing = true
	_interstitial = Load.NONE
	print("[ads] show interstitial")
	await backend.show_interstitial()
	_showing = false
	_load_interstitial()
	return true


func _set_consent(status: AdsBackend.Consent) -> void:
	var allowed := status == AdsBackend.Consent.OBTAINED or status == AdsBackend.Consent.NOT_REQUIRED
	var was := consent
	consent = Consent.CAN_REQUEST if allowed else Consent.CANNOT_REQUEST
	print("[ads] consent %s: %s" % [AdsBackend.Consent.keys()[status].to_lower(), "ads on" if allowed else "no ad requests"])
	if allowed and was != Consent.CAN_REQUEST:
		await backend.initialize()
		_load_rewarded()
		_load_interstitial()
	offers_changed.emit()


func _load_rewarded() -> void:
	if consent != Consent.CAN_REQUEST or _rewarded != Load.NONE:
		return
	_rewarded = Load.LOADING
	print("[ads] request rewarded")
	var filled := await backend.load_rewarded()
	_rewarded = Load.READY if filled else Load.NONE
	offers_changed.emit()
	if not filled:
		_retry(_load_rewarded)


func _load_interstitial() -> void:
	if consent != Consent.CAN_REQUEST or _interstitial != Load.NONE:
		return
	_interstitial = Load.LOADING
	print("[ads] request interstitial")
	var filled := await backend.load_interstitial()
	_interstitial = Load.READY if filled else Load.NONE
	if not filled:
		_retry(_load_interstitial)


## Runs the coroutine `work`; its result, or `fallback` if it takes longer than `timeout_ms`
## (a late result is dropped).
func _within(work: Callable, timeout_ms: int, fallback: Variant) -> Variant:
	var box := {}  # filled in place: a lambda can't reassign a captured variable
	(func() -> void: box.value = await work.call()).call()
	var started := Time.get_ticks_msec()
	while not box.has("value") and Time.get_ticks_msec() - started < timeout_ms:
		await get_tree().process_frame
	if not box.has("value"):
		print("[ads] consent update timed out after %d ms" % timeout_ms)
	return box.get("value", fallback)


func _retry(load: Callable) -> void:
	if is_inside_tree():
		get_tree().create_timer(RETRY_S).timeout.connect(load)

extends GutTest
## G8: AdsGate over the fake backend (design D6/D17, eng D3/D7). No ad request before consent,
## none without it, no fill hides the offers, a reward only on the earned-reward callback, and
## the "Next pile" wait for an interstitial is bounded.

const C := AdsBackend.Consent

var fake: FakeAdsBackend
var gate: AdsGate


func _gate(consent: AdsBackend.Consent) -> void:
	fake = FakeAdsBackend.new(get_tree())
	fake.consent = consent
	gate = AdsGate.new(fake)
	add_child_autofree(gate)


func _settle() -> void:
	for i in 5:
		await get_tree().process_frame


func test_no_request_before_consent_then_loads_after_the_form() -> void:
	_gate(C.REQUIRED)
	await _settle()
	assert_eq(fake.requests, [] as Array[String], "nothing before consent is resolved")
	assert_false(fake.initialized)
	await gate.resolve_consent()
	await _settle()
	assert_eq(fake.forms_shown, 1, "the form shows where consent is required")
	assert_eq(gate.consent, AdsGate.Consent.CAN_REQUEST)
	assert_true(fake.initialized)
	assert_true(fake.requests.has("rewarded") and fake.requests.has("interstitial"))
	assert_true(gate.offers_visible())


func test_no_requests_at_all_when_consent_isnt_given() -> void:
	_gate(C.REQUIRED)
	fake.consent_after_form = C.REQUIRED  # form failed or was closed without an answer
	await gate.resolve_consent()
	await _settle()
	assert_eq(gate.consent, AdsGate.Consent.CANNOT_REQUEST)
	assert_false(fake.initialized)
	assert_eq(fake.requests, [] as Array[String])
	assert_false(gate.offers_visible())
	assert_false(await gate.show_interstitial())
	assert_eq(fake.shown, [] as Array[String])


func test_no_form_where_consent_isnt_required() -> void:
	_gate(C.NOT_REQUIRED)
	await gate.resolve_consent()
	assert_eq(fake.forms_shown, 0)
	assert_eq(gate.consent, AdsGate.Consent.CAN_REQUEST)


func test_offers_hidden_until_consent_and_on_no_fill() -> void:
	_gate(C.NOT_REQUIRED)
	assert_false(gate.offers_visible(), "consent not resolved yet")
	fake.fill = false
	await gate.resolve_consent()
	await _settle()
	assert_true(fake.requests.has("rewarded"))
	assert_false(gate.offers_visible(), "no fill: offers hidden, never a dead button")


func test_reward_only_on_the_earned_callback() -> void:
	_gate(C.NOT_REQUIRED)
	await gate.resolve_consent()
	await _settle()
	fake.earn = false
	assert_false(await gate.show_rewarded(), "closed early: no reward")
	await _settle()
	fake.earn = true
	assert_true(await gate.show_rewarded())
	assert_eq(fake.shown, ["rewarded", "rewarded"] as Array[String])


func test_next_pile_waits_at_most_three_seconds_for_an_interstitial() -> void:
	_gate(C.NOT_REQUIRED)
	fake.fill = false
	await gate.resolve_consent()
	await _settle()
	fake.fill = true
	fake.load_frames = 100_000  # never arrives in time
	var started := Time.get_ticks_msec()
	assert_false(await gate.show_interstitial())
	var waited := Time.get_ticks_msec() - started
	assert_between(waited, AdsGate.INTERSTITIAL_WAIT_MS, AdsGate.INTERSTITIAL_WAIT_MS + 500)
	assert_eq(fake.shown, [] as Array[String], "no fill in time: straight to the new pile")


func test_a_ready_interstitial_shows() -> void:
	_gate(C.NOT_REQUIRED)
	await gate.resolve_consent()
	await _settle()
	assert_true(await gate.show_interstitial())
	assert_eq(fake.shown, ["interstitial"] as Array[String])


# Found by /qa on 2026-10-29: boot awaited the consent update with no limit, so a UMP callback
# that never came left the player on the boot screen.
func test_boot_goes_on_without_ads_when_consent_never_answers() -> void:
	_gate(C.NOT_REQUIRED)
	fake.consent_frames = 1_000_000
	gate.consent_timeout_ms = 200
	var box := {}
	(func() -> void:
		await gate.resolve_consent()
		box.done = true).call()
	await wait_until(func() -> bool: return box.has("done"), 2.0)
	assert_true(box.has("done"), "boot went on")
	assert_eq(gate.consent, AdsGate.Consent.CANNOT_REQUEST, "unknown consent: no ads this session")
	assert_eq(fake.requests, [] as Array[String])

class_name AdMobBackend
extends AdsBackend
## AdsBackend over the Poing AdMob plugin (AdMob + UMP, Android). The ad units are Google's test
## units until the real ones arrive with the AdMob account (G13a).

const REWARDED_UNIT := "ca-app-pub-3940256099942544/5224354917"
const INTERSTITIAL_UNIT := "ca-app-pub-3940256099942544/1033173712"

## A callback turned into something to await.
class _Wait:
	signal done(value: Variant)


var _rewarded: RewardedAd
var _interstitial: InterstitialAd


static func available() -> bool:
	return Engine.has_singleton("PoingGodotAdMob")


func update_consent() -> AdsBackend.Consent:
	var wait := _Wait.new()
	var params := ConsentRequestParameters.new()
	params.tag_for_under_age_of_consent = false  # 18+ audience, not child-directed
	UserMessagingPlatform.consent_information.update(params,
		func() -> void: wait.done.emit(""),
		func(error: FormError) -> void: wait.done.emit(error.message))
	var error: String = await wait.done
	if not error.is_empty():
		print("[ads] consent update failed: %s (using the last status)" % error)
	return UserMessagingPlatform.consent_information.get_consent_status() as AdsBackend.Consent


func show_consent_form() -> void:
	if not UserMessagingPlatform.consent_information.get_is_consent_form_available():
		return
	var wait := _Wait.new()
	UserMessagingPlatform.load_consent_form(
		func(form: ConsentForm) -> void: form.show(func(_error: FormError) -> void: wait.done.emit(null)),
		func(error: FormError) -> void:
			print("[ads] consent form failed to load: %s" % error.message)
			wait.done.emit(null))
	await wait.done


func privacy_options_required() -> bool:
	return UserMessagingPlatform.consent_information.get_privacy_options_requirement_status() \
		== ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED


func show_privacy_options() -> void:
	var wait := _Wait.new()
	UserMessagingPlatform.show_privacy_options_form(func(_error: FormError) -> void: wait.done.emit(null))
	await wait.done


func initialize() -> void:
	var wait := _Wait.new()
	var listener := OnInitializationCompleteListener.new()
	listener.on_initialization_complete = func(_status: InitializationStatus) -> void: wait.done.emit(null)
	MobileAds.initialize(listener)
	await wait.done


func load_rewarded() -> bool:
	var wait := _Wait.new()
	var callback := RewardedAdLoadCallback.new()
	callback.on_ad_loaded = func(ad: RewardedAd) -> void:
		_rewarded = ad
		wait.done.emit(true)
	callback.on_ad_failed_to_load = func(error: LoadAdError) -> void:
		print("[ads] rewarded failed to load: %s" % error.message)
		wait.done.emit(false)
	RewardedAdLoader.new().load(REWARDED_UNIT, AdRequest.new(), callback)
	return await wait.done


func load_interstitial() -> bool:
	var wait := _Wait.new()
	var callback := InterstitialAdLoadCallback.new()
	callback.on_ad_loaded = func(ad: InterstitialAd) -> void:
		_interstitial = ad
		wait.done.emit(true)
	callback.on_ad_failed_to_load = func(error: LoadAdError) -> void:
		print("[ads] interstitial failed to load: %s" % error.message)
		wait.done.emit(false)
	InterstitialAdLoader.new().load(INTERSTITIAL_UNIT, AdRequest.new(), callback)
	return await wait.done


func show_rewarded() -> bool:
	if _rewarded == null:
		return false
	var wait := _Wait.new()
	var got := {earned = false}  # filled in place: a lambda can't reassign a captured variable
	var listener := OnUserEarnedRewardListener.new()
	listener.on_user_earned_reward = func(_item: RewardedItem) -> void: got.earned = true
	_rewarded.full_screen_content_callback.on_ad_dismissed_full_screen_content = func() -> void: wait.done.emit(null)
	_rewarded.full_screen_content_callback.on_ad_failed_to_show_full_screen_content = func(_error: AdError) -> void: wait.done.emit(null)
	_rewarded.show(listener)
	await wait.done
	_rewarded.destroy()
	_rewarded = null
	return got.earned


func show_interstitial() -> void:
	if _interstitial == null:
		return
	var wait := _Wait.new()
	_interstitial.full_screen_content_callback.on_ad_dismissed_full_screen_content = func() -> void: wait.done.emit(null)
	_interstitial.full_screen_content_callback.on_ad_failed_to_show_full_screen_content = func(_error: AdError) -> void: wait.done.emit(null)
	_interstitial.show()
	await wait.done
	_interstitial.destroy()
	_interstitial = null

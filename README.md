# Haystack Co.

Somewhere in this haystack is a needle. Dig it out by hand, then build the machines that dig for you.

An Android portrait 3D idle game built in Godot 4. Design: [docs/designs/haystack-co.md](docs/designs/haystack-co.md) (live plan: the last sections) and [DESIGN.md](DESIGN.md). Work is tracked in [GitHub issues](https://github.com/BrewingBytes/HaystackCo/issues).

## Godot version pin

| Component | Version | Why |
|---|---|---|
| Godot | **4.7.2-stable** (editor, export templates, CI) | Latest stable (2026-08-18); the AdMob plugin is tested through 4.7.2 |
| Poing AdMob plugin | 5.1.0 (Android `ads` only, no mediation) | "Minimum Godot export version 4.4+ (testing through 4.7.2)", compileSdk 35 |
| GUT | 9.7.1 | Current release for Godot 4.6+ |
| godot-lib (helper plugin) | `org.godotengine:godot:4.7.2.stable` | Must match the engine |
| godot-cpp (native module) | 10.0.0-stable, `api_version` 4.7, pinned by SHA-256 in `native/CMakeLists.txt` | v10 targets Godot 4.3+ by API version |
| Android NDK | r28 (28.2.13676358 locally; CI uses the runner's latest) | 16 KB-aligned arm64 builds |
| Android | minSdk 24, targetSdk 36, arm64-v8a only, Gradle build, AAB | Play's target-API rule; arm64 is every target phone and the only ABI we test. x86_64 (Chromebooks, Intel emulators) is left out until it gets a smoke test |

Bumping any of these: change `GODOT_VERSION` in `.github/workflows/ci.yml`, `godotVersion` in `plugins/android/haystack_helpers/build.gradle.kts`, and this table, then re-run the 16 KB check.

**16 KB page size (Play requirement):** verified on 2026-10-27. A signed release AAB with the AdMob plugin passes `tools/check_16kb.sh`: zipalign `-P 16` OK, and every `.so` has 16 KB ELF LOAD alignment (`libgodot_android.so`, `libc++_shared.so`, arm64).

### Accessibility findings (design D14)

Verified on 2026-10-27 on an arm64 Android 36 emulator (Play image), release AAB:

- **Android font scale:** Godot does not scale its UI with the Android font-size setting. Our `HaystackHelpers` plugin reads `fontScale`, and the UI theme will scale from it (G9). *Verified:* the log reads `font scale 1.00`, then `2.00` after switching to 200% and resuming, in the same process. *Still to check:* that the text itself doesn't change size, on the Compatibility build (see the emulator note below).
- **Font-size change killed the game (fixed):** Godot's build template leaves `fontScale` out of the activity's `configChanges`. Changing the system font size while the game was in the background recreated the activity, Godot force-quit, and the player came back to the home screen. `addons/haystack_android` now adds `fontScale|fontWeightAdjustment` to the template manifest on every export, and CI checks the AAB's mask.
- **Reduce motion:** the plugin reads `ANIMATOR_DURATION_SCALE`. A value of 0 ("Remove animations") turns on reduced motion by default. *Verified:* `reduce motion true` after Remove animations, re-read on resume.
- **TalkBack:** forum reports say Godot's AccessKit screen-reader support (4.5+) works on desktop but not with Android TalkBack ([1](https://forum.godotengine.org/t/question-about-accessibility-on-android/122578), [2](https://forum.godotengine.org/t/european-market-compliance-android-embedded-mode-talkback-on-godot-node-view-is-not-focusable/130058)). *Verified:* with TalkBack on, the plugin reports `screen reader true`, but the accessibility tree is just an unlabeled `SurfaceView`, so TalkBack has nothing to read. We still set `accessibility_name` on controls, but the plan assumes no screen-reader support on Android. The store listing says the 3D yard isn't screen-reader accessible.
- **Emulator note:** Godot's Vulkan present fails on the Mac emulator in both software and `-gpu host` modes (`VkResult error 5`), so the screen stays black. The Compatibility build renders there, so visual checks and the frame gate run on that build (DEVICE-1).

## Layout

```
project.godot, export_presets.cfg   Godot project (Mobile renderer, portrait); "Android Compat" preset = Compatibility renderer
sim/                                integer sim (no Nodes, time or files): PileSim ties together the height grid, pile
                                    generation + needles, tools/ (brush specs, magnet, detector), reveal, conveyor dig,
                                    offline and the hay ledger; machines/ has placement rules, the shelf and placement
                                    mode (design D4); economy.json + Economy (the catalog, schema-checked), Wallet and
                                    Inventory (hay is currency once it leaves the pile; Buy spends it); GameState +
                                    SaveCodec (what a save holds, and its bytes); ClockGuard (time away, the game's
                                    day); AdPolicy (interstitial ceilings)
world/                              yard, hay pile (meshes + shaders), orbit camera, height picker, straw textures,
                                    GestureRouter (the eng gesture state machine), machine views (ghost + print), yard HUD
game/                               main scene (consent, load at boot, save every 30 s / on pause, pile card and Next
                                    pile), SaveStore (files, backup, quarantine), Settings (device prefs), AdsGate +
                                    AdMob/fake backends, dev stand-ins for G9's offer surfaces, autoplay frame harness,
                                    Game Loop + a11y wrappers, spike config
ui/                                 UiTheme (DESIGN.md tokens, fonts, number formats), the Shop, bundled fonts, SVG icons
test/                               GUT tests (headless)
tools/check_pacing.gd               pacing gate (G5): pacing_bot.gd plays, pacing_gate.gd checks the targets
tools/check_16kb.sh                 Play 16 KB page-size check for an AAB
tools/gen_straw_texture.gd          regenerates world/textures/straw_*.png (outputs are committed)
addons/gut, addons/admob            vendored GUT 9.7.1 and Poing AdMob 5.1.0
addons/haystack_android             packs our Android plugin into exports; patches the template manifest
addons/haystack_native              GDExtension manifest for the native module (libraries in bin/, built, not committed)
native/                             C++ ports of sim hot paths: pile generation (G2b), brush strokes (G5), save tile
                                    deltas (G6); CMake + godot-cpp
plugins/android/haystack_helpers    Kotlin Godot Android plugin (a11y settings, Test Lab Game Loop hooks)
```

## G2 rendering spike

The yard renders the largest planned pile (1024 × 1024 cells of 12.5 cm: 120 m across, 30 m tall). Heights are 16-bit integers uploaded as 64 × 64 tiles, re-sent only when dirty. The pile is drawn as a coarse mesh (one vertex per 4 cells) plus a fine patch (one vertex per cell) that follows the camera, so rake furrows show up close. Loose straw is a 20K-card MultiMesh placed entirely on the GPU.

**Frame harness.** `game/autoplay.gd` runs a warm-up (5 min, every phase, so shader compiles land there and are logged separately), then 60 s each of orbit (including full zoom-out), rake and conveyor. A missed frame is an interval over 1.5 × the frame period; a phase passes at ≤ 5% missed. It also times a rake stamp, picking, an 8 h offline fast-forward and tile uploads, and records thermal status. Results go to the Test Lab results file, to `user://spike_results.json` and to logcat (`[spike] key=value`, one line per key).

| Scenario | Grid | Camera | Use |
|---|---|---|---|
| 1 | 1024 | orbit | the gate run |
| 2 | 1024 | fixed three-quarter | ladder rung 2 |
| 3 / 4 | 768 / 512 | orbit | smaller-pile fallbacks |
| 9 | 1024 | orbit | 10 s smoke run |

```sh
# Gate device: the arm64 Android 36 emulator (DEVICE-1). Install the universal APK from
# build/haystack-compat.aab first (the Mobile renderer can't present on the Mac emulator).
adb shell am start -a com.google.intent.action.TEST_LOOP -t application/javascript --ei scenario 1 \
  -n com.brewingbytes.haystack/com.brewingbytes.haystack.helpers.GameLoopLauncher
adb logcat -s godot:I | grep '\[spike\]'

# Desktop: smoke run, or a screenshot to judge the look
godot -- --scenario=9
godot -- --shot=/tmp/yard.png --rake --zoom=0.45
godot -- --shot=/tmp/needle.png --dig-needle   # or --trench
godot -- --shot=/tmp/ghost.png --place          # or --placed
# In the desktop yard, keys 1–5 pick rake, pitchfork, blower, magnet, detector; B buys a conveyor
# (placement mode), R turns the ghost. On a phone, the DEV · BUY CONVEYOR button stands in for the Shop (G9).
```

**Gate result (2026-10-27, emulator, Compatibility renderer, 1024 grid): frames PASS.**

| Scenario | Orbit missed | Rake missed | Conveyor missed | Interval p95 | Shader-compile hitches (warm-up) |
|---|---|---|---|---|---|
| 1 orbit camera | 0.17% | 0.03% | 0.06% | 17.8–18.4 ms | 12 |
| 2 fixed camera | 0.19% | 0.31% | 0.22% | 19.2–19.5 ms | 7 |

| Budget | Emulator | Result |
|---|---|---|
| Pile generation ≤ 300 ms | 2.3–5.9 s in GDScript; **8.7 ms in C++** (G2b) | pass with the native module |
| Rake ≤ 2 ms/frame (p95) | 0.6–0.9 ms | pass |
| 8 h offline < 500 ms | 128 ms (sloped trenches) | pass |
| 8 h away, G7 return path (1-min steps, needle checks) < 500 ms | 183–234 ms (2026-10-28, scenario 9 `come_back_8h_ms`) | pass |
| Tile upload | 0.07 ms per 64² tile | pass |

**G4 on the emulator (2026-10-27):** top-band orbit, recenter (320 ms ease) and double-tap-and-drag zoom all work, driven by a monkey script (`adb emu event` and `input` are too slow for a 300 ms double tap; `sendevent` needs root). Found and fixed on the way: Godot marks touch releases handled before `_unhandled_input`, and emulates a mouse click per touch, so the yard reads touches in `_input` and ignores emulated mouse events. **First launch after an install shows a blank screen for 20–40 s on the emulator** while Godot compiles shaders (later launches use the cache); DESIGN's boot "Raking the yard…" screen with shader warm-up (G9) must cover this.

Thermal status stayed 0. Emulator frame times reflect the Mac's GPU, not a low-end phone (DEVICE-1). Conveyor trenches have 2:1 side walls with ±25 cm of lumpiness, cut top-down to the ground. The trench end face is still vertical: sloping it would multiply offline cost, so a steep-face texture projection hides the smearing instead.

## G5 economy and pacing

The catalog is `sim/economy.json`; every tunable number (prices, `unitsPerHay`, pile sizes, needles, reveal, tools, conveyor, offline caps, `hayBoostMinutes`) lives there, and `Economy` rejects unknown keys or behaviors, missing keys, non-integers and out-of-range values. `SimDefaults` reads it.

**checkPacing (2026-10-28, bundled economy, 500 install seeds): PASS in 89 s.** First needle 0:05 (≤ 1:00). First machine: worst 8:42, median 8:36, best 7:35 (≤ 10:00). Seed 1 buys pitchfork 0:49, magnet 2:23, blower 3:35, detector 5:21, conveyor 8:37. Report only: 2 piles/hour and 1 ad break/hour in a 60-minute session. Prices at 3× fail the gate (GUT).

The bot rakes 4 strokes/s in a back-and-forth raster over 8 m windows, starting at the flank the default camera frames and moving on when a pass yields under a quarter of the window's first pass. It always uses the brush with the most hay per stroke (the pitchfork, not the blower, which pushes most of its hay), buys the cheapest unowned item as soon as it can, and places machines at the nearest edge spot facing the centre. Strokes go through `SimNative.brush_stroke` (byte parity with `BrushTool.apply`); pile 1 is played once and forked per install seed. The run is single-threaded on purpose: the native stroke copies the grid, and worker threads were slower.

## G6 saves

`user://save/game.sav` is the save; `game.bak` is a copy of the last good one, made before each write; writes go to a `.tmp` file that is renamed over (Godot has no fsync). The file is `HSTK` · version · length · body · SHA-256, and the hash is checked before the version, so damage falls back to the backup and only an intact save from a newer app is refused (left untouched; that session doesn't save). A file that fails to load moves to `save/quarantine/` (newest 4 kept).

The grid isn't stored whole. The pile is regenerated from its seed, checked against the digest it had when generated, and only the 64² tiles play changed are stored, each as heights or as hay removed (whichever packs smaller). A half-cleared 1024 pile is 28.7 KB (target ≤ 150 KB); a fresh pile is under 2 KB. Android backs up `save/` and skips `save/quarantine/` (rules in the helper AAR, checked in CI on the AAB). Saves run every 30 s, on pause or quit, and when a pile is finished; `--no-save`, `--shot` and autoplay runs never touch them. The notices ("Restored your last save", "starting fresh", "Update required") are in the debug line until G9's UI.

## G7 time away

`ClockGuard` (saved with the game) decides what time away is owed: now − last seen, clamped to 0..8 h (`offline.capMinutes`); a clock moved back pays nothing and resets last seen; at most 12 h a day (`dailyCapMinutes`). The game's day (local calendar day) only moves forward; a saved day more than one day ahead snaps back to today with today's allowances used up (eng D8 ForwardDay; logged for G12). It also holds today's interstitial count, which `AdPolicy` uses for the 6-a-day cap.

Machines dig through the owed time in 1-minute steps, within the current pile only: it stops when the pile is complete (`offline.pileCompletions` is 0 until pile-crossing is built) or every machine has dug its full reach. Needles found that way are `Offline` finds; the hay goes straight into the wallet. This runs at boot (after the load, off the main thread) and on resume from the background (yard input and processing held, then a save). The summary ("Away: +N hay from M min of digging (capped)") is in the debug line until G9's away sheet. 8 h on a 1024 pile with 4 conveyors: 218 ms on the desktop, 183–234 ms on the emulator (budget < 500 ms; autoplay reports it as `come_back_8h_ms`).

## G8 ads

Consent comes first (design D6): at boot `AdsGate` refreshes UMP consent and shows the form where it's required, before the yard. Only when consent allows requests does it start the AdMob SDK and keep one rewarded and one interstitial loaded (a failed load retries a minute later in the background); otherwise nothing is ever requested. `AdMobBackend` wraps the Poing plugin on Android; on desktop and in tests `FakeAdsBackend` stands in and records every request. The ad units are Google's test units until the AdMob account exists (G13a).

**Interstitial (`AdPolicy`, eng D3/D7):** a finished pile shows its card ("PILE n CLEARED", hay, needles, "Next pile") with the yard held still and pile n+1 generating behind it. The ad check runs only on the "Next pile" tap: never with a pointer down, never in the first session (until a later cold start or 30 min away), never before the first machine, 1 per pile, 6 a day on the clock guard's forward-only day, 4 min apart and 2 min after a rewarded ad. The button reads "Loading…" for at most 3 s while an ad loads; no fill goes straight to the new pile. Machines on clear ground keep digging the new pile, buried ones go to the shelf (re-review D10).

**Rewarded (design D17):** offers show only when consent allows ads and one is ready, and a reward is granted only on the earned-reward callback. 2× hay doubles hay for 10 min of play (`hayBoostMinutes`; it pauses in the background and is saved; the HUD rate shows "2× m:ss"); 2× offline doubles the hay from the last time away, never the needles; PING (48dp, bottom right, with the detector selected) rings where the detector would beep at half strength around the unfound needle nearest the camera, for 8 s. Until G9's Shop, away sheet and Settings, the 2× offers, Privacy options and the pile card are stand-ins (`game/dev_offers.gd`, `game/pile_card.gd`). New games now start on the catalog's pile 1 (512 cells); the harnesses keep the 1024 spike pile.

## G9a yard HUD

The HUD follows DESIGN.md with the bundled fonts (`ui/fonts/`, OFL, listed in `docs/assets.md`) and the tokens in `ui/ui_theme.gd`:
- **Top:** the hay counter (stencil, full digits up to 999,999, then "1.24M") with the hay-strand glyph. The rate under it is hay/s from the machines still digging, plus "2× m:ss" while the reward runs.
- **Top centre:** "PILE n". At font scale ≥ 1.5 it moves under the rate.
- **Top right:** mute (saved in `user://settings.cfg`, apart from the game save), SHOP ("SHOP · n" while machines wait on the shelf) and recenter.
- **Fades:** the top fade stays solid down to 8dp below the counter block at any font size, so the counter and rate stay above 4.5:1 over hay (9.9:1 and 5.9:1 even over white).
- **Tray:** five tool cells, 76dp, in price order. Locked tools show a lock and their price; tapping one opens the Shop scrolled to it. The placement bar replaces the tray while placing.
- **Notice line:** carries "Restored your last save", "Couldn't load your save, starting fresh", "Storage is full, progress isn't saving" (stays until a save works), the first-ghost hint, and, until G9c, the time-away summary.
- **Machines:** tapping a placed machine shows its label (name, rate, Move, Shelve) and a ground outline.
- **First Shop visit:** SHOP pulses twice the first time anything is affordable, until that visit (`cueShopSeen`).

The Shop (`ui/shop_screen.gd`) is the first-playable stub: YOUR MACHINES (Place; the first is the one orange), TOOLS and MACHINES, with ghost Buy buttons. When short of hay, Buy is disabled with "n more hay" under it. G9b adds the art, Settings, "More soon" and the 2× hay plate.

Figures with a decimal point ("+0.9/s", "1.5 M") use Barlow with tabular figures, not B612 Mono, whose full-width point reads "0. 9" (design D19). The debug line now shows only with `--info` or under autoplay. Desktop checks: `--font-scale=2` and the `--shot` flags `--shop` and `--label`.

## Build and test

The native module (pile generation in C++) is optional locally: without it, `PileGen` falls back to the GDScript reference and the parity test is skipped. CI builds it and requires it.

```sh
# Native module → addons/haystack_native/bin/ (macOS; for Android add the NDK toolchain flags in native/CMakeLists.txt)
cmake -S native -B native-build -G Ninja -DCMAKE_BUILD_TYPE=Release && cmake --build native-build
```

Requirements: Godot 4.7.2 + its Android export templates, JDK 17, the Android SDK (`ANDROID_HOME`) with an NDK, and `bundletool`.

```sh
# Helper plugin → addons/haystack_android/bin/*.aar
(cd plugins/android && ./gradlew :haystack_helpers:assemble)

# Tests and pacing (headless)
godot --headless --import
godot --headless -s addons/gut/gut_cmdln.gd
godot --headless -s res://tools/check_pacing.gd   # -- --economy=<file> --seeds=<n>; exit 1 = target missed or bad catalog, 2 = bad arguments

# Signed release AAB (set the keystore via env; never commit keystores)
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=... GODOT_ANDROID_KEYSTORE_RELEASE_USER=... GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=...
godot --headless --install-android-build-template --export-release "Android" build/haystack.aab
tools/check_16kb.sh build/haystack.aab
```

CI (`.github/workflows/ci.yml`) runs a gitleaks scan, GUT and checkPacing headless, then builds the helper plugin, exports a signed AAB with an ephemeral key, and runs the 16 KB check. The AdMob app ID and ad units are still Google's test IDs; the real ones arrive with G13a (AdMob account).

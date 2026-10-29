# TODOS

## In-game share replay (deferred by CEO review D3, 2026-10-27)
- **What:** A player-facing "Share your find" button that renders an ~8 s 9:16 replay of a needle find.
- **Why:** Lets every player find become a post; organic distribution once the game is live.
- **Pros:** Player-made clips; reuses Gemmory's 9:16 encoder; the deterministic sim makes replay cheap during play.
- **Cons:** An always-on input ring buffer (~25 KB) plus grid snapshots (3 × 512 KB) during play, and the offscreen replay must pass the emulator frame gate.
- **Context:** The design is in `docs/designs/haystack-co.md` git history (office-hours round 3, "Share clip"): take the newest snapshot ≥ 8 s before the find, re-simulate the buffered inputs and machine ticks, render offscreen *after* the find. Only `Player` and `Machine` finds get a share offer; `Offline` finds never do. For the MVP, marketing clips are screen-recorded.
- **Effort:** human M / CC S
- **Priority:** P2
- **Depends on:** the MVP sim being deterministic (pile sim + input model), Gemmory encoder copied.

## First-person walk mode (deferred by design consultation D8, 2026-10-27)
- **What:** A Find The Needle-style first-person mode: walk up to the pile and place machines by hand, alongside the default orbit camera.
- **Why:** Founder wants the PC game's physical, "I'm standing in the barn" feel; the MVP ships the orbit camera first (one-handed, portrait, in bed).
- **Pros:** Closest to the viral original; makes physical machine placement feel tactile.
- **Cons:** A second control scheme (two virtual sticks in portrait), motion-sickness risk, more QA.
- **Context:** Decided after the 3D reversal (design D7 = real 3D). Camera, input and placement code should keep camera mode behind an interface so walk mode is additive.
- **Effort:** human M / CC S (after the 3D MVP)
- **Priority:** P2
- **Depends on:** the 3D re-plan (CEO + eng review), the orbit-camera MVP.

## No-ads purchase (deferred by CEO re-review D3, 2026-10-27)
- **What:** Play Billing "remove ads" one-time purchase.
- **Why:** Revenue from players who dislike ads; cut #1 on the agreed list (CEO D4) after the Godot switch.
- **Pros:** Early IAP revenue; player choice.
- **Cons:** Godot Play Billing plugin + porting Gemmory's Inventory/Entitlements logic (~1d).
- **Context:** Launch is ads-only with capped interstitials and optional rewarded ads. Use godot-sdk-integrations/godot-google-play-billing.
- **Effort:** human S / CC S
- **Priority:** P2
- **Depends on:** the Godot MVP shipping.

## Remote Config economy overrides (deferred by CEO re-review D4, 2026-10-27)
- **What:** Firebase Remote Config overrides of the bundled economy, validated and activated at next cold start (original D10/D12 rules).
- **Why:** Retune pacing without an app update.
- **Pros:** Faster live tuning.
- **Cons:** Needs RC in the custom Godot Firebase Android plugin (~2d).
- **Context:** Launch uses the bundled economy; checkPacing (headless Godot) gates every release. The Firebase plugin built for Analytics/Crashlytics (D5) is the place to add RC.
- **Effort:** human M / CC S
- **Priority:** P2
- **Depends on:** the Firebase Godot plugin (kept, D5).

## Offline digging across piles (deferred by CEO re-review D6, 2026-10-27)
- **What:** Let offline machines finish the current pile and continue into pile n+1.
- **Why:** More generous idle loop for long absences.
- **Pros:** More offline hay.
- **Cons:** Needs a rule for relocating physically placed machines onto a new, unseen pile shape, plus tests (~1d+).
- **Context:** MVP stops offline accrual when the current pile completes; the pile-done card waits on return, and the player re-places machines on the new pile.
- **Effort:** human M / CC S
- **Priority:** P3
- **Depends on:** placement system (3D MVP).

## Firebase Analytics + Crashlytics (deferred by CEO re-review D11, 2026-10-27)
- **What:** Custom Godot Android plugin wrapping Gemmory's Firebase Analytics + Crashlytics (UMP-gated), plus a Godot logger hook forwarding script errors as non-fatals; the six CEO D7 events + machine_placed.
- **Why:** Real-player pacing medians (first_needle ≤ 60 s, first_machine ≤ 10 min) and script-error visibility after public launch.
- **Pros:** The core pacing evidence at scale; crash/non-fatal triage.
- **Cons:** ~3–3.5d native plugin work; no maintained Godot Firebase plugin.
- **Context:** Launch uses Play Console vitals + an exportable on-device event log for closed testers. Remote Config (D4 TODO) should land in the same plugin.
- **Effort:** human M / CC S
- **Priority:** P1 for 1.1
- **Depends on:** Godot MVP; consent flow from the AdMob/UMP plugin.

## More things to find in the pile (founder idea, 2026-10-27)
- **What:** Find types beyond the needle: other needle kinds (sewing, knitting, darning, a rusty one), "nits", and odd finds, each with its own look, glint and value.
- **Why:** Variety per pile and a collection to complete; gives each new, bigger pile a reason beyond size.
- **Pros:** Cheap content once the reveal path exists; a natural collection screen and store-screenshot subject.
- **Cons:** Each find needs a model, a reveal moment and economy tuning (checkPacing); "nits" needs a decision on what it means in the yard.
- **Context:** Raised during the G2 spike. The MVP sim reveals one needle type; keep the find type a data field in the catalog (G3/G5) so this is additive.
- **Effort:** human M / CC S (after the MVP)
- **Priority:** P2
- **Depends on:** G3 reveal, G5 catalog.

## Placement search hitch (found in G5, 2026-10-28)
- **What:** `Placement.nearest_edge_spot` takes ~110 ms on the desktop (8 headings × 5 offsets × radius steps, each building a footprint dictionary), so opening placement mode will hitch on the emulator.
- **Why:** Buy → placement is the "first machine" moment; a visible stall there undercuts it.
- **Pros:** Small, local fix: test the footprint cells directly instead of building a set per candidate, or step the radius coarsely and then refine.
- **Cons:** None beyond the time; GUT already covers the chosen spot.
- **Context:** Found while profiling the pacing bot (the bot now places on the tick after Buy, so the gate doesn't pay for it).
- **Effort:** human S / CC S
- **Priority:** P1 (before G9's Shop)
- **Depends on:** nothing.

## Pacing after the first machine (for G12 balance, 2026-10-28)
- **What:** The checkPacing report shows 2 piles/hour and 1 ad break/hour over a 60-minute session; the pile 1 needle comes at 0:05 for the bot.
- **Why:** Piles 2+ hide needles anywhere within 85% of the radius, and raking alone finds them slowly, so later piles drag and interstitial opportunities are rare (eng D9 asked to watch this number).
- **Pros:** The report already prints both numbers for every economy change.
- **Cons:** Tuning needs the magnet/detector in the bot's play and real tester data (G12 event log).
- **Context:** The gate targets (≤ 60 s, ≤ 10 min) pass with margin; this is about the hour after them.
- **Effort:** human S / CC S
- **Priority:** P2
- **Depends on:** G12 event log.

## Away sheet for short absences (found by /qa on G7, 2026-10-28)
- **What:** Coming back after 10 s with a working conveyor credits "+9 hay from 0 min of digging". DESIGN skips the away sheet only at 0 hay, so every quick app switch would open it.
- **Why:** A sheet with Collect after a notification glance is friction on the most common resume.
- **Pros:** One threshold in G9's sheet (e.g. under 1 min away, or under N hay: credit silently, the counter ticks).
- **Cons:** A design call (what counts as "away"); needs a DESIGN.md line.
- **Context:** G7 only writes the debug line; `GameState.come_back` already credits the hay either way, so this is purely presentation.
- **Effort:** human S / CC S
- **Priority:** P2 (decide in G9)
- **Depends on:** G9 away sheet.

---
# gstack: design-md-format=spec
name: Haystack Co.
description: A real 3D hay yard you build by hand; machines arrive as Prussian-blue blueprints and print into steel, and the HUD is the drawing sheet around it.
colors:
  ground: "#122640"
  surface: "#1A3558"
  raised: "#23466F"
  text: "#EEF1EC"
  text-muted: "#A9BDD6"
  action: "#FF5A1F"
  action-pressed: "#E54A12"
  action-hover: "#FF7140"
  on-action: "#122640"
  glint: "#FFFFFF"
  needle: "#C9D3DC"
  line: "#A9B5BF"
  hairline: "#3A5272"
  success: "#7FD49B"
  warning: "#F2B33D"
  error: "#FF8A78"
  scrim: "#0B1829"
  ghost-line: "#EEF1EC"
  ghost-fill: "#2C6FB7"
  ghost-invalid: "#FF8A78"
  yard-ground: "#3B3A33"
  machine-paint: "#C9D3DC"
typography:
  display:
    fontFamily: Big Shoulders Stencil
    fontWeight: 800
    fontSize: 44px
    lineHeight: 0.9
  display-large:
    fontFamily: Big Shoulders Stencil
    fontWeight: 800
    fontSize: 64px
    lineHeight: 0.9
  title:
    fontFamily: Big Shoulders Stencil
    fontWeight: 700
    fontSize: 32px
    lineHeight: 1
  body:
    fontFamily: Barlow Semi Condensed
    fontWeight: 400
    fontSize: 17px
    lineHeight: 1.45
  label:
    fontFamily: Barlow Semi Condensed
    fontWeight: 600
    fontSize: 13px
    letterSpacing: 0.06em
  count:
    fontFamily: Barlow Semi Condensed
    fontWeight: 600
    fontSize: 15px
    fontFeature: tnum
  mono:
    fontFamily: B612 Mono
    fontWeight: 400
    fontSize: 12px
rounded:
  sm: 2px
  full: 9999px
spacing:
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
  2xl: 48px
components:
  button-primary:
    backgroundColor: "{colors.action}"
    textColor: "{colors.on-action}"
    rounded: "{rounded.sm}"
  button-primary-hover:
    backgroundColor: "{colors.action-hover}"
  button-primary-pressed:
    backgroundColor: "{colors.action-pressed}"
  button-primary-disabled:
    backgroundColor: "{colors.raised}"
    textColor: "{colors.text-muted}"
  button-ghost:
    textColor: "{colors.text}"
    borderColor: "{colors.line}"
    rounded: "{rounded.sm}"
  plate:
    backgroundColor: "{colors.ground}"
    borderColor: "{colors.line}"
    rounded: "{rounded.sm}"
  sheet:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.sm}"
  tool-cell:
    backgroundColor: "{colors.ground}"
    borderColor: "{colors.hairline}"
    textColor: "{colors.text-muted}"
  tool-cell-selected:
    textColor: "{colors.text}"
    borderColor: "{colors.text}"
  placement-bar:
    backgroundColor: "{colors.ground}"
    borderColor: "{colors.line}"
    rounded: "{rounded.sm}"
  notice:
    backgroundColor: "{colors.ground}"
    borderColor: "{colors.line}"
    textColor: "{colors.text}"
    rounded: "{rounded.sm}"
  toggle-off:
    borderColor: "{colors.line}"
    textColor: "{colors.text-muted}"
    rounded: "{rounded.sm}"
  toggle-on:
    backgroundColor: "{colors.text}"
    textColor: "{colors.on-action}"
    rounded: "{rounded.sm}"
---

# Haystack Co.

## Overview

**Creative North Star:** Cyanotype to Blueprint. Blueprints *were* cyanotypes: Anna Atkins made the first sun-prints of plants and straw, and engineers later copied machine drawings with the same Prussian-blue process. The interface is that print. Hand tools look like soft sun-printed silhouettes, machines look like crisp engineering drawings, and the only warm thing on screen is the photographic hay you are digging.

**Product context:** Android portrait 3D idle game for adults (Play target audience 18+), built in Godot 4. You rake a big generated haystack by hand under an orbit camera, a needle clinks out, you sell the hay, buy five tools, then physically place conveyors in the yard that dig into the pile (Find The Needle style, not UI automation). Player: the wind-down grinder, evening or in bed, 5–15 minutes, sound on. Category peers (Find The Needle on PC, the Poki and Play clones, Thinflow's sorting game) are all sunny cartoon gold, blue sky or red barn, chunky wood-sign type.

**The one thing to remember:** "From a rake to a factory." Every decision below makes the move from hand to machine visible.

**Mode per surface:**
- Experience: the Yard (3D world: pile, ground, placed machines; HUD hugs the edges).
- Operate: Shop, Pile done, While you were away, Settings, Update required, Unsupported device.
- Persuade: Play Store icon, feature graphic, screenshots.

**Reference sites (research 2026-10-27):** dexerto.com viral-clip article (photographic straw), poki.com "Find The Needle in Haystack" (cartoon gold on cyan), dekudeals.com "A Needle In A Haystack: Sorting Game" (cartoon barn, wood-sign title).

**Key characteristics:**
- Deep blue print, chalk-white line work, faint paper tooth.
- Warm, real hay is the only saturated warm color.
- One orange action per screen.
- Sharp 2dp corners, lines instead of shadows.
- In the world, a machine you place appears first as a blueprint ghost and prints into a real steel machine when dropped. The yard visibly fills with your factory.

## Colors

**Strategy:** Committed. Prussian blue owns every surface; neutrals are blue-derived; one International-orange action. Gold, yellow and brown never appear in chrome: the hay owns warmth, and the currency is marked by a small hay-strand glyph instead of gold. (The strand glyph is a piece of hay, so it may be straw-colored.)

**Light or dark:** dark, fixed by the use scene (evening, in bed, lights low). The app does not switch with the system theme. There is no light variant.

- `ground` is the paper; `surface` is the wash for sheets and the pile-done card; `raised` is a pressed or disabled fill. Hierarchy comes from lines (`line`, `hairline`) before it comes from fills.
- `action` is the only interactive fill. Text on it is `on-action` ink (4.9:1), never white (white on this orange is 3.1:1 and fails).
- `text` on `ground` 13.4:1, on `surface` 10.9:1; `text-muted` on `ground` 7.9:1, `surface` 6.5:1, `raised` 5.0:1. All pass AA for body text.
- `action` itself on `ground` is 4.9:1: fine for fills and icons, but it's never used as a text color.
- `success` (8.6:1), `warning` (8.2:1) and `error` (6.7:1) are for short status lines, always beside an icon or word, never color alone.
- `glint` is pure white and only ever flashes on the needle (≤ 400ms). `needle` is the steel of the needle itself.
- Hay colors live in the shader (T13), not in these tokens: straw mid-tones around #B8873A–#E9C77A with deep blue-black shadows, lit from the upper left. The pile must never be tinted blue.

## Typography

All three families are OFL and were verified in `google/fonts` METADATA on 2026-10-27 (Big Shoulders Stencil: variable `opsz` 10–72, `wght` 100–900; Barlow Semi Condensed: 100–900 with `tnum`, checked in the font's GSUB table; B612 Mono: 400/700). Bundle the TTFs in the Godot project (`res://ui/fonts/`) so first launch and offline render correctly.

- **Big Shoulders Stencil (display):** a machine nameplate or feed-sack stencil, always clean: no distressed, grunge or worn-paint texture. Only at **28sp or larger**: the hay counter (44sp), "NEEDLE FOUND" on the pile-done card (64sp), screen titles (32sp), store art. The stencil gaps hurt legibility below that size.
- **Barlow Semi Condensed (UI, body and counts):** compact enough that five tool cells survive 200% font. Labels are 600, uppercase, +0.06em. **Every comma-grouped number** (prices, totals, hay from a pile) uses the `count` style: 600 weight with `tnum`, so columns line up and commas sit tight.
- **B612 Mono (rates and timers):** Airbus's cockpit face, used for whole figures with no thousands separator: "+38/s", "7h 59m", "2 / 2", dimension marks on plates. Not for comma-grouped numbers, because its full-width comma reads as "12, 480", and not for decimals, because its full-width point reads as "0. 9": a figure with a decimal point ("+0.9/s", "1.5 M") uses the `count` style (design D19).
- Scale: 64 / 44 / 32 / 17 / 15 / 13 / 12 sp. Adjacent levels differ by family or size, not weight alone. Respect the system font scale (read from Android, see Accessibility): at 200% the counter caps at 56sp; tray labels scale to at most 1.3× (13 → 17sp) so one-word labels like "DETECTOR" fit a 72dp cell (design D13).
- **Big numbers:** the HUD counter shows full digits up to 999,999, then abbreviates to three significant figures ("1.24M", "3.5B"). The Shop title, pile-done sheet and accessible names keep the full comma-grouped value.

## Layout

- **Yard (Play):** the 3D world fills the screen edge to edge under an orbit camera (fixed three-quarter camera only if the spike requires it). HUD on top: counter top-left with the rate under it, "PILE n" top-center, and top-right a column of 48dp controls: mute, then **SHOP** (ghost button, hay-strand glyph + label; reads "SHOP · 3" while machines wait on the shelf), then **recenter** (only when the camera is off its default view). Bottom: the tool tray, a five-cell "title block" 76dp tall. **No machine cards or plates float over the world**: machines exist only as objects in the yard. Tapping a placed machine shows a small anchored label (opaque `ground` plate, `line` border: name, rate in mono, Move, Shelve) above it.
- **HUD fades (contrast over hay, design D12):** top: `ground` at 90% from the status bar to 64dp below it, easing to 0% by 140dp. Bottom: the same mirrored, from the tray up 56dp. Acceptance: counter and rate ≥ 4.5:1 against the brightest hay frame, checked on a screenshot. No text shadow, outline or blur.
- **At font scale ≥ 1.5:** "PILE n" moves under the rate on the left; the top-right controls keep their column.
- **Gestures:** 1 finger on hay = rake with the selected tool; 1 finger starting on ground or inside the top fade band = orbit; double-tap-and-drag = zoom; 2 fingers = orbit + zoom. Recenter eases back over 320ms (instant under reduced motion). While placing, raking is off.
- **Navigation:** Yard → SHOP → Shop; Shop title bar has a back arrow (left) and a Settings gear (right, 48dp) beside the hay count. Every Operate screen has a back arrow. Android Back closes the top sheet or screen; on the Yard it does nothing (never quits).
- **Operate screens:** a strict single column of plates with 16dp side margins and 12dp between plates, like a parts catalogue. Title bar: stencil title left, the hay count (count style) right, a `line` rule under it.
- **Pile done:** a bottom sheet over a `scrim` at 78%, full width. Kicker "PILE n" (label, between `line` rules), stencil 64sp headline **"CLEARED"**, then a ruled table: Hay from this pile (count) · Needles 2 / 2 (mono) · Found by "you, conveyor" (body) · Time 14m 20s (mono). Table labels in Barlow (body). Then "n machines to place" in `text-muted`, tappable (opens the Shop at YOUR MACHINES), and one full-width orange "NEXT PILE · n" button (52dp). The interstitial check happens only on that tap (eng D7); while it runs (≤ 3 s) the button reads "Loading…". "NEEDLE FOUND" is reserved for the in-world moment and store art (design D9).
- Spacing: 4dp base; 16dp screen margins; 48dp minimum touch targets; the tray never changes height.
- Low-end screen: everything above fits on a 720×1600 phone at 100% and 200% font.

## Elevation & Depth

Depth is drawn, not shadowed. A plate is a 1dp `line` border on `ground`; a sheet is `surface` with a 1dp `text` top rule; a pressed state is `raised`. No drop shadows on UI chrome, no blur panels, no glow. The only real depth on screen is the hay's own shader lighting.

## Shapes

`rounded.sm` (2dp) on every button, plate, cell and sheet; `full` only for the mute focus ring and progress dots. No pill buttons. A card never sits inside a card; inside a plate, sections are separated by hairlines.

## Components

- **Tool cell (tray):** icon (28dp line drawing) over an uppercase label. Default: `text-muted`, icon at 75%. Selected: `text` label, icon 100%, a 2dp `text` outline inset 6dp. Pressed: `raised` fill. Locked tool: icon at 35% plus a small lock and the price in the count style. Focus-visible: 2dp `glint` outline offset 3dp.
- **Hand tools vs machines (the progression rule, Shop and tray art):** rake, pitchfork, magnet, blower and detector are drawn as **photogram silhouettes**: thick soft strokes with a slight blur, as if laid on sun paper. The conveyor and every future machine are drawn as **blueprints**: thin crisp strokes, dimension lines, a spec row in B612 Mono. Drawn as SVG icons imported into Godot.
- **Machine in the world:** a 3D model (restyled CC0 or the custom conveyor) in `machine-paint` steel with one `action` orange safety stripe; belts animate at the machine's real dig rate. Selected: a 2dp `text` outline ring on the ground around its footprint, plus the anchored label. Shelved machines live in the Shop under "Your machines" with a Place button.
- **Shop:** three sections, each a Barlow label over a `line` rule: **YOUR MACHINES** (only when the shelf is not empty; listed first; plate button "Place"), **TOOLS**, **MACHINES**. Above them, when an ad is ready, the optional ghost plate "Double hay · 10 min" + "Watch a video". Tapping a locked tray tool opens the Shop scrolled to it.
- **Shop plate:** 96dp art cell (photogram or blueprint) | name, spec row (mono), and either "Owned · in hand" (`success`) or price (count style) + Buy. Buy is a ghost button (design D18): affordable = 1dp `text` border + `text` label; short of hay = `raised` fill + `text-muted` label (still announces the price) with "n more hay" in `text-muted` under it. The Shop's single orange is the first YOUR MACHINES "Place"; with an empty shelf the Shop has no orange. Buying a machine spends the hay, puts it on the shelf, closes the Shop and starts placement (see In-world).
- **Buttons:** primary = orange fill, ink text, uppercase 600, 2dp corners, min 44dp tall (52dp on the pile-done card); hover/pressed as tokens; disabled as tokens. Ghost = 1dp `line` border, `text` label. Never more than one primary per screen.
- **Placement bar:** replaces the tray while placing, same 76dp height: machine name (label) | **PLACE** (`button-primary`, disabled while the ghost is invalid) | Cancel (ghost). Cancel returns the machine to the shelf; no hay is lost.
- **Notice line:** one line, `notice` plate 8dp above the tray, icon + body text, 4 s, no buttons, never over the tray or the finger, announced to accessibility services. Copy: "Restored your last save" · "Couldn't load your save, starting fresh" · "Storage is full, progress isn't saving" (`warning` icon; stays until a save succeeds) · first ghost only: "Drag to move · ⟳ to turn · PLACE when the lines are white".
- **Toggle (Settings):** a 44×28dp box, 2dp corners. Off: 1dp `line` border, "OFF" in `text-muted`. On: `text` fill, ink "ON". The whole 56dp row is the target. No pill, no orange.
- **First-run cues (design D8):** the first time anything is affordable, the SHOP button's 2dp `text` outline pulses twice (600ms each; static under reduced motion) until the first Shop visit. The ghost-finger stroke hint shows on pile 1 until the first rake.
- **Rewarded offers (optional, never block play):** 2× hay in the Shop (above); while active the HUD rate reads "+38/s · 2× 7:59" (mono). Detector ping: a 48dp ghost "PING" in the bottom fade above the DETECTOR cell, only while the detector is selected and an ad is ready; hidden on no fill, never a dead button.
- **Mute:** shows the sound-on speaker by default (sound on is the wind-down default); the crossed speaker only when muted.
- **Hay counter:** stencil 44sp in `text` with the hay-strand glyph, and the rate under it in B612 Mono `text-muted`. It ticks up after the needle moment, never during it.
- **While you were away:** a sheet like Pile done: stencil headline "WHILE YOU WERE AWAY", a ruled table (time away, hay, needles found by machines, "capped" note in `text-muted` if the daily cap hit), one orange "Collect" button; the 2× offline rewarded offer is a ghost button beside it, never the primary. Skipped entirely when 0 hay (eng).
- **Update required / Unsupported device:** a full `ground` screen, stencil title, one paragraph of plain copy. Update: one orange "Update" button (Play link). Unsupported: the reason in one line and a "Close" ghost button. No hay.
- **Settings:** 56dp plate rows: Sound · Haptics · Reduce motion (defaults to the system setting) · Privacy options (reopens the UMP form) · Privacy policy (link) · Licenses (from `docs/assets.md`) · Export tester log (closed-test builds only); then the version in mono `text-muted`.
- **Boot and loading:** boot splash is plain `ground` with the stencil wordmark (no engine logo) → UMP consent form on first launch where required (design D6) → "Raking the yard…" (body) over a hairline progress bar while the pile generates and shaders warm up → the yard. The same line covers a next-pile generation over 300 ms. Never a spinner.
- **Empty, loading and error states:** "More soon" plate when everything is owned; YOUR MACHINES hidden when the shelf is empty; "Counting your hay…" with a hairline bar (input blocked) for a slow offline credit; ad no-fill shows "No video right now" as a `text-muted` line in place of the ghost button. On return, the away sheet comes first; if the pile finished offline, the pile-done sheet follows on the same scrim.

## In-world (3D yard)

- **Placement flow (design D4, founder mock tile 2):** Buy (or "Place" on a shelved machine) → the Shop closes → the ghost appears at the nearest valid spot at the pile's edge, facing its centre → one finger on the ghost drags it (lifting never drops it) → ⟳ turns it 45° → **PLACE** on the placement bar prints it. Backgrounding the app mid-placement returns the machine to the shelf. If no valid spot is on screen, the ghost stays at its last valid spot and PLACE is disabled.
- **Placement ghost (the blueprint):** while placing, the machine renders as a Prussian blueprint: `ghost-fill` at 35% opacity with `ghost-line` edges and dimension ticks on the ground showing its reach channel. Valid spot: lines solid. Invalid (on hay, overlapping, out of bounds): lines turn `ghost-invalid` and the drop is disabled. A rotate control (48dp) sits beside the ghost in addition to two-finger twist.
- **Printing:** on drop, the ghost "prints" into the real machine over 400ms: the blueprint lines fade as the steel material fades in from the base up, with a soft mechanical clunk. Under reduced motion it swaps instantly. This is the second authored moment, after the needle glint.
- **Scale ("the pile will be bigggggger", founder):** the pile is a landmark, not an object. It towers over every machine (a 4 m conveyor is a sliver at its foot), the default camera shows only part of one flank, and seeing the whole pile takes full zoom-out. Each new pile is bigger than the last. Never frame a pile so it fits on one screen at default zoom, in the game, in mocks or in store art.
- **Digging shape:** the pile is a height map, so all digging opens it **from the top**: the rake leaves dips and furrows, the conveyor cuts a straight trench toward the centre that deepens as it advances. Never caves, tunnels or overhanging hay, in the game, in mocks or in store art (eng architecture; design D8).
- **Hay:** photographic straw look from the shader (warm mid-tones, blue-black shadows, lit from the upper left). The only warm material in the world besides the orange safety stripe; the hay is never tinted blue.
- **Yard:** muted, dark, unsaturated ground (`yard-ground`), dusk lighting with a cool blue ambient and one warm key light from the upper left. Realistic, weathered props at the yard's edge only (wooden fence, a shed exterior, a wheelbarrow, crates), restyled CC0 in the same desaturated materials; pack colors are never used as shipped. No sky gradient, no sun disc, no cartoon props, no barn interior, nothing between the camera and the pile.
- **Needle:** thin steel (`needle`) with the single white `glint` flash when found.
- **Asset licenses:** every CC0 or custom asset is listed in `docs/assets.md` with source and license.

## Accessibility

- 48dp minimum targets everywhere; whole rows are targets in Operate screens.
- A small Kotlin Android plugin reads `Configuration.fontScale` and `Settings.Global.ANIMATOR_DURATION_SCALE` at start and on resume (design D14). The UI theme scales from fontScale (Godot doesn't do it on its own; verify on the pinned version in G1). Reduce motion defaults to on when the animator scale is 0, and the Settings toggle overrides it.
- Reduced motion: glint → 200ms fade, print → instant swap, counter jumps, belts and particles stop, SHOP pulse becomes a static outline, recenter is instant.
- Screen readers: menus, sheets and buttons get accessible names if the pinned Godot version supports them on Android (checked in G1). The 3D yard itself is not screen-reader accessible, and the store listing says so plainly.
- Contrast: every text token passes AA on its surface (see Colors); HUD text over the world relies on the measured fades (Layout).
- Check every screen at 720×1600 at 100% and 200% font.

## Store listing (Persuade, design D10)

- **Icon (adaptive, no text):** one steel (`needle`) needle on a diagonal across a `ground` field, the `glint` at its eye, a thin `action` safety stripe along the background's lower edge. No hay, no gold. Must read at 48px.
- **Screenshots (5, 1080×1920, real captures):** a `ground` band at the top with a 44sp stencil caption: "DIG BY HAND." (rake furrows) · "FIND THE NEEDLE." (glint) · "DRAW THE MACHINE." (blueprint ghost) · "WATCH IT DIG." (steel conveyor in its trench) · "EVERY PILE BIGGER." (zoomed out, the pile still overflows the frame).
- **Feature graphic (1024×500):** a pile flank with a conveyor trench, the stencil wordmark on a left `ground` panel.
- In every frame: the pile overflows the frame, trenches only (no tunnels), photographic hay, no mascots, no gold.

## Do's and Don'ts

- Do keep every warm color inside the hay shader.
- Do draw hand tools as photograms and machines as blueprints. A new machine always gets a blueprint plate.
- Do use the `count` style (Barlow + tnum) for any comma-grouped number and B612 Mono for rates and timers.
- Do keep one orange action per screen, with ink text on it.
- Do check every new screen at 720×1600 and 200% font.
- Don't use gold, coin piles, treasure chests, sparkle bursts or confetti. This is the category's default and it reads like a kids' game.
- Don't use cartoon hay, mascots, faces or a red barn, in the app or in store art.
- Don't use the stencil below 28sp, and don't set white text on orange.
- Don't add drop shadows, glow, gradients or rounded pills to chrome.
- Don't float machine cards, plates or counters over the world: automation is physical (founder rule, "not cookie clicker").
- Don't let an ad or a label cover the tool tray or the finger.
- Don't say "sell": dug hay is the currency the moment it leaves the pile (design D16).

## Motion

- **Approach:** intentional and slow. Machines move at their real rate; nothing bounces or overshoots.
- **Easing:** enter ease-out, exit ease-in, move ease-in-out.
- **Duration:** micro 80ms (cell press), short 200ms (sheet fade), medium 320ms (sheet slide), long 600ms (counter tick after a find).
- **Authored moments (two):** the needle found, and a placed machine printing from blueprint into steel (see In-world). Needle found: The pile and all chrome hold still for 250ms; a single white glint travels the needle (400ms); the clink and haptic land at the glint's peak; then the counter ticks up (600ms). Under reduced motion the glint becomes a 200ms fade and the counter jumps.
- Machine belt dashes and particles stop under reduced motion; the rate number keeps updating.

## Decisions Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-10-27 | Initial design system created: "Cyanotype to Blueprint" | /design-consultation. Founder's anchor: "from a rake to a factory". Research showed every competitor is sunny cartoon gold. Synthesis of my draft (deep blue for bedtime, Barlow UI, authored needle moment) and an independent Claude subagent's (cyanotype concept, photogram-to-blueprint tools, International orange, Big Shoulders Stencil). |
| 2026-10-27 | Dark only, no light theme | Use scene: evening, in bed, lights low. |
| 2026-10-27 | No gold in chrome; hay-strand glyph marks the currency | Lets the warm hay be the only warm thing; separates from the gold clones; reads adult. |
| 2026-10-27 | Comma-grouped counts in Barlow Semi Condensed `tnum`; B612 Mono only for rates and timers | The preview showed B612 Mono's full-width comma rendering "12,480" as "12, 480" (D6). |
| 2026-10-27 | Ink text on orange, never white | White on #FF5A1F is 3.1:1 (fails AA); ink #122640 is 4.9:1. |
| 2026-10-27 | 3D yard with physically placed machines; machine plates removed from the Play HUD | Founder: "automations need to be physically placed", "not cookie clicker", "find the needle style"; design D7 real 3D, CEO re-review D1 Godot 4 |
| 2026-10-27 | Placement ghost is the blueprint; dropping prints it into steel | Puts "from a rake to a factory" into the world itself |
| 2026-10-27 | Bundle fonts as .ttf in the Godot project (`res://ui/fonts/`), not Android res/font | Engine changed to Godot (CEO re-review D1) |
| 2026-10-27 | Revisions from the ChatGPT mock grid: piles overflow the screen; digging is top-down trenches only (no tunnels/overhangs); clean stencil; Barlow for table labels; mute icon shows sound on; realistic edge-of-yard props allowed | Founder-supplied mock (design-system-20261027/chatgpt-mock-grid-1.png); design D8 "A) Trenches from the top" |
| 2026-10-27 | Pile scale is a landmark: default view shows one flank; each pile bigger | Founder: "the pile will be bigggggger" |
| 2026-10-27 | /plan-design-review (D3–D17): SHOP button + Settings gear in Shop; mock's PLACE-bar placement flow; Shop sections + "SHOP · n"; consent form first; state table + notice line; one-shot first-run cues; "PILE n CLEARED"; store art spec; Settings rows + square toggle; measured HUD fades; big-number abbreviation + tray label cap; system font/motion via Kotlin helper; one-handed orbit band + recenter; no Sell step; contextual rewarded offers | Founder answers in the design plan review, each asked separately |
| 2026-10-27 | Shop Buy buttons are ghost; the one orange is the shelf's first Place (D18) | "One orange per screen" conflicted with orange Buy in a list; founder's design-review mock outlines Buy |
| 2026-10-29 | Figures with a decimal point use `count` (Barlow + tnum), not B612 Mono (D19) | G9a screenshots: B612 Mono's full-width point rendered "+0.9/s" as "+0. 9/s" (same issue as the comma). Founder chose this over per-minute rates. Shop spec rows use `count` throughout so the column is one style |

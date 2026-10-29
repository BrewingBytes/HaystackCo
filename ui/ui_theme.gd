class_name UiTheme
extends RefCounted
## DESIGN.md tokens for the 2D UI: colors, the three bundled families (Big Shoulders Stencil,
## Barlow Semi Condensed, B612 Mono), the type scale with the system font scale applied, and the
## plate and button styles. The canvas is 720 wide, so 1dp is 2 canvas units.

const DP := 2.0

const GROUND := Color("#122640")
const SURFACE := Color("#1A3558")
const RAISED := Color("#23466F")
const TEXT := Color("#EEF1EC")
const TEXT_MUTED := Color("#A9BDD6")
const ACTION := Color("#FF5A1F")
const ACTION_PRESSED := Color("#E54A12")
const ACTION_HOVER := Color("#FF7140")
const ON_ACTION := Color("#122640")
const GLINT := Color("#FFFFFF")
const LINE := Color("#A9B5BF")
const HAIRLINE := Color("#3A5272")
const SUCCESS := Color("#7FD49B")
const WARNING := Color("#F2B33D")
const ERROR := Color("#FF8A78")
const SCRIM := Color("#0B1829")
const STRAW := Color("#D9B25E")  # the hay-strand glyph only: a piece of hay may be straw-colored

enum Style { DISPLAY, DISPLAY_LARGE, TITLE, BODY, LABEL, COUNT, MONO }

const _SIZES := {
	Style.DISPLAY: 44, Style.DISPLAY_LARGE: 64, Style.TITLE: 32,
	Style.BODY: 17, Style.LABEL: 13, Style.COUNT: 15, Style.MONO: 12,
}

## Font scale override for desktop checks (`--font-scale=2`); null = the system's.
static var font_scale_override: Variant = null
static var _fonts := {}


static func font_scale() -> float:
	if font_scale_override != null:
		return font_scale_override
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--font-scale="):
			return arg.substr(13).to_float()
	return A11y.font_scale()


## Canvas size of `style` at the system font scale, capped at `max_scale` (the counter caps at
## 56sp, tray labels at 1.3×).
static func size(style: Style, max_scale := 2.0) -> int:
	return int(round(_SIZES[style] * minf(font_scale(), max_scale) * DP))


static func font(style: Style) -> Font:
	if _fonts.has(style):
		return _fonts[style]
	var variation := FontVariation.new()
	var ts := TextServerManager.get_primary_interface()
	match style:
		Style.DISPLAY, Style.DISPLAY_LARGE, Style.TITLE:
			variation.base_font = load("res://ui/fonts/BigShouldersStencil.ttf")
			variation.variation_opentype = {
				ts.name_to_tag("wght"): 700 if style == Style.TITLE else 800,
				ts.name_to_tag("opsz"): _SIZES[style],
			}
		Style.BODY:
			variation.base_font = load("res://ui/fonts/BarlowSemiCondensed-Regular.ttf")
		Style.LABEL:
			variation.base_font = load("res://ui/fonts/BarlowSemiCondensed-SemiBold.ttf")
			variation.spacing_glyph = int(round(0.06 * _SIZES[style] * DP))  # +0.06em
		Style.COUNT:
			variation.base_font = load("res://ui/fonts/BarlowSemiCondensed-SemiBold.ttf")
			variation.opentype_features = {ts.name_to_tag("tnum"): 1}
		Style.MONO:
			variation.base_font = load("res://ui/fonts/B612Mono-Regular.ttf")
	_fonts[style] = variation
	return variation


static func label(style: Style, text := "", color := TEXT, max_scale := 2.0) -> Label:
	var l := Label.new()
	l.text = text.to_upper() if style == Style.LABEL else text
	style_label(l, style, color, max_scale)
	return l


static func style_label(l: Label, style: Style, color := TEXT, max_scale := 2.0) -> void:
	l.add_theme_font_override("font", font(style))
	l.add_theme_font_size_override("font_size", size(style, max_scale))
	l.add_theme_color_override("font_color", color)
	if style in [Style.DISPLAY, Style.DISPLAY_LARGE, Style.TITLE]:
		l.add_theme_constant_override("line_spacing", 0)


## A flat box: `fill` with a `border_dp` border in `border`, 2dp corners (rounded.sm).
static func flat(fill: Color, border := Color.TRANSPARENT, border_dp := 0.0, pad_x_dp := 16.0, pad_y_dp := 8.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(int(border_dp * DP))
	box.set_corner_radius_all(int(2 * DP))
	box.content_margin_left = pad_x_dp * DP
	box.content_margin_right = pad_x_dp * DP
	box.content_margin_top = pad_y_dp * DP
	box.content_margin_bottom = pad_y_dp * DP
	return box


## The `plate` component: `ground`, 1dp `line` border.
static func plate(pad_dp := 12.0) -> StyleBoxFlat:
	return flat(GROUND, LINE, 1, pad_dp, pad_dp)


enum Kind { PRIMARY, GHOST }


## DESIGN.md buttons: primary = orange fill with ink text; ghost = 1dp `line` border, `text`
## label. Uppercase label style, 2dp corners, at least 48dp tall.
static func button(text: String, kind: Kind, accessible := "") -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.accessibility_name = accessible if not accessible.is_empty() else text
	b.custom_minimum_size = Vector2(0, 48 * DP)
	b.add_theme_font_override("font", font(Style.LABEL))
	b.add_theme_font_size_override("font_size", size(Style.LABEL, 1.5))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	set_kind(b, kind)
	return b


static func set_kind(b: Button, kind: Kind) -> void:
	if kind == Kind.PRIMARY:
		b.add_theme_stylebox_override("normal", flat(ACTION))
		b.add_theme_stylebox_override("hover", flat(ACTION_HOVER))
		b.add_theme_stylebox_override("pressed", flat(ACTION_PRESSED))
		b.add_theme_stylebox_override("disabled", flat(RAISED))
		_font_colors(b, ON_ACTION)
	else:
		b.add_theme_stylebox_override("normal", flat(GROUND, LINE, 1))
		b.add_theme_stylebox_override("hover", flat(RAISED, LINE, 1))
		b.add_theme_stylebox_override("pressed", flat(RAISED, TEXT, 1))
		b.add_theme_stylebox_override("disabled", flat(RAISED, RAISED, 1))
		_font_colors(b, TEXT)
	b.add_theme_color_override("font_disabled_color", TEXT_MUTED)


static func _font_colors(b: Button, color: Color) -> void:
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(state, color)


## A 1dp rule in `color`, for section heads and title bars.
static func rule(color := LINE) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(0, DP)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func icon(name: String) -> Texture2D:
	return load("res://ui/icons/%s.svg" % name)


# --- Numbers (DESIGN.md "Big numbers", "count" and "mono" styles) --------------------------

## "12,480": comma-grouped, for the `count` style and accessible names.
static func grouped(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(-3)
	return ("-" if n < 0 else "") + digits + out


## The HUD counter: full digits up to 999,999, then three significant figures ("1.24M", "3.5B").
static func abbreviated(n: int) -> String:
	if n < 1_000_000:
		return grouped(n)
	var units := ["M", "B", "T", "Q"]
	var value := n / 1_000_000.0
	var unit := 0
	while value >= 999.5 and unit < units.size() - 1:
		value /= 1000.0
		unit += 1
	var decimals := 2 if value < 9.995 else (1 if value < 99.95 else 0)
	var text := String.num(value, decimals)
	if text.contains("."):
		text = text.rstrip("0").rstrip(".")
	return text + units[unit]


## The style for a figure: B612 Mono for whole numbers and timers; `count` (Barlow + tnum)
## once it has a decimal point, which B612 Mono sets a full cell wide ("0. 9", design D19).
static func figure_style(text: String) -> Style:
	return Style.COUNT if text.contains(".") else Style.MONO


## Restyles `l` for its current text (figure_style), keeping `color` and the size cap.
static func style_figure(l: Label, color := TEXT_MUTED, max_scale := 2.0) -> void:
	var style := figure_style(l.text)
	if l.get_theme_font("font") != font(style):  # the HUD calls this every frame
		style_label(l, style, color, max_scale)


## "1.5", "3": one decimal, none when it's whole.
static func decimal(value: float) -> String:
	return String.num(snappedf(value, 0.1), 1).trim_suffix(".0")


## A rate: "+0.9/s", "+38/s" (shown with figure_style).
static func rate(hay_per_s: float) -> String:
	if hay_per_s < 9.95:
		return "+%s/s" % decimal(hay_per_s)
	return "+%d/s" % roundi(hay_per_s)


## A timer (B612 Mono): "7:59".
static func clock(ms: int) -> String:
	var s := ceili(ms / 1000.0)
	return "%d:%02d" % [s / 60, s % 60]

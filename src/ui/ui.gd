class_name UI
extends RefCounted
## Shared UI helpers: fonts, palette, 9-slice panels, labels, buttons.

const COL := {
	"ink": Color8(12, 10, 20), "bg": Color8(22, 20, 33), "panel": Color8(34, 31, 48),
	"line": Color8(66, 62, 86), "dim": Color8(120, 116, 142), "text": Color8(226, 222, 236),
	"white": Color8(248, 246, 252), "cyan": Color8(96, 212, 236), "pink": Color8(255, 86, 170),
	"yellow": Color8(255, 204, 102), "orange": Color8(232, 146, 60), "red": Color8(230, 62, 70),
	"green": Color8(140, 214, 96), "lime": Color8(190, 240, 100), "purple": Color8(170, 100, 230),
	"rust": Color8(170, 96, 52), "blue": Color8(90, 150, 230),
}
const CAT_COL := {
	"civil": Color8(96, 212, 236), "industry": Color8(232, 146, 60), "hostile": Color8(230, 62, 70),
	"military": Color8(140, 190, 90), "special": Color8(170, 100, 230), "train": Color8(255, 204, 102),
	"action": Color8(255, 86, 170),
}
const CAT_NAME := {"civil": "민간", "industry": "산업", "hostile": "위험", "military": "군사",
	"special": "특수", "train": "열차", "action": "작전"}

static var _fonts := {}
static var _tex := {}


static func font(size: int = 11) -> Font:
	var key := size
	if _fonts.has(key):
		return _fonts[key]
	var path := "res://assets/fonts/Galmuri11.ttf"
	match size:
		7:
			path = "res://assets/fonts/Galmuri7.ttf"
		9:
			path = "res://assets/fonts/Galmuri9.ttf"
		12:
			path = "res://assets/fonts/Galmuri11-Bold.ttf"
	var f: FontFile = load(path)
	_fonts[key] = f
	return f


## Galmuri fonts render crisp at these pixel sizes
static func px(size: int) -> int:
	match size:
		7:
			return 8
		9:
			return 10
		12:
			return 12
	return 12


static func tex(path: String) -> Texture2D:
	if _tex.has(path):
		return _tex[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	_tex[path] = t
	return t


static func style(path: String, margin := 4, content := 4) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex(path)
	sb.texture_margin_left = margin
	sb.texture_margin_right = margin
	sb.texture_margin_top = margin
	sb.texture_margin_bottom = margin
	sb.content_margin_left = content
	sb.content_margin_right = content
	sb.content_margin_top = content
	sb.content_margin_bottom = content
	return sb


static func flat(bg: Color, border := Color(0, 0, 0, 0), bw := 1, content := 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw if border.a > 0 else 0)
	sb.set_content_margin_all(content)
	sb.anti_aliasing = false
	return sb


static func panel(dark := false) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style("res://assets/sprites/ui/panel_dark.png" if dark else "res://assets/sprites/ui/panel.png", 4, 6))
	return p


static func label(text: String, size := 11, color: Color = COL.text, shadow := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(size))
	l.add_theme_font_size_override("font_size", px(size))
	l.add_theme_color_override("font_color", color)
	if shadow:
		l.add_theme_color_override("font_shadow_color", Color(0.02, 0.02, 0.05, 0.9))
		l.add_theme_constant_override("shadow_offset_x", 1)
		l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func rich(size := 11) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_override("normal_font", font(size))
	r.add_theme_font_override("bold_font", font(12))
	r.add_theme_font_size_override("normal_font_size", px(size))
	r.add_theme_font_size_override("bold_font_size", 12)
	r.add_theme_color_override("default_color", COL.text)
	r.add_theme_color_override("font_shadow_color", Color(0.02, 0.02, 0.05, 0.9))
	r.add_theme_constant_override("shadow_offset_x", 1)
	r.add_theme_constant_override("shadow_offset_y", 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func button(text: String, size := 11, hot := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font(size))
	b.add_theme_font_size_override("font_size", px(size))
	b.add_theme_color_override("font_color", COL.text)
	b.add_theme_color_override("font_hover_color", COL.white)
	b.add_theme_color_override("font_pressed_color", COL.yellow)
	b.add_theme_color_override("font_disabled_color", COL.dim)
	b.add_theme_stylebox_override("normal", style("res://assets/sprites/ui/button_hot.png" if hot else "res://assets/sprites/ui/button.png", 3, 5))
	b.add_theme_stylebox_override("hover", style("res://assets/sprites/ui/button_hover.png", 3, 5))
	b.add_theme_stylebox_override("pressed", style("res://assets/sprites/ui/button_hot.png", 3, 5))
	b.add_theme_stylebox_override("disabled", style("res://assets/sprites/ui/button_off.png", 3, 5))
	b.mouse_entered.connect(func(): Audio.sfx("hover", -14.0))
	b.pressed.connect(func(): Audio.sfx("click", -6.0))
	return b


static func fac_tex(t: String) -> Texture2D:
	return tex("res://assets/sprites/fac/%s.png" % t)


static func card_title(id: String) -> String:
	if id.begins_with("car:"):
		return Defs.CARS[id.substr(4)].name
	if id.begins_with("mod:"):
		return Defs.MODULES[id.substr(4)].name
	return Defs.FACILITIES[id].name


static func card_cat(id: String) -> String:
	if id.begins_with("car:") or id.begins_with("mod:"):
		return "train"
	if id == "purge":
		return "action"
	return Defs.FACILITIES[id].cat


static func card_icon(id: String) -> Texture2D:
	if id.begins_with("car:"):
		return tex("res://assets/sprites/train/%s.png" % id.substr(4))
	if id.begins_with("mod:"):
		return mod_icon(id.substr(4))
	if id == "purge":
		return tex("res://assets/sprites/fac/rubble.png")
	return fac_tex(id)


static func mod_icon(m: String) -> Texture2D:
	var name: String = {"ap": "ammo"}.get(m, m)
	var t := tex("res://assets/sprites/icon/%s.png" % name)
	if t == null:
		t = tex("res://assets/sprites/icon/wrench.png")
	return t


static func relic_icon(r: String) -> Texture2D:
	return tex("res://assets/sprites/icon/%s.png" % r)


## short reward description used on depot / reward cards
static func reward_info(id: String) -> Dictionary:
	var parts := id.split(":")
	var kind := parts[0]
	var arg := parts[1] if parts.size() > 1 else ""
	match kind:
		"car":
			return {"title": Defs.CARS[arg].name, "desc": Defs.CARS[arg].desc, "icon": tex("res://assets/sprites/train/%s.png" % arg), "tag": "차량"}
		"mod":
			return {"title": Defs.MODULES[arg].name, "desc": Defs.MODULES[arg].desc, "icon": mod_icon(arg), "tag": "개조"}
		"relic":
			return {"title": Defs.RELICS[arg].name, "desc": Defs.RELICS[arg].desc, "icon": relic_icon(arg), "tag": "유물"}
		"repair":
			return {"title": "긴급 수리", "desc": "선체 %s%% 수리." % arg, "icon": tex("res://assets/sprites/icon/patch.png"), "tag": "수리"}
		"supplies":
			return {"title": "보급 상자", "desc": "보급품 +%s." % arg, "icon": tex("res://assets/sprites/icon/crate.png"), "tag": "보급"}
		"cards":
			var ids := arg.split(",")
			return {"title": "카드 2장", "desc": "%s, %s" % [card_title(ids[0]), card_title(ids[1])], "icon": fac_tex(ids[0]), "tag": "카드"}
		"card":
			return {"title": card_title(arg), "desc": "카드 1장: " + card_title(arg), "icon": card_icon(arg), "tag": "카드"}
	return {"title": id, "desc": "", "icon": null, "tag": ""}


static func punch(node: CanvasItem, amount := 0.25, time := 0.25) -> void:
	if node == null or not is_instance_valid(node):
		return
	var tw := node.create_tween()
	node.scale = Vector2.ONE * (1.0 + amount)
	tw.tween_property(node, "scale", Vector2.ONE, time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

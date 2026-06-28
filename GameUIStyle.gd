class_name GameUIStyle
extends RefCounted

const COLOR_PANEL := Color(0.025, 0.035, 0.07, 0.86)
const COLOR_PANEL_BORDER := Color(0.16, 0.78, 0.9, 0.45)
const COLOR_BUTTON := Color(0.045, 0.075, 0.13, 0.94)
const COLOR_BUTTON_HOVER := Color(0.075, 0.16, 0.24, 0.98)
const COLOR_BUTTON_PRESSED := Color(0.025, 0.05, 0.09, 1.0)
const COLOR_BUTTON_DISABLED := Color(0.04, 0.045, 0.055, 0.72)
const COLOR_ACCENT := Color(0.25, 0.92, 1.0, 0.9)
const COLOR_ACCENT_SOFT := Color(0.18, 0.58, 0.72, 0.55)
const COLOR_GOLD := Color(1.0, 0.78, 0.24, 0.96)
const COLOR_GLASS := Color(0.5, 0.95, 1.0, 0.08)
const COLOR_TEXT := Color(0.94, 0.98, 1.0, 1.0)
const COLOR_TEXT_DIM := Color(0.62, 0.72, 0.82, 1.0)
const BUTTON_TEXTURE_MARGIN_LEFT := 48.0
const BUTTON_TEXTURE_MARGIN_TOP := 28.0
const BUTTON_TEXTURE_MARGIN_RIGHT := 48.0
const BUTTON_TEXTURE_MARGIN_BOTTOM := 28.0

static func make_panel_style(alpha: float = 0.86) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(COLOR_PANEL.r, COLOR_PANEL.g, COLOR_PANEL.b, alpha)
	style.border_color = COLOR_PANEL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0, 0, 0, 0.38)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 2)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style

static func make_button_style(state: String = "normal") -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	match state:
		"hover":
			style.bg_color = Color(COLOR_BUTTON_HOVER.r, COLOR_BUTTON_HOVER.g, COLOR_BUTTON_HOVER.b, 0.99)
			style.border_color = COLOR_ACCENT
			style.shadow_color = Color(0.1, 0.75, 0.95, 0.34)
			style.shadow_size = 14
		"pressed":
			style.bg_color = COLOR_BUTTON_PRESSED
			style.border_color = COLOR_GOLD
			style.shadow_color = Color(1.0, 0.65, 0.16, 0.26)
			style.shadow_size = 7
			style.content_margin_top = 3
		"disabled":
			style.bg_color = COLOR_BUTTON_DISABLED
			style.border_color = Color(0.25, 0.3, 0.35, 0.38)
		_:
			style.bg_color = COLOR_BUTTON
			style.border_color = COLOR_ACCENT_SOFT
			style.shadow_color = Color(0, 0, 0, 0.24)
			style.shadow_size = 6
	style.set_border_width_all(3)
	style.set_corner_radius_all(7)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = maxf(style.content_margin_top, 2)
	style.content_margin_bottom = 2
	return style

static func apply_panel(panel: Panel, alpha: float = 0.86) -> void:
	panel.add_theme_stylebox_override("panel", make_panel_style(alpha))

static func apply_pressed_button_panel(panel: Panel) -> void:
	var style := _make_panel_texture_style("pressed")
	if style:
		panel.add_theme_stylebox_override("panel", style)
	else:
		panel.add_theme_stylebox_override("panel", make_panel_style(0.9))

static func apply_button(button: Button, font_size: int = 24) -> void:
	button.focus_mode = Control.FOCUS_NONE
	var use_texture := _should_use_texture_for_size(button.size)
	button.add_theme_stylebox_override("normal", _make_button_visual_style("normal", use_texture))
	button.add_theme_stylebox_override("hover", _make_button_visual_style("hover", use_texture))
	button.add_theme_stylebox_override("pressed", _make_button_visual_style("pressed", use_texture))
	button.add_theme_stylebox_override("disabled", _make_button_visual_style("disabled", use_texture))
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", COLOR_GOLD)
	button.add_theme_color_override("font_disabled_color", COLOR_TEXT_DIM)
	button.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	button.add_theme_constant_override("outline_size", 3)
	button.add_theme_font_size_override("font_size", font_size)

static func apply_texture_button(button: TextureButton, font_size: int = 24, force_simple: bool = false) -> void:
	button.texture_normal = null
	button.texture_hover = null
	button.texture_pressed = null
	button.texture_disabled = null
	button.ignore_texture_size = true
	button.focus_mode = Control.FOCUS_NONE
	button.modulate = Color.WHITE
	button.clip_contents = true
	button.set_meta("use_button_texture", false if force_simple else _should_use_texture_for_size(button.size))

	var skin := button.get_node_or_null("DreamButtonSkin") as Panel
	if skin == null:
		skin = Panel.new()
		skin.name = "DreamButtonSkin"
		skin.set_anchors_preset(Control.PRESET_FULL_RECT)
		skin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(skin)
		button.move_child(skin, 0)
	_ensure_texture_button_decoration(button)
	_apply_texture_button_state(button, skin, "normal")

	var label := button.get_node_or_null("Label") as Label
	if label:
		style_button_label(label, font_size)
		button.move_child(label, button.get_child_count() - 1)

	button.mouse_entered.connect(func() -> void:
		if not button.disabled:
			_apply_texture_button_state(button, skin, "hover")
	)
	button.mouse_exited.connect(func() -> void:
		_apply_texture_button_state(button, skin, "normal" if not button.disabled else "disabled")
	)
	button.button_down.connect(func() -> void:
		if not button.disabled:
			_apply_texture_button_state(button, skin, "pressed")
	)
	button.button_up.connect(func() -> void:
		_apply_texture_button_state(button, skin, "hover" if not button.disabled else "disabled")
	)

static func style_button_label(label: Label, font_size: int = 24) -> void:
	label.anchor_left = 0.0
	label.anchor_top = 0.0
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	label.offset_left = 0.0
	label.offset_top = 4.0
	label.offset_right = 0.0
	label.offset_bottom = 4.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.self_modulate = Color.WHITE
	label.add_theme_color_override("font_color", COLOR_TEXT)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.86))
	label.add_theme_constant_override("outline_size", 2 if font_size >= 34 else 3)
	label.add_theme_font_size_override("font_size", font_size)
	var settings := label.label_settings
	if settings == null:
		settings = LabelSettings.new()
	label.label_settings = settings
	settings.font_size = font_size
	settings.font_color = COLOR_TEXT
	settings.outline_color = Color(0, 0, 0, 0.86)
	settings.outline_size = 2 if font_size >= 34 else 3

static func set_texture_button_disabled(button: TextureButton, disabled: bool) -> void:
	button.disabled = disabled
	var skin := button.get_node_or_null("DreamButtonSkin") as Panel
	if skin:
		_apply_texture_button_state(button, skin, "disabled" if disabled else "normal")

static func _apply_texture_button_state(button: TextureButton, skin: Panel, state: String) -> void:
	var use_texture := bool(button.get_meta("use_button_texture", true))
	var texture_style := _make_button_texture_style(state) if use_texture else null
	if texture_style:
		skin.add_theme_stylebox_override("panel", texture_style)
		_set_decor_visible(button, false)
	elif not use_texture:
		skin.add_theme_stylebox_override("panel", make_button_style(state))
		_set_decor_visible(button, false)
	else:
		skin.add_theme_stylebox_override("panel", make_button_style(state))
		_set_decor_visible(button, true)
		_apply_decor_state(button, state)
	var label := button.get_node_or_null("Label") as Label
	if label == null:
		return
	match state:
		"hover":
			_apply_button_label_color(label, Color.WHITE)
		"pressed":
			_apply_button_label_color(label, COLOR_GOLD)
		"disabled":
			_apply_button_label_color(label, COLOR_TEXT_DIM)
		_:
			_apply_button_label_color(label, COLOR_TEXT)

static func _apply_button_label_color(label: Label, color: Color) -> void:
	label.add_theme_color_override("font_color", color)
	if label.label_settings:
		label.label_settings.font_color = color

static func _make_button_visual_style(state: String, use_texture: bool = true) -> StyleBox:
	var texture_style := _make_button_texture_style(state) if use_texture else null
	if texture_style:
		return texture_style
	return make_button_style(state)

static func _make_button_texture_style(state: String) -> StyleBoxTexture:
	var path := _button_texture_path(state)
	if path == "" or not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var style := StyleBoxTexture.new()
	style.texture = tex
	style.texture_margin_left = BUTTON_TEXTURE_MARGIN_LEFT
	style.texture_margin_top = BUTTON_TEXTURE_MARGIN_TOP
	style.texture_margin_right = BUTTON_TEXTURE_MARGIN_RIGHT
	style.texture_margin_bottom = BUTTON_TEXTURE_MARGIN_BOTTOM
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.draw_center = true
	return style

static func _make_panel_texture_style(state: String) -> StyleBoxTexture:
	var style := _make_button_texture_style(state)
	if style == null:
		return null
	style.texture_margin_left = 54
	style.texture_margin_top = 42
	style.texture_margin_right = 54
	style.texture_margin_bottom = 42
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 28
	style.content_margin_bottom = 28
	return style

static func _button_texture_path(state: String) -> String:
	match state:
		"hover":
			return "res://Assets/UI/button_hover.png"
		"pressed":
			return "res://Assets/UI/button_pressed.png"
		"disabled":
			return "res://Assets/UI/button_disabled.png"
		_:
			return "res://Assets/UI/button_normal.png"

static func _should_use_texture_for_size(size: Vector2) -> bool:
	if size.x <= 0 or size.y <= 0:
		return true
	if size.x < 180.0 or size.y < 52.0:
		return false
	if size.x / size.y > 3.35:
		return false
	return true

static func _ensure_texture_button_decoration(button: TextureButton) -> void:
	var inner := button.get_node_or_null("DreamInnerFrame") as Panel
	if inner == null:
		inner = Panel.new()
		inner.name = "DreamInnerFrame"
		inner.set_anchors_preset(Control.PRESET_FULL_RECT)
		inner.offset_left = 4
		inner.offset_top = 4
		inner.offset_right = -4
		inner.offset_bottom = -4
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(inner)

	var top_glow := button.get_node_or_null("DreamTopGlow") as ColorRect
	if top_glow == null:
		top_glow = ColorRect.new()
		top_glow.name = "DreamTopGlow"
		top_glow.anchor_left = 0.0
		top_glow.anchor_top = 0.0
		top_glow.anchor_right = 1.0
		top_glow.anchor_bottom = 0.0
		top_glow.offset_left = 10
		top_glow.offset_top = 5
		top_glow.offset_right = -10
		top_glow.offset_bottom = 9
		top_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(top_glow)

	var scan := button.get_node_or_null("DreamScanLine") as ColorRect
	if scan == null:
		scan = ColorRect.new()
		scan.name = "DreamScanLine"
		scan.anchor_left = 0.08
		scan.anchor_right = 0.92
		scan.anchor_top = 0.46
		scan.anchor_bottom = 0.46
		scan.offset_top = -1
		scan.offset_bottom = 1
		scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(scan)

	_ensure_corner_line(button, "DreamCornerTL_H", Vector2(8, 8), Vector2(34, 3))
	_ensure_corner_line(button, "DreamCornerTL_V", Vector2(8, 8), Vector2(3, 20))
	_ensure_corner_line(button, "DreamCornerBR_H", Vector2(-42, -11), Vector2(34, 3), true)
	_ensure_corner_line(button, "DreamCornerBR_V", Vector2(-11, -28), Vector2(3, 20), true)

static func _ensure_corner_line(button: TextureButton, node_name: String, pos: Vector2, size: Vector2, from_bottom_right: bool = false) -> void:
	var line := button.get_node_or_null(node_name) as ColorRect
	if line:
		return
	line = ColorRect.new()
	line.name = node_name
	line.size = size
	if from_bottom_right:
		line.anchor_left = 1.0
		line.anchor_top = 1.0
		line.anchor_right = 1.0
		line.anchor_bottom = 1.0
	line.position = pos
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(line)

static func _apply_decor_state(button: TextureButton, state: String) -> void:
	var inner := button.get_node_or_null("DreamInnerFrame") as Panel
	if inner:
		var inner_style := StyleBoxFlat.new()
		inner_style.bg_color = Color(0, 0, 0, 0)
		inner_style.set_border_width_all(1)
		inner_style.set_corner_radius_all(4)
		match state:
			"hover":
				inner_style.border_color = Color(0.75, 1.0, 1.0, 0.5)
			"pressed":
				inner_style.border_color = Color(COLOR_GOLD.r, COLOR_GOLD.g, COLOR_GOLD.b, 0.68)
			"disabled":
				inner_style.border_color = Color(0.5, 0.55, 0.62, 0.18)
			_:
				inner_style.border_color = Color(0.7, 0.95, 1.0, 0.26)
		inner.add_theme_stylebox_override("panel", inner_style)

	var top_glow := button.get_node_or_null("DreamTopGlow") as ColorRect
	if top_glow:
		match state:
			"hover":
				top_glow.color = Color(0.75, 1.0, 1.0, 0.26)
			"pressed":
				top_glow.color = Color(COLOR_GOLD.r, COLOR_GOLD.g, COLOR_GOLD.b, 0.2)
			"disabled":
				top_glow.color = Color(0.7, 0.8, 0.9, 0.04)
			_:
				top_glow.color = COLOR_GLASS

	var scan := button.get_node_or_null("DreamScanLine") as ColorRect
	if scan:
		match state:
			"hover":
				scan.color = Color(0.35, 0.95, 1.0, 0.24)
			"pressed":
				scan.color = Color(COLOR_GOLD.r, COLOR_GOLD.g, COLOR_GOLD.b, 0.22)
			_:
				scan.color = Color(0.2, 0.7, 0.9, 0.09)

	var corner_color := Color(COLOR_GOLD.r, COLOR_GOLD.g, COLOR_GOLD.b, 0.48)
	match state:
		"hover":
			corner_color = Color(COLOR_GOLD.r, COLOR_GOLD.g, COLOR_GOLD.b, 0.9)
		"pressed":
			corner_color = Color(0.35, 0.95, 1.0, 0.85)
		"disabled":
			corner_color = Color(0.5, 0.55, 0.62, 0.22)
	for node_name in ["DreamCornerTL_H", "DreamCornerTL_V", "DreamCornerBR_H", "DreamCornerBR_V"]:
		var line := button.get_node_or_null(node_name) as ColorRect
		if line:
			line.color = corner_color

static func _set_decor_visible(button: TextureButton, visible: bool) -> void:
	for node_name in ["DreamInnerFrame", "DreamTopGlow", "DreamScanLine", "DreamCornerTL_H", "DreamCornerTL_V", "DreamCornerBR_H", "DreamCornerBR_V"]:
		var node := button.get_node_or_null(node_name) as CanvasItem
		if node:
			node.visible = visible

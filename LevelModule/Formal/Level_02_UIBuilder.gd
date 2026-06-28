# ============================================================
# Level_02_UIBuilder.gd - 关卡2 UI 构建器（简化版）
# 仅保留叙事/黑屏；干扰/睁眼/IDE/配置 UI 已备份
# ============================================================
extends RefCounted
class_name Level_02_UIBuilder

var level: Level_02
var canvas: CanvasLayer

func _init(parent: Level_02, canvas_layer: CanvasLayer) -> void:
	level = parent
	canvas = canvas_layer

func build_all() -> void:
	_build_blackout_overlay()
	_build_narrative_panel()
	_build_ending_prompt()

func _build_blackout_overlay() -> void:
	var overlay = ColorRect.new()
	overlay.name = "BlackoutOverlay"
	overlay.visible = false
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(overlay)
	level._blackout_overlay = overlay

func _build_narrative_panel() -> void:
	var panel = Panel.new()
	panel.name = "NarrativePanel"
	panel.visible = false
	panel.anchor_left = 0.0
	panel.anchor_top = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 0.0
	panel.offset_top = -200.0
	panel.offset_right = 0.0
	panel.offset_bottom = 0.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.85)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var label = RichTextLabel.new()
	label.name = "RichTextLabel"
	label.anchor_left = 0.0
	label.anchor_top = 0.0
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	label.offset_left = 20.0
	label.offset_top = 20.0
	label.offset_right = -20.0
	label.offset_bottom = -20.0
	label.bbcode_enabled = true
	label.fit_content = true
	label.add_theme_font_size_override("normal_font_size", 27)
	label.add_theme_color_override("default_color", Color(0.9, 0.85, 0.75))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	level._narrative_text = label

	canvas.add_child(panel)
	level._narrative_panel = panel

func _build_ending_prompt() -> void:
	var prompt = Control.new()
	prompt.name = "EndingPrompt"
	prompt.visible = false
	prompt.set_anchors_preset(Control.PRESET_FULL_RECT)
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg = ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.95)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.add_child(bg)

	var label = Label.new()
	label.name = "EndingLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 36)
	label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7))
	label.position = Vector2(240, 240)
	label.size = Vector2(800, 240)
	prompt.add_child(label)
	level._ending_label = label

	canvas.add_child(prompt)
	level._ending_prompt = prompt

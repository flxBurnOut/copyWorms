# ============================================================
# Level_03_UIBuilder.gd - 关卡3 UI 构建器
# 负责构建关卡3全部 Canvas UI（纯代码构建，与关卡1/2模式一致）:
#   BlackoutOverlay / NarrativePanel / CodeRainOverlay /
#   WarmGlowOverlay / GlitchOverlay / EndingPrompt
# 只构建节点并写入主控字段，不持有任何流程状态
# ============================================================
extends RefCounted
class_name Level_03_UIBuilder

var level: Level_03
var canvas: CanvasLayer

const VIEW_W: float = 1280.0
const VIEW_H: float = 720.0

func _init(parent: Level_03, canvas_layer: CanvasLayer) -> void:
	level = parent
	canvas = canvas_layer

func build_all() -> void:
	_build_narrative_panel()
	_build_code_rain_overlay()
	_build_glitch_overlay()
	_build_ending_prompt()


# ---- 叙事面板（复用关卡1/2样式） ----

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


# ---- 代码雨（Matrix 风格，CodeRain 独立类） ----

func _build_code_rain_overlay() -> void:
	var rain = CodeRain.new()
	rain.name = "CodeRainOverlay"
	canvas.add_child(rain)
	level._code_rain_overlay = rain


# ---- Glitch 覆盖层（复用关卡1的 GlitchShader） ----

func _build_glitch_overlay() -> void:
	var overlay = ColorRect.new()
	overlay.name = "GlitchOverlay"
	overlay.visible = false
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shader = load("res://LevelModule/Formal/glitch_effect.gdshader")
	if shader:
		var mat = ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("intensity", 0.0)
		overlay.material = mat

	canvas.add_child(overlay)
	level._glitch_overlay = overlay


# ---- 终局提示（绿色系统文本） ----

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
	label.add_theme_font_size_override("font_size", 30)
	# 绿色终端文字
	label.add_theme_color_override("font_color", Color(0, 1.0, 0.25, 0.95))
	label.position = Vector2(240, 240)
	label.size = Vector2(800, 240)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.add_child(label)
	level._ending_label = label

	canvas.add_child(prompt)
	level._ending_prompt = prompt

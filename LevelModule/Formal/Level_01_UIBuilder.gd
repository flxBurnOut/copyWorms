# ============================================================
# Level_01_UIBuilder.gd - UI 构建器
# 负责叙事面板、睡眠覆盖层、IDE界面、Glitch覆盖层的创建
# ============================================================
extends RefCounted
class_name Level_01_UIBuilder

var level: Level_01
var canvas: CanvasLayer

func _init(parent: Level_01, canvas_layer: CanvasLayer) -> void:
	level = parent
	canvas = canvas_layer

func build_all() -> void:
	_build_sleep_overlay()
	_build_narrative_panel()
	_build_ide_ui()
	_build_left_edge_flash()
	_build_right_edge_flash()
	_build_glitch_overlay()

func _build_sleep_overlay() -> void:
	var overlay = ColorRect.new()
	overlay.name = "SleepOverlay"
	overlay.visible = false
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(overlay)
	level._sleep_overlay = overlay

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

func _build_ide_ui() -> void:
	var ide = Control.new()
	ide.name = "IdeUI"
	ide.visible = false
	ide.set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg = TextureRect.new()
	bg.name = "IdeBackground"
	bg.anchor_left = 0.0
	bg.anchor_top = 0.0
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.offset_left = 0.0
	bg.offset_top = 0.0
	bg.offset_right = 0.0
	bg.offset_bottom = 0.0
	bg.texture = _load_ide_background_texture()
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = 0
	bg.show()
	ide.add_child(bg)

	var chat = RichTextLabel.new()
	chat.name = "ChatWindow"
	chat.anchor_left = 1.0
	chat.anchor_top = 0.0
	chat.anchor_right = 1.0
	chat.anchor_bottom = 1.0
	chat.offset_left = -236.0
	chat.offset_top = 174.0
	chat.offset_right = -58.0
	chat.offset_bottom = -34.0
	chat.bbcode_enabled = true
	chat.scroll_following = true
	chat.fit_content = false
	chat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chat.add_theme_font_size_override("normal_font_size", 21)
	chat.add_theme_color_override("default_color", Color(0.9, 0.9, 0.95))
	ide.add_child(chat)
	level._chat_window = chat

	# 代码滚动区域：贴合截图中间的大编辑器区域，背景由整张 IDE 截图提供。
	var code_panel = Control.new()
	code_panel.name = "CodeScrollPanel"
	code_panel.visible = false
	code_panel.anchor_left = 0.0
	code_panel.anchor_top = 0.0
	code_panel.anchor_right = 1.0
	code_panel.anchor_bottom = 1.0
	code_panel.offset_left = 124.0
	code_panel.offset_top = 120.0
	code_panel.offset_right = -260.0
	code_panel.offset_bottom = -52.0
	code_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ide.add_child(code_panel)

	var code_text = RichTextLabel.new()
	code_text.name = "CodeScrollText"
	code_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	code_text.bbcode_enabled = true
	code_text.scroll_following = true
	code_text.fit_content = false
	code_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	code_text.add_theme_font_size_override("normal_font_size", 22)
	code_text.add_theme_color_override("default_color", Color(0.55, 0.95, 0.65))
	code_panel.add_child(code_text)
	level._code_scroll_panel = code_panel
	level._code_scroll_text = code_text

	# 保留隐藏预览视口供原有 prototype_crashed/超时流程使用，不再显示在 UI 上。
	var viewport_container = SubViewportContainer.new()
	viewport_container.name = "ViewportContainer"
	viewport_container.position = Vector2(-2000, -2000)
	viewport_container.size = Vector2(320, 180)
	viewport_container.stretch = true

	var mini_viewport = SubViewport.new()
	mini_viewport.name = "MiniViewport"
	mini_viewport.size = Vector2(320, 180)
	mini_viewport.transparent_bg = true
	viewport_container.add_child(mini_viewport)
	level._mini_viewport = mini_viewport
	level._viewport_container = viewport_container
	ide.add_child(viewport_container)

	canvas.add_child(ide)
	level._ide_ui = ide

func _load_ide_background_texture() -> Texture2D:
	const BG_PATH := "res://Assets/UI/ai_ide_background.png"
	var texture := load(BG_PATH) as Texture2D
	if texture:
		return texture
	push_warning("[Level_01_UIBuilder] 无法加载 IDE 背景图: %s" % BG_PATH)
	var image := Image.create(1280, 720, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.06, 0.07, 0.12, 1.0))
	return ImageTexture.create_from_image(image)

func _build_left_edge_flash() -> void:
	# 主光条（窄、亮）
	var flash = ColorRect.new()
	flash.name = "LeftEdgeFlash"
	flash.color = Color(1.0, 0.85, 0.2, 0.0)
	flash.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	flash.offset_right = 8
	flash.visible = false
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 100
	canvas.add_child(flash)
	level._left_edge_flash = flash
	# 扩散光晕（宽、淡）
	var glow = ColorRect.new()
	glow.name = "LeftEdgeGlow"
	glow.color = Color(1.0, 0.9, 0.3, 0.0)
	glow.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	glow.offset_right = 30
	glow.visible = false
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.z_index = 99
	canvas.add_child(glow)
	level._left_edge_glow = glow

func _build_right_edge_flash() -> void:
	# 主光条（窄、亮）
	var flash = ColorRect.new()
	flash.name = "RightEdgeFlash"
	flash.color = Color(1.0, 0.85, 0.2, 0.0)
	flash.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	flash.offset_left = -8
	flash.visible = false
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 100
	canvas.add_child(flash)
	level._right_edge_flash = flash
	# 扩散光晕（宽、淡）
	var glow = ColorRect.new()
	glow.name = "RightEdgeGlow"
	glow.color = Color(1.0, 0.9, 0.3, 0.0)
	glow.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	glow.offset_left = -30
	glow.visible = false
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.z_index = 99
	canvas.add_child(glow)
	level._right_edge_glow = glow

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

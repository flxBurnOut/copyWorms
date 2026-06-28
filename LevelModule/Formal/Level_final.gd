# ============================================================
# Level_final.gd - 终局关卡（视频演出后进入）
# 玩家出生 (784,576)，交互点 (472,472)，交互后显示"太阳照常升起"
# ============================================================
extends Node2D

var _all_interactives: Array[InteractiveObject] = []
var _dialog_open: bool = false
var _dialog_panel: Panel = null
var _dialog_label: RichTextLabel = null
var _dialog_lines: Array[String] = []
var _dialog_index: int = 0
var _ending_triggered: bool = false

const PLAYER_SPAWN := Vector2(320, 616)
const INTERACT_POS := Vector2(192, 592)
const INTERACT_ID := "final_sun"

func _ready() -> void:
	# 清除旧玩家
	if GameManager.player_ref and is_instance_valid(GameManager.player_ref):
		GameManager.player_ref.queue_free()
		GameManager.player_ref = null
	# 背景色
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.size = Vector2(400, 720)
	bg.position = Vector2(0, 0)
	bg.color = Color(0.769, 0.6, 0.286, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = -10
	add_child(bg)

	# 创建玩家（普通外观，非赛博非岭南）
	var path := "res://PlayerModule/Formal/Player_Warrior.tscn"
	if ResourceLoader.exists(path):
		var p = load(path).instantiate()
		p.position = PLAYER_SPAWN
		add_child(p)
		GameManager.register_player(p)

		# 禁用跳跃/攻击/闪避/技能
		p.can_jump = false
		p.can_dash = false
		p.can_attack = false
		p.can_skill = false
		p.runtime_move_speed_multiplier = 0.2
		var cam = p.get_node_or_null("SmoothCamera") as SmoothCamera
		if cam:
			# 摄像机配置
			cam.limit_left = 0
			cam.limit_right = 400
			cam.limit_top = 314
			cam.limit_bottom = 640
			cam.zoom = Vector2(3.5, 3.5)
			cam.offset = Vector2.ZERO
			cam.lerp_speed = 2.5
			cam.bind_target(p)
			cam.follow_enabled = true
			cam.make_current()
	# 不加载 HUD（不显示血条和技能图标）
	# 创建交互点
	_create_interactive()
	# 订阅交互事件
	EventBus.subscribe(GlobalDefine.EventName.INTERACTIVE_OBJECT_TRIGGERED, self, "_on_object_interacted")
	set_process(true)
	set_process_input(true)
	print("[Level_final] 终局关卡加载完成")


func _exit_tree() -> void:
	prepare_for_level_exit()


func prepare_for_level_exit() -> void:
	InputManager.unblock_input("终局")
	_dialog_open = false
	EventBus.unsubscribe_all(self)


func _create_interactive() -> void:
	var obj = InteractiveObject.new()
	obj.name = "FinalSun"
	obj.object_id = INTERACT_ID
	obj.is_active = true
	obj.prompt_text = ""
	obj.position = INTERACT_POS
	obj.collision_layer = 0
	obj.collision_mask = GlobalDefine.Collision.PLAYER
	var col = CollisionShape2D.new()
	col.name = "CollisionShape2D"
	var rect = RectangleShape2D.new()
	rect.size = Vector2(100, 80)
	col.shape = rect
	obj.add_child(col)
	add_child(obj)
	_all_interactives.append(obj)
	# 复用关卡1光点视觉
	obj.apply_level01_dot_visual()

func _process(_delta: float) -> void:
	var pl = GameManager.player_ref
	if pl and is_instance_valid(pl) and not _dialog_open:
		for obj in _all_interactives:
			if is_instance_valid(obj):
				obj.check_player_in_range(pl)

func _input(event: InputEvent) -> void:
	if _dialog_open:
		return
	var is_left_click = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if event.is_action_pressed("ui_accept") or is_left_click:
		var obj = _find_nearby_interactive()
		if obj:
			EventBus.emit(GlobalDefine.EventName.INTERACTIVE_OBJECT_TRIGGERED, {"object_id": obj.object_id})
			get_viewport().set_input_as_handled()

func _find_nearby_interactive() -> InteractiveObject:
	for obj in _all_interactives:
		if is_instance_valid(obj) and obj.is_active and not obj.completed and obj.is_player_in_range:
			return obj
	return null

func _on_object_interacted(data: Dictionary) -> void:
	var oid = data.get("object_id", "")
	if oid == INTERACT_ID:
		_trigger_ending()

## 交互触发：锁定交互 + 显示文本框5s + 同时渐入黑屏5s → 切回标题界面
func _trigger_ending() -> void:
	if _ending_triggered:
		return
	_ending_triggered = true
	# 锁定交互物
	for obj in _all_interactives:
		if is_instance_valid(obj):
			obj.mark_completed()
			obj.set_active(false)
	_dialog_open = true
	InputManager.block_input("终局", self)
	# 显示文本框
	if not _dialog_panel:
		_create_dialog_panel()
	_dialog_panel.visible = true
	_dialog_label.text = "太阳照常升起"
	# 同时开始5s黑屏渐入
	var cv = CanvasLayer.new()
	cv.name = "FadeCanvas"
	cv.layer = 2000
	add_child(cv)
	var black = ColorRect.new()
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.size = get_viewport_rect().size
	black.position = Vector2.ZERO
	black.color = Color(0, 0, 0, 0.0)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(black)
	# 5s 渐入满黑 → 切回标题界面
	var tw = get_tree().create_tween()
	tw.tween_property(black, "color:a", 1.0, 5.0).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		SceneTransitionManager.request_scene_change("res://UI/TitleScreen.tscn", self)
	)

## 创建文本框面板
func _create_dialog_panel() -> void:
	var cv = CanvasLayer.new()
	cv.name = "DialogLayer"
	cv.layer = 50
	add_child(cv)
	_dialog_panel = Panel.new()
	_dialog_panel.position = Vector2(240, 520)
	_dialog_panel.size = Vector2(800, 140)
	_dialog_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.85)
	style.set_corner_radius_all(8)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	_dialog_panel.add_theme_stylebox_override("panel", style)
	cv.add_child(_dialog_panel)
	_dialog_label = RichTextLabel.new()
	_dialog_label.bbcode_enabled = true
	_dialog_label.fit_content = true
	_dialog_label.position = Vector2(20, 16)
	_dialog_label.size = Vector2(760, 108)
	_dialog_label.add_theme_font_size_override("normal_font_size", 33)
	_dialog_label.add_theme_color_override("default_color", Color(0.95, 0.9, 0.8))
	_dialog_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog_panel.add_child(_dialog_label)

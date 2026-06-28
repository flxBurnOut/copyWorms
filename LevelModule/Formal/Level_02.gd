# ============================================================
# Level_02.gd - 第二关「撕裂与沉溺」控制器（分段版）
# 流程: 阁楼 → 老街探索 → 右边界切换 Level_02_01
# ============================================================
extends LevelBase
class_name Level_02

@export var level_data: Level02Data = null

enum LevelState {
	DREAM_ATTIC,
	DREAM_STREET,
	LEVEL_END_TRANSIT,
}

var current_state: int = LevelState.DREAM_ATTIC

var has_observed_window: bool = false
var has_entered_street: bool = false
var has_triggered_chair_memory: bool = false

var _dream_root: Node2D = null
var _dynamic_actors: Node2D = null
var _attic_door_wall: StaticBody2D = null
var _street_entry_trigger: Area2D = null
var _level_exit_trigger: Area2D = null

var _window_node: InteractiveObject = null
var _attic_door_node: InteractiveObject = null
var _rattan_chair_node: InteractiveObject = null
var _chips_cat_node: InteractiveObject = null
var _all_interactives: Array[InteractiveObject] = []

var _blackout_overlay: ColorRect = null
var _narrative_panel: Panel = null
var _narrative_text: RichTextLabel = null
var _ending_prompt: Control = null
var _ending_label: Label = null

var _interact_cooldown: float = 0.0
var _is_interacting: bool = false
var _narrative_open: bool = false
var _narrative_enter_pressed: bool = false
var _transition_running: bool = false
const NARRATIVE_INPUT_TIMEOUT: float = 30.0

var _street_enemies: Array[Node2D] = []
var _enemy_slime_scene: PackedScene = null

const FINAL_BLACKOUT_FADE_DURATION: float = 0.8
const NEXT_LEVEL_SEGMENT_PATH: String = "res://LevelModule/Formal/Level_02_01.tscn"
const CHIPS_CAT_TEXTS: Array[String] = [
	"薯片，是你！我最爱的猫！",
	"薯片总是躺在药店前的桌子，懒洋洋地露出肚皮晒着太阳，看见他总感觉心中有温暖的太阳",
	"喵呜唔～",
]

var _level_complete_emitted: bool = false
var _fsm: Level_02_FSM = null
var _combat_hint_label: Label = null       # 战斗操作提示标签
var _combat_hint_shown: bool = false       # 提示是否已显示


func _on_ready() -> void:
	super._on_ready()

	if not level_config:
		level_config = load("res://DataConfig/Level/Level02Config.tres") as LevelConfig
		_apply_config()
	if not level_data:
		level_data = load("res://DataConfig/Level/Level02Data.tres") as Level02Data

	var enemy_path = "res://EnemyModule/Formal/Enemy_LanternGhost.tscn"
	if ResourceLoader.exists(enemy_path):
		_enemy_slime_scene = load(enemy_path)

	var builder = Level_02_SceneBuilder.new(self)
	builder.build_all()

	_setup_camera_limits()
	_restore_player_mechanics()
	_ensure_player_collision_layer()

	_all_interactives = [_window_node, _attic_door_node, _rattan_chair_node, _chips_cat_node]

	EventBus.subscribe(GlobalDefine.EventName.INTERACTIVE_OBJECT_TRIGGERED, self, "_on_object_interacted")
	EventBus.subscribe(GlobalDefine.EventName.ENEMY_DIED, self, "_on_enemy_died_combat_hint")
	_fsm = Level_02_FSM.new(self)

	if not InputManager.game_action.is_connected(_on_game_action):
		InputManager.game_action.connect(_on_game_action)

	_load_hud()
	set_process(true)

	if level_data and level_data.attic_intro_text != "":
		_show_narrative(level_data.attic_intro_text, _show_combat_hint)

	print("[Level_02] 初始化完成 — 当前: DREAM_ATTIC")


func _exit_tree() -> void:
	if InputManager.game_action.is_connected(_on_game_action):
		InputManager.game_action.disconnect(_on_game_action)


func _load_hud() -> void:
	var hud_path = "res://UI/HUD.tscn"
	if ResourceLoader.exists(hud_path):
		var hud = load(hud_path).instantiate()
		add_child(hud)


func _get_or_create_child(node_name: String, node_type: Variant) -> Node:
	var existing = get_node_or_null(node_name)
	if existing:
		return existing
	var node = node_type.new()
	node.name = node_name
	add_child(node)
	return node

func _create_static_body(node_name: String, pos: Vector2, size: Vector2) -> StaticBody2D:
	var body = StaticBody2D.new()
	body.name = node_name
	body.position = pos
	body.collision_layer = GlobalDefine.Collision.TERRAIN
	body.collision_mask = 0
	var col_shape = CollisionShape2D.new()
	var rect_shape = RectangleShape2D.new()
	rect_shape.size = size
	col_shape.shape = rect_shape
	col_shape.name = "CollisionShape2D"
	body.add_child(col_shape)
	return body

func _create_interactive(node_name: String, obj_id: String, pos: Vector2, size: Vector2) -> InteractiveObject:
	var obj = InteractiveObject.new()
	obj.name = node_name
	obj.position = pos
	obj.object_id = obj_id
	obj.collision_layer = 0
	obj.collision_mask = GlobalDefine.Collision.PLAYER
	var col_shape = CollisionShape2D.new()
	col_shape.name = "CollisionShape2D"
	var rect_shape = RectangleShape2D.new()
	rect_shape.size = size
	col_shape.shape = rect_shape
	obj.add_child(col_shape)
	var indicator = ColorRect.new()
	indicator.name = "Indicator"
	indicator.color = Color(0.5, 0.5, 0.5, 0.3)
	indicator.size = size
	indicator.position = -size / 2
	indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	obj.add_child(indicator)
	return obj

func _ensure_player_collision_layer() -> void:
	var player = GameManager.player_ref
	if not player or not is_instance_valid(player):
		return
	if not (player.collision_layer & GlobalDefine.Collision.PLAYER):
		player.collision_layer |= GlobalDefine.Collision.PLAYER

func _setup_camera_limits() -> void:
	if not level_config:
		return
	_set_camera_limits(level_config.camera_limit_left, level_config.camera_limit_right,
		level_config.camera_limit_top, level_config.camera_limit_bottom)

func _set_camera_limits(left: int, right: int, top: int, bottom: int) -> void:
	var player = GameManager.player_ref
	if not player or not is_instance_valid(player):
		return
	var cam = player.get_node_or_null("SmoothCamera") as SmoothCamera
	if not cam:
		return
	cam.limit_left = 0
	cam.limit_right = right
	cam.limit_top = top
	cam.limit_bottom = 640
	cam.bind_target(player)

func _restore_player_mechanics() -> void:
	var player = GameManager.player_ref
	if not player:
		return
	player.can_jump = true
	player.can_dash = true
	player.can_attack = true
	player.can_skill = true
	player.can_double_jump = false
	player.runtime_move_speed_multiplier = 1.0

func _enforce_level_restrictions() -> void:
	var player = GameManager.player_ref
	if player and is_instance_valid(player) and player.can_double_jump:
		player.can_double_jump = false

func _freeze_player(freeze: bool) -> void:
	var player = GameManager.player_ref
	if not player:
		return
	# [旧实现 - 保留以备回退] 已迁移至 PlayerBase.set_frozen() 统一处理动画冻结问题
	# if freeze:
	#     player.velocity = Vector2.ZERO
	#     player.set_physics_process(false)
	#     player.set_process_input(false)
	#     player._change_state(GlobalDefine.PlayerState.IDLE)
	# else:
	#     player.set_physics_process(true)
	#     player.set_process_input(true)
	player.set_frozen(freeze)
	for obj in _all_interactives:
		if is_instance_valid(obj):
			obj.freeze_monitoring(freeze)


func _on_game_action(action: StringName, _event: InputEvent) -> void:
	if action != &"ui_accept":
		return
	_handle_accept_input()

func _handle_accept_input() -> void:
	if current_state == LevelState.LEVEL_END_TRANSIT:
		return
	if _narrative_open:
		_narrative_enter_pressed = true
		return
	if _is_interacting or _interact_cooldown > 0.0 or _transition_running:
		if not _transition_running and _interact_cooldown > 0.5:
			_safe_end_interaction()
		return
	var obj = _find_nearby_interactive()
	if obj:
		_interact_cooldown = 0.3
		EventBus.emit(GlobalDefine.EventName.INTERACTIVE_OBJECT_TRIGGERED, {"object_id": obj.object_id})

func _input(event: InputEvent) -> void:
	# 鼠标左键等价于Enter（对话推进/交互触发）
	var is_left_click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if not event.is_action_pressed("ui_accept") and not is_left_click:
		return
	if current_state == LevelState.LEVEL_END_TRANSIT:
		get_viewport().set_input_as_handled()
		return
	if _narrative_open:
		_narrative_enter_pressed = true
		get_viewport().set_input_as_handled()
		return
	if _is_interacting or _interact_cooldown > 0.0 or _transition_running:
		if not _transition_running and _interact_cooldown > 0.5:
			_safe_end_interaction()
		return
	var obj = _find_nearby_interactive()
	if obj:
		_interact_cooldown = 0.3
		EventBus.emit(GlobalDefine.EventName.INTERACTIVE_OBJECT_TRIGGERED, {"object_id": obj.object_id})
		get_viewport().set_input_as_handled()

func _find_nearby_interactive() -> InteractiveObject:
	for obj in _all_interactives:
		if is_instance_valid(obj) and obj.is_active and not obj.completed and obj.is_player_in_range:
			return obj
	var player = GameManager.player_ref
	if not player or not is_instance_valid(player):
		return null
	var best: InteractiveObject = null
	var best_dist: float = INF
	const FALLBACK_RADIUS: float = 120.0
	for obj in _all_interactives:
		if not is_instance_valid(obj) or not obj.is_active or obj.completed:
			continue
		var d: float = player.global_position.distance_to(obj.global_position)
		if d < FALLBACK_RADIUS and d < best_dist:
			best_dist = d
			best = obj
	if best:
		best.is_player_in_range = true
	return best


func _process(delta: float) -> void:
	if _interact_cooldown > 0.0:
		_interact_cooldown -= delta
	_enforce_level_restrictions()
	if not _is_interacting and not _transition_running and not _narrative_open:
		if InputManager.is_input_blocked:
			InputManager.force_unblock_all()
	_poll_interactives_in_range()
	if _is_interacting and current_state != LevelState.LEVEL_END_TRANSIT:
		if not _narrative_open and not _transition_running:
			_safe_end_interaction()

func _poll_interactives_in_range() -> void:
	var player = GameManager.player_ref
	if not player or not is_instance_valid(player):
		return
	for obj in _all_interactives:
		if is_instance_valid(obj):
			obj.check_player_in_range(player)

func _safe_end_interaction() -> void:
	if not _narrative_open and not _transition_running:
		_is_interacting = false
	_interact_cooldown = 0.0

func _run_safely(fn: Callable) -> void:
	if not fn.is_valid():
		return
	_interact_cooldown = 0.0
	fn.call()
	_safe_end_interaction()


func _on_object_interacted(data: Dictionary) -> void:
	var obj_id: String = data.get("object_id", "")
	if not _fsm:
		return
	_interact_cooldown = 0.0
	_run_safely(func(): _fsm.handle_interaction(obj_id))

func _get_interactive_by_id(obj_id: String) -> InteractiveObject:
	match obj_id:
		"window_l2": return _window_node
		"attic_door": return _attic_door_node
		"rattan_chair": return _rattan_chair_node
		"chips_cat": return _chips_cat_node
	return null

func _mark_interaction_completed(obj_id: String) -> void:
	var obj = _get_interactive_by_id(obj_id)
	if obj and not obj.allow_repeat:
		obj.mark_completed()


## 显示战斗操作提示（屏幕上方，击杀一个怪物后消失）
func _show_combat_hint() -> void:
	if _combat_hint_shown: return
	_combat_hint_shown = true
	var cv = get_node_or_null("CanvasLayerUI")
	if not cv:
		# fallback: 直接加到关卡根节点
		cv = self
	_combat_hint_label = Label.new()
	_combat_hint_label.name = "CombatHintLabel"
	_combat_hint_label.text = "[%s] 跳跃    [%s] 攻击    [%s] 冲刺    [%s] 技能" % [
		_get_first_action_event_display(&"player_jump"),
		_get_first_action_event_display(&"player_attack"),
		_get_first_action_event_display(&"player_dash"),
		_get_first_action_event_display(&"player_skill"),
	]
	_combat_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combat_hint_label.add_theme_font_size_override("font_size", 27)
	_combat_hint_label.add_theme_color_override("font_color", Color(1, 0.95, 0.7, 0.9))
	_combat_hint_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_combat_hint_label.add_theme_constant_override("shadow_offset_x", 1)
	_combat_hint_label.add_theme_constant_override("shadow_offset_y", 1)
	_combat_hint_label.size = Vector2(1280, 40)
	_combat_hint_label.position = Vector2(0, 30)
	_combat_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combat_hint_label.z_index = 150
	cv.add_child(_combat_hint_label)
	# 淡入动画
	_combat_hint_label.modulate.a = 0.0
	var tw = _combat_hint_label.create_tween()
	tw.tween_property(_combat_hint_label, "modulate:a", 1.0, 0.4)


## 击杀怪物后隐藏战斗提示
func _on_enemy_died_combat_hint(_data: Dictionary) -> void:
	if not _combat_hint_shown or not _combat_hint_label: return
	_combat_hint_shown = false
	var label = _combat_hint_label
	_combat_hint_label = null
	# 淡出后移除
	var tw = label.create_tween()
	tw.tween_property(label, "modulate:a", 0.0, 0.5)
	tw.tween_callback(label.queue_free)
	# 取消订阅（只触发一次）
	EventBus.unsubscribe(GlobalDefine.EventName.ENEMY_DIED, self)


func _get_first_action_event_display(action: StringName) -> String:
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	if events.is_empty():
		return "?"
	return KeybindManager.get_event_display_text(events[0])


func _show_narrative(text: String, callback: Callable = Callable()) -> void:
	InputManager.block_input("叙事面板", self)
	if _narrative_open:
		if _narrative_panel:
			_narrative_panel.hide()
		_narrative_open = false
	_is_interacting = true
	_narrative_open = true
	_freeze_player(true)
	if _narrative_panel:
		_narrative_panel.show()
		if _narrative_text:
			_narrative_text.text = text
	await get_tree().create_timer(0.3).timeout

	_narrative_enter_pressed = false
	var wait_elapsed: float = 0.0
	var wait_delta: float = 0.05
	while _narrative_open and wait_elapsed < NARRATIVE_INPUT_TIMEOUT:
		if _narrative_enter_pressed:
			break
		await get_tree().create_timer(wait_delta).timeout
		wait_elapsed += wait_delta

	if _narrative_panel:
		_narrative_panel.hide()
	_freeze_player(false)
	_narrative_open = false
	_is_interacting = false
	_interact_cooldown = 0.0
	InputManager.unblock_input("叙事面板")
	if callback.is_valid():
		_run_safely(callback)

func _show_narrative_sequence(texts: Array[String], callback: Callable = Callable()) -> void:
	if texts.is_empty():
		if callback.is_valid():
			_run_safely(callback)
		return
	InputManager.block_input("叙事面板", self)
	if _narrative_open:
		if _narrative_panel:
			_narrative_panel.hide()
		_narrative_open = false
	_is_interacting = true
	_narrative_open = true
	_freeze_player(true)
	if _narrative_text:
		_narrative_text.text = texts[0]
	if _narrative_panel:
		_narrative_panel.show()
	await get_tree().create_timer(0.3).timeout

	for i in range(texts.size()):
		if not _narrative_open:
			break
		if i > 0 and _narrative_text:
			_narrative_text.text = texts[i]
		await _wait_for_narrative_advance()

	if _narrative_panel:
		_narrative_panel.hide()
	_freeze_player(false)
	_narrative_open = false
	_is_interacting = false
	_interact_cooldown = 0.0
	InputManager.unblock_input("叙事面板")
	if callback.is_valid():
		_run_safely(callback)

func _wait_for_narrative_advance() -> void:
	var wait_delta: float = 0.05
	while _narrative_open and Input.is_action_pressed("ui_accept"):
		await get_tree().create_timer(wait_delta).timeout

	_narrative_enter_pressed = false
	var wait_elapsed: float = 0.0
	while _narrative_open and wait_elapsed < NARRATIVE_INPUT_TIMEOUT:
		if _narrative_enter_pressed:
			break
		await get_tree().create_timer(wait_delta).timeout
		wait_elapsed += wait_delta

func _fade_blackout(to_alpha: float, duration: float) -> void:
	if not _blackout_overlay:
		await get_tree().create_timer(duration).timeout
		return
	_blackout_overlay.show()
	var tween = create_tween()
	tween.tween_property(_blackout_overlay, "color:a", to_alpha, duration)
	await tween.finished
	if to_alpha <= 0.0:
		_blackout_overlay.hide()


func _handle_window_observe() -> void:
	if not level_data:
		return
	has_observed_window = true
	_mark_interaction_completed("window_l2")
	_show_narrative(level_data.window_text_l2)

func _transition_attic_to_street() -> void:
	if _transition_running or not level_data:
		return
	_mark_interaction_completed("attic_door")
	_show_narrative(level_data.attic_door_text, func(): _do_attic_door_transition())

func _handle_chips_cat_interaction() -> void:
	if _chips_cat_node and _chips_cat_node.completed:
		return
	if _chips_cat_node:
		_chips_cat_node.allow_repeat = false
	_show_narrative_sequence(CHIPS_CAT_TEXTS, func():
		_mark_interaction_completed("chips_cat")
	)

func _do_attic_door_transition() -> void:
	_transition_running = true
	_is_interacting = true
	InputManager.block_input("趟栊门转场", self)
	_freeze_player(true)
	await _fade_blackout(1.0, 0.8)

	if _attic_door_wall and is_instance_valid(_attic_door_wall):
		var shape = _attic_door_wall.get_node_or_null("CollisionShape2D")
		if shape:
			shape.disabled = true
		_attic_door_wall.visible = false
	if _attic_door_node and is_instance_valid(_attic_door_node):
		_attic_door_node.set_active(false)
		_attic_door_node.visible = false
	var player = GameManager.player_ref
	if player and is_instance_valid(player):
		player.global_position = Vector2(435, 550)
		player.velocity = Vector2.ZERO

	_enter_street_state()
	await _fade_blackout(0.0, 0.8)
	_freeze_player(false)
	InputManager.unblock_input("趟栊门转场")
	_transition_running = false
	_safe_end_interaction()

func _enter_street_state() -> void:
	if has_entered_street:
		return
	has_entered_street = true
	current_state = LevelState.DREAM_STREET
	_spawn_street_enemies()

func _on_street_entry_body_entered(body: Node2D) -> void:
	if not _is_player_body(body):
		return
	if current_state != LevelState.DREAM_ATTIC:
		return
	_enter_street_state()

func _on_level_exit_body_entered(body: Node2D) -> void:
	if not _is_player_body(body):
		return
	if current_state != LevelState.DREAM_STREET:
		return
	_trigger_level_end()

func _is_player_body(body: Node2D) -> bool:
	if not body is CharacterBody2D:
		return false
	if body.collision_layer & GlobalDefine.Collision.PLAYER:
		return true
	return body.is_in_group("player")

func _spawn_street_enemies() -> void:
	if not _enemy_slime_scene:
		return
	var config = load("res://DataConfig/Enemy/StreetSlimeConfig.tres") as EnemyConfig
	var spawn_points: Array[Vector2] = []
	if level_data and not level_data.street_enemy_spawn_points.is_empty():
		spawn_points = level_data.street_enemy_spawn_points
	else:
		spawn_points = [Vector2(1500, 540), Vector2(2100, 540), Vector2(2800, 540)]
	var count = mini(spawn_points.size(), 5)
	for i in range(count):
		var enemy = _spawn_enemy_with_config(_enemy_slime_scene, spawn_points[i], config)
		if enemy:
			_street_enemies.append(enemy)

func _spawn_enemy_with_config(scene: PackedScene, spawn_pos: Vector2, config: EnemyConfig) -> Node2D:
	if not scene:
		return null
	var enemy = scene.instantiate()
	if config:
		enemy.config = config
	enemy.global_position = spawn_pos
	if _dynamic_actors:
		_dynamic_actors.add_child(enemy)
	else:
		add_child(enemy)
	return enemy


func _trigger_level_end() -> void:
	if _transition_running:
		return
	_transition_running = true
	_is_interacting = true
	current_state = LevelState.LEVEL_END_TRANSIT
	InputManager.block_input("关卡2分段转场", self)
	_freeze_player(true)

	await _fade_blackout(1.0, FINAL_BLACKOUT_FADE_DURATION)

	get_viewport().gui_release_focus()
	_emit_level_complete()

func _emit_level_complete() -> void:
	if _level_complete_emitted:
		return
	_level_complete_emitted = true
	var next_path = NEXT_LEVEL_SEGMENT_PATH
	get_viewport().gui_release_focus()
	InputManager.force_unblock_all()
	_full_cleanup()
	if not _is_loaded_under_main_entry():
		print("[Level_02] 无 MainEntry，直接切换场景 → ", next_path)
		SceneTransitionManager.request_scene_change(next_path, self)
		return
	print("[Level_02] 发射 LEVEL_COMPLETE → ", next_path)
	EventBus.emit(GlobalDefine.EventName.LEVEL_COMPLETE, {
		"level": self,
		"next_level": next_path,
	})

func _is_loaded_under_main_entry() -> bool:
	var node = get_parent()
	while node:
		if node.name == "MainEntry":
			return true
		node = node.get_parent()
	return false

func _full_cleanup() -> void:
	for e in _street_enemies:
		if is_instance_valid(e):
			GameManager.unregister_enemy(e)
			e.queue_free()
	_street_enemies.clear()
	InputManager.unblock_input("关卡2清理")
	EventBus.unsubscribe_all(self)

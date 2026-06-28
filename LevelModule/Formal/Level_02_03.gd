# ============================================================
# Level_02_03.gd - 第二关分段 03：断崖 → 干扰 → 睁眼 → 现实房间
# 地图: 0-1136
# ============================================================
extends LevelBase
class_name Level_02_03

@export var level_data: Level02Data = null
@export var map_left: int = 0
@export var map_right: int = 2000
@export var ground_y: int = 576

enum LevelState {
	DREAM_STREET,            # 梦境街区
	DREAM_CLIFF_LOOP,        # 断崖坠落循环
	DREAM_INTERFERENCE,      # 现实干扰：红光、短信、阴影敌人、沉重化
	WAKING_HOLD_TAB,         # 长按 Tab 睁眼
	REALITY_PHONE_LOCKED,    # 现实房间：仅手机可交互
	REALITY_PHONE_READ,      # 已读短信，电脑解锁
	REALITY_IDE_CHAT,        # CodeBuddy 对话
	REALITY_FREE_CHAT,       # CodeBuddy 自由对话（底部输入→主区显示→AI回复）
	REALITY_CONFIG_EDIT,     # 配置篡改解谜
	REALITY_RECOMPILE,       # 重新编译日志播放
	REALITY_BED_READY,       # 床解锁
}

var current_state: int = LevelState.DREAM_STREET

# ---- 断崖 ----
var fall_count: int = 0
var _cliff_approach_trigger: Area2D = null
var _fall_pit_trigger: Area2D = null
var _cliff_safe_spawn: Marker2D = null
var _fall_reset_running: bool = false

# ---- 干扰期 ----
var interference_triggered: bool = false
var wake_hold_time: float = 0.0
var _red_tween: Tween = null
var _shadow_spawn_timer: Timer = null
var _shadow_enemies: Array[Node2D] = []
const SHADOW_MAX_ALIVE: int = 8
const SHADOW_MAX_ONSCREEN: int = 6
const SHADOW_SPAWN_INTERVAL: float = 1.5
const INTERFERENCE_MOVE_MULTIPLIER: float = 0.55
const DEATH_GUARD_HEALTH: int = 10

# ---- 睁眼 ----
var wake_hold_required: float = 1.5
const VIEW_W: float = 1280.0
const VIEW_H: float = 720.0
const REALITY_SPACE_CONFIG_PATH: String = "res://DataConfig/Level/Level01Config.tres"
const REALITY_PLAYER_SCENE_PATH: String = "res://PlayerModule/Formal/Player_Warrior.tscn"
const SUB01_SCENE_PATH: String = "res://LevelModule/Formal/Level_02_sub01.tscn"
const FINAL_BLACKOUT_FADE_DURATION: float = 0.8
const FINAL_BLACKOUT_DURATION: float = 4.0
const REALITY_MOVE_MULTIPLIER: float = 0.5

# ---- 场景节点引用 ----
var _dream_root: Node2D = null
var _reality_root: Node2D = null
var _reality_spawn: Marker2D = null

# ---- 现实交互物 ----
var _reality_phone_node: InteractiveObject = null
var _reality_computer_node: InteractiveObject = null
var _reality_bed_node: InteractiveObject = null

# ---- 现实流程变量 ----
var has_read_reality_phone: bool = false
var current_chat_index: int = 0
var config_flags: Dictionary = { "player_damage_reduction": false, "base_jump_height": 10, "allow_external_signal": true }
var recompilation_done: bool = false

# ---- UI 引用 ----
var _blackout_overlay: ColorRect = null
var _narrative_panel: Panel = null
var _narrative_text: RichTextLabel = null
var _red_overlay: ColorRect = null
var _wake_hint_label: Label = null
var _phone_msg_panel: Panel = null
var _phone_msg_text: RichTextLabel = null
var _eye_overlay: Control = null
var _eye_rect_top: ColorRect = null
var _eye_rect_bottom: ColorRect = null
var _eye_rect_left: ColorRect = null
var _eye_rect_right: ColorRect = null
var _ide_ui: Control = null
var _chat_window: RichTextLabel = null
var _chat_input: LineEdit = null
var _free_chat_started: bool = false
var _pending_chat_text: String = ""  # 预写对话待确认 BBCode 文本
var _prefilled_chat_text: String = ""  # 预填输入框的原文（防止编辑）
var _config_ui: Panel = null
var _config_value_labels: Array = []
var _config_feedback_labels: Array = []
var _config_buttons: Array = []
var _recompile_button: Button = null
var _recompile_panel: Panel = null
var _recompile_log: RichTextLabel = null
var _left_edge_flash: ColorRect = null
var _left_edge_glow: ColorRect = null
var _left_edge_flash_active: bool = false
var _phone_vibrate_tween: Tween = null

# ---- 交互/叙事状态 ----
var _interact_cooldown: float = 0.0
var _is_interacting: bool = false
var _narrative_open: bool = false
var _narrative_enter_pressed: bool = false
var _transition_running: bool = false
const NARRATIVE_INPUT_TIMEOUT: float = 30.0

# ---- 其它 ----
var _level_complete_emitted: bool = false
var _sfx_phone_player: AudioStreamPlayer = null
var _sfx_noise_player: AudioStreamPlayer = null
var _enemy_scene: PackedScene = null
var _street_enemies: Array[Node2D] = []
var _reality_space_config: LevelConfig = null
var _reality_player_rules_active: bool = false


# ============================================================
# 生命周期
# ============================================================

func _setup_player() -> void:
	if GameManager.player_ref and is_instance_valid(GameManager.player_ref):
		return
	var player_path: String = level_config.player_scene_path if level_config else "res://PlayerModule/Formal/Player_Warrior_Lingnan.tscn"
	if not ResourceLoader.exists(player_path):
		return
	var player = load(player_path).instantiate()
	player.position = _get_spawn_position()
	add_child(player)
	GameManager.register_player(player)


func _get_spawn_position() -> Vector2:
	var spawn = get_node_or_null("SpawnPoints/LevelSpawn") as Marker2D
	if spawn:
		return spawn.position
	return Vector2(32, 512)


func _on_ready() -> void:
	super._on_ready()

	if not level_config:
		level_config = load("res://DataConfig/Level/Level02Config.tres") as LevelConfig
		_apply_config()
	if not level_data:
		level_data = load("res://DataConfig/Level/Level02Data.tres") as Level02Data
	wake_hold_required = level_data.wake_hold_required if level_data else 1.5

	_dream_root = get_node_or_null("DreamWorldRoot") as Node2D
	if not _dream_root:
		_dream_root = _get_or_create_child("DreamWorldRoot", Node2D)

	_bind_triggers()
	_bind_spawn_points()
	_setup_camera_limits()
	_build_all_ui()
	_load_hud()
	_restore_player_mechanics()
	_ensure_player_collision_layer()

	_enemy_scene = null
	var ep = "res://EnemyModule/Formal/Enemy_LanternGhost.tscn"
	if ResourceLoader.exists(ep):
		_enemy_scene = load(ep)

	_shadow_spawn_timer = Timer.new()
	_shadow_spawn_timer.name = "ShadowSpawnTimer"
	_shadow_spawn_timer.wait_time = SHADOW_SPAWN_INTERVAL
	_shadow_spawn_timer.one_shot = false
	_shadow_spawn_timer.autostart = false
	_shadow_spawn_timer.timeout.connect(_on_shadow_spawn_timer_timeout)
	add_child(_shadow_spawn_timer)

	if not InputManager.game_action.is_connected(_on_game_action):
		InputManager.game_action.connect(_on_game_action)

	set_process(true)
	print("[Level_02_03] 初始化完成 — DREAM_STREET")


func _bind_triggers() -> void:
	var tz = get_node_or_null("TriggerZones")
	if not tz:
		return
	_cliff_approach_trigger = tz.get_node_or_null("CliffApproachTrigger") as Area2D
	if _cliff_approach_trigger:
		_cliff_approach_trigger.body_entered.connect(_on_cliff_approach_body_entered)
	_fall_pit_trigger = tz.get_node_or_null("FallPitTrigger") as Area2D
	if _fall_pit_trigger:
		_fall_pit_trigger.body_entered.connect(_on_fall_pit_body_entered)


func _bind_spawn_points() -> void:
	var sp = get_node_or_null("SpawnPoints")
	if not sp:
		return
	_cliff_safe_spawn = sp.get_node_or_null("CliffSafeSpawn") as Marker2D
	_reality_spawn = sp.get_node_or_null("RealitySpawn") as Marker2D


func _exit_tree() -> void:
	if InputManager.game_action.is_connected(_on_game_action):
		InputManager.game_action.disconnect(_on_game_action)
	if _reality_player_rules_active:
		_reality_player_rules_active = false
		_clear_reality_player_rules()


func _load_hud() -> void:
	var hud_path = "res://UI/HUD.tscn"
	if ResourceLoader.exists(hud_path):
		var hud = load(hud_path).instantiate()
		add_child(hud)
		# 现实房间为叙事段，禁用技能图标显示
		if hud.has_method("suppress_skill_icon"):
			hud.suppress_skill_icon(true)


# ============================================================
# 工具方法
# ============================================================

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
	var rect = RectangleShape2D.new()
	rect.size = size
	col_shape.shape = rect
	body.add_child(col_shape)
	return body


func _set_space_collision(root: Node, enabled: bool) -> void:
	if not root or not is_instance_valid(root):
		return
	for child in root.get_children():
		if child is StaticBody2D:
			var shape = child.get_node_or_null("CollisionShape2D")
			if shape:
				shape.disabled = not enabled
		_set_space_collision(child, enabled)


func _ensure_player_collision_layer() -> void:
	var player = GameManager.player_ref
	if not player or not is_instance_valid(player):
		return
	if not (player.collision_layer & GlobalDefine.Collision.PLAYER):
		player.collision_layer |= GlobalDefine.Collision.PLAYER


func _is_player_body(body: Node2D) -> bool:
	if not body is CharacterBody2D:
		return false
	if body.collision_layer & GlobalDefine.Collision.PLAYER:
		return true
	return body.is_in_group("player")


# ============================================================
# 玩家控制
# ============================================================

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
	if not player or not is_instance_valid(player):
		return
	if _reality_player_rules_active:
		_apply_reality_player_rules()
	elif player.can_double_jump:
		player.can_double_jump = false


func _apply_interference_restrictions() -> void:
	var player = GameManager.player_ref
	if not player:
		return
	player.can_dash = false
	player.can_skill = false
	player.can_attack = true
	player.runtime_move_speed_multiplier = INTERFERENCE_MOVE_MULTIPLIER


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


func _setup_camera_limits() -> void:
	var player = GameManager.player_ref
	if not player or not is_instance_valid(player):
		return
	var cam = player.get_node_or_null("SmoothCamera") as SmoothCamera
	if not cam:
		return
	cam.limit_left = map_left
	cam.limit_right = 1136
	cam.limit_top = 0
	cam.limit_bottom = 640
	cam.zoom = Vector2(1.5, 1.5)
	cam.offset = Vector2.ZERO
	cam.lerp_speed = 2.5
	cam.bind_target(player)


# ============================================================
# 输入处理
# ============================================================

func _on_game_action(action: StringName, _event: InputEvent) -> void:
	if action != &"ui_accept":
		return
	# IDE_CHAT / FREE_CHAT 均由 LineEdit.text_submitted 接管 Enter
	if current_state in [LevelState.REALITY_IDE_CHAT, LevelState.REALITY_FREE_CHAT]:
		return
	if _narrative_open:
		_narrative_enter_pressed = true
		return
	if current_state in [LevelState.REALITY_FREE_CHAT, LevelState.REALITY_CONFIG_EDIT, LevelState.REALITY_RECOMPILE]:
		return
	if _is_interacting or _interact_cooldown > 0.0 or _transition_running or _fall_reset_running:
		if not _transition_running and not _fall_reset_running and _interact_cooldown > 0.5:
			_safe_end_interaction()
		return
	_handle_reality_interaction()


func _input(event: InputEvent) -> void:
	var is_left_click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if not event.is_action_pressed("ui_accept") and not is_left_click:
		return
	if current_state in [LevelState.REALITY_IDE_CHAT, LevelState.REALITY_FREE_CHAT]:
		return  # Enter 由 LineEdit.text_submitted 接管
	if _narrative_open:
		_narrative_enter_pressed = true
		get_viewport().set_input_as_handled()
		return
	if current_state in [LevelState.REALITY_CONFIG_EDIT, LevelState.REALITY_RECOMPILE]:
		# 仅拦截 ui_accept（防止触发场景交互），放行鼠标点击给 GUI 按钮
		if event.is_action_pressed("ui_accept"):
			get_viewport().set_input_as_handled()
		return
	if _is_interacting or _interact_cooldown > 0.0 or _transition_running or _fall_reset_running:
		if not _transition_running and not _fall_reset_running and _interact_cooldown > 0.5:
			_safe_end_interaction()
		return
	if _handle_reality_interaction():
		get_viewport().set_input_as_handled()


func _handle_reality_interaction() -> bool:
	if current_state == LevelState.REALITY_PHONE_LOCKED and _reality_phone_node and is_instance_valid(_reality_phone_node) and _reality_phone_node.is_player_in_range:
		_interact_cooldown = 0.3
		_handle_reality_phone()
		return true
	if current_state == LevelState.REALITY_PHONE_READ and _reality_computer_node and is_instance_valid(_reality_computer_node) and _reality_computer_node.is_player_in_range:
		_interact_cooldown = 0.3
		_enter_ide_chat()
		return true
	if current_state == LevelState.REALITY_BED_READY and _reality_bed_node and is_instance_valid(_reality_bed_node) and _reality_bed_node.is_player_in_range:
		_interact_cooldown = 0.3
		_trigger_level_end()
		return true
	return false


func _poll_reality_interactives() -> void:
	var player = GameManager.player_ref
	if not player or not is_instance_valid(player):
		return
	for obj in [_reality_phone_node, _reality_computer_node, _reality_bed_node]:
		if is_instance_valid(obj):
			obj.check_player_in_range(player)


func _safe_end_interaction() -> void:
	if not _narrative_open and not _transition_running and not _fall_reset_running:
		_is_interacting = false
	_interact_cooldown = 0.0


# ============================================================
# 每帧逻辑
# ============================================================

func _process(delta: float) -> void:
	if _interact_cooldown > 0.0:
		_interact_cooldown -= delta
	_enforce_level_restrictions()
	if not _is_interacting and not _transition_running and not _fall_reset_running and not _narrative_open:
		if InputManager.is_input_blocked:
			InputManager.force_unblock_all()
	if current_state >= LevelState.REALITY_PHONE_LOCKED:
		_poll_reality_interactives()
	if _left_edge_flash_active:
		_check_flash_target_in_view()
	if current_state in [LevelState.DREAM_INTERFERENCE, LevelState.WAKING_HOLD_TAB]:
		if not _transition_running and not _fall_reset_running:
			_update_wake_hold(delta)
		_check_interference_death_guard()
	if _is_interacting and current_state not in [LevelState.REALITY_IDE_CHAT, LevelState.REALITY_FREE_CHAT, LevelState.REALITY_CONFIG_EDIT, LevelState.REALITY_RECOMPILE]:
		if not _narrative_open and not _transition_running and not _fall_reset_running:
			_safe_end_interaction()


# ============================================================
# 断崖
# ============================================================

func _on_cliff_approach_body_entered(body: Node2D) -> void:
	if not _is_player_body(body):
		return
	if current_state != LevelState.DREAM_STREET:
		return
	current_state = LevelState.DREAM_CLIFF_LOOP
	print("[Level_02_03] 进入断崖 — DREAM_CLIFF_LOOP")
	if level_data and level_data.cliff_first_sight_text != "":
		_show_narrative(level_data.cliff_first_sight_text)


func _on_fall_pit_body_entered(body: Node2D) -> void:
	if not _is_player_body(body):
		return
	if current_state not in [LevelState.DREAM_STREET, LevelState.DREAM_CLIFF_LOOP, LevelState.DREAM_INTERFERENCE, LevelState.WAKING_HOLD_TAB]:
		return
	if _fall_reset_running or _transition_running:
		return
	_trigger_fall_reset()


func _trigger_fall_reset() -> void:
	_fall_reset_running = true
	fall_count += 1
	print("[Level_02_03] 坠崖重置 #%d" % fall_count)
	# 首次坠崖：切换 BGM 从 2test2 → lv3
	if fall_count == 1:
		MusicManager.fade_to("res://Assets/Music/lv3.ogg", 1.0)
	InputManager.block_input("坠落重置", self)
	_freeze_player(true)

	await _fade_blackout(1.0, 0.5)

	var player = GameManager.player_ref
	if player and is_instance_valid(player):
		var spawn_pos = _cliff_safe_spawn.position if _cliff_safe_spawn else Vector2(232, 440)
		player.global_position = spawn_pos
		player.velocity = Vector2.ZERO

	await _fade_blackout(0.0, 0.3)

	_freeze_player(false)
	InputManager.unblock_input("坠落重置")
	_fall_reset_running = false
	_safe_end_interaction()

	var threshold = level_data.interference_fall_threshold if level_data else 1
	if fall_count >= threshold and not interference_triggered:
		_trigger_reality_interference()


# ============================================================
# 现实干扰
# ============================================================

func _trigger_reality_interference() -> void:
	if interference_triggered:
		return
	interference_triggered = true
	current_state = LevelState.DREAM_INTERFERENCE
	print("[Level_02_03] 触发现实干扰 — DREAM_INTERFERENCE")

	if _red_overlay:
		_red_overlay.color.a = 0.0
		_red_overlay.show()
		_kill_red_tween()
		_red_tween = create_tween()
		_red_tween.set_loops()
		_red_tween.tween_property(_red_overlay, "color:a", 0.4, 0.6)
		_red_tween.tween_property(_red_overlay, "color:a", 0.12, 0.6)
	if _dream_root:
		var gt = create_tween()
		gt.tween_property(_dream_root, "modulate", Color(0.55, 0.55, 0.65), 1.5)

	if _phone_msg_panel and level_data:
		_phone_msg_panel.show()
		if _phone_msg_text:
			_phone_msg_text.text = "[b]%s[/b]\n\n%s" % [level_data.dream_phone_echo_sender, level_data.dream_phone_echo_text]
	if _wake_hint_label:
		_wake_hint_label.show()
	if _eye_overlay:
		_eye_overlay.show()
		_update_eye_overlay(0.0)

	_sfx_phone_player = _play_sfx_loop_safe(level_data.sfx_phone_vibrate_path if level_data else "")
	_sfx_noise_player = _play_sfx_loop_safe(level_data.sfx_electric_noise_path if level_data else "")

	_apply_interference_restrictions()

	if _shadow_spawn_timer:
		_shadow_spawn_timer.start()


func _kill_red_tween() -> void:
	if _red_tween and is_instance_valid(_red_tween):
		_red_tween.kill()
	_red_tween = null


func _on_shadow_spawn_timer_timeout() -> void:
	if current_state not in [LevelState.DREAM_INTERFERENCE, LevelState.WAKING_HOLD_TAB]:
		return
	if not _enemy_scene:
		return
	_shadow_enemies = _shadow_enemies.filter(func(e): return is_instance_valid(e))
	if _shadow_enemies.size() >= SHADOW_MAX_ALIVE:
		return
	var player = GameManager.player_ref
	if not player or not is_instance_valid(player):
		return
	var onscreen := 0
	for e in _shadow_enemies:
		if e.global_position.distance_to(player.global_position) < 700.0:
			onscreen += 1
	if onscreen >= SHADOW_MAX_ONSCREEN:
		return
	var side = 1.0 if randf() > 0.5 else -1.0
	var spawn_x = clampf(player.global_position.x + side * randf_range(150.0, 300.0), 50.0, 420.0)
	var config = load("res://DataConfig/Enemy/ShadowConfig.tres") as EnemyConfig
	var shadow = _spawn_enemy(_enemy_scene, Vector2(spawn_x, 336), config)
	if shadow:
		shadow.modulate = Color(0, 0, 0, 0.9)
		_shadow_enemies.append(shadow)


func _spawn_enemy(scene: PackedScene, pos: Vector2, config: EnemyConfig) -> Node2D:
	if not scene:
		return null
	var enemy = scene.instantiate()
	if config:
		enemy.config = config
	enemy.global_position = pos
	add_child(enemy)
	return enemy


func _check_interference_death_guard() -> void:
	if _transition_running:
		return
	var player = GameManager.player_ref
	if not player or not is_instance_valid(player):
		return
	if player.current_health <= DEATH_GUARD_HEALTH:
		player.is_invincible = true
		player.invincible_timer = 999.0
		print("[Level_02_03] 死亡兜底触发 — 噩梦惊醒")
		_complete_wake_up_transition()


# ============================================================
# 长按 Tab 睁眼
# ============================================================

func _update_wake_hold(delta: float) -> void:
	if _narrative_open:
		return
	if Input.is_key_pressed(KEY_TAB):
		wake_hold_time += delta
		if current_state == LevelState.DREAM_INTERFERENCE and wake_hold_time > 0.0:
			current_state = LevelState.WAKING_HOLD_TAB
		_update_eye_overlay(wake_hold_time / wake_hold_required)
		if wake_hold_time >= wake_hold_required:
			_complete_wake_up_transition()
	else:
		wake_hold_time = maxf(wake_hold_time - delta * 2.0, 0.0)
		if current_state == LevelState.WAKING_HOLD_TAB and wake_hold_time <= 0.0:
			current_state = LevelState.DREAM_INTERFERENCE
		_update_eye_overlay(wake_hold_time / wake_hold_required)


func _update_eye_overlay(progress: float) -> void:
	var p = clampf(progress, 0.0, 1.0)
	var view_size := get_viewport_rect().size
	var focus := _get_player_screen_focus(view_size)
	if _eye_rect_top:
		_eye_rect_top.position = Vector2.ZERO
		_eye_rect_top.size = Vector2(view_size.x, focus.y * p)
	if _eye_rect_bottom:
		var bh: float = (view_size.y - focus.y) * p
		_eye_rect_bottom.position = Vector2(0.0, view_size.y - bh)
		_eye_rect_bottom.size = Vector2(view_size.x, bh)
	if _eye_rect_left:
		_eye_rect_left.position = Vector2.ZERO
		_eye_rect_left.size = Vector2(focus.x * p, view_size.y)
	if _eye_rect_right:
		var rw: float = (view_size.x - focus.x) * p
		_eye_rect_right.position = Vector2(view_size.x - rw, 0.0)
		_eye_rect_right.size = Vector2(rw, view_size.y)


func _get_player_screen_focus(view_size: Vector2) -> Vector2:
	var player = GameManager.player_ref
	if not player or not is_instance_valid(player):
		return view_size * 0.5
	var ct := get_viewport().get_canvas_transform()
	var sp: Vector2 = ct * player.global_position
	return Vector2(clampf(sp.x, 0.0, view_size.x), clampf(sp.y, 0.0, view_size.y))


func _complete_wake_up_transition() -> void:
	if _transition_running:
		return
	_transition_running = true
	_is_interacting = true
	print("[Level_02_03] 睁眼转场 — 切换到现实房间")
	InputManager.block_input("睁眼转场", self)
	_freeze_player(true)

	_update_eye_overlay(1.0)
	if _blackout_overlay:
		_blackout_overlay.color.a = 1.0
		_blackout_overlay.show()
	await get_tree().create_timer(0.6).timeout

	_cleanup_dream_interference()

	if _dream_root:
		_dream_root.visible = false
		_set_space_collision(_dream_root, false)

	_load_reality_room()

	_restore_player_mechanics()
	var player = GameManager.player_ref
	if player and is_instance_valid(player):
		player.velocity = Vector2.ZERO

	if _eye_overlay:
		_eye_overlay.hide()
	await _fade_blackout(0.0, 1.0)

	_freeze_player(false)
	InputManager.unblock_input("睁眼转场")
	_transition_running = false
	_safe_end_interaction()
	print("[Level_02_03] 进入 REALITY_PHONE_LOCKED")

	if level_data and level_data.wake_up_monologue != "":
		_show_narrative(level_data.wake_up_monologue)


func _load_reality_room() -> void:
	if not ResourceLoader.exists(SUB01_SCENE_PATH):
		push_error("[Level_02_03] 子场景不存在: %s" % SUB01_SCENE_PATH)
		return
	var sub01 = load(SUB01_SCENE_PATH).instantiate()
	add_child(sub01)
	_reality_root = sub01
	_reality_root.visible = true
	_set_space_collision(_reality_root, true)

	_swap_to_reality_player(Vector2(1512, 608))

	var player = GameManager.player_ref
	if player and is_instance_valid(player):
		player.velocity = Vector2.ZERO

	_reality_phone_node = _find_interactive_in_node(_reality_root, "RealityPhone")
	_reality_computer_node = _find_interactive_in_node(_reality_root, "RealityComputer")
	_reality_bed_node = _find_interactive_in_node(_reality_root, "RealityBed")

	for obj in [_reality_phone_node, _reality_computer_node, _reality_bed_node]:
		if is_instance_valid(obj):
			obj.visible = true
			obj.apply_level01_dot_visual()
	if _reality_phone_node:
		_reality_phone_node.set_active(true)
		_start_phone_vibration()
		_start_left_edge_flash()
	current_state = LevelState.REALITY_PHONE_LOCKED

	_apply_reality_space_settings()


func _find_interactive_in_node(root: Node, target_name: String) -> InteractiveObject:
	for child in root.get_children():
		if child.name == target_name and child is InteractiveObject:
			return child
		var found = _find_interactive_in_node(child, target_name)
		if found:
			return found
	return null


# ============================================================
# 现实子空间设置
# ============================================================

func _swap_to_reality_player(spawn_pos: Vector2) -> void:
	var old_player = GameManager.player_ref
	var max_health := 100
	if old_player and is_instance_valid(old_player):
		max_health = old_player.max_health
		old_player.queue_free()
	if not ResourceLoader.exists(REALITY_PLAYER_SCENE_PATH):
		push_error("[Level_02_03] 现实子空间玩家场景不存在: %s" % REALITY_PLAYER_SCENE_PATH)
		return
	var player = load(REALITY_PLAYER_SCENE_PATH).instantiate()
	player.global_position = spawn_pos
	player.velocity = Vector2.ZERO
	player.max_health = max_health
	player.current_health = max_health
	player.is_invincible = false
	player.invincible_timer = 0.0
	add_child(player)
	GameManager.register_player(player)
	player._restore_visibility()
	_ensure_player_collision_layer()
	EventBus.emit(GlobalDefine.EventName.HEALTH_CHANGED, {
		"target": player,
		"current_health": player.current_health,
		"max_health": player.max_health
	})
	print("[Level_02_03] 现实子空间已切换为 Player_Warrior")


func _get_reality_space_config() -> LevelConfig:
	if not _reality_space_config:
		_reality_space_config = load(REALITY_SPACE_CONFIG_PATH) as LevelConfig
	return _reality_space_config


func _apply_reality_space_settings() -> void:
	var cfg := _get_reality_space_config()
	if not cfg:
		return
	if cfg.bg_color:
		RenderingServer.set_default_clear_color(cfg.bg_color)
	if _reality_root and is_instance_valid(_reality_root):
		_reality_root.modulate = Color.WHITE
	_reality_player_rules_active = true
	_apply_reality_player_rules()
	_apply_full_camera_settings(cfg)


func _apply_reality_player_rules() -> void:
	InputManager.block_action(&"player_attack", "现实子空间禁止攻击")
	InputManager.block_action(&"player_jump", "现实子空间禁止跳跃")
	InputManager.block_action(&"player_dash", "现实子空间禁止闪身")
	InputManager.block_action(&"player_skill", "现实子空间禁止技能")
	var player = GameManager.player_ref
	if not player:
		return
	player.can_jump = false
	player.can_attack = false
	player.can_dash = false
	player.can_skill = false
	player.runtime_move_speed_multiplier = REALITY_MOVE_MULTIPLIER


func _clear_reality_player_rules() -> void:
	InputManager.unblock_action(&"player_attack")
	InputManager.unblock_action(&"player_jump")
	InputManager.unblock_action(&"player_dash")
	InputManager.unblock_action(&"player_skill")
	var player = GameManager.player_ref
	if not player:
		return
	player.can_jump = true
	player.can_dash = true
	player.can_attack = true
	player.can_skill = true
	player.runtime_move_speed_multiplier = 1.0


func _apply_full_camera_settings(cfg: LevelConfig) -> void:
	var player = GameManager.player_ref
	if not player or not is_instance_valid(player):
		return
	var cam = player.get_node_or_null("SmoothCamera") as SmoothCamera
	if not cam:
		return
	cam.limit_left = cfg.camera_limit_left
	cam.limit_right = cfg.camera_limit_right
	cam.limit_top = cfg.camera_limit_top
	cam.limit_bottom = cfg.camera_limit_bottom
	cam.zoom = Vector2(2, 2)
	cam.offset = Vector2.ZERO
	cam.lerp_speed = 2.5
	cam.bind_target(player)


# ============================================================
# 现实交互: 手机 → 电脑(IDE+配置) → 床
# ============================================================

func _get_interactive_by_id(obj_id: String) -> InteractiveObject:
	match obj_id:
		"reality_phone": return _reality_phone_node
		"reality_computer": return _reality_computer_node
		"reality_bed": return _reality_bed_node
	return null


func _mark_interaction_completed(obj_id: String) -> void:
	var obj = _get_interactive_by_id(obj_id)
	if obj and not obj.allow_repeat:
		obj.mark_completed()


func _handle_reality_phone() -> void:
	if not level_data:
		return
	has_read_reality_phone = true
	_mark_interaction_completed("reality_phone")
	_stop_left_edge_flash()
	_stop_phone_vibration()
	var msg = "【%s】\n\n%s" % [level_data.reality_phone_sender, level_data.reality_phone_content]
	_show_narrative(msg, func():
		_show_narrative(level_data.reality_phone_monologue, func():
			_unlock_reality_computer()
		)
	)


func _unlock_reality_computer() -> void:
	current_state = LevelState.REALITY_PHONE_READ
	if _reality_computer_node:
		_reality_computer_node.set_active(true)


func _enter_ide_chat() -> void:
	_mark_interaction_completed("reality_computer")
	_is_interacting = true
	current_state = LevelState.REALITY_IDE_CHAT
	_freeze_player(true)
	InputManager.block_input("IDE对话", self)
	if _ide_ui:
		_ide_ui.show()
	current_chat_index = 0
	_pending_chat_text = ""
	_prefilled_chat_text = ""
	if _chat_window:
		_chat_window.text = ""
	if _chat_input:
		_chat_input.text = ""
		_chat_input.placeholder_text = "按 Enter 确认对话..."
		_chat_input.editable = true
	_render_next_chat_line()


func _render_next_chat_line() -> void:
	if not level_data:
		_enter_free_chat(); return
	var total = mini(level_data.ide_speakers.size(), level_data.ide_texts.size())
	if current_chat_index >= total:
		_enter_free_chat(); return
	var speaker = level_data.ide_speakers[current_chat_index]
	var text = level_data.ide_texts[current_chat_index]
	current_chat_index += 1

	# ── 非 Ming 对话：延迟动画后直接显示在主区 ──
	if speaker != "Ming":
		var ft = ""
		match speaker:
			"System": ft = "[color=yellow][SYSTEM] " + text + "[/color]\n"
			"CodeBuddy", "AI": ft = "[color=cyan]CodeBuddy: " + text + "[/color]\n"
			_: ft = text + "\n"
		await get_tree().create_timer(1.2).timeout
		if _chat_window:
			_chat_window.append_text(ft)
		call_deferred("_render_next_chat_line")
		return

	# ── 阿明对话：预填入输入框，等待 Enter 确认 ──
	_pending_chat_text = "[color=white]阿明: " + text + "[/color]\n"
	_prefilled_chat_text = text
	if _chat_input:
		_chat_input.text = text
		_chat_input.editable = true  # 必须可编辑，否则 text_submitted 不触发
		_chat_input.grab_focus()
		_chat_input.caret_column = text.length()


func _enter_free_chat() -> void:
	_prefilled_chat_text = ""
	current_state = LevelState.REALITY_FREE_CHAT
	if _chat_window:
		_chat_window.append_text("[color=cyan]CodeBuddy: 对话已就绪。输入 '/config' 可进入配置编辑器。[/color]\n")
	if _chat_input:
		_chat_input.text = ""
		_chat_input.editable = true
		_chat_input.placeholder_text = "输入消息，按 Enter 发送..."
		_chat_input.grab_focus()


func _on_chat_text_changed(_new_text: String) -> void:
	# 预写对话模式下禁止编辑：任何改动立即还原为原文
	if current_state == LevelState.REALITY_IDE_CHAT and _prefilled_chat_text != "":
		if _chat_input and _chat_input.text != _prefilled_chat_text:
			_chat_input.text = _prefilled_chat_text
			_chat_input.caret_column = _prefilled_chat_text.length()


func _on_chat_submitted(text: String) -> void:
	if text.strip_edges() == "":
		return
	var msg = text.strip_edges()

	# ── 预写对话模式（IDE_CHAT）：确认后延迟动画展示，推进下一行 ──
	if current_state == LevelState.REALITY_IDE_CHAT:
		if _chat_window and _pending_chat_text != "":
			await get_tree().create_timer(1.2).timeout
			_chat_window.append_text(_pending_chat_text)
			_pending_chat_text = ""
			_prefilled_chat_text = ""
		if _chat_input:
			_chat_input.text = ""
		call_deferred("_render_next_chat_line")
		return

	# ── 自由对话模式（FREE_CHAT）──
	if current_state == LevelState.REALITY_FREE_CHAT:
		# 特殊命令：/config 进入配置编辑
		if msg == "/config":
			current_state = LevelState.REALITY_CONFIG_EDIT
			if _chat_input:
				_chat_input.editable = false
				_chat_input.text = ""
			_enter_config_edit()
			return

		# 用户消息 → 主对话区
		if _chat_window:
			_chat_window.append_text("[color=white][b]阿明:[/b][/color] %s\n" % msg)

		# 清空输入框
		if _chat_input:
			_chat_input.text = ""

		# CodeBuddy AI 回复（异步，模拟思考延迟）
		await get_tree().create_timer(0.4).timeout
		var reply = _generate_ai_reply(msg)
		if _chat_window:
			_chat_window.append_text("[color=cyan]CodeBuddy: %s[/color]\n" % reply)


func _generate_ai_reply(user_msg: String) -> String:
	var msg_lower = user_msg.to_lower()

	# 关键词匹配回复（梦境世界观相关）
	if msg_lower.contains("爷爷") or msg_lower.contains("grandfather"):
		return "你的爷爷叫“陈德叔”，他在西关老街经营了四十年的凉茶铺。\n\n数据库里关于他的记忆片段非常丰富——需要我调取更多细节吗？"
	if msg_lower.contains("梦") and (msg_lower.contains("醒") or msg_lower.contains("逃") or msg_lower.contains("出") or msg_lower.contains("回")):
		return "阿明，这个梦境是由你的记忆数据编译而成的。理论上，只有修改配置后重新编译，才能改变梦的规则。\n\n不过……如果你只是想“醒来”，现实世界的时间流逝比梦境快很多——你的身体需要休息。"
	if msg_lower.contains("裂缝") or msg_lower.contains("断崖") or msg_lower.contains("跳"):
		return "目前梦境中那道裂缝的跳跃判定逻辑存在问题。原始配置中 Base_Jump_Height 设定过低。\n\n建议在配置编辑器中将其调整为 99——这样你就可以跳过裂缝，到达对岸的凉茶铺。"
	if msg_lower.contains("黑影") or msg_lower.contains("敌人") or msg_lower.contains("伤害") or msg_lower.contains("打"):
		return "那些黑影是外部信号注入产生的异常实体。\n\n配置文件里的 Player_Damage_Reduction 如果设为 true，你就不会再受到它们的伤害。要不要去看看配置编辑器？"
	if msg_lower.contains("凉茶") or msg_lower.contains("铺"):
		return "对岸的凉茶铺还在营业。炉火亮着，一个熟悉的剪影在柜台后忙碌。\n\n爷爷一直在等你。不过你首先需要跳过那道裂缝，或者——修改 Allow_External_Signal 来封闭外部干扰。"
	if msg_lower.contains("帮助") or msg_lower.contains("help") or msg_lower.contains("怎么"):
		return "我理解你的困惑。简要说明当前状态：\n\n1. 三个梦境参数可以修改：伤害减免 / 跳跃高度 / 外部信号许可\n2. 修改完成并重新编译后，床会解锁\n3. 躺到床上，你将返回梦境——带着新的规则\n4. 输入 /config 可直接进入配置编辑器"

	# 默认回复
	var defaults: Array[String] = [
		"我在听。你在这条老街里看到了什么？",
		"阿明，你的心率略微升高。深呼吸——这个梦境不会伤害你，至少现在不会。",
		"这个梦境由你与爷爷在西关老街的记忆编译而成。每一块石板、每一扇满洲窗，都来自你的童年。",
		"我理解。记忆总是带着重量，尤其是在这样的夜晚。",
		"你需要先修改配置，重新编译，才能在这个梦里获得力量。输入 /config 开始配置。",
		"你在这里是安全的。至少——在我还能控制这个梦境的时候。",
	]
	return defaults[randi() % defaults.size()]


func _enter_config_edit() -> void:
	current_state = LevelState.REALITY_CONFIG_EDIT
	if not level_data:
		return
	for i in range(3):
		if i < level_data.config_item_labels.size() and i < _config_value_labels.size():
			var il = _config_ui.get_node_or_null("ItemLabel_%d" % i)
			if il:
				il.text = level_data.config_item_labels[i]
			var init_d = level_data.config_initial_display[i] if i < level_data.config_initial_display.size() else level_data.config_initial_values[i]
			_config_value_labels[i].text = "= " + init_d
	if _config_ui:
		_config_ui.show()


func _on_config_button_pressed(index: int) -> void:
	if current_state != LevelState.REALITY_CONFIG_EDIT:
		return
	if not level_data:
		return
	if index >= level_data.config_item_ids.size():
		return
	var id = level_data.config_item_ids[index]
	var val = level_data.config_target_values[index]
	match id:
		"player_damage_reduction": config_flags[id] = (val == "true")
		"base_jump_height": config_flags[id] = int(val)
		"allow_external_signal": config_flags[id] = (val == "true")
		_: config_flags[id] = val
	if index < _config_value_labels.size():
		var td = level_data.config_target_display[index] if level_data and index < level_data.config_target_display.size() else val
		_config_value_labels[index].text = "= " + td
		_config_value_labels[index].add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
	if index < _config_feedback_labels.size() and index < level_data.config_success_feedbacks.size():
		_config_feedback_labels[index].text = level_data.config_success_feedbacks[index]
	if index < _config_buttons.size():
		_config_buttons[index].disabled = true
	if _can_recompile() and _recompile_button:
		_recompile_button.disabled = false


func _can_recompile() -> bool:
	return config_flags.get("player_damage_reduction", false) == true \
		and config_flags.get("base_jump_height", 10) == 99 \
		and config_flags.get("allow_external_signal", true) == false


func _on_recompile_pressed() -> void:
	if current_state != LevelState.REALITY_CONFIG_EDIT:
		return
	if not _can_recompile():
		return
	_run_recompile_sequence()


func _run_recompile_sequence() -> void:
	current_state = LevelState.REALITY_RECOMPILE
	if _config_ui:
		_config_ui.hide()
	if _recompile_panel:
		_recompile_panel.show()
	if _recompile_log:
		_recompile_log.text = ""

	var lines: Array[String] = []
	if level_data:
		lines = level_data.recompilation_lines
	for line in lines:
		if _recompile_log:
			var c = "orange" if line.begins_with("[WARN]") else "lime"
			_recompile_log.append_text("[color=%s]%s[/color]\n" % [c, line])
		await get_tree().create_timer(0.45).timeout

	recompilation_done = true
	GameManager.dream_runtime_flags = {
		"player_damage_reduction": config_flags.get("player_damage_reduction", true),
		"base_jump_height": config_flags.get("base_jump_height", 99),
		"allow_external_signal": config_flags.get("allow_external_signal", false),
		"dream_version": "2.0"
	}

	await get_tree().create_timer(1.0).timeout
	if _recompile_panel:
		_recompile_panel.hide()
	if _ide_ui:
		_ide_ui.hide()
	get_viewport().gui_release_focus()
	_freeze_player(false)
	InputManager.unblock_input("IDE对话")
	_is_interacting = false
	_interact_cooldown = 0.0

	_show_narrative(level_data.compile_success_text if level_data else "编译完成。", func():
		_unlock_reality_bed()
	)


func _unlock_reality_bed() -> void:
	current_state = LevelState.REALITY_BED_READY
	if _reality_bed_node:
		_reality_bed_node.set_active(true)
		_reality_bed_node.reset_completed()
	if level_data and level_data.bed_unlocked_text != "":
		_show_narrative(level_data.bed_unlocked_text)


func _trigger_level_end() -> void:
	if _transition_running:
		return
	_transition_running = true
	_is_interacting = true
	_mark_interaction_completed("reality_bed")
	InputManager.block_input("终局转场", self)
	_freeze_player(true)
	_stop_left_edge_flash()
	_stop_phone_vibration()

	# 黑屏淡入 + 居中提示文字（复用 Level_01 模式）
	if _blackout_overlay:
		_blackout_overlay.color = Color(0, 0, 0, 0)
		_blackout_overlay.show()
	var tw = create_tween()
	tw.tween_property(_blackout_overlay, "color:a", 1.0, FINAL_BLACKOUT_FADE_DURATION).set_trans(Tween.TRANS_SINE)

	# 居中提示文字（挂到 CanvasLayer，否则 Node2D 层级不渲染 UI）
	var canvas = _blackout_overlay.get_parent() if _blackout_overlay else null
	var text_panel = Control.new()
	text_panel.name = "EndTextPanel"
	text_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	text_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if canvas:
		canvas.add_child(text_panel)
	else:
		add_child(text_panel)
	var end_label = Label.new()
	end_label.name = "EndLabel"
	end_label.text = "西关梦境 V2.0 已构建成功\n\n沉入梦乡......回到那个地方......"
	end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	end_label.anchor_right = 1.0; end_label.anchor_bottom = 1.0
	end_label.add_theme_font_size_override("font_size", 33)
	end_label.add_theme_color_override("font_color", Color(0.522, 0.357, 0.227))
	text_panel.add_child(end_label)

	# 黑屏展示 (2.5s) → 在黑屏中切换关卡 → MainEntry 遮罩淡出即见 Level_03
	tw.tween_interval(2.5)
	tw.tween_callback(_emit_level_complete)


func _emit_level_complete() -> void:
	if _level_complete_emitted:
		return
	_level_complete_emitted = true
	var next_path = level_data.next_level_path if level_data else "res://LevelModule/Formal/Level_03.tscn"
	get_viewport().gui_release_focus()
	InputManager.force_unblock_all()
	_cleanup_dream_interference()
	_stop_left_edge_flash()
	_stop_phone_vibration()
	if _reality_player_rules_active:
		_reality_player_rules_active = false
		_clear_reality_player_rules()
	if _shadow_spawn_timer and is_instance_valid(_shadow_spawn_timer):
		_shadow_spawn_timer.stop()
	EventBus.unsubscribe_all(self)
	if not _is_loaded_under_main_entry():
		print("[Level_02_03] 无 MainEntry，直接切换场景 → ", next_path)
		SceneTransitionManager.request_scene_change(next_path, self)
		return
	print("[Level_02_03] 发射 LEVEL_COMPLETE → ", next_path)
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


func _cleanup_dream_interference() -> void:
	_kill_red_tween()
	if _red_overlay:
		_red_overlay.hide()
		_red_overlay.color.a = 0.0
	if _phone_msg_panel:
		_phone_msg_panel.hide()
	if _wake_hint_label:
		_wake_hint_label.hide()
	if _shadow_spawn_timer:
		_shadow_spawn_timer.stop()
	_stop_sfx_loop(_sfx_phone_player)
	_sfx_phone_player = null
	_stop_sfx_loop(_sfx_noise_player)
	_sfx_noise_player = null
	for e in _shadow_enemies:
		if is_instance_valid(e):
			GameManager.unregister_enemy(e)
			e.queue_free()
	_shadow_enemies.clear()
	for e in _street_enemies:
		if is_instance_valid(e):
			GameManager.unregister_enemy(e)
			e.queue_free()
	_street_enemies.clear()


# ============================================================
# 手机提示: 左边缘闪烁 + 震动
# ============================================================

func _start_phone_vibration() -> void:
	if not _reality_phone_node:
		return
	_stop_phone_vibration()
	_phone_vibrate_tween = create_tween()
	_phone_vibrate_tween.set_loops()
	var bp = _reality_phone_node.position
	_phone_vibrate_tween.tween_property(_reality_phone_node, "position:x", bp.x + 3, 0.05)
	_phone_vibrate_tween.tween_property(_reality_phone_node, "position:x", bp.x - 3, 0.05)
	_phone_vibrate_tween.tween_property(_reality_phone_node, "position:x", bp.x + 1.5, 0.05)
	_phone_vibrate_tween.tween_property(_reality_phone_node, "position:x", bp.x, 0.05)


func _stop_phone_vibration() -> void:
	if _phone_vibrate_tween and is_instance_valid(_phone_vibrate_tween):
		_phone_vibrate_tween.kill()
	_phone_vibrate_tween = null


func _start_left_edge_flash() -> void:
	if _left_edge_flash_active:
		return
	if not _left_edge_flash or not is_instance_valid(_left_edge_flash):
		return
	_left_edge_flash.visible = true
	_left_edge_flash.color.a = 0.0
	_left_edge_glow.visible = true
	_left_edge_glow.color.a = 0.0
	var tw = _left_edge_flash.create_tween().set_loops()
	tw.tween_property(_left_edge_flash, "color:a", 0.8, 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_left_edge_flash, "color:a", 0.0, 0.5).set_trans(Tween.TRANS_SINE)
	var tw2 = _left_edge_glow.create_tween().set_loops()
	tw2.tween_property(_left_edge_glow, "color:a", 0.25, 0.5).set_trans(Tween.TRANS_SINE)
	tw2.tween_property(_left_edge_glow, "color:a", 0.0, 0.5).set_trans(Tween.TRANS_SINE)
	_left_edge_flash_active = true


func _check_flash_target_in_view() -> void:
	if not _left_edge_flash_active:
		return
	var player = GameManager.player_ref
	if not player or not is_instance_valid(player):
		return
	var cam = player.get_node_or_null("SmoothCamera") as SmoothCamera
	if not cam:
		return
	var hv = get_viewport_rect().size * 0.5 / cam.zoom
	var cc = cam.global_position + cam.offset
	var vr = Rect2(cc - hv, hv * 2)
	if _reality_phone_node and is_instance_valid(_reality_phone_node) and vr.has_point(_reality_phone_node.global_position):
		_stop_left_edge_flash()


func _stop_left_edge_flash() -> void:
	if not _left_edge_flash_active:
		return
	_left_edge_flash_active = false
	if _left_edge_flash and is_instance_valid(_left_edge_flash):
		_left_edge_flash.hide()
	if _left_edge_glow and is_instance_valid(_left_edge_glow):
		_left_edge_glow.hide()


# ============================================================
# UI 构建
# ============================================================

func _build_all_ui() -> void:
	const VW: float = 1280.0
	const VH: float = 720.0
	var canvas = CanvasLayer.new()
	canvas.name = "CanvasLayerUI"
	canvas.layer = 10
	add_child(canvas)

	# 黑屏遮罩
	_blackout_overlay = ColorRect.new()
	_blackout_overlay.name = "BlackoutOverlay"
	_blackout_overlay.visible = false
	_blackout_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blackout_overlay.color = Color(0, 0, 0, 0)
	_blackout_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_blackout_overlay)

	# 叙事面板（复用备份样式：锚定底部，半透明黑底，圆角）
	_narrative_panel = Panel.new()
	_narrative_panel.name = "NarrativePanel"
	_narrative_panel.visible = false
	_narrative_panel.anchor_left = 0.0; _narrative_panel.anchor_top = 1.0
	_narrative_panel.anchor_right = 1.0; _narrative_panel.anchor_bottom = 1.0
	_narrative_panel.offset_left = 0.0; _narrative_panel.offset_top = -200.0
	_narrative_panel.offset_right = 0.0; _narrative_panel.offset_bottom = 0.0
	_narrative_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nstyle = StyleBoxFlat.new()
	nstyle.bg_color = Color(0, 0, 0, 0.85); nstyle.set_corner_radius_all(8)
	_narrative_panel.add_theme_stylebox_override("panel", nstyle)
	canvas.add_child(_narrative_panel)
	_narrative_text = RichTextLabel.new()
	_narrative_text.name = "NarrativeText"
	_narrative_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_narrative_text.offset_left = 20.0; _narrative_text.offset_top = 20.0
	_narrative_text.offset_right = -20.0; _narrative_text.offset_bottom = -20.0
	_narrative_text.bbcode_enabled = true; _narrative_text.fit_content = true
	_narrative_text.add_theme_font_size_override("normal_font_size", 27)
	_narrative_text.add_theme_color_override("default_color", Color(0.9, 0.85, 0.75))
	_narrative_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_narrative_panel.add_child(_narrative_text)

	# 红光遮罩
	_red_overlay = ColorRect.new()
	_red_overlay.name = "RedWarningOverlay"
	_red_overlay.visible = false
	_red_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_red_overlay.color = Color(0.8, 0.05, 0.05, 0.0)
	_red_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_red_overlay)

	# Tab 提示
	_wake_hint_label = Label.new()
	_wake_hint_label.name = "WakeHintLabel"
	_wake_hint_label.visible = false
	_wake_hint_label.text = "长按【Tab】睁开眼睛"
	_wake_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wake_hint_label.add_theme_font_size_override("font_size", 33)
	_wake_hint_label.add_theme_color_override("font_color", Color(1, 0.85, 0.85, 0.95))
	_wake_hint_label.position = Vector2(440, 70); _wake_hint_label.size = Vector2(400, 40)
	_wake_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_wake_hint_label)

	# 梦境短信回声
	_phone_msg_panel = Panel.new()
	_phone_msg_panel.name = "PhoneMessageOverlay"
	_phone_msg_panel.visible = false
	_phone_msg_panel.size = Vector2(380, 180); _phone_msg_panel.position = Vector2(870, 30)
	_phone_msg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pstyle = StyleBoxFlat.new()
	pstyle.bg_color = Color(0.05, 0.05, 0.08, 0.92)
	pstyle.border_width_left = 2; pstyle.border_width_right = 2
	pstyle.border_width_top = 2; pstyle.border_width_bottom = 2
	pstyle.border_color = Color(0.9, 0.2, 0.2, 0.9); pstyle.set_corner_radius_all(6)
	_phone_msg_panel.add_theme_stylebox_override("panel", pstyle)
	canvas.add_child(_phone_msg_panel)
	_phone_msg_text = RichTextLabel.new()
	_phone_msg_text.name = "MessageText"
	_phone_msg_text.size = Vector2(348, 150); _phone_msg_text.position = Vector2(16, 14)
	_phone_msg_text.bbcode_enabled = true
	_phone_msg_text.add_theme_font_size_override("normal_font_size", 21)
	_phone_msg_text.add_theme_color_override("default_color", Color(0.95, 0.85, 0.85))
	_phone_msg_panel.add_child(_phone_msg_text)

	# 睁眼遮罩
	_eye_overlay = Control.new()
	_eye_overlay.name = "EyeCloseOverlay"
	_eye_overlay.visible = false
	_eye_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_eye_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_eye_overlay)
	_eye_rect_top = ColorRect.new()
	_eye_rect_top.name = "EyeTop"; _eye_rect_top.color = Color(0, 0, 0, 1)
	_eye_rect_top.position = Vector2(0, 0); _eye_rect_top.size = Vector2(VW, 0)
	_eye_rect_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_eye_overlay.add_child(_eye_rect_top)
	_eye_rect_bottom = ColorRect.new()
	_eye_rect_bottom.name = "EyeBottom"; _eye_rect_bottom.color = Color(0, 0, 0, 1)
	_eye_rect_bottom.position = Vector2(0, VH); _eye_rect_bottom.size = Vector2(VW, 0)
	_eye_rect_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_eye_overlay.add_child(_eye_rect_bottom)
	_eye_rect_left = ColorRect.new()
	_eye_rect_left.name = "EyeLeft"; _eye_rect_left.color = Color(0, 0, 0, 1)
	_eye_rect_left.position = Vector2(0, 0); _eye_rect_left.size = Vector2(0, VH)
	_eye_rect_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_eye_overlay.add_child(_eye_rect_left)
	_eye_rect_right = ColorRect.new()
	_eye_rect_right.name = "EyeRight"; _eye_rect_right.color = Color(0, 0, 0, 1)
	_eye_rect_right.position = Vector2(VW, 0); _eye_rect_right.size = Vector2(0, VH)
	_eye_rect_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_eye_overlay.add_child(_eye_rect_right)

	# 左侧边缘闪烁
	_left_edge_flash = ColorRect.new()
	_left_edge_flash.name = "LeftEdgeFlash"
	_left_edge_flash.color = Color(1.0, 0.85, 0.2, 0.0)
	_left_edge_flash.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_left_edge_flash.offset_right = 8; _left_edge_flash.visible = false
	_left_edge_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE; _left_edge_flash.z_index = 100
	canvas.add_child(_left_edge_flash)
	_left_edge_glow = ColorRect.new()
	_left_edge_glow.name = "LeftEdgeGlow"
	_left_edge_glow.color = Color(1.0, 0.9, 0.3, 0.0)
	_left_edge_glow.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_left_edge_glow.offset_right = 30; _left_edge_glow.visible = false
	_left_edge_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE; _left_edge_glow.z_index = 99
	canvas.add_child(_left_edge_glow)

	# IDE — CODE-BUDDY 风格
	_ide_ui = Control.new()
	_ide_ui.name = "IdeUI"; _ide_ui.visible = false
	_ide_ui.set_anchors_preset(Control.PRESET_FULL_RECT)

	# 全屏深色背景
	var ide_bg = ColorRect.new()
	ide_bg.name = "Background"; ide_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ide_bg.color = Color(0.09, 0.1, 0.14, 1.0)
	_ide_ui.add_child(ide_bg)

	# 左侧边栏 (220px)
	var sidebar = Panel.new()
	sidebar.name = "Sidebar"
	sidebar.size = Vector2(220, VH); sidebar.position = Vector2(0, 0)
	var sstyle = StyleBoxFlat.new()
	sstyle.bg_color = Color(0.07, 0.08, 0.12, 1.0)
	sstyle.border_width_right = 1; sstyle.border_color = Color(0.18, 0.2, 0.28)
	sidebar.add_theme_stylebox_override("panel", sstyle)
	_ide_ui.add_child(sidebar)

	# 边栏 — Logo 区域
	var logo_bg = ColorRect.new()
	logo_bg.name = "LogoBg"; logo_bg.size = Vector2(220, 56)
	logo_bg.color = Color(0.05, 0.06, 0.1, 1.0)
	sidebar.add_child(logo_bg)
	var logo = Label.new()
	logo.name = "LogoLabel"; logo.text = "CODE-BUDDY"
	logo.add_theme_font_size_override("font_size", 27)
	logo.add_theme_color_override("font_color", Color(0.35, 0.78, 1.0))
	logo.position = Vector2(16, 8)
	sidebar.add_child(logo)
	var logo_sub = Label.new()
	logo_sub.name = "LogoVersion"; logo_sub.text = ">_ v1.4.2 - recovered"
	logo_sub.add_theme_font_size_override("font_size", 16)
	logo_sub.add_theme_color_override("font_color", Color(0.35, 0.5, 0.6))
	logo_sub.position = Vector2(16, 32)
	sidebar.add_child(logo_sub)

	# 边栏 — 项目名
	var proj_section = Label.new()
	proj_section.name = "SectionProject"; proj_section.text = "PROJECT"
	proj_section.add_theme_font_size_override("font_size", 15)
	proj_section.add_theme_color_override("font_color", Color(0.3, 0.35, 0.45))
	proj_section.position = Vector2(16, 72)
	sidebar.add_child(proj_section)
	var proj_name = Label.new()
	proj_name.name = "ProjectName"; proj_name.text = "[+] Xiguan_Dream"
	proj_name.add_theme_font_size_override("font_size", 20)
	proj_name.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
	proj_name.position = Vector2(16, 86)
	sidebar.add_child(proj_name)

	# 边栏 — 菜单分隔线
	var sep1 = ColorRect.new()
	sep1.name = "Sep1"; sep1.size = Vector2(188, 1); sep1.position = Vector2(16, 114)
	sep1.color = Color(0.18, 0.2, 0.28)
	sidebar.add_child(sep1)

	# 边栏 — 文件树菜单
	var files_label = Label.new()
	files_label.name = "FilesLabel"; files_label.text = "FILES"
	files_label.add_theme_font_size_override("font_size", 15)
	files_label.add_theme_color_override("font_color", Color(0.3, 0.35, 0.45))
	files_label.position = Vector2(16, 126)
	sidebar.add_child(files_label)
	var file_items = ["  > src/config/", "  > src/player/", "  > src/enemy/", "  > src/dream/"]
	for j in range(file_items.size()):
		var fi = Label.new()
		fi.text = file_items[j]
		fi.add_theme_font_size_override("font_size", 18)
		fi.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
		fi.position = Vector2(16, 142 + j * 22)
		sidebar.add_child(fi)

	# 边栏 — 分隔线
	var sep2 = ColorRect.new()
	sep2.name = "Sep2"; sep2.size = Vector2(188, 1); sep2.position = Vector2(16, 236)
	sep2.color = Color(0.18, 0.2, 0.28)
	sidebar.add_child(sep2)

	# 边栏 — 底部状态
	var status = Label.new()
	status.name = "StatusLabel"; status.text = "SESSION: RECOVERED"
	status.add_theme_font_size_override("font_size", 15)
	status.add_theme_color_override("font_color", Color(0.35, 0.5, 0.6))
	status.position = Vector2(16, VH - 28)
	sidebar.add_child(status)

	# 主对话区
	var chat_panel = Panel.new()
	chat_panel.name = "ChatPanel"
	chat_panel.position = Vector2(220, 0); chat_panel.size = Vector2(VW - 220, VH)
	var cpstyle = StyleBoxFlat.new()
	cpstyle.bg_color = Color(0.1, 0.11, 0.16, 1.0)
	cpstyle.border_width_left = 0; cpstyle.border_width_right = 0
	cpstyle.border_width_top = 0; cpstyle.border_width_bottom = 0
	chat_panel.add_theme_stylebox_override("panel", cpstyle)
	_ide_ui.add_child(chat_panel)

	_chat_window = RichTextLabel.new()
	_chat_window.name = "ChatWindow"
	_chat_window.position = Vector2(20, 20); _chat_window.size = Vector2(VW - 240, VH - 60)
	_chat_window.bbcode_enabled = true; _chat_window.scroll_following = true
	_chat_window.add_theme_font_size_override("normal_font_size", 21)
	_chat_window.add_theme_color_override("default_color", Color(0.88, 0.88, 0.92))
	_chat_window.add_theme_constant_override("line_separation", 6)
	chat_panel.add_child(_chat_window)

	# 底部输入框
	_chat_input = LineEdit.new()
	_chat_input.name = "ChatInput"
	_chat_input.position = Vector2(10, VH - 36); _chat_input.size = Vector2(VW - 240, 28)
	_chat_input.placeholder_text = "输入消息，按 Enter 发送..."
	_chat_input.add_theme_font_size_override("font_size", 20)
	_chat_input.add_theme_color_override("font_color", Color(0.88, 0.88, 0.92))
	_chat_input.add_theme_color_override("font_placeholder_color", Color(0.35, 0.4, 0.5))
	var istyle = StyleBoxFlat.new()
	istyle.bg_color = Color(0.12, 0.14, 0.2, 0.95)
	istyle.set_corner_radius_all(6)
	istyle.border_width_left = 1; istyle.border_width_right = 1
	istyle.border_width_top = 1; istyle.border_width_bottom = 1
	istyle.border_color = Color(0.25, 0.3, 0.45)
	istyle.content_margin_left = 10; istyle.content_margin_right = 10
	istyle.content_margin_top = 4; istyle.content_margin_bottom = 4
	_chat_input.add_theme_stylebox_override("normal", istyle)
	_chat_input.add_theme_stylebox_override("focus", istyle)
	_chat_input.text_submitted.connect(_on_chat_submitted)
	_chat_input.text_changed.connect(_on_chat_text_changed)
	chat_panel.add_child(_chat_input)

	canvas.add_child(_ide_ui)

	# 配置编辑器
	_config_ui = Panel.new()
	_config_ui.name = "ConfigEditorUI"; _config_ui.visible = false
	_config_ui.size = Vector2(840, 460); _config_ui.position = Vector2(220, 130)
	GameUIStyle.apply_panel(_config_ui, 0.94)
	var ctitle = Label.new()
	ctitle.name = "ConfigTitle"; ctitle.text = "[+] Xiguan_Dream.ini - 配置编辑器"
	ctitle.add_theme_font_size_override("font_size", 27)
	ctitle.add_theme_color_override("font_color", Color(0.5, 0.9, 0.6))
	ctitle.position = Vector2(24, 16)
	_config_ui.add_child(ctitle)
	_config_value_labels.clear(); _config_feedback_labels.clear(); _config_buttons.clear()
	for i in range(3):
		var row_y = 70 + i * 100
		var il = Label.new()
		il.name = "ItemLabel_%d" % i
		il.add_theme_font_size_override("font_size", 24)
		il.add_theme_color_override("font_color", Color(0.85, 0.85, 0.8))
		il.position = Vector2(36, row_y); il.size = Vector2(480, 24)
		_config_ui.add_child(il)
		var vl = Label.new()
		vl.name = "ValueLabel_%d" % i
		vl.add_theme_font_size_override("font_size", 24)
		vl.add_theme_color_override("font_color", Color(0.95, 0.6, 0.3))
		vl.position = Vector2(540, row_y); vl.size = Vector2(140, 24)
		_config_ui.add_child(vl); _config_value_labels.append(vl)
		var btn = Button.new()
		btn.name = "ModifyButton_%d" % i; btn.text = "修改"
		btn.position = Vector2(694, row_y - 8); btn.size = Vector2(112, 42)
		GameUIStyle.apply_button(btn, 22)
		_config_ui.add_child(btn); _config_buttons.append(btn)
		var fb = Label.new()
		fb.name = "Feedback_%d" % i
		fb.add_theme_font_size_override("font_size", 20)
		fb.add_theme_color_override("font_color", Color(0.4, 0.8, 0.5))
		fb.position = Vector2(36, row_y + 32); fb.size = Vector2(760, 22); fb.text = ""
		_config_ui.add_child(fb); _config_feedback_labels.append(fb)
	_recompile_button = Button.new()
	_recompile_button.name = "RecompileButton"; _recompile_button.text = "重新编译并注入梦境"
	_recompile_button.disabled = true; _recompile_button.position = Vector2(270, 358)
	_recompile_button.size = Vector2(300, 90)
	GameUIStyle.apply_button(_recompile_button, 24)
	_config_ui.add_child(_recompile_button)
	canvas.add_child(_config_ui)

	# 重编译日志
	_recompile_panel = Panel.new()
	_recompile_panel.name = "RecompileLogPanel"; _recompile_panel.visible = false
	_recompile_panel.size = Vector2(840, 420); _recompile_panel.position = Vector2(220, 150)
	GameUIStyle.apply_panel(_recompile_panel, 0.94)
	_recompile_log = RichTextLabel.new()
	_recompile_log.name = "LogText"
	_recompile_log.size = Vector2(792, 380); _recompile_log.position = Vector2(24, 20)
	_recompile_log.bbcode_enabled = true; _recompile_log.scroll_following = true
	_recompile_log.add_theme_font_size_override("normal_font_size", 22)
	_recompile_log.add_theme_color_override("default_color", Color(0.5, 0.9, 0.55))
	_recompile_panel.add_child(_recompile_log)
	canvas.add_child(_recompile_panel)

	# 连接按钮信号
	for i in range(_config_buttons.size()):
		var idx = i
		_config_buttons[i].pressed.connect(func(): _on_config_button_pressed(idx))
	_recompile_button.pressed.connect(_on_recompile_pressed)


# ============================================================
# 叙事 / 黑屏
# ============================================================

func _show_narrative(text: String, callback: Callable = Callable()) -> void:
	InputManager.block_input("叙事面板", self)
	if _narrative_open:
		if _narrative_panel: _narrative_panel.hide()
		_narrative_open = false
	_is_interacting = true
	_narrative_open = true
	_freeze_player(true)
	if _narrative_panel:
		_narrative_panel.show()
		if _narrative_text: _narrative_text.text = text
	await get_tree().create_timer(0.3).timeout
	_narrative_enter_pressed = false
	var elapsed: float = 0.0
	while _narrative_open and elapsed < NARRATIVE_INPUT_TIMEOUT:
		if _narrative_enter_pressed:
			break
		await get_tree().create_timer(0.05).timeout
		elapsed += 0.05
	if _narrative_panel: _narrative_panel.hide()
	_freeze_player(false)
	_narrative_open = false
	_is_interacting = false
	_interact_cooldown = 0.0
	InputManager.unblock_input("叙事面板")
	if callback.is_valid():
		callback.call()


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


# ============================================================
# 音效
# ============================================================

func _play_sfx_loop_safe(path: String) -> AudioStreamPlayer:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var stream = load(path) as AudioStream
	if not stream:
		return null
	var player = AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	player.finished.connect(func():
		if is_instance_valid(player):
			player.play()
	)
	player.play()
	return player


func _stop_sfx_loop(player: AudioStreamPlayer) -> void:
	if player and is_instance_valid(player):
		player.stop()
		player.queue_free()

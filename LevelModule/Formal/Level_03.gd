# ============================================================
# Level_03.gd - 第三关「赛博蜃景与真实回声」控制器
# 场景节点 → Level_03.tscn（编辑器可视编辑）
# UI 构建   → Level_03_UIBuilder
# 状态调度  → Level_03_FSM
#
# 新架构（无缝单坐标空间，由 .tscn 中 Ground 碰撞体实际位置决定）:
#   1. 凉茶铺(HavenGround): 0~640
#   2. 岭南街巷(AlleyGround): 640~2128
#   3. 过渡走廊(CorridorGroundCold): 2144~4032
#   4. 赛博城(CyberGround, CyberCityRoot.x=3600): 4032~6816
#   5. 状态流: TEA_SHOP_FRONT → LINGNAN_COMBAT → WORLD_SHIFT → CYBER_CITY → ...
#   6. 击退反转: 赛博阶段敌人击中后玩家向左击退
#   7. 跨关卡: 读取 GameManager.dream_runtime_flags
# ============================================================
extends LevelBase
class_name Level_03

@export var level_data: Level03Data = null

enum LevelState {
	TEA_SHOP_FRONT,       # 凉茶铺前：爷爷NPC对话
	LINGNAN_COMBAT,       # 岭南街巷战斗
	WORLD_SHIFT,          # 世界异化演出（抖动+颜色腐蚀+墙壁消失）
	CYBER_CITY,           # 赛博城中村探索+战斗
	MEMORY_COLLECTION,    # 异常数据光团收集（2个）
	AWAKENING,            # 彻底觉醒独白
	LEVEL_END_TRANSIT     # 关卡结束转场
}

var current_state: int = LevelState.TEA_SHOP_FRONT

# ---- 任务进度 ----
var grandpa_dialogue_index: int = 0
var memory_echoes_collected: int = 0
var ai_warning_1_triggered: bool = false
var ai_warning_2_triggered: bool = false
var _lingnan_enemies_alive: int = 0

# ---- 场景节点引用（SceneBuilder 写入） ----
var _safe_haven_root: Node2D = null
var _cyber_city_root: Node2D = null
var _dynamic_actors: Node2D = null
var _background_visual: Node2D = null   # PixelworkMapStitch 背景视觉层

# ---- 交互物引用 ----
var _grandpa_node: InteractiveObject = null
var _memory_echo_1_node: InteractiveObject = null
var _memory_echo_2_node: InteractiveObject = null
var _echo_sprite_1: Sprite2D = null   # 记忆光团1贴图
var _echo_sprite_2: Sprite2D = null   # 记忆光团2贴图
var _all_interactives: Array[InteractiveObject] = []

# ---- 触发器引用 ----
var _warning_1_trigger: Area2D = null
var _warning_2_trigger: Area2D = null
var _warning_barrier_1: WarningBarrier = null
var _warning_barrier_2: WarningBarrier = null

# ---- UI 引用（UIBuilder 写入） ----
var _narrative_panel: Panel = null
var _narrative_text: RichTextLabel = null
var _code_rain_overlay: CodeRain = null
var _glitch_overlay: ColorRect = null
var _ending_prompt: Control = null
var _ending_label: Label = null

# ---- 交互/叙事状态 ----
var _interact_cooldown: float = 0.0
var _is_interacting: bool = false
var _narrative_open: bool = false
var _narrative_enter_pressed: bool = false
var _transition_running: bool = false
const NARRATIVE_INPUT_TIMEOUT: float = 30.0

# ---- 敌人管理 ----
var _enemy_cyber_wolf_scene: PackedScene = null
var _enemy_lantern_ghost_scene: PackedScene = null
var _enemy_paper_effigy_scene: PackedScene = null
var _enemy_cyber_bull_scene: PackedScene = null
var _lingnan_enemies: Array[Node2D] = []
var _cyber_enemies: Array[Node2D] = []
var _enemy_spawn_timer: Timer = null
const ENEMY_MAX_ALIVE: int = 6
const ENEMY_MAX_ONSCREEN: int = 4
const ENEMY_SPAWN_INTERVAL: float = 5.0

# ---- 击退反转 ----
const KNOCKBACK_REVERSE_FORCE: float = 350.0

# ---- Glitch 效果 ----
const GLITCH_AMBIENT: float = 0.04   # 赛博城基底微弱强度
const GLITCH_SPIKE: float = 0.8      # 互动时峰值强度

# ---- 终局 ----
var _ending_enter_armed: bool = false
var _level_complete_emitted: bool = false

var _fsm: Level_03_FSM = null


# ============================================================
# 生命周期
# ============================================================

func _setup_player() -> void:
	if GameManager.player_ref and is_instance_valid(GameManager.player_ref):
		return
	var player_path = level_config.player_scene_path if level_config and level_config.player_scene_path != "" else "res://PlayerModule/Formal/Player_Warrior_Lingnan.tscn"
	if ResourceLoader.exists(player_path):
		var player = load(player_path).instantiate()
		var spawn_pos = level_config.spawn_point if level_config else Vector2(56, 296)
		player.position = spawn_pos
		add_child(player)
		GameManager.register_player(player)
		print("[Level_03] 玩家创建成功 (Lingnan 皮肤)")

func _on_ready() -> void:
	super._on_ready()

	# 入场黑屏遮罩（初始化在黑屏下进行，末尾淡出呈现关卡）
	_play_intro_fade_in()

	if not level_config:
		level_config = load("res://DataConfig/Level/Level03Config.tres") as LevelConfig
		_apply_config()
	if not level_data:
		level_data = load("res://DataConfig/Level/Level03Data.tres") as Level03Data

	# 预加载敌人场景
	var wolf_path = "res://EnemyModule/Formal/Enemy_CyberWolf.tscn"
	if ResourceLoader.exists(wolf_path):
		_enemy_cyber_wolf_scene = load(wolf_path)
	var lantern_path = "res://EnemyModule/Formal/Enemy_LanternGhost.tscn"
	if ResourceLoader.exists(lantern_path):
		_enemy_lantern_ghost_scene = load(lantern_path)
	var effigy_path = "res://EnemyModule/Formal/Enemy_PaperEffigy.tscn"
	if ResourceLoader.exists(effigy_path):
		_enemy_paper_effigy_scene = load(effigy_path)
	var bull_path = "res://EnemyModule/Formal/Enemy_CyberBull.tscn"
	if ResourceLoader.exists(bull_path):
		_enemy_cyber_bull_scene = load(bull_path)

	_apply_dream_runtime_flags()

	# 从 .tscn 绑定已有节点（SceneBuilder 的角色已被编辑器可视化替代）
	_bind_scene_nodes()
	# 墙壁结界可视化
	_build_wall_visuals()
	# Canvas UI 仍由 UIBuilder 运行时构建（未截取到 .tscn 中）
	_build_canvas_ui()
	_set_all_color_rect_mouse_ignore(self)

	# 赛博城初始: 隐藏 + 碰撞禁用
	_set_space_collision(_cyber_city_root, false)

	_setup_camera_limits()
	# 凉茶铺阶段：摄像机限制在凉茶铺+街巷区域 (AlleyGround 末端=2128)
	_set_camera_limits(0, 2120, 168, 608)
	_cache_ui_refs()
	_ensure_player_collision_layer()

	_all_interactives = [_grandpa_node, _memory_echo_1_node, _memory_echo_2_node]

	EventBus.subscribe(GlobalDefine.EventName.INTERACTIVE_OBJECT_TRIGGERED, self, "_on_object_interacted")
	EventBus.subscribe(GlobalDefine.EventName.PLAYER_HURT, self, "_on_player_hurt")
	# 监听敌人死亡以追踪岭南战斗进度
	EventBus.subscribe(GlobalDefine.EventName.ENEMY_DIED, self, "_on_enemy_died")
	# 监听玩家死亡 — 重生
	EventBus.subscribe(GlobalDefine.EventName.PLAYER_DIED, self, "_on_player_died")
	_fsm = Level_03_FSM.new(self)

	if not InputManager.game_action.is_connected(_on_game_action):
		InputManager.game_action.connect(_on_game_action)

	_enemy_spawn_timer = Timer.new()
	_enemy_spawn_timer.name = "EnemySpawnTimer"
	_enemy_spawn_timer.wait_time = ENEMY_SPAWN_INTERVAL
	_enemy_spawn_timer.one_shot = false
	_enemy_spawn_timer.autostart = false
	_enemy_spawn_timer.timeout.connect(_on_enemy_spawn_timer_timeout)
	add_child(_enemy_spawn_timer)

	_load_hud()
	set_process(true)
	print("[Level_03] 初始化完成 — 当前: TEA_SHOP_FRONT")
	# 初始化完成，淡出黑屏呈现关卡
	_finish_intro_fade_in()

	# 关卡开场叙事，延迟 0.5s 弹出
	await get_tree().create_timer(0.5).timeout
	_show_narrative("[color=white]我……我真的回来了！\n爷爷就在前面！爷爷！爷爷！[/color]")


## 入场黑屏遮罩：创建满黑 CanvasLayer，覆盖整个初始化过程
func _play_intro_fade_in() -> void:
	var cv = CanvasLayer.new()
	cv.name = "IntroFadeCanvas"
	cv.layer = 2000
	add_child(cv)
	var black = ColorRect.new()
	black.name = "IntroFadeBlack"
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.size = get_viewport_rect().size
	black.position = Vector2.ZERO
	black.color = Color(0, 0, 0, 1.0)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(black)

## 初始化完成后淡出黑屏（1.5s），完成后自动清理遮罩节点
func _finish_intro_fade_in() -> void:
	var cv = get_node_or_null("IntroFadeCanvas")
	if not cv: return
	var black = cv.get_node_or_null("IntroFadeBlack")
	if not black: return
	var tw = get_tree().create_tween()
	tw.tween_property(black, "color:a", 0.0, 1.5).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(cv.queue_free)


func _exit_tree() -> void:
	_disconnect_input_manager()


# ============================================================
# 关卡切换辅助（对齐 Level_01/Level_02 关卡退出三件套）
# ============================================================

## 是否在 MainEntry 托管下运行（决定走 EventBus 还是直接 change_scene_to_file）
func _is_loaded_under_main_entry() -> bool:
	var node = get_parent()
	while node:
		if node.name == "MainEntry":
			return true
		node = node.get_parent()
	return false

## 断开 InputManager.game_action 信号连接，防止跨关卡输入泄漏
func _disconnect_input_manager() -> void:
	if InputManager.game_action.is_connected(_on_game_action):
		InputManager.game_action.disconnect(_on_game_action)


func _load_hud() -> void:
	var hud_path = "res://UI/HUD.tscn"
	if ResourceLoader.exists(hud_path):
		var hud = load(hud_path).instantiate()
		add_child(hud)
		print("[Level_03] HUD 加载成功")
	else:
		push_warning("[Level_03] HUD.tscn 未找到，跳过")


# ============================================================
# 跨关卡配置
# ============================================================

func _apply_dream_runtime_flags() -> void:
	var flags = GameManager.dream_runtime_flags
	if flags.is_empty():
		print("[Level_03] 无跨关卡配置，使用默认值")
		return
	print("[Level_03] 应用跨关卡配置: ", flags)
	var player = GameManager.player_ref
	if player and is_instance_valid(player):
		if flags.get("base_jump_height", 10) > 50:
			player.can_double_jump = true
			print("[Level_03] 跨关卡跳跃增强: 启用二段跳")


# ============================================================
# 工具方法
# ============================================================

func _get_or_create_child(node_name: String, node_type) -> Node:
	var existing = get_node_or_null(node_name)
	if existing: return existing
	var node = node_type.new()
	node.name = node_name
	add_child(node)
	return node

func _create_static_body(node_name: String, pos: Vector2, size: Vector2, col: Color) -> StaticBody2D:
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
	var color_rect = ColorRect.new()
	color_rect.name = "ColorRect"
	color_rect.color = col
	color_rect.size = size
	color_rect.position = -size / 2
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(color_rect)
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
	if not player or not is_instance_valid(player): return
	if not (player.collision_layer & GlobalDefine.Collision.PLAYER):
		player.collision_layer |= GlobalDefine.Collision.PLAYER


# ============================================================
# 从 .tscn 绑定已有场景节点（替代原 SceneBuilder 的角色）
# ============================================================

func _bind_scene_nodes() -> void:
	# 空间根节点
	_safe_haven_root = $SafeHavenRoot
	_cyber_city_root = $CyberCityRoot
	_dynamic_actors = $DynamicActors

	# 交互物
	_grandpa_node = $InteractiveObjects/Grandpa
	_grandpa_node.allow_repeat = false
	_grandpa_node.apply_level01_dot_visual()

	_memory_echo_1_node = $InteractiveObjects/MemoryEcho1
	_memory_echo_1_node.is_active = false   # 初始禁用，CYBER_CITY 阶段才激活
	_memory_echo_2_node = $InteractiveObjects/MemoryEcho2
	_memory_echo_2_node.is_active = false

	# 记忆光团贴图（已在 .tscn 中作为 MemoryEcho 子节点配置）
	_echo_sprite_1 = _memory_echo_1_node.get_node_or_null("EchoSprite")
	_echo_sprite_2 = _memory_echo_2_node.get_node_or_null("EchoSprite")

	# 触发器 — 连接 body_entered 信号
	_warning_1_trigger = $TriggerZones/Warning1Trigger
	_warning_1_trigger.body_entered.connect(_on_warning_1_trigger_body_entered)
	_warning_2_trigger = $TriggerZones/Warning2Trigger
	_warning_2_trigger.body_entered.connect(_on_warning_2_trigger_body_entered)

	# 系统入侵防火墙特效
	var warn_shader = load("res://LevelModule/Formal/warning_barrier.gdshader")
	if warn_shader:
		_warning_barrier_1 = WarningBarrier.new()
		_warning_barrier_1.name = "WarningBarrier1"
		_warning_barrier_1.setup(_warning_1_trigger, warn_shader)
		add_child(_warning_barrier_1)

		_warning_barrier_2 = WarningBarrier.new()
		_warning_barrier_2.name = "WarningBarrier2"
		_warning_barrier_2.setup(_warning_2_trigger, warn_shader)
		add_child(_warning_barrier_2)

	# 出生点
	player_spawn_point = $SpawnPoints/TeaShopSpawn

	# 背景 PixelworkMapStitch 视觉层（名称含日期批次号，用前缀匹配）
	for child in get_children():
		if child.name.begins_with("Level_03_base_"):
			_background_visual = child
			break


func _build_canvas_ui() -> void:
	var canvas = _get_or_create_child("CanvasLayerUI", CanvasLayer)
	canvas.layer = 2
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	Level_03_UIBuilder.new(self, canvas).build_all()


func _set_all_color_rect_mouse_ignore(node: Node) -> void:
	for child in node.get_children():
		if child is ColorRect:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_all_color_rect_mouse_ignore(child)


func _set_space_collision(root: Node, enabled: bool) -> void:
	if not root or not is_instance_valid(root): return
	for child in root.get_children():
		if child is StaticBody2D:
			var shape = child.get_node_or_null("CollisionShape2D")
			if shape: shape.disabled = not enabled
		_set_space_collision(child, enabled)

func _setup_camera_limits() -> void:
	if not level_config: return
	var player = GameManager.player_ref
	if not player or not is_instance_valid(player): return
	var cam = player.get_node_or_null("SmoothCamera") as SmoothCamera
	if not cam: return
	cam.limit_left = level_config.camera_limit_left
	cam.limit_right = level_config.camera_limit_right
	cam.limit_top = level_config.camera_limit_top
	cam.limit_bottom = level_config.camera_limit_bottom
	cam.zoom = Vector2(1.75, 1.75)
	cam.bind_target(player)

func _set_camera_limits(left: int, right: int, top: int, bottom: int) -> void:
	var player = GameManager.player_ref
	if not player or not is_instance_valid(player): return
	var cam = player.get_node_or_null("SmoothCamera") as SmoothCamera
	if not cam: return
	cam.limit_left = left
	cam.limit_right = right
	cam.limit_top = top
	cam.limit_bottom = bottom
	cam.zoom = Vector2(1.75, 1.75)
	cam.bind_target(player)

func _cache_ui_refs() -> void:
	var canvas = $CanvasLayerUI
	if not canvas: return
	_narrative_panel = canvas.get_node_or_null("NarrativePanel")
	if _narrative_panel: _narrative_text = _narrative_panel.get_node_or_null("RichTextLabel")
	_code_rain_overlay = canvas.get_node_or_null("CodeRainOverlay")
	_glitch_overlay = canvas.get_node_or_null("GlitchOverlay")
	_ending_prompt = canvas.get_node_or_null("EndingPrompt")
	if _ending_prompt: _ending_label = _ending_prompt.get_node_or_null("EndingLabel")


# ============================================================
# 玩家控制
# ============================================================

func _restore_combat_mechanics() -> void:
	var player = GameManager.player_ref
	if not player: return
	player.can_attack = true
	player.can_dash = true
	player.can_skill = true
	var flags = GameManager.dream_runtime_flags
	if flags.get("base_jump_height", 10) > 50:
		player.can_double_jump = true

func _swap_player_to_cyber() -> void:
	var old_player = GameManager.player_ref
	if not old_player or not is_instance_valid(old_player): return

	var saved_facing_right: bool = old_player.is_facing_right

	if InputManager.game_action.is_connected(old_player._on_game_action):
		InputManager.game_action.disconnect(old_player._on_game_action)
	GameManager.player_ref = null
	old_player.queue_free()

	var cyber_path = "res://PlayerModule/Formal/Player_Warrior_Cyber.tscn"
	if not ResourceLoader.exists(cyber_path):
		push_error("[Level_03] Player_Warrior_Cyber.tscn 不存在!")
		return
	var new_player = load(cyber_path).instantiate()
	add_child(new_player)
	# 换皮后血条恢复至满血（_ready 中 _apply_config 已设 max_health，此处确保 current 同步并通知 HUD）
	new_player.max_health = new_player.max_health  # 保留 config 中的值
	new_player.current_health = new_player.max_health
	EventBus.emit(GlobalDefine.EventName.HEALTH_CHANGED, {
		"target": new_player,
		"current_health": new_player.current_health,
		"max_health": new_player.max_health
	})
	new_player.global_position = Vector2(2048, 576)
	new_player.velocity = Vector2.ZERO
	new_player.is_facing_right = saved_facing_right
	GameManager.register_player(new_player)
	print("[Level_03] 玩家切换为赛博皮肤")

func _enforce_level_restrictions() -> void:
	var player = GameManager.player_ref
	if not player or not is_instance_valid(player): return
	# 所有战斗状态持续保障能力开启（防止 UI 焦点/叙事面板冻结等意外关闭）
	if current_state not in [LevelState.LEVEL_END_TRANSIT]:
		if not player.can_attack: player.can_attack = true
		if not player.can_dash: player.can_dash = true
		if not player.can_skill: player.can_skill = true

func _freeze_player(freeze: bool) -> void:
	var player = GameManager.player_ref
	if not player: return
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
		if is_instance_valid(obj): obj.freeze_monitoring(freeze)


func _on_player_died(_data: Dictionary) -> void:
	# 参照 Level_04/Level_05 的统一做法：玩家死亡 → 显示游戏结束面板 → 玩家点击"重新开始"重载关卡
	# 不做原地重生（避免与场景重载逻辑冲突导致传送回出生点）。
	# Player_Warrior._on_die() 会调用 GameManager.trigger_game_over()，
	# 同步 emit GAME_OVER → HUD 显示游戏结束面板。
	# 此处无需额外处理，仅作为监听占位（如未来需做死亡动画延迟可在此扩展）。
	pass

# ---- 失败提示遮罩（已弃用，保留方法避免外部调用报错） ----
func _show_failure_overlay() -> void: pass
func _hide_failure_overlay() -> void: pass

# ============================================================

func _on_game_action(action: StringName, _event: InputEvent) -> void:
	if action != &"ui_accept": return
	_handle_accept_input()

func _handle_accept_input() -> void:
	if current_state == LevelState.LEVEL_END_TRANSIT:
		if _ending_enter_armed:
			_ending_enter_armed = false
			_emit_level_complete()
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
	# 游戏结束后禁止所有输入（参照 Level_04 做法）
	if GameManager.is_game_over: return
	# 鼠标左键等价于Enter（对话推进/交互触发）
	var is_left_click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if not event.is_action_pressed("ui_accept") and not is_left_click: return
	if current_state == LevelState.LEVEL_END_TRANSIT:
		if _ending_enter_armed:
			_ending_enter_armed = false
			_emit_level_complete()
			# _emit_level_complete 可能同步触发 change_scene_to_file 释放当前场景，
			# 此时 get_viewport() 返回 null，安全判断避免崩溃
			var vp = get_viewport()
			if vp:
				vp.set_input_as_handled()
		return
	if _narrative_open:
		_narrative_enter_pressed = true
		get_viewport().set_input_as_handled()
		return
	if _is_interacting or _interact_cooldown > 0.0 or _transition_running:
		if not _transition_running and _interact_cooldown > 0.5:
			_safe_end_interaction()
		return
	var nearby_obj = _find_nearby_interactive()
	if nearby_obj:
		_interact_cooldown = 0.3
		EventBus.emit(GlobalDefine.EventName.INTERACTIVE_OBJECT_TRIGGERED, {"object_id": nearby_obj.object_id})
		get_viewport().set_input_as_handled()

func _find_nearby_interactive() -> InteractiveObject:
	for obj in _all_interactives:
		if is_instance_valid(obj) and obj.is_active and not obj.completed and obj.is_player_in_range:
			return obj
	var player = GameManager.player_ref
	if not player or not is_instance_valid(player): return null
	var best: InteractiveObject = null
	var best_dist: float = INF
	const FALLBACK_RADIUS: float = 120.0
	for obj in _all_interactives:
		if not is_instance_valid(obj) or not obj.is_active or obj.completed: continue
		var d: float = player.global_position.distance_to(obj.global_position)
		if d < FALLBACK_RADIUS and d < best_dist:
			best_dist = d
			best = obj
	if best: best.is_player_in_range = true
	return best


# ============================================================
# 每帧逻辑
# ============================================================

func _process(delta: float) -> void:
	if _interact_cooldown > 0.0:
		_interact_cooldown -= delta
	_enforce_level_restrictions()
	_poll_interactives_in_range()
	# 防火墙距离检测
	var player = GameManager.player_ref
	if player and is_instance_valid(player):
		var ppos = player.global_position
		if _warning_barrier_1: _warning_barrier_1.update(ppos)
		if _warning_barrier_2: _warning_barrier_2.update(ppos)
	if _is_interacting and current_state not in [LevelState.LEVEL_END_TRANSIT]:
		if not _narrative_open and not _transition_running:
			_safe_end_interaction()

func _poll_interactives_in_range() -> void:
	var player = GameManager.player_ref
	if not player or not is_instance_valid(player): return
	for obj in _all_interactives:
		if is_instance_valid(obj): obj.check_player_in_range(player)

func _safe_end_interaction() -> void:
	if not _narrative_open and not _transition_running:
		_is_interacting = false
	_interact_cooldown = 0.0

func _run_safely(fn: Callable) -> void:
	if not fn.is_valid(): return
	_interact_cooldown = 0.0
	fn.call()
	_safe_end_interaction()


# ============================================================
# FSM 调度
# ============================================================

func _on_object_interacted(data: Dictionary) -> void:
	var obj_id: String = data.get("object_id", "")
	if not _fsm:
		push_error("[Level_03] FSM 为 null")
		return
	_run_safely(func(): _fsm.handle_interaction(obj_id))

func _get_interactive_by_id(obj_id: String) -> InteractiveObject:
	match obj_id:
		"grandpa": return _grandpa_node
		"memory_echo_1": return _memory_echo_1_node
		"memory_echo_2": return _memory_echo_2_node
	return null

func _mark_interaction_completed(obj_id: String) -> void:
	var obj = _get_interactive_by_id(obj_id)
	if obj and not obj.allow_repeat: obj.mark_completed()


# ============================================================
# 叙事面板
# ============================================================

func _show_narrative(text: String, callback: Callable = Callable()) -> void:
	InputManager.block_input("叙事面板", self)
	if _narrative_open:
		if _narrative_panel: _narrative_panel.hide()
		_narrative_open = false
	_is_interacting = true
	_narrative_open = true
	GameManager.is_dialog_active = true
	_freeze_player(true)
	if _narrative_panel:
		_narrative_panel.show()
		if _narrative_text: _narrative_text.text = text
	await get_tree().create_timer(0.3).timeout
	_narrative_enter_pressed = false
	var wait_elapsed: float = 0.0
	var wait_delta: float = 0.05
	while _narrative_open and wait_elapsed < NARRATIVE_INPUT_TIMEOUT:
		if _narrative_enter_pressed: break
		await get_tree().create_timer(wait_delta).timeout
		wait_elapsed += wait_delta
	if _narrative_panel: _narrative_panel.hide()
	_freeze_player(false)
	_narrative_open = false
	GameManager.is_dialog_active = false
	_is_interacting = false
	_interact_cooldown = 0.0
	InputManager.unblock_input("叙事面板")
	if callback.is_valid(): _run_safely(callback)


# ============================================================
# 阶段1: 凉茶铺前 — 爷爷对话链
# ============================================================

func _start_grandpa_dialogue() -> void:
	if not level_data: return
	grandpa_dialogue_index = 0
	_advance_grandpa_dialogue()

func _advance_grandpa_dialogue() -> void:
	if not level_data: return
	if grandpa_dialogue_index >= level_data.grandpa_dialogues.size():
		_trigger_grandpa_glitch()
		return
	var entry = level_data.grandpa_dialogues[grandpa_dialogue_index]
	var speaker = entry.get("speaker", "")
	var text = entry.get("text", "")
	var formatted = ""
	match speaker:
		"Ming": formatted = "[color=white]阿明：[/color]" + text
		"Grandpa":
			if grandpa_dialogue_index >= 4:
				formatted = "[color=gray][GLITCH] [/color][color=cyan]爷爷：[/color]" + text
			else:
				formatted = "[color=cyan]爷爷：[/color]" + text
		_: formatted = text
	grandpa_dialogue_index += 1
	if speaker == "Grandpa" and grandpa_dialogue_index == 4:
		_flash_grandpa_indicator()
	_show_narrative(formatted, func(): _advance_grandpa_dialogue())

func _flash_grandpa_indicator() -> void:
	if not _grandpa_node: return
	var indicator = _grandpa_node.get_node_or_null("Indicator")
	if not indicator: return
	indicator.color = Color(0, 1, 0, 0.5)
	var tween = create_tween()
	tween.tween_property(indicator, "color:a", 0.15, 0.3)
	tween.tween_property(indicator, "color:a", 0.5, 0.3)

func _trigger_grandpa_glitch() -> void:
	if not level_data: return
	_mark_interaction_completed("grandpa")
	_show_narrative(level_data.grandpa_glitch_text, func():
		_show_narrative(level_data.ming_realization_text, func():
			_trigger_lingnan_combat()
		)
	)


# ============================================================
# 阶段2: 岭南街巷战斗
# ============================================================

func _trigger_lingnan_combat() -> void:
	current_state = LevelState.LINGNAN_COMBAT
	print("[Level_03] 进入 LINGNAN_COMBAT")

	# 爷爷NPC消失
	if _grandpa_node and is_instance_valid(_grandpa_node):
		_grandpa_node.is_active = false
		var sprite = _grandpa_node.get_node_or_null("Sprite")
		if sprite: sprite.visible = false

	# 开启战斗能力
	_restore_combat_mechanics()

	# 打开凉茶铺右墙 — 允许玩家进入街巷区域战斗
	_remove_wall("SafeHavenRoot/HavenRightWall")

	# 在墙后刷一只冲脸纸扎人，直接命令其朝玩家冲锋
	var rush_config = load("res://DataConfig/Enemy/PaperEffigyConfig.tres") as EnemyConfig
	var rush_enemy = _spawn_enemy_with_config(_enemy_paper_effigy_scene, Vector2(680, 540), rush_config)
	if rush_enemy:
		_lingnan_enemies.append(rush_enemy)
		# 为该敌人生成独立配置副本，扩大检测范围至 1000px
		rush_enemy.config = rush_config.duplicate()
		rush_enemy.config.detect_range = 1000.0
		# 直接设置为追逐状态，跳过 AI 检测延迟
		var player = GameManager.player_ref
		if player and is_instance_valid(player):
			rush_enemy.target = player
			rush_enemy.current_state = GlobalDefine.EnemyState.CHASE

	# 扩展相机到凉茶铺+街巷 (AlleyGround 末端=2128)
	_set_camera_limits(0, 2120, 168, 608)

	# 在凉茶铺+街巷区域生成敌人
	_spawn_lingnan_enemies()

	# 给敌人一个物理帧启动 AI，再弹出叙事——这样冲脸怪已经开始跑向玩家
	await get_tree().physics_frame

	# 显示战斗开始叙事
	if level_data:
		_show_narrative("[color=yellow]空气中弥漫着不安的气息……有什么东西正在逼近！[/color]")

func _spawn_lingnan_enemies() -> void:
	if not _enemy_paper_effigy_scene or not _enemy_lantern_ghost_scene:
		push_warning("[Level_03] 敌人场景缺失")
		return

	var spawn_points = level_data.lingnan_enemy_spawn_points if level_data else []
	if spawn_points.is_empty():
		spawn_points = [Vector2(955, 540), Vector2(1170, 540), Vector2(1385, 540), Vector2(1600, 540), Vector2(1815, 540)]

	var count = level_data.lingnan_enemy_count if level_data else 5
	var effigy_config = load("res://DataConfig/Enemy/PaperEffigyConfig.tres") as EnemyConfig
	var lantern_config = load("res://DataConfig/Enemy/LanternGhostConfig.tres") as EnemyConfig

	for i in range(mini(spawn_points.size(), count)):
		var is_lantern = (i % 2 == 0)  # 交替：灯笼鬼, 纸扎人, 灯笼鬼...
		var scene = _enemy_lantern_ghost_scene if is_lantern else _enemy_paper_effigy_scene
		var config = lantern_config if is_lantern else effigy_config
		var enemy = _spawn_enemy_with_config(scene, spawn_points[i], config)
		if enemy:
			_lingnan_enemies.append(enemy)

	_lingnan_enemies_alive = _lingnan_enemies.size()
	print("[Level_03] 岭南敌人生成: %d 只" % _lingnan_enemies.size())


# ============================================================
# 敌人死亡监听（追踪岭南战斗进度）
# ============================================================

func _on_enemy_died(data: Dictionary) -> void:
	var enemy = data.get("enemy")
	if not enemy or not is_instance_valid(enemy): return

	if current_state == LevelState.LINGNAN_COMBAT:
		if enemy in _lingnan_enemies:
			_lingnan_enemies.erase(enemy)
			_lingnan_enemies_alive = _lingnan_enemies.size()
			print("[Level_03] 岭南敌人剩余: %d" % _lingnan_enemies_alive)
			if _lingnan_enemies_alive <= 0:
				_on_lingnan_combat_complete()


# ============================================================
# 阶段3: 世界异化演出（无缝，无黑屏）
# ============================================================

func _on_lingnan_combat_complete() -> void:
	if _transition_running: return
	_transition_running = true
	current_state = LevelState.WORLD_SHIFT
	print("[Level_03] 岭南战斗结束 → 世界异化开始")

	# 1) 画面抖动（3秒，玩家仍可移动但视觉混乱）
	_start_screen_shake(3.0)

	# 2) Glitch增强
	if _glitch_overlay and _glitch_overlay.material:
		_glitch_overlay.show()
		var tween = create_tween()
		tween.tween_property(_glitch_overlay.material, "shader_parameter/intensity", 0.8, 2.0)

	# 等待2秒后打开街巷右墙 + 赛博城显现
	await get_tree().create_timer(2.0).timeout

	_remove_wall("LingnanAlleyRoot/AlleyRightWall")
	_remove_wall("TransitionCorridorRoot/CorridorRightWall")
	# 走廊区域生成敌人（CyberBull + PaperEffigy 各2只）
	_spawn_corridor_enemies()

	# 赛博城显现 + 碰撞启用
	if _cyber_city_root:
		_cyber_city_root.visible = true
		_set_space_collision(_cyber_city_root, true)
		# 移除赛博城左墙（旧双空间架构遗留，与走廊右墙重叠，不拆除则阻挡通行）
		_remove_wall("CyberCityRoot/CyberLeftWall")

	# 6) 玩家皮肤切换（赛博战斗系统，摄像机保持与岭南阶段一致）
	_swap_player_to_cyber()
	# 新玩家自带新 SmoothCamera 会重置为默认值，重新应用相机设置
	_set_camera_limits(1728, 6816, 168, 608)

	# 7) 背景分层变暗（仅 PixworkMapStitch，敌人/玩家不受影响）
	_dim_background_smooth(3.0)

	# 8) Glitch渐退
	if _glitch_overlay and _glitch_overlay.material:
		var tween2 = create_tween()
		tween2.tween_property(_glitch_overlay.material, "shader_parameter/intensity", GLITCH_AMBIENT, 1.0)

	# 9) 代码雨
	_start_code_rain()

	# 10) CodeBuddy广播
	await _show_codebuddy_broadcast()

	# 11) 生成赛博敌人 + 启动刷新
	_spawn_cyber_enemies()
	if _enemy_spawn_timer: _enemy_spawn_timer.start()

	# 12) 激活交互物
	if _memory_echo_1_node: _memory_echo_1_node.set_active(true)
	if _memory_echo_2_node: _memory_echo_2_node.set_active(true)

	current_state = LevelState.CYBER_CITY
	_transition_running = false
	print("[Level_03] 进入 CYBER_CITY — 无缝穿越完成")


# ============================================================
# 画面抖动
# ============================================================

func _start_screen_shake(duration: float) -> void:
	var player = GameManager.player_ref
	if not player or not is_instance_valid(player): return
	var cam = player.get_node_or_null("SmoothCamera") as SmoothCamera
	if not cam: return

	var original_offset = cam.offset
	var tween = create_tween()
	for i in range(int(duration * 20)):
		var shake_amount = 16.0 * (1.0 - float(i) / (duration * 20.0))  # 衰减，强度翻倍
		tween.tween_property(cam, "offset", Vector2(randf_range(-shake_amount, shake_amount), randf_range(-shake_amount, shake_amount)), 0.05)
	tween.tween_property(cam, "offset", original_offset, 0.1)


# ============================================================
# 背景分层变暗（仅 PixworkMapStitch 视觉层，敌人/玩家不受影响）
# ============================================================

func _dim_background_smooth(duration: float = 3.0) -> void:
	if not _background_visual or not is_instance_valid(_background_visual):
		return
	# modulate 仅作用于该节点及其子节点的渲染，不改变场景树中其他节点
	var target_modulate = Color(0.55, 0.58, 0.65, 1.0)  # 40%暗度，略带蓝调
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(_background_visual, "modulate", target_modulate, duration)
	print("[Level_03] 背景变暗开始，持续 %.1f 秒" % duration)


# ============================================================
# 墙壁结界可视化（Shader 扫描线光幕）
# ============================================================

## 为所有墙壁 StatidBody2D 挂载结界光幕 ColorRect + Shader
func _build_wall_visuals() -> void:
	var shader_res = load("res://LevelModule/Formal/warning_barrier.gdshader")
	if not shader_res:
		push_warning("[Level_03] warning_barrier.gdshader 加载失败")
		return
	var barrier_mat = ShaderMaterial.new()
	barrier_mat.shader = shader_res

	# 全部深蓝
	var walls = [
		{path = "SafeHavenRoot/HavenRightWall"},
		{path = "LingnanAlleyRoot/AlleyRightWall"},
		{path = "TransitionCorridorRoot/CorridorRightWall"},
		{path = "CyberCityRoot/CyberLeftWall"},
		{path = "CyberCityRoot/CyberRightWall"},
	]
	for entry in walls:
		_add_barrier_shader_to_wall(entry["path"], barrier_mat)


func _add_barrier_shader_to_wall(wall_path: String, mat_template: ShaderMaterial) -> void:
	var wall = get_node_or_null(wall_path)
	if not wall or not is_instance_valid(wall):
		push_warning("[Level_03] 墙壁节点未找到: %s" % wall_path)
		return

	# 从 CollisionShape2D 获取墙面尺寸和位置
	var col_shape = wall.get_node_or_null("CollisionShape2D")
	if not col_shape or not col_shape.shape is RectangleShape2D:
		push_warning("[Level_03] 墙壁 %s 无 CollisionShape2D" % wall_path)
		return
	var rect_size: Vector2 = col_shape.shape.size
	var col_pos: Vector2 = col_shape.position

	# 每面墙独立的 ShaderMaterial（共享 shader 资源，独立参数）
	var mat = ShaderMaterial.new()
	mat.shader = mat_template.shader
	mat.set_shader_parameter("intensity", 1.8)
	mat.set_shader_parameter("alert_level", 1.0)
	mat.set_shader_parameter("barrier_color", Color(0.04, 0.12, 0.7, 1.0))  # 深蓝
	mat.set_shader_parameter("fade", 1.0)

	var cr = ColorRect.new()
	cr.name = "ColorRect"
	cr.size = rect_size
	cr.position = col_pos - rect_size / 2  # 居中于碰撞体位置
	cr.material = mat
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cr.z_index = 5
	wall.add_child(cr)
	print("[Level_03] 光幕已挂载: %s (size=%s)" % [wall_path, rect_size])


# ============================================================
# 墙壁移除（打开通道）
# ============================================================

func _remove_wall(wall_path: String) -> void:
	var wall = get_node_or_null(wall_path)
	if not wall: return
	var shape = wall.get_node_or_null("CollisionShape2D")
	if shape: shape.disabled = true
	# 视觉淡出
	var cr = wall.get_node_or_null("ColorRect")
	if cr:
		var tween = create_tween()
		if cr.material and cr.material is ShaderMaterial:
			# Shader 结界：Tween fade uniform 到 0
			tween.tween_method(func(v: float): cr.material.set_shader_parameter("fade", v), 1.0, 0.0, 0.5)
		else:
			tween.tween_property(cr, "color:a", 0.0, 0.5)


# ============================================================
# CodeBuddy 广播
# ============================================================

func _show_codebuddy_broadcast() -> void:
	if not level_data: return
	var lines = level_data.codebuddy_broadcast_lines
	if lines.is_empty(): return
	for line in lines:
		var formatted = "[color=red][BROADCAST] " + line + "[/color]"
		await _show_narrative(formatted)


# ============================================================
# 代码雨
# ============================================================

func _start_code_rain() -> void:
	if _code_rain_overlay and is_instance_valid(_code_rain_overlay):
		_code_rain_overlay.start_rain()

func _stop_code_rain() -> void:
	if _code_rain_overlay and is_instance_valid(_code_rain_overlay):
		_code_rain_overlay.stop_rain()


# ============================================================
# AI阻挠弹窗
# ============================================================

func _on_warning_1_trigger_body_entered(body: Node2D) -> void:
	if not _is_player_body(body): return
	if ai_warning_1_triggered: return
	if current_state not in [LevelState.CYBER_CITY, LevelState.MEMORY_COLLECTION]: return
	ai_warning_1_triggered = true
	if _warning_barrier_1:
		_warning_barrier_1.trigger_breach(func():
			if level_data and level_data.ai_warning_1_text != "":
				_show_narrative(level_data.ai_warning_1_text)
		)
	elif level_data and level_data.ai_warning_1_text != "":
		_show_narrative(level_data.ai_warning_1_text)

func _on_warning_2_trigger_body_entered(body: Node2D) -> void:
	if not _is_player_body(body): return
	if ai_warning_2_triggered: return
	if current_state not in [LevelState.CYBER_CITY, LevelState.MEMORY_COLLECTION]: return
	ai_warning_2_triggered = true
	if _warning_barrier_2:
		_warning_barrier_2.trigger_breach(func():
			if level_data and level_data.ai_warning_2_text != "":
				_show_narrative(level_data.ai_warning_2_text)
		)
	elif level_data and level_data.ai_warning_2_text != "":
		_show_narrative(level_data.ai_warning_2_text)

func _is_player_body(body: Node2D) -> bool:
	if not body is CharacterBody2D: return false
	if body.collision_layer & GlobalDefine.Collision.PLAYER: return true
	return body.is_in_group("player")


# ============================================================
# 赛博城敌人管理
# ============================================================

func _spawn_cyber_enemies() -> void:
	if not _enemy_cyber_wolf_scene:
		push_warning("[Level_03] Enemy_CyberWolf.tscn 缺失，跳过敌人")
		return

	var cleaner_config = load("res://DataConfig/Enemy/CleanerConfig.tres") as EnemyConfig
	var cleaner_points = level_data.cleaner_spawn_points if level_data else []
	if cleaner_points.is_empty():
		cleaner_points = [Vector2(4596, 540), Vector2(5010, 540), Vector2(5424, 540), Vector2(5838, 540), Vector2(6252, 540)]
	for i in range(mini(cleaner_points.size(), 5)):
		var enemy = _spawn_enemy_with_config(_enemy_cyber_wolf_scene, cleaner_points[i], cleaner_config)
		if enemy:
			enemy.modulate = Color(0.3, 0.35, 0.4, 0.95)
			_cyber_enemies.append(enemy)

	var security_config = load("res://DataConfig/Enemy/SecurityConfig.tres") as EnemyConfig
	var security_points = level_data.security_spawn_points if level_data else []
	if security_points.is_empty():
		security_points = [Vector2(4803, 480), Vector2(5424, 480), Vector2(6045, 480)]
	for i in range(mini(security_points.size(), 3)):
		var enemy = _spawn_enemy_with_config(_enemy_cyber_wolf_scene, security_points[i], security_config)
		if enemy:
			enemy.modulate = Color(0.9, 0.15, 0.15, 0.95)
			_cyber_enemies.append(enemy)

	print("[Level_03] 赛博敌人生成: %d 只" % _cyber_enemies.size())

func _spawn_corridor_enemies() -> void:
	if not _enemy_cyber_bull_scene or not _enemy_paper_effigy_scene:
		return
	# 走廊区域 CorridorGroundCold: [2144, 4032]，4只均匀分布
	var bull_config = load("res://DataConfig/Enemy/CyberBullConfig.tres") as EnemyConfig
	var effigy_config = load("res://DataConfig/Enemy/PaperEffigyConfig.tres") as EnemyConfig
	var positions = [Vector2(2612, 540), Vector2(2930, 540), Vector2(3248, 540), Vector2(3566, 540)]
	var scenes = [_enemy_cyber_bull_scene, _enemy_paper_effigy_scene, _enemy_cyber_bull_scene, _enemy_paper_effigy_scene]
	var configs = [bull_config, effigy_config, bull_config, effigy_config]
	for i in range(4):
		var enemy = _spawn_enemy_with_config(scenes[i], positions[i], configs[i])
		if enemy:
			_cyber_enemies.append(enemy)
	print("[Level_03] 走廊敌人生成: 4 只 (CyberBull+PaperEffigy)")

func _spawn_enemy_with_config(scene: PackedScene, spawn_pos: Vector2, config: EnemyConfig) -> Node2D:
	if not scene: return null
	var enemy = scene.instantiate()
	if config: enemy.config = config
	enemy.global_position = spawn_pos
	if _dynamic_actors:
		_dynamic_actors.add_child(enemy)
	else:
		add_child(enemy)
	return enemy

func _on_enemy_spawn_timer_timeout() -> void:
	if current_state not in [LevelState.CYBER_CITY, LevelState.MEMORY_COLLECTION]:
		return
	if not _enemy_cyber_wolf_scene:
		return
	# 性能约束
	_cyber_enemies = _cyber_enemies.filter(func(e): return is_instance_valid(e))
	if _cyber_enemies.size() >= ENEMY_MAX_ALIVE: return
	var player = GameManager.player_ref
	if not player or not is_instance_valid(player): return
	var onscreen := 0
	for e in _cyber_enemies:
		if e.global_position.distance_to(player.global_position) < 700.0:
			onscreen += 1
	if onscreen >= ENEMY_MAX_ONSCREEN: return

	var side = 1.0 if randf() > 0.3 else -1.0
	var spawn_x = clampf(player.global_position.x + side * randf_range(400.0, 600.0), 4100.0, 6700.0)
	var config = load("res://DataConfig/Enemy/CleanerConfig.tres") as EnemyConfig
	var enemy = _spawn_enemy_with_config(_enemy_cyber_wolf_scene, Vector2(spawn_x, 540), config)
	if enemy:
		enemy.modulate = Color(0.3, 0.35, 0.4, 0.95)
		_cyber_enemies.append(enemy)


# ============================================================
# 击退反转
# ============================================================

func _on_player_hurt(data: Dictionary) -> void:
	if current_state not in [LevelState.LINGNAN_COMBAT, LevelState.CYBER_CITY, LevelState.MEMORY_COLLECTION]:
		return
	var player = data.get("player")
	if not player or not is_instance_valid(player): return

	var flags = GameManager.dream_runtime_flags
	var has_damage_reduction = flags.get("player_damage_reduction", false)
	if has_damage_reduction:
		var heal_amount = data.get("damage", 0) / 2
		if heal_amount > 0 and player.current_health < player.max_health:
			player.current_health = mini(player.current_health + heal_amount, player.max_health)
			EventBus.emit(GlobalDefine.EventName.HEALTH_CHANGED, {
				"target": player,
				"current_health": player.current_health,
				"max_health": player.max_health
			})

	# 赛博阶段：击退方向反转
	if current_state in [LevelState.CYBER_CITY, LevelState.MEMORY_COLLECTION]:
		player.velocity.x = -KNOCKBACK_REVERSE_FORCE


# ============================================================
# 异常数据光团收集
# ============================================================

func _handle_memory_echo_1() -> void:
	if not level_data: return
	memory_echoes_collected += 1
	_mark_interaction_completed("memory_echo_1")
	_spike_glitch()
	_show_narrative(level_data.memory_echo_1_subtitle, func():
		_show_narrative(level_data.memory_echo_1_codebuddy, func():
			_check_memory_collection_complete()
		)
	)

func _handle_memory_echo_2() -> void:
	if not level_data: return
	memory_echoes_collected += 1
	_mark_interaction_completed("memory_echo_2")
	_spike_glitch()
	_show_narrative(level_data.memory_echo_2_subtitle, func():
		_show_narrative(level_data.memory_echo_2_codebuddy, func():
			_check_memory_collection_complete()
		)
	)

func _check_memory_collection_complete() -> void:
	if memory_echoes_collected >= 2:
		_trigger_awakening()
	else:
		if current_state == LevelState.CYBER_CITY:
			current_state = LevelState.MEMORY_COLLECTION
			print("[Level_03] 进入 MEMORY_COLLECTION (已收集 %d/2)" % memory_echoes_collected)

## 互动时触发 glitch 强度脉冲，随后自动衰减回基线
func _spike_glitch() -> void:
	if not _glitch_overlay or not _glitch_overlay.material:
		return
	# 立即跳到峰值
	var mat: ShaderMaterial = _glitch_overlay.material
	mat.set_shader_parameter("intensity", GLITCH_SPIKE)
	var tween = create_tween()
	tween.tween_property(mat, "shader_parameter/intensity", GLITCH_AMBIENT, 2.0)


# ============================================================
# 觉醒与终局
# ============================================================

func _trigger_awakening() -> void:
	if _transition_running: return
	_transition_running = true
	_is_interacting = true
	current_state = LevelState.AWAKENING
	print("[Level_03] 觉醒开始")

	InputManager.block_input("觉醒", self)
	_freeze_player(true)
	_stop_cyber_elements()

	if _cyber_city_root:
		var tween = create_tween()
		tween.tween_property(_cyber_city_root, "modulate", Color(0.3, 0.3, 0.35), 1.5)
		await tween.finished

	if level_data and level_data.awakening_monologue != "":
		_show_narrative(level_data.awakening_monologue, func(): _trigger_level_end())
	else:
		_trigger_level_end()

func _stop_cyber_elements() -> void:
	if _enemy_spawn_timer: _enemy_spawn_timer.stop()
	_stop_code_rain()
	for e in _cyber_enemies:
		if is_instance_valid(e): e.set_physics_process(false)

func _trigger_level_end() -> void:
	current_state = LevelState.LEVEL_END_TRANSIT
	_freeze_player(false)
	_is_interacting = false
	_interact_cooldown = 0.0
	InputManager.force_unblock_all()
	if _ending_prompt:
		_ending_prompt.show()
		if _ending_label and level_data:
			_ending_label.text = level_data.override_protocol_text
	_ending_enter_armed = true
	_transition_running = false

func _emit_level_complete() -> void:
	if _level_complete_emitted: return
	_level_complete_emitted = true
	var next_path = level_data.next_level_path if level_data else "res://LevelModule/Formal/Level_04.tscn"
	# 关卡退出三件套：释放 GUI 焦点 + 强制解除输入屏蔽 + 清理
	get_viewport().gui_release_focus()
	InputManager.force_unblock_all()
	_full_cleanup()
	# 双模切换：无 MainEntry 托管时直接换场景，否则走 EventBus 由 MainEntry 接管
	if not _is_loaded_under_main_entry():
		print("[Level_03] 无 MainEntry，直接切换场景 → ", next_path)
		SceneTransitionManager.request_scene_change(next_path, self)
		return
	print("[Level_03] 发射 LEVEL_COMPLETE → ", next_path)
	EventBus.emit(GlobalDefine.EventName.LEVEL_COMPLETE, {"level": self, "next_level": next_path})

func _full_cleanup() -> void:
	_disconnect_input_manager()
	for e in _cyber_enemies:
		if is_instance_valid(e):
			GameManager.unregister_enemy(e)
			e.queue_free()
	_cyber_enemies.clear()
	if _enemy_spawn_timer and is_instance_valid(_enemy_spawn_timer):
		_enemy_spawn_timer.stop()
	EventBus.unsubscribe_all(self)

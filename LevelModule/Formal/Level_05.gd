# ============================================================
# Level_05.gd - 第五关（双世界 PixelTearing 侵蚀预览）
# 安全区跟随玩家，player_uv 映射到 TopSprite 的 UV 空间
# ← → 侵蚀深度  /  空格切换上层地图
# ============================================================
extends LevelBase
class_name Level_05

@onready var _top_sprite: Sprite2D = $TopSprite
@onready var _bot_sprite: Sprite2D = $BotSprite
@onready var _cyber_collisions: Node2D = $CyberCollisions
@onready var _lingnan_collisions: Node2D = $LingnanCollisions

var _top_mat: ShaderMaterial = null
var _edge_tear: ColorRect = null
var _corruption: float = 0.35
var _top_is_lingnan: bool = true
var _in_boss_arena: bool = false
var _boss_instance: Node2D = null
var _current_player_skin: String = "Cyber"   # 当前玩家皮肤（"Cyber"/"Lingnan"），用于G键切换
var _layer_swap_cd: float = 0.0              # 双世界切换冷却（防战斗中频繁切换）

# ---- 双角色独立血量（Boss战：Cyber/Lingnan 各100血，切人换血条，总200血） ----
const DUAL_CHAR_MAX_HP: int = 100
var _cyber_health: int = DUAL_CHAR_MAX_HP
var _lingnan_health: int = DUAL_CHAR_MAX_HP
var _cyber_hint_shown: bool = false   # 赛博人物首次扣血到50时是否已显示提示
var _lingnan_hint_shown: bool = false # 岭南人物首次扣血到50时是否已显示提示
const LAYER_SWAP_COOLDOWN: float = 1.2       # 切换冷却时长

# ---- bg5 区域（Boss击杀后灯笼对话跳转） ----
var _in_bg5: bool = false
var _lantern_instance: Node2D = null
@onready var _bg5_bg: Sprite2D = $Bg5
@onready var _bg5_collisions: Node2D = $Bg5Collisions
const BG5_CENTER_X: float = 569.0            # bg5区域x中心（与bg4远离）
const BG5_PLAYER_POS := Vector2(569, 8076)
const BG5_CAM_LEFT: int = 200
const BG5_CAM_RIGHT: int = 2200
const BG5_CAM_TOP: int = 7700
const BG5_CAM_BOTTOM: int = 8300

# ---- 交互物 ----
var _all_interactives: Array[InteractiveObject] = []

# ---- Boss 血条 ----
var _boss_bar_container: Control = null
var _boss_bar_fill: ColorRect = null
var _boss_bar_label: Label = null
const BOSS_BAR_MAX_WIDTH: float = 400.0

# ---- 对话框 ----
var _dialog_panel: Panel = null
var _dialog_label: RichTextLabel = null
var _dialog_enter_pressed: bool = false
var _dialog_open: bool = false
var _dialog_callback: Callable = Callable()
var _dialog_lines: Array[String] = []
var _dialog_index: int = 0
var _dialog_close_cooldown: float = 0.0   # 对话关闭后的输入冷却，防Enter串扰
var _grandpa_video_started: bool = false

# ---- 侵蚀值 ----
var _erosion_value: float = 0.0
var _erosion_bar_bg: ColorRect = null
var _erosion_bar_fill: ColorRect = null
var _erosion_label: Label = null
var _code_rain_overlay: CodeRain = null
const EROSION_MAX: float = 100.0
const EROSION_RATE: float = 0.7
const EROSION_KILL_REDUCE: float = 15.0

# ---- 敌人 ----
## 所有敌人：换层时清空重建
var _all_enemies: Array[Node2D] = []
var _enemy_lantern_scene: PackedScene = null
var _enemy_paper_scene: PackedScene = null
var _enemy_wolf_scene: PackedScene = null
var _enemy_bull_scene: PackedScene = null

# ---- 双世界独立敌人组（切换世界时切换显示，各自血量独立保存） ----
var _lingnan_enemies: Array[Node2D] = []   # 岭南世界怪物（纸人+灯笼）
var _cyber_enemies: Array[Node2D] = []     # 赛博世界怪物（狼人+冲撞兽）


func _setup_player() -> void:
	# 清除 lv4 遗留的旧玩家引用
	if GameManager.player_ref:
		if is_instance_valid(GameManager.player_ref):
			GameManager.player_ref.queue_free()
		GameManager.player_ref = null

	var path = "res://PlayerModule/Formal/Player_Warrior_Cyber.tscn"
	if ResourceLoader.exists(path):
		var p = load(path).instantiate()
		p.position = Vector2(-1603, 380)
		_current_player_skin = "Cyber"
		# Lingnan 角色初始满血100（Cyber 的初始血量由 _on_ready 从 lv4 继承设置）
		_lingnan_health = DUAL_CHAR_MAX_HP
		add_child(p)
		GameManager.register_player(p)
		# _ready 中 _apply_config 会重置血量,需在此之后设为独立血量
		p.max_health = DUAL_CHAR_MAX_HP
		p.current_health = _cyber_health
		var cam = p.get_node_or_null("SmoothCamera") as SmoothCamera
		if cam:
			cam.zoom = Vector2(1.33, 1.33)
			cam.bind_target(p)
			cam.follow_enabled = true
			cam.make_current()
		# 摄像机边界从碰撞体读取（bg3 区域，上边界 80）
		_set_cam_from_group($CyberCollisions, 80, 648)
		# 推送血量到 HUD
		EventBus.emit(GlobalDefine.EventName.HEALTH_CHANGED, {
			"target": p,
			"current_health": p.current_health,
			"max_health": p.max_health
		})

func _swap_player_skin(skin: String) -> void:
	var old = GameManager.player_ref
	if not old or not is_instance_valid(old): return
	# 保存旧角色的血量到对应变量（双角色独立血量，切人不回满）
	if _current_player_skin == "Cyber":
		_cyber_health = old.current_health
		_check_low_hp_hint("Cyber", _cyber_health)
	else:
		_lingnan_health = old.current_health
		_check_low_hp_hint("Lingnan", _lingnan_health)
	var f = old.is_facing_right; var pos = old.global_position
	# 保存旧摄像机限制
	var old_cam = old.get_node_or_null("SmoothCamera")
	var saved_limits = null
	if old_cam:
		saved_limits = [old_cam.limit_left, old_cam.limit_right, old_cam.limit_top, old_cam.limit_bottom]
	if InputManager.game_action.is_connected(old._on_game_action):
		InputManager.game_action.disconnect(old._on_game_action)
	# 先创建新玩家，再释放旧的
	var path = "res://PlayerModule/Formal/Player_Warrior_" + skin + ".tscn"
	if not ResourceLoader.exists(path): return
	var p = load(path).instantiate()
	p.global_position = pos
	# 恢复目标角色的独立血量（不回满）
	p.max_health = DUAL_CHAR_MAX_HP
	p.current_health = _cyber_health if skin == "Cyber" else _lingnan_health
	p.is_facing_right = f; p.velocity = Vector2.ZERO
	GameManager.player_ref = null
	add_child(p); GameManager.register_player(p)
	# 释放旧玩家（先禁用处理，再释放）
	old.set_physics_process(false)
	old.set_process(false)
	old.queue_free()
	# _ready 中 _apply_config 会重置血量为 max_health，需在此之后恢复独立血量
	p.max_health = DUAL_CHAR_MAX_HP
	p.current_health = _cyber_health if skin == "Cyber" else _lingnan_health
	_current_player_skin = skin  # 更新为新skin
	# 恢复摄像机：设限制 → bind_target(snap+reset) → 激活
	var cam = p.get_node_or_null("SmoothCamera") as SmoothCamera
	if cam:
		if saved_limits:
			cam.limit_left = saved_limits[0]; cam.limit_right = saved_limits[1]
			cam.limit_top = saved_limits[2]; cam.limit_bottom = saved_limits[3]
		cam.zoom = Vector2(1.33, 1.33)
		cam.bind_target(p)
		cam.follow_enabled = true
		cam.make_current()
	# 推送血量到 HUD（修复换皮肤后血条不更新）
	EventBus.emit(GlobalDefine.EventName.HEALTH_CHANGED, {
		"target": p,
		"current_health": p.current_health,
		"max_health": p.max_health
	})

## G键切换人物形象（仅bg4 Boss区域）：赛博 ↔ 岭南
func _toggle_boss_skin() -> void:
	var new_skin = "Lingnan" if _current_player_skin == "Cyber" else "Cyber"
	var path = "res://PlayerModule/Formal/Player_Warrior_" + new_skin + ".tscn"
	if not ResourceLoader.exists(path):
		print("[Level_05] 切换皮肤失败，场景不存在: %s" % path)
		return
	_swap_player_skin(new_skin)

func _snap_camera(p: CharacterBody2D) -> void:
	var c = p.get_node_or_null("SmoothCamera")
	if c: c.global_position = p.global_position

func _set_camera_limits(l: int, r: int, t: int, b: int) -> void:
	var p = GameManager.player_ref; if not p or not is_instance_valid(p): return
	var c = p.get_node_or_null("SmoothCamera") as SmoothCamera; if not c: return
	c.limit_left = l; c.limit_right = r; c.limit_top = t; c.limit_bottom = b

## 遍历容器内所有 StaticBody2D 的 RectangleShape2D，取世界坐标 AABB 并集
func _collision_group_rect(group: Node) -> Rect2:
	var rect := Rect2()
	var first := true
	if not group or not is_instance_valid(group): return rect
	for body in group.get_children():
		if body is StaticBody2D:
			for c in body.get_children():
				if c is CollisionShape2D and c.shape is RectangleShape2D:
					var rs := c.shape as RectangleShape2D
					var center: Vector2 = (body as Node2D).global_position + (c as CollisionShape2D).position
					var r := Rect2(center - rs.size / 2.0, rs.size)
					if first: rect = r; first = false
					else: rect = rect.merge(r)
	return rect

## 从碰撞体容器设摄像机边界（左/右从碰撞体读，上边界手动指定，下边界可选手动指定）
func _set_cam_from_group(group: Node, top: int, bottom: int = -1) -> void:
	if not group or not is_instance_valid(group): return
	var rect := _collision_group_rect(group)
	var b: int = bottom if bottom >= 0 else int(rect.end.y)
	_set_camera_limits(int(rect.position.x), int(rect.end.x), top, b)

func _on_ready() -> void:
	super._on_ready()

	# 入场黑屏遮罩（初始化在黑屏下进行，末尾淡出呈现关卡）
	_play_intro_fade_in()

	# 继承 lv4 的侵蚀值
	var flags = GameManager.dream_runtime_flags
	if flags.has("erosion_value"):
		_erosion_value = flags["erosion_value"]
	# 继承 lv4 的玩家血量：作为 Cyber 角色的初始血量（Boss战前玩家的血量延续到Cyber）
	# Lingnan 角色初始为满血100（Boss战双角色独立血量）
	if flags.has("player_health"):
		_cyber_health = clampi(int(flags["player_health"]), 1, DUAL_CHAR_MAX_HP)
	_lingnan_health = DUAL_CHAR_MAX_HP
	var p = GameManager.player_ref
	if p and is_instance_valid(p):
		p.max_health = DUAL_CHAR_MAX_HP
		p.current_health = _cyber_health
		EventBus.emit(GlobalDefine.EventName.HEALTH_CHANGED, {
			"target": p,
			"current_health": p.current_health,
			"max_health": p.max_health
		})

	# 订阅敌人死亡事件
	EventBus.subscribe(GlobalDefine.EventName.ENEMY_DIED, self, "_on_enemy_died")
	# 订阅战斗事件：击中敌人/被击中 → 触发双世界切换
	EventBus.subscribe(GlobalDefine.EventName.PLAYER_ATTACK_HIT, self, "_on_combat_swap_layer")
	EventBus.subscribe(GlobalDefine.EventName.PLAYER_HURT, self, "_on_combat_swap_layer")
	# 订阅血量变化：Boss战角色首次扣血到50时再次显示换人提示
	EventBus.subscribe(GlobalDefine.EventName.HEALTH_CHANGED, self, "_on_health_changed")
	# 订阅交互事件
	EventBus.subscribe(GlobalDefine.EventName.INTERACTIVE_OBJECT_TRIGGERED, self, "_on_object_interacted")

	# 加载 HUD（修复 lv5 血条不显示）
	_load_hud()

	# 缓存交互物
	_cache_interactives()

	# 加载敌人场景
	_enemy_lantern_scene = _load_scene("res://EnemyModule/Formal/Enemy_LanternGhost.tscn")
	_enemy_paper_scene   = _load_scene("res://EnemyModule/Formal/Enemy_PaperEffigy.tscn")
	_enemy_wolf_scene    = _load_scene("res://EnemyModule/Formal/Enemy_CyberWolf.tscn")
	_enemy_bull_scene    = _load_scene("res://EnemyModule/Formal/Enemy_CyberBull.tscn")

	# 初始：岭南在上 → 赛博在下层透出 → 激活赛博碰撞体
	_set_collision_group_active(_cyber_collisions, true)
	_set_collision_group_active(_lingnan_collisions, false)
	# bg5 碰撞体初始禁用（tscn 已设 visible=false，碰撞体需脚本关闭）
	_set_bg5_area_active(false)
	_build_code_rain_overlay()

	# 岭南在上 → 生成双世界怪物（赛博世界怪物隐藏）
	_spawn_dual_world_enemies()

	var shader = load("res://LevelModule/Formal/PixelTearing.gdshader")
	if shader:
		_top_mat = ShaderMaterial.new()
		_top_mat.shader = shader
		var noise = load("res://Resources/TearingNoiseTexture.tres")
		_top_mat.set_shader_parameter("noise_tex", noise)
		_top_mat.set_shader_parameter("noise_size", Vector2(512.0, 512.0))
		_top_mat.set_shader_parameter("corruption_level", _corruption)
		_top_mat.set_shader_parameter("player_uv", Vector2(0.5, 0.5))
		_top_mat.set_shader_parameter("chunk_size", 20.0)
		_top_mat.set_shader_parameter("glitch_color", Color(0.8, 0.1, 0.6, 1.0))
		_top_sprite.material = _top_mat

	# 边缘撕裂覆盖层
	var cv = get_node_or_null("CanvasLayer")
	if cv:
		_edge_tear = ColorRect.new()
		_edge_tear.name = "EdgeTear"
		_edge_tear.set_anchors_preset(Control.PRESET_FULL_RECT)
		_edge_tear.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_edge_tear.z_index = 110
		var tear_shader = load("res://LevelModule/Formal/edge_tear.gdshader")
		if tear_shader:
			var mat = ShaderMaterial.new()
			mat.shader = tear_shader
			mat.set_shader_parameter("intensity", 0.2)
			_edge_tear.material = mat
		cv.add_child(_edge_tear)

	# 侵蚀进度条
	_build_erosion_bar()

	set_process_input(true)
	set_process(true)
	# 初始化完成，淡出黑屏呈现关卡
	_finish_intro_fade_in()

	# 检查点恢复：如果之前在bg4死亡，直接传送玩家到bg4区域重新开始Boss战
	print("[Level_05] 检查点阶段: %d, 路径: %s" % [GameManager.checkpoint_stage, GameManager.checkpoint_scene_path])
	if GameManager.checkpoint_stage >= 4:
		# 跳过bg3，直接进入bg4
		_in_boss_arena = true
		# 标记交互点已完成（避免重复触发）
		for obj in _all_interactives:
			if obj.object_id == "enter_boss":
				obj.mark_completed()
		# 直接传送到bg4并生成Boss
		_teleport_and_setup_camera(Vector2(931, 5037), 620, 1710, 4509, 5135, 1.5)
		_set_boss_area_active(true)
		_set_map_sprites_visible(false)
		_spawn_boss()
		_show_boss_bar()
		# 恢复玩家满血（检查点重开：双角色都回满100血）
		_cyber_health = DUAL_CHAR_MAX_HP
		_lingnan_health = DUAL_CHAR_MAX_HP
		var pp = GameManager.player_ref
		if pp and is_instance_valid(pp):
			pp.max_health = DUAL_CHAR_MAX_HP
			pp.current_health = DUAL_CHAR_MAX_HP
			EventBus.emit(GlobalDefine.EventName.HEALTH_CHANGED, {
				"target": pp,
				"current_health": pp.current_health,
				"max_health": pp.max_health
			})
		print("[Level_05] 从检查点恢复：直接进入bg4 Boss战")
		# 显示"按G切换人物外观"指引
		_show_skin_hint()
	# 调试：阶段测试面板（按0开关）
	_setup_stage_test_panel()


func _setup_stage_test_panel() -> void:
	var script = load("res://Tools/StageTestPanel.gd")
	if not script:
		push_error("[Level_05] 无法加载 StageTestPanel.gd")
		return
	var panel = script.new(self, [
		{"name": "bg3: 双世界侵蚀", "action": func(): _goto_bg3_test()},
		{"name": "bg4: Boss战", "action": func(): _goto_bg4_test()},
		{"name": "bg5: 灯笼结局", "action": func(): _goto_bg5_test()},
	])
	add_child(panel)

func _goto_bg3_test() -> void:
	_in_boss_arena = false
	_in_bg5 = false
	_set_boss_area_active(false)
	_set_bg5_area_active(false)
	_set_map_sprites_visible(true)
	_set_collision_group_active(_cyber_collisions, true)
	_set_collision_group_active(_lingnan_collisions, false)
	_teleport_and_setup_camera(Vector2(-1603, 380), 0, 0, 80, 648, 1.33)
	_set_cam_from_group($CyberCollisions, 80, 648)
	_despawn_boss()
	_hide_boss_bar()
	_spawn_all_enemies(true)
	_sync_code_rain_for_bg5()

func _goto_bg4_test() -> void:
	_in_boss_arena = true
	_in_bg5 = false
	_set_boss_area_active(true)
	_set_map_sprites_visible(false)
	_set_bg5_area_active(false)
	_teleport_and_setup_camera(Vector2(931, 5037), 620, 1710, 4509, 5135, 1.5)
	_set_cam_from_group($BossCollisions, 4512)
	_spawn_boss()
	_show_boss_bar()
	_show_skin_hint()
	_sync_code_rain_for_bg5()

func _goto_bg5_test() -> void:
	_in_boss_arena = false
	_in_bg5 = true
	if _current_player_skin != "Cyber":
		_swap_player_skin("Cyber")
	_set_boss_area_active(false)
	_set_map_sprites_visible(false)
	_set_bg5_area_active(true)
	_teleport_and_setup_camera(BG5_PLAYER_POS, BG5_CAM_LEFT, BG5_CAM_RIGHT, 7448, BG5_CAM_BOTTOM, 1.33)
	_set_cam_from_group($Bg5Collisions, 7448)
	_hide_boss_bar()
	_despawn_boss()
	_sync_code_rain_for_bg5()


func _exit_tree() -> void:
	prepare_for_level_exit()


func prepare_for_level_exit() -> void:
	Engine.time_scale = 1.0
	InputManager.unblock_input("视频演出")
	InputManager.unblock_input("对话")
	_dialog_open = false
	_dialog_callback = Callable()
	_clear_all_enemies()
	_despawn_boss()
	if _lantern_instance and is_instance_valid(_lantern_instance):
		_lantern_instance.queue_free()
		_lantern_instance = null
	GameManager.boss_target = null
	EventBus.unsubscribe_all(self)


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


func _process(delta: float) -> void:
	# 切换冷却递减
	_layer_swap_cd = maxf(0.0, _layer_swap_cd - delta)
	# 对话期间暂停侵蚀
	if not _dialog_open and not _in_bg5:
		_modify_erosion(EROSION_RATE * delta)
	_corruption = _erosion_value / 100.0

	# player_uv → 玩家在屏幕上的 UV
	var player_uv = Vector2(0.5, 0.5)
	var p = GameManager.player_ref
	var vp = get_viewport()
	if p and is_instance_valid(p) and vp:
		var size = vp.get_visible_rect().size
		if size.x > 0.0 and size.y > 0.0:
			# get_global_transform_with_canvas() 包含相机变换 → 真实屏幕像素坐标
			var screen_pos = p.get_global_transform_with_canvas().origin
			player_uv = Vector2(
				clampf(screen_pos.x / size.x, 0.0, 1.0),
				clampf(screen_pos.y / size.y, 0.0, 1.0)
			)

	_top_mat.set_shader_parameter("corruption_level", _corruption)
	_top_mat.set_shader_parameter("player_uv", player_uv)

	# 边缘撕裂强度随侵蚀值上升
	if _edge_tear and _edge_tear.material:
		_edge_tear.material.set_shader_parameter("intensity", clampf(_corruption * 0.6, 0.05, 0.5))

	# 交互物轮询兜底（对话期间不检测；冷却期间仍检测距离，只防Enter串扰）
	var pl = GameManager.player_ref
	if pl and is_instance_valid(pl) and not _dialog_open:
		for obj in _all_interactives:
			if is_instance_valid(obj):
				obj.check_player_in_range(pl)
	# 对话关闭冷却递减
	_dialog_close_cooldown = maxf(0.0, _dialog_close_cooldown - delta)
	# 灯笼提示更新
	_update_lantern_prompt()

	# Boss 血条更新
	_update_boss_bar()

	# 对话推进
	if _dialog_open and _dialog_enter_pressed:
		_dialog_enter_pressed = false
		_advance_dialog()

	# bg5 区域持续隐藏UI + 禁用战斗能力（防止切人后恢复）
	if _in_bg5:
		_update_bg5_ui_hide()
		var pp = GameManager.player_ref
		if pp and is_instance_valid(pp):
			if pp.can_attack: pp.can_attack = false
			if pp.can_skill: pp.can_skill = false
			if pp.can_dash: pp.can_dash = false
			if pp.can_attack_hold_dash: pp.can_attack_hold_dash = false

func _input(event: InputEvent) -> void:
	# 玩家死亡后禁止所有交互输入
	if GameManager.is_game_over: return
	# 鼠标左键等价于Enter（对话推进/交互触发）
	var is_left_click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	# 对话框打开时，Enter或左键推进对话
	if _dialog_open:
		if event.is_action_pressed("ui_accept") or is_left_click:
			_dialog_enter_pressed = true
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_left"):
		_corruption = maxf(0.0, _corruption - 0.05)
		get_viewport().set_input_as_handled()
		_update_label()
	elif event.is_action_pressed("ui_right"):
		_corruption = minf(1.0, _corruption + 0.05)
		get_viewport().set_input_as_handled()
		_update_label()
	elif event.is_action_pressed("ui_accept") or is_left_click:
		if _dialog_close_cooldown > 0:
			get_viewport().set_input_as_handled()
		else:
			# 优先检测灯笼（自定义交互）
			if _is_player_near_lantern() and not _in_bg5:
				_on_lantern_interacted()
				get_viewport().set_input_as_handled()
			else:
				var obj = _find_nearby_interactive()
				if obj:
					EventBus.emit(GlobalDefine.EventName.INTERACTIVE_OBJECT_TRIGGERED, {"object_id": obj.object_id})
					get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_G:
		# G键切换人物形象（仅限bg4 Boss区域，赛博/岭南之间切换）
		if _in_boss_arena and not _dialog_open:
			_toggle_boss_skin()
			get_viewport().set_input_as_handled()


## 切换双世界上下层（bg3区域）：战斗触发，带抖屏效果
func _swap_world_layer() -> void:
	_top_is_lingnan = not _top_is_lingnan
	if _top_is_lingnan:
		_top_sprite.texture = load("res://LevelModule/Scenes/PixelworkMapStitch/Level05_Lingnan/bg 3-2.png")
		_top_sprite.scale = Vector2(1.6, 1.6)
		_bot_sprite.texture = load("res://LevelModule/Scenes/PixelworkMapStitch/Level05_Cyber/bg 3-1.png")
		_bot_sprite.scale = Vector2(0.8, 0.8)
		_top_mat.set_shader_parameter("glitch_color", Color(0.8, 0.1, 0.6, 1.0))
		_set_collision_group_active(_lingnan_collisions, false)
		_set_collision_group_active(_cyber_collisions, true)
		_show_enemy_group(_lingnan_enemies, true)
		_show_enemy_group(_cyber_enemies, false)
	else:
		_top_sprite.texture = load("res://LevelModule/Scenes/PixelworkMapStitch/Level05_Cyber/bg 3-1.png")
		_top_sprite.scale = Vector2(0.8, 0.8)
		_bot_sprite.texture = load("res://LevelModule/Scenes/PixelworkMapStitch/Level05_Lingnan/bg 3-2.png")
		_bot_sprite.scale = Vector2(1.6, 1.6)
		_top_mat.set_shader_parameter("glitch_color", Color(0.1, 0.8, 0.9, 1.0))
		_set_collision_group_active(_lingnan_collisions, true)
		_set_collision_group_active(_cyber_collisions, false)
		_show_enemy_group(_cyber_enemies, true)
		_show_enemy_group(_lingnan_enemies, false)
	_update_label()
	# 抖屏效果：世界撕裂感
	_trigger_screen_shake(8.0, 0.25)

## 生成双世界怪物（岭南+赛博各一组，各自独立血量，赛博组初始隐藏）
func _spawn_dual_world_enemies() -> void:
	_clear_all_enemies()
	_lingnan_enemies.clear()
	_cyber_enemies.clear()
	var ground_spots = [Vector2(-1000, 420), Vector2(0, 415), Vector2(800, 425)]
	var special_spots = [Vector2(200, 380), Vector2(600, 370)]
	# 岭南世界：纸人 + 灯笼（初始显示）
	for sp in ground_spots:
		var e = _spawn_one(_enemy_paper_scene, sp)
		if e: _lingnan_enemies.append(e)
	for sp in special_spots:
		var e = _spawn_one(_enemy_lantern_scene, sp)
		if e: _lingnan_enemies.append(e)
	# 赛博世界：狼人 + 冲撞兽（初始隐藏）
	for sp in ground_spots:
		var e = _spawn_one(_enemy_wolf_scene, sp)
		if e: _cyber_enemies.append(e)
	for sp in special_spots:
		var e = _spawn_one(_enemy_bull_scene, sp)
		if e: _cyber_enemies.append(e)
	# 隐藏赛博世界怪物
	_show_enemy_group(_cyber_enemies, false)

## 显示/隐藏一组敌人（隐藏时暂停AI并禁用碰撞，显示时恢复）
func _show_enemy_group(group: Array, visible_flag: bool) -> void:
	for e in group:
		if is_instance_valid(e):
			e.visible = visible_flag
			e.set_physics_process(visible_flag)
			# 禁用/启用碰撞
			if e is CollisionObject2D:
				if visible_flag:
					(e as CollisionObject2D).collision_layer = GlobalDefine.Collision.ENEMY
				else:
					(e as CollisionObject2D).collision_layer = 0
			# 隐藏时暂停移动
			if not visible_flag:
				e.velocity = Vector2.ZERO
				if e is EnemyBase:
					(e as EnemyBase).current_state = GlobalDefine.EnemyState.IDLE


## 触发抖屏（通过玩家相机的 shake 方法）
func _trigger_screen_shake(strength: float, duration: float) -> void:
	var p = GameManager.player_ref
	if not p or not is_instance_valid(p): return
	var cam = p.get_node_or_null("SmoothCamera") as SmoothCamera
	if cam and cam.has_method("shake"):
		cam.shake(strength, duration)


## 战斗触发双世界切换：击中敌人或被击中时（仅bg3区域，带冷却防频繁切换）
func _on_combat_swap_layer(_data: Dictionary) -> void:
	# 仅在bg3双世界区域生效，Boss区域/bg5内不触发
	if _in_boss_arena or _in_bg5: return
	if _dialog_open: return
	if _layer_swap_cd > 0.0: return
	_layer_swap_cd = LAYER_SWAP_COOLDOWN
	_swap_world_layer()


func _set_collision_group_active(group: Node2D, active: bool) -> void:
	if not group: return
	for child in group.get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", not active)
		elif child is StaticBody2D:
			for c in child.get_children():
				if c is CollisionShape2D:
					c.set_deferred("disabled", not active)

func _update_label() -> void:
	pass  # InfoLabel 已移除，侵蚀信息由 _erosion_label 显示

func _load_scene(path: String) -> PackedScene:
	if ResourceLoader.exists(path):
		return load(path)
	return null

func _load_hud() -> void:
	var p = "res://UI/HUD.tscn"
	if ResourceLoader.exists(p):
		var hud = load(p).instantiate()
		add_child(hud)
		# 立即推送当前血量到 HUD
		var pl = GameManager.player_ref
		if pl and is_instance_valid(pl):
			EventBus.emit(GlobalDefine.EventName.HEALTH_CHANGED, {
				"target": pl,
				"current_health": pl.current_health,
				"max_health": pl.max_health
			})

func _cache_interactives() -> void:
	_all_interactives.clear()
	_collect_interactives_recursive(self)

func _collect_interactives_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is InteractiveObject:
			_all_interactives.append(child)
			child.apply_level01_dot_visual()
		_collect_interactives_recursive(child)

func _find_nearby_interactive() -> InteractiveObject:
	for obj in _all_interactives:
		if is_instance_valid(obj) and obj.is_active and not obj.completed and obj.is_player_in_range:
			return obj
	return null

func _get_interactive_by_id(object_id: String) -> InteractiveObject:
	for obj in _all_interactives:
		if is_instance_valid(obj) and obj.object_id == object_id:
			return obj
	return null

func _on_object_interacted(data: Dictionary) -> void:
	var oid: String = data.get("object_id", "")
	if oid == "enter_boss":
		_enter_boss_arena()
	elif oid == "grandpa":
		if _grandpa_video_started:
			return
		_grandpa_video_started = true
		var grandpa := _get_interactive_by_id("grandpa")
		if grandpa:
			grandpa.mark_completed()
		_show_dialog(["爷爷？"], _play_grandpa_video)

## 播放视频演出（爷爷交互后）：先淡入黑屏，再播放视频
func _play_grandpa_video() -> void:
	if not _grandpa_video_started:
		_grandpa_video_started = true
	var stream := load("res://Assets/视频演出.ogv") as VideoStream
	if stream == null:
		push_error("[Level_05] 视频演出.ogv 加载失败")
		_show_dialog(["（视频加载失败）"], Callable())
		return
	# 屏蔽游戏输入
	InputManager.block_input("视频演出", self)
	# 用 CanvasLayer 确保在最上层
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	# 淡入黑屏
	var black_bg := ColorRect.new()
	black_bg.color = Color(0, 0, 0, 0)  # 初始透明
	black_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	black_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	black_bg.z_index = 200
	layer.add_child(black_bg)
	var fade_tween := black_bg.create_tween()
	fade_tween.tween_property(black_bg, "color:a", 1.0, 1.0)  # 1秒淡入到全黑
	await fade_tween.finished
	print("[Level_05] 淡入黑屏完成，开始播放视频")
	# 视频播放器（静音视频原声，BGM 继续播放不打断）
	var vp := VideoStreamPlayer.new()
	vp.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.expand = true
	vp.autoplay = true
	vp.stream = stream
	vp.volume_db = -80.0  # 禁用视频原声
	vp.bus = "Master"
	vp.mouse_filter = Control.MOUSE_FILTER_STOP
	black_bg.add_child(vp)
	print("[Level_05] 视频演出开始播放")
	# 等待视频播放结束
	await vp.finished
	print("[Level_05] 视频演出播放结束，淡入黑屏")
	# 视频结束后：保留 layer/black_bg，淡入黑屏（1.5s），再切换关卡
	var fade_out_tween := black_bg.create_tween()
	# black_bg 当前已是 alpha=1.0（视频前淡入过），但视频 expand 会盖住它，
	# 这里把视频移除后让黑屏自然显现，并加一个保险淡入
	vp.queue_free()
	black_bg.color.a = 1.0
	fade_out_tween.tween_interval(1.5)
	await fade_out_tween.finished
	# 清理
	InputManager.unblock_input("视频演出")
	layer.queue_free()
	print("[Level_05] 黑屏淡入完成，切换到 Level_final")
	# 切换到终局关卡
	GameManager.run_mode = GlobalDefine.RunMode.FORMAL
	SceneTransitionManager.request_scene_change("res://LevelModule/Formal/Level_final.tscn", self)

## Boss死亡时缓结束后：恢复时缓，生成灯笼，显示死亡对话
func _on_boss_death_recover(death_pos: Vector2) -> void:
	Engine.time_scale = 1.0
	_spawn_lantern(death_pos)
	_show_dialog([
		"[color=#ff6b9d]花旦：[/color]为什么要拥抱……残酷的现实……",
	], Callable())

## 在Boss死亡位置生成灯笼交互物
func _spawn_lantern(pos: Vector2) -> void:
	if _lantern_instance and is_instance_valid(_lantern_instance):
		_lantern_instance.queue_free()
	var lantern = Node2D.new()
	lantern.name = "BossLantern"
	lantern.global_position = pos + Vector2(0, 15)
	# 灯笼背后的发光
	var glow = Sprite2D.new()
	glow.name = "Glow"
	var tex = load("res://Assets/Effects/灯笼.png") as Texture2D
	if tex:
		glow.texture = tex
		glow.scale = Vector2(0.05, 0.05)
		glow.modulate = Color(1.0, 0.8, 0.3, 0.6)
		glow.z_index = 4
		lantern.add_child(glow)
	# 灯笼贴图
	if tex:
		var spr = Sprite2D.new()
		spr.name = "LanternSprite"
		spr.texture = tex
		spr.scale = Vector2(0.05, 0.05)
		spr.z_index = 5
		lantern.add_child(spr)
	# 交互提示标签
	var prompt = Label.new()
	prompt.name = "Prompt"
	prompt.text = "按 Enter 拾起灯笼"
	prompt.visible = false
	prompt.add_theme_font_size_override("font_size", 21)
	prompt.add_theme_color_override("font_color", Color(1, 0.9, 0.2, 0.95))
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.position = Vector2(-80, -55)
	prompt.size = Vector2(160, 20)
	lantern.add_child(prompt)
	add_child(lantern)
	_lantern_instance = lantern
	if tex and glow:
		_play_lantern_spawn(lantern, glow)
	print("[Level_05] 灯笼已生成于 %s" % lantern.global_position)

## 灯笼出场动效：从小变大出现 + 落地弹两下
## 注意：只移动 sprite/glow 子节点（视觉），不移动 lantern 本身（Area2D位置不变，防body_exited误触发）
func _play_lantern_spawn(lantern: Node2D, glow: Sprite2D) -> void:
	var spr = lantern.get_node_or_null("LanternSprite") as Sprite2D
	if not spr: return
	# 视觉初始位置：上方100px，scale从0增长
	spr.position = Vector2(0, -100)
	glow.position = Vector2(0, -100)
	spr.scale = Vector2(0.0, 0.0)
	glow.scale = Vector2(0.0, 0.0)
	# glow 呼吸动画（持续循环）
	var glow_tw = glow.create_tween().set_loops()
	glow_tw.tween_property(glow, "modulate:a", 0.3, 0.8).set_trans(Tween.TRANS_SINE)
	glow_tw.tween_property(glow, "modulate:a", 0.7, 0.8).set_trans(Tween.TRANS_SINE)
	# 出现：scale 0→0.05（0.4s），sprite/glow 从上方下落
	var tw = spr.create_tween()
	var gtw = glow.create_tween()
	tw.tween_property(spr, "scale", Vector2(0.05, 0.05), 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	gtw.tween_property(glow, "scale", Vector2(0.07, 0.07), 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 下落到地面（y=0，即 lantern 中心）
	tw.tween_property(spr, "position:y", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	gtw.parallel().tween_property(glow, "position:y", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# 弹起第一次（上移40，再落回）
	tw.tween_property(spr, "position:y", -40.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	gtw.parallel().tween_property(glow, "position:y", -40.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(spr, "position:y", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	gtw.parallel().tween_property(glow, "position:y", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# 弹起第二次（上移15，再落回）
	tw.tween_property(spr, "position:y", -15.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	gtw.parallel().tween_property(glow, "position:y", -15.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(spr, "position:y", 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	gtw.parallel().tween_property(glow, "position:y", 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

## 玩家与灯笼交互：对话后跳转bg5
func _on_lantern_interacted() -> void:
	# 灯笼设为 allow_repeat，不标记 completed，对话结束后仍可再次交互
	_show_dialog([
		"[color=cyan]阿明：[/color]这是……爷爷给我的手提灯笼？",
	], _teleport_to_bg5)

## 检查玩家是否在灯笼交互范围内（自定义距离检测，不依赖Area2D）
func _is_player_near_lantern() -> bool:
	if not _lantern_instance or not is_instance_valid(_lantern_instance): return false
	var p = GameManager.player_ref
	if not p or not is_instance_valid(p): return false
	return p.global_position.distance_to(_lantern_instance.global_position) <= 130.0

## 更新灯笼提示标签显隐（每帧调用）
func _update_lantern_prompt() -> void:
	if not _lantern_instance or not is_instance_valid(_lantern_instance): return
	var prompt = _lantern_instance.get_node_or_null("Prompt")
	if not prompt: return
	var near = _is_player_near_lantern() and not _dialog_open and not _in_bg5
	prompt.visible = near
	if near:
		var alpha = 0.6 + 0.4 * abs(sin(Time.get_ticks_msec() * 0.004))
		prompt.add_theme_color_override("font_color", Color(1, 0.9, 0.2, alpha))

## 传送至bg5区域（激活bg5节点 + 传送 + 隐藏bg3/bg4）
func _teleport_to_bg5() -> void:
	_in_boss_arena = false
	_in_bg5 = true
	if _current_player_skin != "Cyber":
		_swap_player_skin("Cyber")
	_set_boss_area_active(false)
	_set_map_sprites_visible(false)
	_set_bg5_area_active(true)
	_teleport_and_setup_camera(BG5_PLAYER_POS, BG5_CAM_LEFT, BG5_CAM_RIGHT, 7448, BG5_CAM_BOTTOM, 1.33)
	_set_cam_from_group($Bg5Collisions, 7448)
	_hide_boss_bar()
	# 进入 bg5：播放 lv6（不打断，从 bossfight 自然过渡）
	MusicManager.fade_to("res://Assets/Music/lv6.ogg", 1.5)
	# bg5 区域玩家移速降为 0.5 倍，禁用闪避/技能/攻击，隐藏所有战斗UI
	var p = GameManager.player_ref
	if p and is_instance_valid(p):
		p.runtime_move_speed_multiplier = 0.5
		p.can_dash = false
		p.can_skill = false
		p.can_attack = false
		p.can_attack_hold_dash = false
	_sync_code_rain_for_bg5()
	print("[Level_05] 已进入 bg5 区域")

## 每帧持续隐藏所有战斗UI（_in_bg5 时调用，防止 HUD _process 恢复可见性）
func _update_bg5_ui_hide() -> void:
	if not _in_bg5: return
	# 隐藏 HUD（血条+技能+蓄力图标+侵蚀进度条都在 HUD 下）
	var hud = get_node_or_null("HUD")
	if hud and hud.visible:
		hud.visible = false

## 激活/禁用bg5区域节点（背景显隐 + 碰撞体开关 + 爷爷交互物开关）
func _set_bg5_area_active(active: bool) -> void:
	if _bg5_bg:
		_bg5_bg.visible = active
	if _bg5_collisions:
		_bg5_collisions.visible = active
		_set_collision_group_active(_bg5_collisions, active)
	# 爷爷交互物随 bg5 一起激活/禁用
	var grandpa = _bg5_bg.get_node_or_null("Grandpa") if _bg5_bg else null
	if grandpa is InteractiveObject:
		(grandpa as InteractiveObject).is_active = active
		(grandpa as Area2D).monitoring = active
	_sync_code_rain_for_bg5()

func _build_code_rain_overlay() -> void:
	var cv = get_node_or_null("CanvasLayer")
	if not cv:
		return
	_code_rain_overlay = CodeRain.new()
	_code_rain_overlay.name = "CodeRainOverlay"
	cv.add_child(_code_rain_overlay)
	_sync_code_rain_for_bg5()

func _sync_code_rain_for_bg5() -> void:
	if not _code_rain_overlay or not is_instance_valid(_code_rain_overlay):
		return
	if _in_bg5:
		_code_rain_overlay.stop_rain(true)
	else:
		_code_rain_overlay.start_rain()

func _enter_boss_arena() -> void:
	if _in_boss_arena: return
	_in_boss_arena = true
	# 标记交互完成
	for obj in _all_interactives:
		if obj.object_id == "enter_boss":
			obj.mark_completed()
	# 显示对话 → 对话结束后传送到 Boss 区域
	_show_dialog([
		"[color=#ff6b9d]花旦：[/color]阿明，你瞧，技术能给你你想要的一切",
		"[color=#ff6b9d]花旦：[/color]它能让回忆拥有形状，它能让记忆死而复生",
		"[color=#ff6b9d]花旦：[/color]留下来吧，永远留在这个温暖的世界里……",
	], _teleport_to_boss)

func _teleport_to_boss() -> void:
	_teleport_and_setup_camera(Vector2(931, 5037), 620, 1710, 4512, 5135, 1.33)
	_set_cam_from_group($BossCollisions, 4512)
	_set_boss_area_active(true)
	_set_map_sprites_visible(false)
	_spawn_boss()
	_show_boss_bar()
	# 更新检查点阶段为4（bg4），重新开始时直接回到bg4
	GameManager.update_checkpoint_stage(4)
	# 显示"按G切换人物外观"指引
	_show_skin_hint()

## bg4 指引提示："按G切换人物外观"，显示3秒后淡出
func _show_skin_hint() -> void:
	var cv = get_node_or_null("CanvasLayer")
	if not cv: return
	# 移除已有提示避免重叠
	var existing = cv.get_node_or_null("SkinHintLabel")
	if existing: existing.queue_free()
	var hint = Label.new()
	hint.name = "SkinHintLabel"
	hint.text = "按 G 切换人物外观"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 40)
	hint.add_theme_color_override("font_color", Color(1, 0.9, 0.3, 0.95))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hint.add_theme_constant_override("outline_size", 6)
	hint.position = Vector2(380, 640)
	hint.size = Vector2(520, 50)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.z_index = 150
	cv.add_child(hint)
	# 3秒后淡出删除
	var tw = hint.create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(hint, "modulate:a", 0.0, 1.0)
	tw.tween_callback(hint.queue_free)

## 血量变化回调：Boss战当前角色首次扣血到50时显示换人提示
func _on_health_changed(data: Dictionary) -> void:
	if not _in_boss_arena: return
	var target = data.get("target")
	if target != GameManager.player_ref: return
	var hp = int(data.get("current_health", 100))
	_check_low_hp_hint(_current_player_skin, hp)

## 检查角色血量是否首次降到50，是则再次显示换人提示
func _check_low_hp_hint(skin: String, hp: int) -> void:
	if not _in_boss_arena: return
	if hp > 50: return
	if skin == "Cyber":
		if _cyber_hint_shown: return
		_cyber_hint_shown = true
	elif skin == "Lingnan":
		if _lingnan_hint_shown: return
		_lingnan_hint_shown = true
	else:
		return
	_show_skin_hint()

## 双血条各回血（Boss召唤小怪全灭奖励）
func _heal_dual_char(amount: int) -> void:
	_cyber_health = mini(_cyber_health + amount, DUAL_CHAR_MAX_HP)
	_lingnan_health = mini(_lingnan_health + amount, DUAL_CHAR_MAX_HP)
	# 当前角色实时回血
	var p = GameManager.player_ref
	if p and is_instance_valid(p):
		p.current_health = _cyber_health if _current_player_skin == "Cyber" else _lingnan_health
		EventBus.emit(GlobalDefine.EventName.HEALTH_CHANGED, {
			"target": p,
			"current_health": p.current_health,
			"max_health": p.max_health
		})
	print("[Level_05] 双血条各回血 %d (Cyber=%d, Lingnan=%d)" % [amount, _cyber_health, _lingnan_health])

func _spawn_all_enemies(lingnan_on_top: bool) -> void:
	_clear_all_enemies()

	var ground_spots = [Vector2(-1000, 420), Vector2(0, 415), Vector2(800, 425)]
	var special_spots = [Vector2(200, 380), Vector2(600, 370)]

	if lingnan_on_top:
		# 纸人 + 灯笼
		for sp in ground_spots:
			_spawn_one(_enemy_paper_scene, sp)
		for sp in special_spots:
			_spawn_one(_enemy_lantern_scene, sp)
	else:
		# 狼人 + 冲撞兽
		for sp in ground_spots:
			_spawn_one(_enemy_wolf_scene, sp)
		for sp in special_spots:
			_spawn_one(_enemy_bull_scene, sp)

func _spawn_one(scene: PackedScene, pos: Vector2) -> Node2D:
	if not scene: return null
	var e = scene.instantiate()
	e.global_position = pos
	add_child(e)
	GameManager.register_enemy(e)
	_all_enemies.append(e)
	return e

func _clear_all_enemies() -> void:
	for e in _all_enemies + _lingnan_enemies + _cyber_enemies:
		if is_instance_valid(e):
			GameManager.unregister_enemy(e)
			e.queue_free()
	_all_enemies.clear()
	_lingnan_enemies.clear()
	_cyber_enemies.clear()


# ============================================================
# 侵蚀值
# ============================================================

func _build_erosion_bar() -> void:
	# 侵蚀进度条加到 HUD 下，与血条/技能图标统一管理（隐藏 HUD 时一起隐藏）
	var hud = get_node_or_null("HUD")
	if not hud:
		# HUD 还没加载，延迟创建到下一帧
		call_deferred("_build_erosion_bar")
		return
	var bar = Control.new()
	bar.name = "ErosionBar"
	bar.position = Vector2(20, 105); bar.size = Vector2(280, 28)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.z_index = 130
	hud.add_child(bar)

	_erosion_bar_bg = ColorRect.new()
	_erosion_bar_bg.size = Vector2(280, 24); _erosion_bar_bg.position = Vector2(0, 4)
	_erosion_bar_bg.color = Color(0.1, 0.05, 0.12, 0.9)
	_erosion_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_erosion_bar_bg)

	_erosion_bar_fill = ColorRect.new()
	_erosion_bar_fill.size = Vector2(0, 24); _erosion_bar_fill.position = Vector2(0, 4)
	_erosion_bar_fill.color = Color(0.65, 0.15, 0.8, 0.95)
	_erosion_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_erosion_bar_fill)

	_erosion_label = Label.new()
	_erosion_label.size = Vector2(280, 24); _erosion_label.position = Vector2(0, 4)
	_erosion_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_erosion_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_erosion_label.add_theme_font_size_override("font_size", 16)
	_erosion_label.add_theme_color_override("font_color", Color.WHITE)
	_erosion_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_erosion_label)

func _update_erosion_bar() -> void:
	if not _erosion_bar_fill or not _erosion_label: return
	var ratio = _erosion_value / EROSION_MAX
	_erosion_bar_fill.size.x = 280.0 * ratio
	_erosion_label.text = "侵蚀 %.0f%%" % _erosion_value
	if ratio > 0.7:
		_erosion_bar_fill.color = Color(0.9, 0.1, 0.2, 0.95)
	elif ratio > 0.4:
		_erosion_bar_fill.color = Color(0.8, 0.25, 0.5, 0.95)

func _modify_erosion(delta: float) -> void:
	_erosion_value = clampf(_erosion_value + delta, 0.0, EROSION_MAX)
	_update_erosion_bar()
	if _erosion_value >= EROSION_MAX:
		print("[Level_05] 侵蚀值已满！")
		var p = GameManager.player_ref
		if p and is_instance_valid(p) and p.current_state != GlobalDefine.PlayerState.DEAD:
			p.die()
		GameManager.trigger_game_over()

func _on_enemy_died(data: Dictionary) -> void:
	var e = data.get("enemy")
	if not e or not is_instance_valid(e): return
	if e in _all_enemies or e in _lingnan_enemies or e in _cyber_enemies:
		_modify_erosion(-EROSION_KILL_REDUCE)
		_all_enemies.erase(e)
		_lingnan_enemies.erase(e)
		_cyber_enemies.erase(e)
	# Boss 死亡处理
	if e == _boss_instance:
		# 灯笼生成位置：X用Boss位置，Y在5000~5077之间随机（地面高度区间）
		var death_pos: Vector2 = Vector2(e.global_position.x, randf_range(5000.0, 5077.0))
		_hide_boss_bar()
		GameManager.boss_target = null
		_boss_instance = null
		# Boss死亡 → 直接过渡到 lv6（bg5/结局主题，视频演出不打断）
		MusicManager.fade_to("res://Assets/Music/lv6.ogg", 2.0)
		# 剧烈抖屏 + 时缓效果
		_trigger_screen_shake(22.0, 0.8)
		Engine.time_scale = 0.25
		# 1.5秒后恢复时缓，生成灯笼并显示死亡对话（ignore_time_scale 不受时缓影响）
		var t = get_tree().create_timer(1.5, true, false, true)
		t.timeout.connect(_on_boss_death_recover.bind(death_pos))


func _spawn_boss() -> void:
	if _boss_instance and is_instance_valid(_boss_instance):
		_boss_instance.queue_free()
	var boss_scene = load("res://EnemyModule/Formal/Enemy_BossHuadan.tscn") as PackedScene
	if not boss_scene:
		printerr("[Level_05] 无法加载 Boss 场景")
		return
	_boss_instance = boss_scene.instantiate()
	_boss_instance.global_position = Vector2(1300, 5037)
	add_child(_boss_instance)
	# 设置 Boss 引用，供弹体自动瞄准
	GameManager.boss_target = _boss_instance
	print("[Level_05] Boss 已生成: %s" % _boss_instance.global_position)

func _despawn_boss() -> void:
	if _boss_instance and is_instance_valid(_boss_instance):
		_boss_instance.queue_free()
		_boss_instance = null
	GameManager.boss_target = null

func _teleport_and_setup_camera(pos: Vector2, lim_l: int, lim_r: int, lim_t: int, lim_b: int, z: float = 1.33) -> void:
	var p = GameManager.player_ref
	if not p or not is_instance_valid(p): return
	p.global_position = pos
	p.velocity = Vector2.ZERO
	var cam = p.get_node_or_null("SmoothCamera") as SmoothCamera
	if cam:
		cam.limit_left = lim_l; cam.limit_right = lim_r
		cam.limit_top = lim_t; cam.limit_bottom = lim_b
		cam.zoom = Vector2(z, z)
		cam.bind_target(p)           # snap 到玩家位置 + 重置 _last_target_x/_lookahead
		cam.follow_enabled = true    # 确保 _pan_camera 未残留关闭
		cam.make_current()
		print("[Level_05] 摄像机: limits=%d,%d,%d,%d zoom=%.2f pos=%s" % [lim_l, lim_r, lim_t, lim_b, z, pos])

func _set_boss_area_active(active: bool) -> void:
	var boss = get_node_or_null("BossCollisions")
	if boss:
		boss.visible = active
		_set_collision_group_active(boss, active)
	var bg4 = get_node_or_null("BossBg")
	if bg4:
		bg4.visible = active

func _set_map_sprites_visible(v: bool) -> void:
	_top_sprite.visible = v
	_bot_sprite.visible = v


# ============================================================
# 对话框系统
# ============================================================

func _show_dialog(lines: Array[String], callback: Callable = Callable()) -> void:
	_dialog_lines = lines
	_dialog_index = 0
	_dialog_callback = callback
	_dialog_open = true
	GameManager.is_dialog_active = true
	InputManager.block_input("对话", self)
	if not _dialog_panel:
		_create_dialog_panel()
	_dialog_panel.visible = true
	_show_dialog_line()

func _create_dialog_panel() -> void:
	var cv = get_node_or_null("CanvasLayer")
	if not cv: cv = self
	_dialog_panel = Panel.new()
	_dialog_panel.name = "DialogPanel"
	_dialog_panel.visible = false
	_dialog_panel.anchor_left = 0.0
	_dialog_panel.anchor_top = 1.0
	_dialog_panel.anchor_right = 1.0
	_dialog_panel.anchor_bottom = 1.0
	_dialog_panel.offset_left = 0.0
	_dialog_panel.offset_top = -200.0
	_dialog_panel.offset_right = 0.0
	_dialog_panel.offset_bottom = 0.0
	_dialog_panel.z_index = 200
	_dialog_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 仿照前三关 NarrativePanel 样式：纯黑半透背景 + 圆角，无紫色边框
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.85)
	style.set_corner_radius_all(8)
	_dialog_panel.add_theme_stylebox_override("panel", style)
	cv.add_child(_dialog_panel)

	_dialog_label = RichTextLabel.new()
	_dialog_label.name = "RichTextLabel"
	_dialog_label.anchor_left = 0.0
	_dialog_label.anchor_top = 0.0
	_dialog_label.anchor_right = 1.0
	_dialog_label.anchor_bottom = 1.0
	_dialog_label.offset_left = 20.0
	_dialog_label.offset_top = 20.0
	_dialog_label.offset_right = -20.0
	_dialog_label.offset_bottom = -20.0
	_dialog_label.bbcode_enabled = true
	_dialog_label.fit_content = true
	_dialog_label.add_theme_font_size_override("normal_font_size", 27)
	# 仿照前三关：暖色调文字（0.9, 0.85, 0.75），非纯白
	_dialog_label.add_theme_color_override("default_color", Color(0.9, 0.85, 0.75))
	_dialog_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog_panel.add_child(_dialog_label)

func _show_dialog_line() -> void:
	if _dialog_index < _dialog_lines.size():
		_dialog_label.text = _dialog_lines[_dialog_index]
	else:
		_close_dialog()

func _advance_dialog() -> void:
	_dialog_index += 1
	_show_dialog_line()

func _close_dialog() -> void:
	_dialog_open = false
	GameManager.is_dialog_active = false
	_dialog_panel.visible = false
	_dialog_close_cooldown = 0.4  # 关闭后0.4秒内不检测交互，防Enter串扰
	InputManager.unblock_input("对话")
	if _dialog_callback.is_valid():
		_dialog_callback.call()


# ============================================================
# Boss 血条
# ============================================================

func _show_boss_bar() -> void:
	if not _boss_bar_container:
		_create_boss_bar()
	_boss_bar_container.visible = true
	# 订阅 Boss 受伤事件
	EventBus.subscribe(GlobalDefine.EventName.ENEMY_HURT, self, "_on_boss_hurt")

func _create_boss_bar() -> void:
	var cv = get_node_or_null("CanvasLayer")
	if not cv: cv = self
	_boss_bar_container = Control.new()
	_boss_bar_container.name = "BossBarContainer"
	_boss_bar_container.position = Vector2(440, 20)
	_boss_bar_container.size = Vector2(BOSS_BAR_MAX_WIDTH, 28)
	_boss_bar_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar_container.z_index = 150
	_boss_bar_container.visible = false
	cv.add_child(_boss_bar_container)

	var bg = ColorRect.new()
	bg.size = Vector2(BOSS_BAR_MAX_WIDTH, 28)
	bg.color = Color(0.1, 0.05, 0.12, 0.9)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar_container.add_child(bg)

	_boss_bar_fill = ColorRect.new()
	_boss_bar_fill.size = Vector2(BOSS_BAR_MAX_WIDTH, 28)
	_boss_bar_fill.color = Color(0.85, 0.1, 0.3, 0.95)
	_boss_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar_container.add_child(_boss_bar_fill)

	_boss_bar_label = Label.new()
	_boss_bar_label.size = Vector2(BOSS_BAR_MAX_WIDTH, 28)
	_boss_bar_label.text = "花旦"
	_boss_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_bar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_boss_bar_label.add_theme_font_size_override("font_size", 22)
	_boss_bar_label.add_theme_color_override("font_color", Color.WHITE)
	_boss_bar_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar_container.add_child(_boss_bar_label)

func _update_boss_bar() -> void:
	if not _boss_bar_container or not _boss_bar_container.visible: return
	if not _boss_instance or not is_instance_valid(_boss_instance): return
	var hp = _boss_instance.current_health
	var max_hp = _boss_instance.max_health
	var ratio = clampf(float(hp) / float(max_hp), 0.0, 1.0)
	_boss_bar_fill.size.x = BOSS_BAR_MAX_WIDTH * ratio
	_boss_bar_label.text = "花旦  %d / %d" % [hp, max_hp]
	# 狂暴变色
	if ratio < 0.3:
		_boss_bar_fill.color = Color(0.95, 0.2, 0.1, 0.95)
	elif ratio < 0.6:
		_boss_bar_fill.color = Color(0.9, 0.4, 0.15, 0.95)

func _on_boss_hurt(data: Dictionary) -> void:
	var enemy = data.get("enemy")
	if enemy and enemy == _boss_instance:
		# 血条会在 _update_boss_bar 中自动更新
		pass

func _hide_boss_bar() -> void:
	if _boss_bar_container:
		_boss_bar_container.visible = false
	EventBus.unsubscribe(GlobalDefine.EventName.ENEMY_HURT, self)

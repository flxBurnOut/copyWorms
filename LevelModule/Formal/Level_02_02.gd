# ============================================================
# Level_02_02.gd - 第二关分段 02 控制器
# 坐标系与 Level_02_01 一致：关卡局部坐标 = 世界坐标，直接使用 position / map_* 常量
# ============================================================
extends LevelBase
class_name Level_02_02

@export var next_level_path: String = "res://LevelModule/Formal/Level_02_03.tscn"
@export var map_left: int = 0
@export var map_right: int = 1474
@export var exit_trigger_position: Vector2 = Vector2(1399.6136, -498.6906)
@export var exit_trigger_size: Vector2 = Vector2(64.7636, 93.5474)

const CAMERA_LIMIT_TOP: int = -835
const CAMERA_LIMIT_BOTTOM: int = 638
const CAMERA_ZOOM: Vector2 = Vector2(1.5, 1.5)
const CAMERA_LERP_SPEED: float = 2.5
const INTRO_NARRATIVE_TEXT: String = "有些梯子看似能爬，却不能爬....有些墙看似不能穿过，却可以穿过...."
const INTRO_NARRATIVE_DELAY: float = 2.0
const NARRATIVE_INPUT_TIMEOUT: float = 30.0
const PAPER_EFFIGY_SCENE_PATH: String = "res://EnemyModule/Formal/Enemy_PaperEffigy.tscn"
const PAPER_EFFIGY_CONFIG_PATH: String = "res://DataConfig/Enemy/PaperEffigyConfig.tres"
const LANTERN_GHOST_SCENE_PATH: String = "res://EnemyModule/Formal/Enemy_LanternGhost.tscn"
const LANTERN_GHOST_CONFIG_PATH: String = "res://DataConfig/Enemy/LanternGhostConfig.tres"
const ENEMY_DETECT_RANGE_CAP: float = 500.0
const PAPER_EFFIGY_SPAWN_POSITIONS: Array[Vector2] = [
	Vector2(552, 368),
	Vector2(864, 360),
	Vector2(616, 184),
	Vector2(1144, 192),
	Vector2(1096, -176),
	Vector2(1104, -384),
]
const LANTERN_GHOST_SPAWN_POSITIONS: Array[Vector2] = [
	Vector2(864, 360),
	Vector2(1144, 192),
	Vector2(1096, -176),
	Vector2(1104, -384),
]

var _exit_trigger: Area2D = null
var _dynamic_actors: Node2D = null
var _level_complete_emitted: bool = false
var _narrative_panel: Panel = null
var _narrative_text: RichTextLabel = null
var _narrative_open: bool = false
var _narrative_enter_pressed: bool = false
var _paper_effigy_scene: PackedScene = null
var _paper_effigies: Array[Node2D] = []
var _lantern_ghost_scene: PackedScene = null
var _lantern_ghosts: Array[Node2D] = []


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


func _on_ready() -> void:
	super._on_ready()

	_bind_spawn_point()
	_setup_camera_limits()
	_ensure_player_collision_layer()
	_build_exit_trigger()
	_build_dynamic_actors_container()
	_build_narrative_ui()
	_load_enemy_scene()
	_build_enemy_spawn_points()
	_spawn_paper_effigies()
	_spawn_lantern_ghosts()
	call_deferred("_remove_ladder_color_rects")
	_load_hud()
	_show_intro_narrative()
	print("[Level_02_02] 初始化完成")


func _setup_camera_limits() -> void:
	var player = GameManager.player_ref
	if not player or not is_instance_valid(player):
		return
	var cam = player.get_node_or_null("SmoothCamera") as SmoothCamera
	if not cam:
		return
	cam.limit_left = map_left
	cam.limit_right = map_right
	cam.limit_top = CAMERA_LIMIT_TOP
	cam.limit_bottom = CAMERA_LIMIT_BOTTOM
	cam.zoom = CAMERA_ZOOM
	cam.offset = Vector2.ZERO
	cam.lerp_speed = CAMERA_LERP_SPEED
	cam.bind_target(player)


func _load_hud() -> void:
	var hud_path = "res://UI/HUD.tscn"
	if ResourceLoader.exists(hud_path):
		var hud = load(hud_path).instantiate()
		add_child(hud)
		print("[Level_02_02] HUD 加载成功")
	else:
		push_warning("[Level_02_02] HUD.tscn 未找到，跳过")


func _remove_ladder_color_rects() -> void:
	var ladders = get_node_or_null("Ladders")
	if not ladders:
		return
	for ladder in ladders.get_children():
		for child in ladder.get_children():
			if child is ColorRect:
				child.queue_free()


func _load_enemy_scene() -> void:
	if ResourceLoader.exists(PAPER_EFFIGY_SCENE_PATH):
		_paper_effigy_scene = load(PAPER_EFFIGY_SCENE_PATH) as PackedScene
	else:
		push_warning("[Level_02_02] Enemy_PaperEffigy.tscn 不存在，跳过纸符人生成")
	if ResourceLoader.exists(LANTERN_GHOST_SCENE_PATH):
		_lantern_ghost_scene = load(LANTERN_GHOST_SCENE_PATH) as PackedScene
	else:
		push_warning("[Level_02_02] Enemy_LanternGhost.tscn 不存在，跳过灯笼鬼生成")


func _build_enemy_spawn_points() -> void:
	var root = _get_or_create_child("EnemySpawnPoints", Node2D)
	var paper_layer = _get_or_create_child_on(root, "PaperEffigyLayer", Node2D)
	var lantern_layer = _get_or_create_child_on(root, "LanternGhostLayer", Node2D)
	if paper_layer.get_child_count() == 0:
		for i in range(PAPER_EFFIGY_SPAWN_POSITIONS.size()):
			_create_marker(paper_layer, "PaperEffigy_%02d" % (i + 1), PAPER_EFFIGY_SPAWN_POSITIONS[i])
	if lantern_layer.get_child_count() == 0:
		for i in range(LANTERN_GHOST_SPAWN_POSITIONS.size()):
			_create_marker(lantern_layer, "LanternGhost_%02d" % (i + 1), LANTERN_GHOST_SPAWN_POSITIONS[i])


func _spawn_paper_effigies() -> void:
	if not _paper_effigy_scene:
		return
	var config = _load_capped_enemy_config(PAPER_EFFIGY_CONFIG_PATH)
	for marker in _get_enemy_spawn_markers("PaperEffigy"):
		var enemy = _paper_effigy_scene.instantiate()
		if config and enemy is EnemyBase:
			(enemy as EnemyBase).config = config
		_dynamic_actors.add_child(enemy)
		enemy.global_position = marker.global_position
		_paper_effigies.append(enemy)


func _spawn_lantern_ghosts() -> void:
	if not _lantern_ghost_scene:
		return
	var config = _load_capped_enemy_config(LANTERN_GHOST_CONFIG_PATH)
	for marker in _get_enemy_spawn_markers("LanternGhost"):
		var enemy = _lantern_ghost_scene.instantiate()
		if config and enemy is EnemyBase:
			(enemy as EnemyBase).config = config
		_dynamic_actors.add_child(enemy)
		enemy.global_position = marker.global_position
		_lantern_ghosts.append(enemy)


func _load_capped_enemy_config(config_path: String) -> EnemyConfig:
	if not ResourceLoader.exists(config_path):
		return null
	var source_config = load(config_path) as EnemyConfig
	if not source_config:
		return null
	var config_copy = source_config.duplicate(true) as EnemyConfig
	config_copy.detect_range = minf(config_copy.detect_range, ENEMY_DETECT_RANGE_CAP)
	return config_copy


func _get_enemy_spawn_markers(name_prefix: String) -> Array[Marker2D]:
	var markers: Array[Marker2D] = []
	var root = get_node_or_null("EnemySpawnPoints")
	if not root:
		return markers
	for layer in root.get_children():
		for child in layer.get_children():
			if child is Marker2D and child.name.begins_with(name_prefix):
				markers.append(child)
	return markers


func _input(event: InputEvent) -> void:
	var is_left_click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if not event.is_action_pressed("ui_accept") and not is_left_click:
		return
	if _narrative_open:
		_narrative_enter_pressed = true
		get_viewport().set_input_as_handled()


func _build_narrative_ui() -> void:
	var canvas = _get_or_create_child("CanvasLayerUI", CanvasLayer) as CanvasLayer
	canvas.layer = 10

	_narrative_panel = canvas.get_node_or_null("NarrativePanel") as Panel
	if not _narrative_panel:
		_narrative_panel = Panel.new()
		_narrative_panel.name = "NarrativePanel"
		_narrative_panel.visible = false
		_narrative_panel.anchor_left = 0.0
		_narrative_panel.anchor_top = 1.0
		_narrative_panel.anchor_right = 1.0
		_narrative_panel.anchor_bottom = 1.0
		_narrative_panel.offset_left = 0.0
		_narrative_panel.offset_top = -200.0
		_narrative_panel.offset_right = 0.0
		_narrative_panel.offset_bottom = 0.0
		_narrative_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0.85)
		style.set_corner_radius_all(8)
		_narrative_panel.add_theme_stylebox_override("panel", style)
		canvas.add_child(_narrative_panel)

	_narrative_text = _narrative_panel.get_node_or_null("RichTextLabel") as RichTextLabel
	if not _narrative_text:
		_narrative_text = RichTextLabel.new()
		_narrative_text.name = "RichTextLabel"
		_narrative_text.anchor_left = 0.0
		_narrative_text.anchor_top = 0.0
		_narrative_text.anchor_right = 1.0
		_narrative_text.anchor_bottom = 1.0
		_narrative_text.offset_left = 20.0
		_narrative_text.offset_top = 20.0
		_narrative_text.offset_right = -20.0
		_narrative_text.offset_bottom = -20.0
		_narrative_text.bbcode_enabled = true
		_narrative_text.fit_content = true
		_narrative_text.add_theme_font_size_override("normal_font_size", 27)
		_narrative_text.add_theme_color_override("default_color", Color(0.9, 0.85, 0.75))
		_narrative_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_narrative_panel.add_child(_narrative_text)


func _show_intro_narrative() -> void:
	await get_tree().create_timer(INTRO_NARRATIVE_DELAY).timeout
	_show_narrative(INTRO_NARRATIVE_TEXT)


func _show_narrative(text: String) -> void:
	InputManager.block_input("叙事面板", self)
	if _narrative_open:
		if _narrative_panel:
			_narrative_panel.hide()
		_narrative_open = false
	_narrative_open = true
	_freeze_player(true)
	if _narrative_panel:
		_narrative_panel.show()
	if _narrative_text:
		_narrative_text.text = text
	await get_tree().create_timer(0.3).timeout

	_narrative_enter_pressed = false
	var wait_elapsed: float = 0.0
	const WAIT_DELTA: float = 0.05
	while _narrative_open and wait_elapsed < NARRATIVE_INPUT_TIMEOUT:
		if _narrative_enter_pressed:
			break
		await get_tree().create_timer(WAIT_DELTA).timeout
		wait_elapsed += WAIT_DELTA

	if _narrative_panel:
		_narrative_panel.hide()
	_freeze_player(false)
	_narrative_open = false
	_narrative_enter_pressed = false
	InputManager.unblock_input("叙事面板")


func _freeze_player(freeze: bool) -> void:
	var player = GameManager.player_ref
	if not player or not is_instance_valid(player):
		return
	# [旧实现 - 保留以备回退] 已迁移至 PlayerBase.set_frozen() 统一处理动画冻结问题
	# if freeze:
	#     player.velocity = Vector2.ZERO
	#     player.set_physics_process(false)
	#     player.set_process_input(false)
	#     if player.has_method("_change_state"):
	#         player._change_state(GlobalDefine.PlayerState.IDLE)
	# else:
	#     player.set_physics_process(true)
	#     player.set_process_input(true)
	player.set_frozen(freeze)


func _ensure_player_collision_layer() -> void:
	var player = GameManager.player_ref
	if not player or not is_instance_valid(player):
		return
	if not (player.collision_layer & GlobalDefine.Collision.PLAYER):
		player.collision_layer |= GlobalDefine.Collision.PLAYER


func _bind_spawn_point() -> void:
	var container = _get_or_create_child("SpawnPoints", Node2D)
	var spawn = container.get_node_or_null("SegmentSpawn") as Marker2D
	if not spawn:
		spawn = Marker2D.new()
		spawn.name = "SegmentSpawn"
		spawn.position = Vector2(138, 546)
		container.add_child(spawn)
	player_spawn_point = spawn


func _get_spawn_position() -> Vector2:
	var spawn = get_node_or_null("SpawnPoints/SegmentSpawn") as Marker2D
	if spawn:
		return spawn.position
	return Vector2(138, 546)


func _build_exit_trigger() -> void:
	var container = _get_or_create_child("TriggerZones", Node2D)
	_exit_trigger = _ensure_trigger_zone(container, "Level0202ExitTrigger", exit_trigger_position, exit_trigger_size)
	if not _exit_trigger.body_entered.is_connected(_on_exit_trigger_body_entered):
		_exit_trigger.body_entered.connect(_on_exit_trigger_body_entered)
	_add_exit_dot_visual(_exit_trigger)


## 给出口触发区添加关卡1同款闪烁光点（10px 黄点 + 24px 光晕 + 正弦闪烁）
func _add_exit_dot_visual(area: Area2D) -> void:
	var indicator = ColorRect.new()
	indicator.name = "Indicator"
	indicator.color = Color(1.0, 0.85, 0.2, 0.9)
	indicator.size = Vector2(10, 10)
	indicator.position = -indicator.size / 2
	indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	indicator.z_index = 10
	area.add_child(indicator)
	var glow = ColorRect.new()
	glow.name = "Glow"
	glow.color = Color(1.0, 0.9, 0.3, 0.3)
	glow.size = Vector2(24, 24)
	glow.position = -glow.size / 2
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.z_index = 9
	area.add_child(glow)
	var tw = indicator.create_tween().set_loops()
	tw.tween_property(indicator, "color:a", 0.2, 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(indicator, "color:a", 0.9, 0.6).set_trans(Tween.TRANS_SINE)
	var tw2 = glow.create_tween().set_loops()
	tw2.tween_property(glow, "color:a", 0.0, 0.6).set_trans(Tween.TRANS_SINE)
	tw2.tween_property(glow, "color:a", 0.3, 0.6).set_trans(Tween.TRANS_SINE)


func _build_dynamic_actors_container() -> void:
	_dynamic_actors = _get_or_create_child("DynamicActors", Node2D) as Node2D


func _get_or_create_child(node_name: String, node_type: Variant) -> Node:
	var existing = get_node_or_null(node_name)
	if existing:
		return existing
	var node = node_type.new()
	node.name = node_name
	add_child(node)
	return node


func _get_or_create_child_on(parent: Node, node_name: String, node_type: Variant) -> Node:
	var existing = parent.get_node_or_null(node_name)
	if existing:
		return existing
	var node = node_type.new()
	node.name = node_name
	parent.add_child(node)
	return node


func _create_marker(parent: Node, node_name: String, pos: Vector2) -> Marker2D:
	var marker = Marker2D.new()
	marker.name = node_name
	marker.position = pos
	parent.add_child(marker)
	return marker


func _create_trigger_zone(zone_name: String, pos: Vector2, size: Vector2) -> Area2D:
	var area = Area2D.new()
	area.name = zone_name
	area.position = pos
	area.collision_layer = 0
	area.collision_mask = GlobalDefine.Collision.PLAYER
	area.monitoring = true
	area.monitorable = false
	var col = CollisionShape2D.new()
	col.name = "CollisionShape2D"
	var shape = RectangleShape2D.new()
	shape.size = size
	col.shape = shape
	area.add_child(col)
	return area


func _ensure_trigger_zone(container: Node, zone_name: String, pos: Vector2, size: Vector2) -> Area2D:
	var area = container.get_node_or_null(zone_name) as Area2D
	if area:
		return area
	area = _create_trigger_zone(zone_name, pos, size)
	container.add_child(area)
	return area


func _on_exit_trigger_body_entered(body: Node2D) -> void:
	if not _is_player_body(body):
		return
	call_deferred("_emit_level_complete")


func _is_player_body(body: Node2D) -> bool:
	if not body is CharacterBody2D:
		return false
	if body.collision_layer & GlobalDefine.Collision.PLAYER:
		return true
	return body.is_in_group("player")


func _emit_level_complete() -> void:
	if _level_complete_emitted:
		return
	_level_complete_emitted = true
	get_viewport().gui_release_focus()
	InputManager.force_unblock_all()
	_cleanup_enemies()
	EventBus.unsubscribe_all(self)
	if next_level_path == "":
		print("[Level_02_02] 下一关路径为空，停留在当前关卡")
		return
	if not _is_loaded_under_main_entry():
		print("[Level_02_02] 无 MainEntry，直接切换场景 → ", next_level_path)
		SceneTransitionManager.request_scene_change(next_level_path, self)
		return
	print("[Level_02_02] 发射 LEVEL_COMPLETE → ", next_level_path)
	EventBus.emit(GlobalDefine.EventName.LEVEL_COMPLETE, {
		"level": self,
		"next_level": next_level_path,
	})


func _cleanup_enemies() -> void:
	for enemy in _paper_effigies:
		if is_instance_valid(enemy):
			GameManager.unregister_enemy(enemy)
			enemy.queue_free()
	_paper_effigies.clear()
	for enemy in _lantern_ghosts:
		if is_instance_valid(enemy):
			GameManager.unregister_enemy(enemy)
			enemy.queue_free()
	_lantern_ghosts.clear()


func _is_loaded_under_main_entry() -> bool:
	var node = get_parent()
	while node:
		if node.name == "MainEntry":
			return true
		node = node.get_parent()
	return false

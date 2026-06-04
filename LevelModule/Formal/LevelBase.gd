# ============================================================
# LevelBase.gd - 关卡基类
# 定义关卡的基础功能：场景搭建、触发区域、摄像机管理等
# 子类只需重写对应虚函数，禁止修改此文件
# ============================================================
extends Node2D
class_name LevelBase

@export var level_config: LevelConfig = null

# 关卡中的敌人出生点
@export var enemy_spawn_points: Array[Marker2D] = []

# 玩家出生点
@export var player_spawn_point: Marker2D = null

var _enemies_spawned: Array[Node2D] = []

# ---- 生命周期 ----

func _ready() -> void:
	_apply_config()
	_setup_camera()
	_setup_player()
	_setup_enemies()
	_setup_triggers()
	GameManager.current_level = self
	EventBus.emit(GlobalDefine.EventName.LEVEL_LOADED, { "level": self })
	_on_ready()

func _apply_config() -> void:
	if level_config and level_config.bg_color:
		RenderingServer.set_default_clear_color(level_config.bg_color)

func _setup_camera() -> void:
	# 如果玩家已经有摄像机就不重复创建
	if GameManager.player_ref and is_instance_valid(GameManager.player_ref):
		var existing = GameManager.player_ref.get_node_or_null("Camera2D")
		if existing:
			return

	var camera = Camera2D.new()
	camera.name = "LevelCamera"
	camera.enabled = true
	camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	camera.position = Vector2(640, 360)
	if level_config:
		camera.limit_left = level_config.camera_limit_left
		camera.limit_right = level_config.camera_limit_right
		camera.limit_top = level_config.camera_limit_top
		camera.limit_bottom = level_config.camera_limit_bottom
	else:
		camera.limit_left = 0
		camera.limit_right = 1280
		camera.limit_top = -1000
		camera.limit_bottom = 1000

	# 摄像机跟随玩家
	if GameManager.player_ref and is_instance_valid(GameManager.player_ref):
		GameManager.player_ref.add_child(camera)
	else:
		add_child(camera)

func _setup_player() -> void:
	# 正式关卡自动生成玩家
	if GameManager.player_ref and is_instance_valid(GameManager.player_ref):
		return  # 玩家已存在
	var player_path = "res://PlayerModule/Formal/Player_Warrior.tscn"
	if ResourceLoader.exists(player_path):
		var player = load(player_path).instantiate()
		var spawn_pos = level_config.spawn_point if level_config else Vector2(640, 500)
		player.position = spawn_pos
		add_child(player)
		GameManager.register_player(player)

func _setup_enemies() -> void:
	for spawn_point in enemy_spawn_points:
		if not is_instance_valid(spawn_point):
			continue
		var enemy = _spawn_enemy_at(spawn_point)
		if enemy:
			_enemies_spawned.append(enemy)

func _spawn_enemy_at(_spawn_point: Marker2D) -> Node2D:
	# 子类重写此方法实现敌人实例化
	return null

func _setup_triggers() -> void:
	# 子类重写此方法添加关卡触发区域
	pass

# ---- 公共方法 ----

## 在指定位置创建敌人
func spawn_enemy(enemy_scene_path: String, position: Vector2) -> Node2D:
	if not ResourceLoader.exists(enemy_scene_path):
		print("[LevelBase] 敌人场景不存在: ", enemy_scene_path)
		return null

	var enemy = load(enemy_scene_path).instantiate()
	enemy.global_position = position
	add_child(enemy)
	return enemy

## 创建简单的地面平台
func create_ground(pos: Vector2, size: Vector2, color: Color = Color(0.4, 0.4, 0.4)) -> StaticBody2D:
	var body = StaticBody2D.new()
	body.position = pos
	body.collision_layer = 1  # 地形在第1层（玩家和敌人都检测）

	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)

	var rect = ColorRect.new()
	rect.color = color
	rect.size = size
	rect.position = -size / 2
	body.add_child(rect)

	add_child(body)
	return body

## 创建墙壁
func create_wall(pos: Vector2, size: Vector2, color: Color = Color(0.35, 0.35, 0.35)) -> StaticBody2D:
	return create_ground(pos, size, color)

# ---- 虚函数（子类重写点，不要修改基类源码） ----

func _on_ready() -> void:
	pass

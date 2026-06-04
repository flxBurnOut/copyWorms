# ============================================================
# PlayerTest.gd - 玩家模块自测场景
# 自带简易地形，自动生成玩家和小怪，可独立运行
# ============================================================
extends Node2D

func _ready() -> void:
	GameManager.run_mode = GlobalDefine.RunMode.SELF_TEST
	print("[PlayerTest] 玩家模块自测场景启动")

	_build_terrain()
	_spawn_player()
	_spawn_test_enemies()
	_load_hud()

func _build_terrain() -> void:
	# 创建简单地形（屏幕720高，地面放在y=600，上方留空间）
	_create_platform(Vector2(640, 620), Vector2(1280, 80), Color(0.35, 0.35, 0.4))  # 主地面
	_create_platform(Vector2(200, 460), Vector2(200, 20), Color(0.4, 0.4, 0.45))   # 左平台
	_create_platform(Vector2(1000, 460), Vector2(200, 20), Color(0.4, 0.4, 0.45))   # 右平台
	_create_platform(Vector2(600, 320), Vector2(300, 20), Color(0.4, 0.4, 0.45))   # 高台
	_create_platform(Vector2(0, 360), Vector2(20, 720), Color(0.3, 0.3, 0.35))      # 左墙
	_create_platform(Vector2(1280, 360), Vector2(20, 720), Color(0.3, 0.3, 0.35))    # 右墙

func _create_platform(pos: Vector2, size: Vector2, color: Color) -> void:
	var body = StaticBody2D.new()
	body.position = pos
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

func _spawn_player() -> void:
	# 使用代码直接创建玩家（不依赖.tscn文件，保证自测可独立运行）
	var player = Player_Warrior.new()
	player.config = load("res://DataConfig/Player/WarriorConfig.tres") as PlayerConfig
	player.position = Vector2(200, 550)
	add_child(player)
	GameManager.register_player(player)

	# 摄像机跟随玩家
	var camera = Camera2D.new()
	camera.enabled = true
	camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	camera.limit_left = 0
	camera.limit_right = 1280
	camera.limit_top = -1000
	camera.limit_bottom = 1000
	player.add_child(camera)

func _spawn_test_enemies() -> void:
	var enemy = Enemy_Slime.new()
	enemy.config = load("res://DataConfig/Enemy/SlimeConfig.tres") as EnemyConfig
	enemy.position = Vector2(600, 588)
	add_child(enemy)

	var enemy2 = Enemy_Slime.new()
	enemy2.config = load("res://DataConfig/Enemy/SlimeConfig.tres") as EnemyConfig
	enemy2.position = Vector2(900, 588)
	add_child(enemy2)

func _load_hud() -> void:
	var hud_path = "res://UI/HUD.tscn"
	if ResourceLoader.exists(hud_path):
		var hud = load(hud_path).instantiate()
		add_child(hud)

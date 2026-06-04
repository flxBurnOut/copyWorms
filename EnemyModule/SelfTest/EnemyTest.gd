# ============================================================
# EnemyTest.gd - 敌人模块自测场景
# 自带简易地形，自动生成玩家和小怪，可独立运行
# ============================================================
extends Node2D

func _ready() -> void:
	GameManager.run_mode = GlobalDefine.RunMode.SELF_TEST
	print("[EnemyTest] 敌人模块自测场景启动")

	_build_terrain()
	_spawn_player()
	_spawn_test_enemies()
	_load_hud()

func _build_terrain() -> void:
	_create_platform(Vector2(640, 620), Vector2(1280, 80), Color(0.35, 0.35, 0.4))
	_create_platform(Vector2(300, 480), Vector2(250, 20), Color(0.4, 0.4, 0.45))
	_create_platform(Vector2(900, 480), Vector2(250, 20), Color(0.4, 0.4, 0.45))
	_create_platform(Vector2(0, 360), Vector2(20, 720), Color(0.3, 0.3, 0.35))
	_create_platform(Vector2(1280, 360), Vector2(20, 720), Color(0.3, 0.3, 0.35))

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
	var player = Player_Warrior.new()
	player.config = load("res://DataConfig/Player/WarriorConfig.tres") as PlayerConfig
	player.position = Vector2(100, 550)
	add_child(player)
	GameManager.register_player(player)

	var camera = Camera2D.new()
	camera.enabled = true
	camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	camera.limit_left = 0
	camera.limit_right = 1280
	camera.limit_top = -1000
	camera.limit_bottom = 1000
	player.add_child(camera)

func _spawn_test_enemies() -> void:
	# 多个史莱姆，放在地面和平台上
	var positions = [
		Vector2(400, 588),
		Vector2(600, 588),
		Vector2(800, 588),
		Vector2(1000, 588),
		Vector2(300, 448),   # 左平台
		Vector2(900, 448),   # 右平台
	]
	for pos in positions:
		var enemy = Enemy_Slime.new()
		enemy.config = load("res://DataConfig/Enemy/SlimeConfig.tres") as EnemyConfig
		enemy.position = pos
		add_child(enemy)

func _load_hud() -> void:
	var hud_path = "res://UI/HUD.tscn"
	if ResourceLoader.exists(hud_path):
		var hud = load(hud_path).instantiate()
		add_child(hud)

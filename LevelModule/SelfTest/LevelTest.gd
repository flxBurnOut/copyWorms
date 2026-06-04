# ============================================================
# LevelTest.gd - 关卡模块自测场景
# 自带简易地形，自动生成玩家和小怪，可独立运行
# ============================================================
extends Node2D

func _ready() -> void:
	GameManager.run_mode = GlobalDefine.RunMode.SELF_TEST
	print("[LevelTest] 关卡模块自测场景启动")

	_build_terrain()
	_spawn_player()
	_spawn_test_enemies()
	_load_hud()

func _build_terrain() -> void:
	# 更复杂的关卡地形，测试平台跳跃（地面y=620，屏幕中央偏下）
	_create_platform(Vector2(640, 620), Vector2(1280, 80), Color(0.35, 0.35, 0.4))
	_create_platform(Vector2(150, 500), Vector2(180, 16), Color(0.45, 0.45, 0.5))
	_create_platform(Vector2(400, 420), Vector2(160, 16), Color(0.45, 0.45, 0.5))
	_create_platform(Vector2(640, 340), Vector2(200, 16), Color(0.45, 0.45, 0.5))
	_create_platform(Vector2(900, 420), Vector2(160, 16), Color(0.45, 0.45, 0.5))
	_create_platform(Vector2(1150, 500), Vector2(180, 16), Color(0.45, 0.45, 0.5))
	_create_platform(Vector2(640, 200), Vector2(120, 16), Color(0.5, 0.5, 0.55))
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
	player.position = Vector2(200, 550)
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
	var positions = [
		Vector2(600, 588),
		Vector2(900, 588),
		Vector2(640, 308),     # 中央高台
		Vector2(1150, 468),    # 右侧平台
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

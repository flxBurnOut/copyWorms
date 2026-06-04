# ============================================================
# Level_01.gd - 第一关：初始之地
# 继承 LevelBase，实现第一关的具体内容
# ============================================================
extends LevelBase
class_name Level_01

func _on_ready() -> void:
	super._on_ready()
	if not level_config:
		level_config = load("res://DataConfig/Level/Level01Config.tres") as LevelConfig
		_apply_config()
	_build_terrain()
	_spawn_level_enemies()

func _build_terrain() -> void:
	# 主地面（y=620，屏幕中央偏下）
	create_ground(Vector2(640, 620), Vector2(1280, 80))

	# 左侧平台
	create_ground(Vector2(200, 460), Vector2(200, 20))

	# 右侧平台
	create_ground(Vector2(1000, 460), Vector2(200, 20))

	# 上方平台
	create_ground(Vector2(600, 320), Vector2(300, 20))

	# 左侧墙壁
	create_wall(Vector2(0, 360), Vector2(20, 720))

	# 右侧墙壁
	create_wall(Vector2(1280, 360), Vector2(20, 720))

func _spawn_level_enemies() -> void:
	# 生成史莱姆（放在地面上，与玩家同一水平线）
	var slime_path = "res://EnemyModule/Formal/Enemy_Slime.tscn"
	if not ResourceLoader.exists(slime_path):
		return

	spawn_enemy(slime_path, Vector2(300, 588))
	spawn_enemy(slime_path, Vector2(900, 588))
	spawn_enemy(slime_path, Vector2(1100, 588))

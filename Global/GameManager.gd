# ============================================================
# GameManager.gd - 游戏管理器 (Autoload)
# 统一管理游戏状态、运行模式、玩家/敌人引用
# ============================================================
extends Node

# 运行模式（根据场景自动切换）
var run_mode: int = GlobalDefine.RunMode.FORMAL

# 全局引用
var player_ref: Node2D = null
var current_level: Node = null
var enemy_list: Array[Node2D] = []

# 游戏状态
var is_paused: bool = false
var is_game_over: bool = false

# ---- 生命周期 ----

func _ready() -> void:
	_detect_run_mode()

## 自动检测运行模式
func _detect_run_mode() -> void:
	var current_scene = get_tree().current_scene
	if current_scene == null:
		run_mode = GlobalDefine.RunMode.FORMAL
		return

	var scene_path = current_scene.scene_file_path
	if scene_path and "SelfTest" in scene_path:
		run_mode = GlobalDefine.RunMode.SELF_TEST
		print("[GameManager] 检测到自测模式: ", scene_path)
	else:
		run_mode = GlobalDefine.RunMode.FORMAL
		print("[GameManager] 正式模式: ", scene_path)

## 正式模式下，场景切换时重新检测
func _on_scene_changed() -> void:
	_detect_run_mode()

# ---- 公共方法 ----

## 注册玩家
func register_player(player: Node2D) -> void:
	player_ref = player
	EventBus.emit(GlobalDefine.EventName.PLAYER_SPAWNED, { "player": player })

## 注册敌人
func register_enemy(enemy: Node2D) -> void:
	enemy_list.append(enemy)
	EventBus.emit(GlobalDefine.EventName.ENEMY_SPAWNED, { "enemy": enemy })

## 注销敌人
func unregister_enemy(enemy: Node2D) -> void:
	enemy_list.erase(enemy)

## 获取所有敌人
func get_enemies() -> Array[Node2D]:
	enemy_list = enemy_list.filter(func(e): return is_instance_valid(e))
	return enemy_list

## 获取离某点最近的敌人
func get_nearest_enemy(pos: Vector2) -> Node2D:
	var nearest: Node2D = null
	var min_dist: float = INF
	for enemy in enemy_list:
		if not is_instance_valid(enemy):
			continue
		var dist = pos.distance_squared_to(enemy.global_position)
		if dist < min_dist:
			min_dist = dist
			nearest = enemy
	return nearest

## 暂停/恢复
func toggle_pause() -> void:
	is_paused = !is_paused
	get_tree().paused = is_paused
	if is_paused:
		EventBus.emit(GlobalDefine.EventName.GAME_PAUSE)
	else:
		EventBus.emit(GlobalDefine.EventName.GAME_RESUME)

## 游戏结束
func trigger_game_over() -> void:
	is_game_over = true
	EventBus.emit(GlobalDefine.EventName.GAME_OVER)

## 判断是否自测模式
func is_self_test() -> bool:
	return run_mode == GlobalDefine.RunMode.SELF_TEST

## 判断是否正式模式
func is_formal() -> bool:
	return run_mode == GlobalDefine.RunMode.FORMAL

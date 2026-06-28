# ============================================================
# Level_02_SceneBuilder.gd - 关卡2场景构建器（简化版）
# 梦境: 阁楼(0-424) / 老街(424-5328)
# ============================================================
extends RefCounted
class_name Level_02_SceneBuilder

var level: Level_02

func _init(parent: Level_02) -> void:
	level = parent

func build_all() -> void:
	_build_dream_world()
	_build_interactives()
	_build_triggers()
	_build_spawn_points()
	_build_dynamic_actors_container()
	_build_canvas_ui()

func _build_dream_world() -> void:
	var dream = level._get_or_create_child("DreamWorldRoot", Node2D)
	level._dream_root = dream
	var collision_container = _get_or_create_child_on(dream, "CollisionBodies", Node2D)

	# ---- A 阁楼 (0-424) ----
	_ensure_static_body(collision_container, "MainAtticFloor", Vector2(212, 620), Vector2(424, 40))
	_ensure_static_body(collision_container, "AtticLeftWall", Vector2(-10, 360), Vector2(20, 720))
	level._attic_door_wall = _ensure_static_body(collision_container, "AtticDoorWall", Vector2(424, 424), Vector2(30, 400))

	# ---- B 老街 (424-5328) ----
	_ensure_static_body(collision_container, "StreetGround", Vector2(2876, 620), Vector2(4904, 40))

	_attach_dream_visual_layers(dream)

func _attach_dream_visual_layers(dream: Node2D) -> void:
	var to_reparent: Array[Node] = []
	for child in level.get_children():
		if child == dream or not child is Node2D:
			continue
		var scene_path: String = child.scene_file_path
		if scene_path.contains("PixelworkMapStitch"):
			to_reparent.append(child)
	for node in to_reparent:
		node.reparent(dream)

func _build_interactives() -> void:
	var container = level._get_or_create_child("InteractiveObjects", Node2D)

	level._window_node = _ensure_interactive(container, "Window_L2", "window_l2", Vector2(304, 552), Vector2(110, 130))
	var win_indicator = level._window_node.get_node_or_null("Indicator")
	if win_indicator:
		win_indicator.queue_free()
	level._window_node.prompt_text = "按 Enter 观察"

	level._attic_door_node = _ensure_interactive(container, "AtticDoor", "attic_door", Vector2(424, 500), Vector2(60, 160))
	var door_indicator = level._attic_door_node.get_node_or_null("Indicator")
	if door_indicator:
		door_indicator.queue_free()
	level._attic_door_node.prompt_text = "按 Enter 推开"

	level._rattan_chair_node = _ensure_interactive(container, "GroceryStore", "rattan_chair", Vector2(880, 552), Vector2(80, 50))
	var chair_indicator = level._rattan_chair_node.get_node_or_null("Indicator")
	if chair_indicator:
		chair_indicator.queue_free()
	level._rattan_chair_node.prompt_text = "按 Enter 回忆"

	level._chips_cat_node = _ensure_interactive(container, "ChipsCat", "chips_cat", Vector2(2824, 552), Vector2(80, 60))
	var cat_indicator = level._chips_cat_node.get_node_or_null("Indicator")
	if cat_indicator:
		cat_indicator.queue_free()
	level._chips_cat_node.prompt_text = "按 Enter 呼唤"
	level._chips_cat_node.allow_repeat = true

func _build_triggers() -> void:
	var container = level._get_or_create_child("TriggerZones", Node2D)

	level._street_entry_trigger = _ensure_trigger_zone(container, "StreetEntryTrigger", Vector2(500, 460), Vector2(80, 360))
	var street_cb = Callable(level, "_on_street_entry_body_entered")
	if not level._street_entry_trigger.body_entered.is_connected(street_cb):
		level._street_entry_trigger.body_entered.connect(street_cb)

	level._level_exit_trigger = _ensure_trigger_zone(container, "LevelExitTrigger", Vector2(5256, 460), Vector2(120, 360))
	var exit_cb = Callable(level, "_on_level_exit_body_entered")
	if not level._level_exit_trigger.body_entered.is_connected(exit_cb):
		level._level_exit_trigger.body_entered.connect(exit_cb)

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

func _build_spawn_points() -> void:
	var container = level._get_or_create_child("SpawnPoints", Node2D)

	var attic_spawn = container.get_node_or_null("AtticSpawn") as Marker2D
	if not attic_spawn:
		attic_spawn = Marker2D.new()
		attic_spawn.name = "AtticSpawn"
		attic_spawn.position = Vector2(140, 550)
		container.add_child(attic_spawn)
	level.player_spawn_point = attic_spawn

func _build_dynamic_actors_container() -> void:
	var actors = level._get_or_create_child("DynamicActors", Node2D)
	level._dynamic_actors = actors

func _build_canvas_ui() -> void:
	var canvas = level._get_or_create_child("CanvasLayerUI", CanvasLayer)
	canvas.layer = 10
	var ui_builder = Level_02_UIBuilder.new(level, canvas)
	ui_builder.build_all()

func _get_or_create_child_on(parent: Node, node_name: String, node_type: Variant) -> Node:
	var existing = parent.get_node_or_null(node_name)
	if existing:
		return existing
	var node = node_type.new()
	node.name = node_name
	parent.add_child(node)
	return node

func _ensure_static_body(container: Node, node_name: String, pos: Vector2, size: Vector2) -> StaticBody2D:
	var body = container.get_node_or_null(node_name) as StaticBody2D
	if body:
		return body
	body = level._create_static_body(node_name, pos, size)
	container.add_child(body)
	return body

func _ensure_interactive(container: Node, node_name: String, obj_id: String, pos: Vector2, size: Vector2) -> InteractiveObject:
	var obj = container.get_node_or_null(node_name) as InteractiveObject
	if obj:
		obj.object_id = obj_id
		return obj
	obj = level._create_interactive(node_name, obj_id, pos, size)
	container.add_child(obj)
	return obj

func _ensure_trigger_zone(container: Node, zone_name: String, pos: Vector2, size: Vector2) -> Area2D:
	var area = container.get_node_or_null(zone_name) as Area2D
	if area:
		return area
	area = _create_trigger_zone(zone_name, pos, size)
	container.add_child(area)
	return area

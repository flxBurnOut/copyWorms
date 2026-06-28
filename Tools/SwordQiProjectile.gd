# ============================================================
# SwordQiProjectile.gd - 闪电剑气弹体
# 赛博战士技能：沿朝向飞行的剑气，碰敌造成伤害后穿透继续飞行
# 纯代码生成视觉：Line2D 渐变线段 + 蓝色闪光尾迹
# ============================================================
extends Area2D

var direction: Vector2 = Vector2.RIGHT
var speed: float = 800.0
var damage: int = 20
var damage_type: int = 1  # GlobalDefine.DamageType.MAGIC
var crit_chance: float = 0.15
var knockback_force: float = 250.0
var max_distance: float = 350.0
var _traveled: float = 0.0
var _hit_enemies: Array = []  # 已命中敌人ID，防止重复
var _owner: Node2D = null
var _homing: bool = false  # 是否追踪（仅Boss战特定弹体启用）
var _homing_delay: float = 0.0  # 追踪延迟（先沿散射方向飞行，延迟结束后才追踪）
const HOMING_DELAY_TIME: float = 0.25  # 散射飞行0.25秒后才开始追踪

# 视觉
var _trail_line: Line2D = null
var _trail_points: Array = []  # 历史位置
const TRAIL_LENGTH := 12
const TRAIL_WIDTH := 6.0

func _ready() -> void:
	# 碰撞形状（胶囊形 → 矩形近似）
	var col_shape = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(40, 16)
	col_shape.shape = shape
	add_child(col_shape)
	
	# 尾迹线
	_trail_line = Line2D.new()
	_trail_line.width = TRAIL_WIDTH
	_trail_line.default_color = Color(0.4, 0.7, 1.0, 0.8)
	_trail_line.z_index = 8
	# 渐变：尾部透明 → 头部亮蓝
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(0.2, 0.5, 1.0, 0.0))
	gradient.add_point(0.5, Color(0.4, 0.7, 1.0, 0.5))
	gradient.add_point(1.0, Color(0.6, 0.9, 1.0, 0.9))
	_trail_line.gradient = gradient
	add_child(_trail_line)
	
	# 头部闪光点
	var head_glow = ColorRect.new()
	head_glow.size = Vector2(20, 8)
	head_glow.position = Vector2(-10, -4)
	head_glow.color = Color(0.7, 0.95, 1.0, 0.9)
	head_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(head_glow)
	
	# 信号
	body_entered.connect(_on_body_entered)
	
	# 碰撞层：检测敌人
	collision_layer = 0  # 弹体本身不属于任何层
	collision_mask = 2   # GlobalDefine.Collision.ENEMY
	
	# 初始朝向
	rotation = direction.angle()

func setup(dir: Vector2, dmg: int, owner: Node2D, dist: float = 350.0) -> void:
	direction = dir.normalized()
	rotation = direction.angle()
	damage = dmg
	_owner = owner
	max_distance = dist

## 带追踪参数的初始化（homing=true 时弹体追踪 boss_target）
func setup_homing(dir: Vector2, dmg: int, owner: Node2D, dist: float = 350.0, homing: bool = false) -> void:
	setup(dir, dmg, owner, dist)
	_homing = homing
	if homing:
		_homing_delay = HOMING_DELAY_TIME  # 先散射飞行，延迟后才追踪

func _physics_process(delta: float) -> void:
	# 追踪逻辑：延迟结束后才开始追踪（保留散射效果）
	if _homing and _homing_delay > 0:
		_homing_delay -= delta
	elif _homing and GameManager.boss_target and is_instance_valid(GameManager.boss_target):
		var to_boss = GameManager.boss_target.global_position - global_position
		if to_boss.length() > 10:
			direction = to_boss.normalized()
	
	var move = direction * speed * delta
	position += move
	_traveled += move.length()
	rotation = direction.angle()
	
	# 更新尾迹
	_trail_points.append(global_position)
	if _trail_points.size() > TRAIL_LENGTH:
		_trail_points.pop_front()
	_update_trail()
	
	# 超出距离消散
	if _traveled >= max_distance:
		_fade_out()

func _update_trail() -> void:
	if not _trail_line:
		return
	_trail_line.clear_points()
	# 转换为本地坐标
	for pt in _trail_points:
		_trail_line.add_point(to_local(pt))

func _on_body_entered(body: Node2D) -> void:
	if not body or not is_instance_valid(body):
		return
	# 防重复命中
	var bid = body.get_instance_id()
	if bid in _hit_enemies:
		return
	_hit_enemies.append(bid)
	
	# 判断是否是敌人
	if not body.has_method("take_damage"):
		return
	
	# 造成伤害
	var result = DamageCalculator.calculate(damage, 0, damage_type, crit_chance)
	var kb_dir = direction.normalized() if direction != Vector2.ZERO else Vector2(1, 0)
	body.take_damage(result["damage"], kb_dir)
	
	# 发出命中事件（用于刀光特效等）
	EventBus.emit(GlobalDefine.EventName.PLAYER_ATTACK_HIT, {
		"attacker": _owner if _owner and is_instance_valid(_owner) else self,
		"target": body,
		"damage": result["damage"],
		"is_crit": result["is_crit"]
	})
	
	# 命中点蓝色闪光
	_spawn_hit_flash(body.global_position)

func _spawn_hit_flash(pos: Vector2) -> void:
	var parent = get_parent()
	if not parent:
		return
	var flash = ColorRect.new()
	flash.size = Vector2(30, 30)
	flash.position = parent.to_local(pos) - flash.size / 2
	flash.color = Color(0.5, 0.8, 1.0, 0.8)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 12
	parent.add_child(flash)
	# 淡出动画
	var tween = flash.create_tween()
	tween.tween_property(flash, "color:a", 0.0, 0.2)
	tween.tween_callback(flash.queue_free)

func _fade_out() -> void:
	# 淡出消失
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.15)
	tween.tween_callback(queue_free)
	set_physics_process(false)

# ============================================================
# EnemyBase.gd - 敌人基类
# 定义所有敌人的公共接口与默认行为
# 子类只需重写对应虚函数，禁止修改此文件
# ============================================================
extends CharacterBody2D
class_name EnemyBase

# 配置引用
@export var config: EnemyConfig = null

# 状态变量
var current_state: int = GlobalDefine.EnemyState.IDLE
var current_health: int = 50
var max_health: int = 50
var is_facing_right: bool = false
var is_dead: bool = false

# 冷却计时器
var attack_cooldown_timer: float = 0.0
var patrol_wait_timer: float = 0.0
var stun_timer: float = 0.0

# 巡逻相关
var patrol_start_pos: Vector2 = Vector2.ZERO
var patrol_direction: int = 1

# 目标引用（通过GM获取，不直接引用节点）
var target: Node2D = null

# 残血闪烁（独立节点，不绑定敌人模型）
var _low_hp_blink: ColorRect = null
var _blink_timer: float = 0.0
const LOW_HP_RATIO: float = 0.3  # 血量低于30%开始闪烁

# ---- 生命周期（子类不要重写，用虚函数扩展） ----

func _ready() -> void:
	_apply_config()
	_setup_visual()
	_setup_collision()
	patrol_start_pos = global_position
	GameManager.register_enemy(self)
	_on_ready()

func _apply_config() -> void:
	if config:
		max_health = config.max_health
		current_health = max_health
	else:
		max_health = 50
		current_health = 50

func _setup_visual() -> void:
	var sprite = ColorRect.new()
	sprite.name = "PlaceholderSprite"
	sprite.color = _get_placeholder_color()
	sprite.size = _get_placeholder_size()
	sprite.position = -sprite.size / 2
	add_child(sprite)

	# 残血闪烁边框（独立节点，浮在模型上方，初始隐藏）
	_low_hp_blink = ColorRect.new()
	_low_hp_blink.name = "LowHPBlink"
	_low_hp_blink.color = Color(1, 0, 0, 0)  # 红色，初始透明
	_low_hp_blink.size = _get_placeholder_size() + Vector2(6, 6)
	_low_hp_blink.position = -_low_hp_blink.size / 2
	add_child(_low_hp_blink)

func _setup_collision() -> void:
	# 碰撞层分离：敌人用第2层，只与第1层（地形）碰撞
	collision_layer = 2
	collision_mask = 1  # 只检测地形层

	var col = CollisionShape2D.new()
	col.name = "CollisionShape"
	var shape = RectangleShape2D.new()
	shape.size = _get_collision_size()
	col.shape = shape
	add_child(col)

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_update_timers(delta)
	_update_low_hp_blink(delta)
	_apply_gravity(delta)
	_update_target()
	_handle_ai(delta)
	move_and_slide()
	_update_facing()
	_on_physics_process(delta)

func _update_timers(delta: float) -> void:
	if attack_cooldown_timer > 0:
		attack_cooldown_timer -= delta
	if patrol_wait_timer > 0:
		patrol_wait_timer -= delta
	if stun_timer > 0:
		stun_timer -= delta

func _apply_gravity(delta: float) -> void:
	if stun_timer > 0:
		return
	var grav = config.gravity if config else 1200.0
	if not is_on_floor():
		velocity.y += grav * delta

func _update_target() -> void:
	# 通过GM获取玩家引用，不直接引用节点
	target = GameManager.player_ref
	if target and not is_instance_valid(target):
		target = null

func _update_facing() -> void:
	if stun_timer > 0:
		return
	if velocity.x > 5:
		is_facing_right = true
		scale.x = 1
	elif velocity.x < -5:
		is_facing_right = false
		scale.x = -1

# ---- 残血闪烁 ----

func _update_low_hp_blink(delta: float) -> void:
	if not _low_hp_blink:
		return

	var hp_ratio = float(current_health) / float(max_health)
	if hp_ratio > LOW_HP_RATIO or hp_ratio <= 0:
		_low_hp_blink.color.a = 0
		return

	_blink_timer += delta
	# 闪烁频率随血量降低而加快
	var blink_speed = lerpf(0.3, 0.08, 1.0 - hp_ratio / LOW_HP_RATIO)
	if _blink_timer >= blink_speed:
		_blink_timer = 0.0
		if _low_hp_blink.color.a > 0.1:
			_low_hp_blink.color.a = 0.1
		else:
			_low_hp_blink.color.a = 0.8

# ---- AI 状态机 ----

func _handle_ai(delta: float) -> void:
	if stun_timer > 0:
		velocity.x = move_toward(velocity.x, 0, 500 * delta)
		return

	match current_state:
		GlobalDefine.EnemyState.IDLE:
			_ai_idle(delta)
		GlobalDefine.EnemyState.PATROL:
			_ai_patrol(delta)
		GlobalDefine.EnemyState.CHASE:
			_ai_chase(delta)
		GlobalDefine.EnemyState.ATTACK:
			_ai_attack(delta)
		GlobalDefine.EnemyState.HURT:
			_ai_hurt(delta)

func _ai_idle(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0, 300 * delta)
	if patrol_wait_timer <= 0:
		patrol_wait_timer = config.patrol_wait_time if config else 2.0
		_change_state(GlobalDefine.EnemyState.PATROL)
	if _can_detect_target():
		_change_state(GlobalDefine.EnemyState.CHASE)

func _ai_patrol(delta: float) -> void:
	var speed = config.move_speed if config else 100.0
	velocity.x = patrol_direction * speed

	# 巡逻范围检测
	var dist_from_start = global_position.x - patrol_start_pos.x
	var wander = config.wander_radius if config else 100.0
	if abs(dist_from_start) > wander:
		patrol_direction *= -1
		_change_state(GlobalDefine.EnemyState.IDLE)

	if _can_detect_target():
		_change_state(GlobalDefine.EnemyState.CHASE)

func _ai_chase(delta: float) -> void:
	if not target or not is_instance_valid(target):
		_change_state(GlobalDefine.EnemyState.IDLE)
		return

	var dir = signf(target.global_position.x - global_position.x)
	var speed = config.move_speed if config else 100.0
	var multiplier = config.chase_speed_multiplier if config else 1.8
	velocity.x = dir * speed * multiplier

	if not _can_detect_target():
		_change_state(GlobalDefine.EnemyState.IDLE)
		return

	if _can_attack_target():
		_change_state(GlobalDefine.EnemyState.ATTACK)

func _ai_attack(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0, 300 * delta)
	if attack_cooldown_timer <= 0 and target and is_instance_valid(target):
		_perform_attack()
		attack_cooldown_timer = config.attack_cooldown if config else 1.5
	_change_state(GlobalDefine.EnemyState.CHASE)

func _ai_hurt(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0, 300 * delta)
	if is_on_floor() and abs(velocity.x) < 10:
		_change_state(GlobalDefine.EnemyState.IDLE)

func _change_state(new_state: int) -> void:
	if is_dead:
		return
	if current_state == new_state:
		return
	current_state = new_state

# ---- 检测 ----

func _can_detect_target() -> bool:
	if not target or not is_instance_valid(target):
		return false
	var detect_range = config.detect_range if config else 300.0
	return global_position.distance_to(target.global_position) <= detect_range

func _can_attack_target() -> bool:
	if not target or not is_instance_valid(target):
		return false
	var attack_range = config.attack_range if config else 40.0
	return global_position.distance_to(target.global_position) <= attack_range

# ---- 攻击 ----

func _perform_attack() -> void:
	_on_attack()

# ---- 伤害与死亡 ----

func take_damage(damage: int, knockback_dir: Vector2 = Vector2.ZERO) -> void:
	if is_dead:
		return

	current_health = maxi(current_health - damage, 0)
	print("[EnemyBase] 受到伤害=%d 剩余血量=%d" % [damage, current_health])

	if knockback_dir != Vector2.ZERO:
		var resist = config.knockback_resistance if config else 0.3
		# 击退：水平为主，向上分量较小（防止飞出屏幕）
		var kb_x = knockback_dir.x * 250.0 * (1.0 - resist)
		var kb_y = -100.0 * (1.0 - resist)  # 固定向上的小力
		velocity = Vector2(kb_x, kb_y)
		stun_timer = 0.3

	EventBus.emit(GlobalDefine.EventName.ENEMY_HURT, {
		"enemy": self,
		"damage": damage,
		"current_health": current_health
	})

	if current_health <= 0:
		die()
	else:
		_change_state(GlobalDefine.EnemyState.HURT)

func die() -> void:
	is_dead = true
	_change_state(GlobalDefine.EnemyState.DEAD)
	GameManager.unregister_enemy(self)
	EventBus.emit(GlobalDefine.EventName.ENEMY_DIED, {
		"enemy": self,
		"exp_reward": config.exp_reward if config else 10
	})
	_on_die()
	queue_free()

# ---- 占位视觉（子类可重写） ----

func _get_placeholder_color() -> Color:
	return Color(0.9, 0.3, 0.3)  # 红色

func _get_placeholder_size() -> Vector2:
	return Vector2(40, 40)

func _get_collision_size() -> Vector2:
	return Vector2(36, 36)

# ---- 取值器 ----

func _get_move_speed() -> float:
	return config.move_speed if config else 100.0

# ---- 虚函数（子类重写点，不要修改基类源码） ----

## 节点就绪后的初始化
func _on_ready() -> void:
	pass

## 每帧物理更新后
func _on_physics_process(_delta: float) -> void:
	pass

## 攻击时触发
func _on_attack() -> void:
	pass

## 死亡时触发
func _on_die() -> void:
	pass

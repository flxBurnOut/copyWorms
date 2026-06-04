# ============================================================
# PlayerBase.gd - 玩家基类
# 定义所有玩家角色的公共接口与默认行为
# 子类只需重写对应虚函数，禁止修改此文件
# ============================================================
extends CharacterBody2D
class_name PlayerBase

# 配置引用
@export var config: PlayerConfig = null

# 状态变量
var current_state: int = GlobalDefine.PlayerState.IDLE
var current_health: int = 100
var max_health: int = 100
var is_invincible: bool = false
var is_facing_right: bool = true
var can_double_jump: bool = false
var has_double_jumped: bool = false

# 跳跃系统（空洞骑士风格：长按跳更高）
var is_jump_held: bool = false
var jump_hold_time: float = 0.0
var max_jump_hold_time: float = 0.25

# 冷却计时器
var attack_cooldown_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var invincible_timer: float = 0.0

# 冲刺相关
var is_dashing: bool = false
var dash_velocity: Vector2 = Vector2.ZERO
var dash_timer: float = 0.0

# 攻击相关
var is_attacking: bool = false
var attack_timer: float = 0.0
var has_hit_this_attack: bool = false

# 闪烁相关
var _blink_timer: float = 0.0
var _blink_visible: bool = true
var _sprite_node: Node = null

# 攻击特效
var _attack_effect_node: ColorRect = null

# 地面检测防抖（防止待机/下落交替闪烁）
var _air_time: float = 0.0
const AIR_THRESHOLD: float = 0.05  # 离地超过此时间才切下落

# ---- 生命周期 ----

func _ready() -> void:
	_apply_config()
	_setup_visual()
	_setup_collision()
	# 设置碰撞层：玩家用第4层，只与第1层（地形）碰撞，绝不与敌人（layer=2）交互
	collision_layer = 4
	collision_mask = 1
	_on_ready()

func _apply_config() -> void:
	if config:
		max_health = config.max_health
		current_health = max_health
	else:
		max_health = 100
		current_health = 100

func _setup_visual() -> void:
	var sprite = ColorRect.new()
	sprite.name = "PlaceholderSprite"
	sprite.color = _get_placeholder_color()
	sprite.size = _get_placeholder_size()
	sprite.position = -sprite.size / 2
	add_child(sprite)
	_sprite_node = sprite

func _setup_collision() -> void:
	var col = CollisionShape2D.new()
	col.name = "CollisionShape"
	var shape = RectangleShape2D.new()
	shape.size = _get_collision_size()
	col.shape = shape
	add_child(col)

func _physics_process(delta: float) -> void:
	_update_timers(delta)
	_handle_input()
	_apply_gravity(delta)
	_handle_state(delta)
	_check_enemy_contact(delta)
	move_and_slide()
	_update_facing()
	_update_blink(delta)
	_on_physics_process(delta)

func _update_timers(delta: float) -> void:
	if attack_cooldown_timer > 0:
		attack_cooldown_timer -= delta
	if dash_cooldown_timer > 0:
		dash_cooldown_timer -= delta
	if invincible_timer > 0:
		invincible_timer -= delta
		if invincible_timer <= 0:
			is_invincible = false
			_restore_visibility()

	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0:
			is_dashing = false

	if is_attacking:
		attack_timer -= delta
		_update_attack_effect()
		if attack_timer <= 0:
			is_attacking = false
			has_hit_this_attack = false
			# 攻击结束：地面切IDLE/RUN，空中切FALL（防止卡死）
			if is_on_floor():
				var input_dir = _get_input_direction()
				if abs(input_dir.x) > 0.1:
					_change_state(GlobalDefine.PlayerState.RUN)
				else:
					_change_state(GlobalDefine.PlayerState.IDLE)
			else:
				_change_state(GlobalDefine.PlayerState.FALL)

func _handle_input() -> void:
	if _input_attack_just_pressed():
		perform_attack()
	if _input_dash_just_pressed():
		perform_dash()
	if _input_skill_just_pressed():
		perform_skill()
	if _input_pause_just_pressed():
		GameManager.toggle_pause()

func _apply_gravity(delta: float) -> void:
	if is_dashing:
		return

	var grav = config.gravity if config else 1200.0

	if current_state == GlobalDefine.PlayerState.JUMP and not is_on_floor():
		if is_jump_held and jump_hold_time < max_jump_hold_time:
			jump_hold_time += delta
			var hold_scale = config.jump_hold_gravity_scale if config else 0.35
			grav *= hold_scale
		else:
			var release_scale = config.jump_release_gravity_scale if config else 2.5
			grav *= release_scale

	if not is_on_floor():
		velocity.y += grav * delta
	else:
		has_double_jumped = false
		is_jump_held = false
		jump_hold_time = 0.0

func _handle_state(delta: float) -> void:
	if is_dashing:
		velocity = dash_velocity
		return

	match current_state:
		GlobalDefine.PlayerState.IDLE:
			_handle_idle(delta)
		GlobalDefine.PlayerState.RUN:
			_handle_run(delta)
		GlobalDefine.PlayerState.JUMP:
			_handle_jump(delta)
		GlobalDefine.PlayerState.FALL:
			_handle_fall(delta)
		GlobalDefine.PlayerState.ATTACK, GlobalDefine.PlayerState.SKILL:
			_handle_attack_state(delta)
		GlobalDefine.PlayerState.HURT:
			_handle_hurt(delta)
		GlobalDefine.PlayerState.DEAD:
			_handle_dead(delta)

func _update_facing() -> void:
	if is_dashing:
		return
	if velocity.x > 10:
		is_facing_right = true
		scale.x = 1
	elif velocity.x < -10:
		is_facing_right = false
		scale.x = -1

# ---- 闪烁效果 ----

func _update_blink(delta: float) -> void:
	if not is_invincible:
		return
	_blink_timer += delta
	if _blink_timer >= 0.08:
		_blink_timer = 0.0
		_blink_visible = !_blink_visible
		if _sprite_node:
			_sprite_node.visible = _blink_visible

func _restore_visibility() -> void:
	if _sprite_node:
		_sprite_node.visible = true

func _update_attack_effect() -> void:
	if not _attack_effect_node or not is_instance_valid(_attack_effect_node):
		return
	if _attack_effect_node.color.a <= 0:
		_attack_effect_node.queue_free()
		_attack_effect_node = null
		return
	_attack_effect_node.color.a -= 0.07
	if _attack_effect_node.color.a < 0:
		_attack_effect_node.color.a = 0

# ---- 敌人接触检测 ----

func _check_enemy_contact(_delta: float) -> void:
	if is_invincible or current_state == GlobalDefine.PlayerState.DEAD:
		return

	for enemy in GameManager.get_enemies():
		if not is_instance_valid(enemy):
			continue
		# 检测碰撞重叠
		var my_rect = Rect2(global_position - _get_collision_size() / 2, _get_collision_size())
		var enemy_size = Vector2(36, 36)
		if enemy.has_method("_get_collision_size"):
			enemy_size = enemy._get_collision_size()
		var enemy_rect = Rect2(enemy.global_position - enemy_size / 2, enemy_size)
		if my_rect.intersects(enemy_rect):
			_take_contact_damage(enemy)
			return

func _take_contact_damage(enemy: Node2D) -> void:
	var atk = 8  # 默认接触伤害
	if enemy.has_method("_get_placeholder_color"):  # 有 config 属性
		if enemy.config:
			atk = enemy.config.attack_damage

	current_health = maxi(current_health - atk, 0)
	is_invincible = true
	invincible_timer = 1.5  # 受伤后1.5秒无敌

	# 击退：向远离敌人的方向
	var kb_dir = signf(global_position.x - enemy.global_position.x)
	if kb_dir == 0:
		kb_dir = 1.0
	velocity = Vector2(kb_dir * 300.0, -200.0)

	EventBus.emit(GlobalDefine.EventName.PLAYER_HURT, {
		"player": self,
		"damage": atk,
		"current_health": current_health
	})
	EventBus.emit(GlobalDefine.EventName.HEALTH_CHANGED, {
		"target": self,
		"current_health": current_health,
		"max_health": max_health
	})

	if current_health <= 0:
		die()
	else:
		_change_state(GlobalDefine.PlayerState.HURT)

func _change_state(new_state: int) -> void:
	if current_state == GlobalDefine.PlayerState.DEAD:
		return
	if current_state == new_state:
		return
	current_state = new_state
	EventBus.emit(GlobalDefine.EventName.PLAYER_STATE_CHANGED, {
		"state": new_state,
		"player": self
	})

# ---- 状态处理 ----

func _handle_idle(delta: float) -> void:
	var input_dir = _get_input_direction()
	if abs(input_dir.x) > 0.1:
		_change_state(GlobalDefine.PlayerState.RUN)
		return
	velocity.x = move_toward(velocity.x, 0, _get_move_speed() * 10 * delta)

	# 防抖：离地超过阈值才切下落
	if not is_on_floor():
		_air_time += delta
		if _air_time > AIR_THRESHOLD:
			_change_state(GlobalDefine.PlayerState.FALL)
	else:
		_air_time = 0.0

	if _input_jump_just_pressed():
		_perform_jump()

func _handle_run(delta: float) -> void:
	var input_dir = _get_input_direction()
	if abs(input_dir.x) < 0.1:
		_change_state(GlobalDefine.PlayerState.IDLE)
		return
	velocity.x = move_toward(velocity.x, input_dir.x * _get_move_speed(), _get_move_speed() * 10 * delta)

	if not is_on_floor():
		_air_time += delta
		if _air_time > AIR_THRESHOLD:
			_change_state(GlobalDefine.PlayerState.FALL)
	else:
		_air_time = 0.0

	if _input_jump_just_pressed():
		_perform_jump()

func _handle_jump(delta: float) -> void:
	var input_dir = _get_input_direction()
	var speed = _get_move_speed()
	velocity.x = move_toward(velocity.x, input_dir.x * speed, speed * 10 * delta)

	if not Input.is_action_pressed("player_jump"):
		is_jump_held = false

	if velocity.y >= 0:
		_change_state(GlobalDefine.PlayerState.FALL)

func _handle_fall(delta: float) -> void:
	var input_dir = _get_input_direction()
	var speed = _get_move_speed()
	velocity.x = move_toward(velocity.x, input_dir.x * speed, speed * 10 * delta)
	if is_on_floor():
		_air_time = 0.0
		has_double_jumped = false
		is_jump_held = false
		jump_hold_time = 0.0
		if abs(input_dir.x) > 0.1:
			_change_state(GlobalDefine.PlayerState.RUN)
		else:
			_change_state(GlobalDefine.PlayerState.IDLE)
	if _input_jump_just_pressed() and not has_double_jumped and can_double_jump:
		_perform_double_jump()

func _handle_attack_state(delta: float) -> void:
	# 空中攻击时保持水平移动能力
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0, _get_move_speed() * 5 * delta)
	else:
		var input_dir = _get_input_direction()
		velocity.x = move_toward(velocity.x, input_dir.x * _get_move_speed(), _get_move_speed() * 3 * delta)
		var grav = config.gravity if config else 1200.0
		velocity.y += grav * delta

func _handle_hurt(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0, _get_move_speed() * 5 * delta)
	if is_on_floor() and abs(velocity.x) < 10:
		_change_state(GlobalDefine.PlayerState.IDLE)

func _handle_dead(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0, 500 * delta)

# ---- 动作 ----

func _perform_jump() -> void:
	var jump_vel = config.jump_velocity if config else -650.0
	velocity.y = jump_vel
	is_jump_held = true
	jump_hold_time = 0.0
	_air_time = AIR_THRESHOLD + 0.01  # 立即超过阈值
	_change_state(GlobalDefine.PlayerState.JUMP)

func _perform_double_jump() -> void:
	has_double_jumped = true
	var jump_vel = config.jump_velocity if config else -650.0
	velocity.y = jump_vel * 0.75
	is_jump_held = true
	jump_hold_time = 0.0
	_change_state(GlobalDefine.PlayerState.JUMP)

func perform_attack() -> void:
	if attack_cooldown_timer > 0 or is_attacking:
		return
	is_attacking = true
	has_hit_this_attack = false
	attack_timer = 0.25
	attack_cooldown_timer = config.attack_cooldown if config else 0.4
	_change_state(GlobalDefine.PlayerState.ATTACK)

	# 攻击视觉：挂到场景层（父节点），用全局坐标避免被玩家scale翻转
	_spawn_attack_effect()

	_on_attack()

func _spawn_attack_effect() -> void:
	var parent = get_parent()
	if not parent:
		return

	# 移除旧特效
	if _attack_effect_node and is_instance_valid(_attack_effect_node):
		_attack_effect_node.queue_free()

	_attack_effect_node = ColorRect.new()
	_attack_effect_node.name = "AttackEffect"
	_attack_effect_node.size = Vector2(55, 10)
	_attack_effect_node.color = Color(1, 1, 1, 0.9)
	# 全局坐标：玩家位置 + 朝向偏移
	var facing = 1.0 if is_facing_right else -1.0
	_attack_effect_node.position = global_position + Vector2(facing * 35, -15)
	parent.add_child(_attack_effect_node)

func perform_dash() -> void:
	if dash_cooldown_timer > 0 or is_dashing:
		return
	is_dashing = true
	dash_timer = config.dash_duration if config else 0.2
	dash_cooldown_timer = config.dash_cooldown if config else 0.8
	var dir = 1.0 if is_facing_right else -1.0
	dash_velocity = Vector2(dir * _get_dash_speed(), 0)
	is_invincible = true
	invincible_timer = dash_timer
	_on_dash()

func perform_skill() -> void:
	if is_attacking or is_dashing:
		return
	_on_skill()

func take_damage(damage: int, knockback_dir: Vector2 = Vector2.ZERO) -> void:
	if is_invincible or current_state == GlobalDefine.PlayerState.DEAD:
		return
	current_health = maxi(current_health - damage, 0)
	is_invincible = true
	invincible_timer = config.hurt_invincible_time if config else 1.0

	if knockback_dir != Vector2.ZERO:
		var knockback_force = config.hurt_knockback if config else 300.0
		velocity = Vector2(knockback_dir.x * knockback_force, -150.0)

	EventBus.emit(GlobalDefine.EventName.PLAYER_HURT, {
		"player": self,
		"damage": damage,
		"current_health": current_health
	})
	EventBus.emit(GlobalDefine.EventName.HEALTH_CHANGED, {
		"target": self,
		"current_health": current_health,
		"max_health": max_health
	})

	if current_health <= 0:
		die()
	else:
		_change_state(GlobalDefine.PlayerState.HURT)

func die() -> void:
	_change_state(GlobalDefine.PlayerState.DEAD)
	EventBus.emit(GlobalDefine.EventName.PLAYER_DIED, { "player": self })
	_on_die()

func heal(amount: int) -> void:
	current_health = mini(current_health + amount, max_health)
	EventBus.emit(GlobalDefine.EventName.HEALTH_CHANGED, {
		"target": self,
		"current_health": current_health,
		"max_health": max_health
	})

# ---- 输入读取 ----

func _get_input_direction() -> Vector2:
	return Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

func _input_jump_just_pressed() -> bool:
	return Input.is_action_just_pressed("player_jump")

func _input_attack_just_pressed() -> bool:
	return Input.is_action_just_pressed("player_attack")

func _input_dash_just_pressed() -> bool:
	return Input.is_action_just_pressed("player_dash")

func _input_skill_just_pressed() -> bool:
	return Input.is_action_just_pressed("player_skill")

func _input_pause_just_pressed() -> bool:
	return Input.is_action_just_pressed("ui_pause")

# ---- 取值器 ----

func _get_move_speed() -> float:
	return config.move_speed if config else 300.0

func _get_dash_speed() -> float:
	return config.dash_speed if config else 800.0

func _get_gravity() -> float:
	return config.gravity if config else 1200.0

# ---- 占位视觉 ----

func _get_placeholder_color() -> Color:
	return Color(0.2, 0.6, 0.9)

func _get_placeholder_size() -> Vector2:
	return Vector2(48, 64)

func _get_collision_size() -> Vector2:
	return Vector2(40, 60)

# ---- 虚函数 ----

func _on_ready() -> void:
	pass

func _on_physics_process(_delta: float) -> void:
	pass

func _on_attack() -> void:
	pass

func _on_dash() -> void:
	pass

func _on_skill() -> void:
	pass

func _on_die() -> void:
	pass

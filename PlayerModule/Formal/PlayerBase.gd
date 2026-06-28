# ============================================================
# PlayerBase.gd - 玩家基类
# 定义所有玩家角色的公共状态机、碰撞、伤害系统
# 视觉层和攻击特效由子类实现
# ============================================================
extends CharacterBody2D
class_name PlayerBase

@export var config: PlayerConfig = null

# 能力开关
var can_jump: bool = true
var can_dash: bool = true
var can_attack: bool = true
var can_skill: bool = true
var can_attack_hold_dash: bool = true

# 运行时移速倍率（关卡可临时调节，如"沉重化"; 默认1.0零影响）
# 不直接修改共享 PlayerConfig.tres
var runtime_move_speed_multiplier: float = 1.0

# 状态变量
var current_state: int = GlobalDefine.PlayerState.IDLE
var current_health: int = 100
var max_health: int = 100
var is_invincible: bool = false
var is_facing_right: bool = true
var _is_super_armor: bool = false  # 霸体：受击不击退不中断
var can_double_jump: bool = false
var has_double_jumped: bool = false

# 跳跃系统
var is_jump_held: bool = false
var jump_hold_time: float = 0.0
var max_jump_hold_time: float = 0.25

# 冷却计时器
var attack_cooldown_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var invincible_timer: float = 0.0

# 击退缓动
var _knockback_force: float = 0.0
var _knockback_timer: float = 0.0
const KNOCKBACK_DURATION: float = 0.35

# 冲刺
var is_dashing: bool = false
var dash_velocity: Vector2 = Vector2.ZERO
var dash_timer: float = 0.0

# 攻击
var is_attacking: bool = false
var attack_timer: float = 0.0
var has_hit_this_attack: bool = false
var _attack_started_in_air: bool = false

# 攻击前摇
var _attack_windup_pending: bool = false
var _attack_windup_timer: float = 0.0
const ATTACK_WINDUP_TIME: float = 0.1

# 闪烁
var _blink_timer: float = 0.0
var _blink_visible: bool = true
var _sprite_node: Node = null

# 地面防抖
var _air_time: float = 0.0
const AIR_THRESHOLD: float = 0.05

# 行走音效计时器
var _walk_sfx_timer: float = 0.0
const WALK_SFX_INTERVAL: float = 0.45

# ---- 生命周期 ----

func _ready() -> void:
	collision_layer = GlobalDefine.Collision.PLAYER
	collision_mask = GlobalDefine.Collision.TERRAIN
	_apply_config()
	_setup_collision()
	# 阶段3: 订阅 InputManager 的游戏操作信号
	# attack/dash/skill 由信号驱动(单次触发)，跳跃/移动保留轮询(需连续状态)
	if not Engine.is_editor_hint():
		if not InputManager.game_action.is_connected(_on_game_action):
			InputManager.game_action.connect(_on_game_action)
	_on_ready()

func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		if InputManager.game_action.is_connected(_on_game_action):
			InputManager.game_action.disconnect(_on_game_action)

func _apply_config() -> void:
	if config:
		max_health = config.max_health
		current_health = max_health
	else:
		max_health = 100
		current_health = 100

func _setup_collision() -> void:
	var col = CollisionShape2D.new()
	col.name = "CollisionShape"
	var shape = RectangleShape2D.new()
	shape.size = _get_collision_size()
	col.shape = shape
	add_child(col)

func _physics_process(delta: float) -> void:
	# 死亡状态下仍允许动画更新（播放死亡动画），但不处理其他逻辑
	if current_state == GlobalDefine.PlayerState.DEAD:
		velocity.x = move_toward(velocity.x, 0, 500 * delta)
		if has_method("_update_animation"):
			call("_update_animation")
		return
	if GameManager.is_game_over:
		return
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
	if attack_cooldown_timer > 0: attack_cooldown_timer -= delta
	if dash_cooldown_timer > 0: dash_cooldown_timer -= delta
	if invincible_timer > 0:
		invincible_timer -= delta
		if invincible_timer <= 0:
			is_invincible = false
			_restore_visibility()
	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0: is_dashing = false
	# 攻击前摇倒计时
	if _attack_windup_pending:
		_attack_windup_timer -= delta
		if _attack_windup_timer <= 0:
			_attack_windup_pending = false
			_on_attack()
	if is_attacking:
		attack_timer -= delta
		if attack_timer <= 0:
			is_attacking = false
			has_hit_this_attack = false
			_attack_started_in_air = false
			if is_on_floor():
				if abs(_get_input_direction().x) > 0.1:
					_change_state(GlobalDefine.PlayerState.RUN)
				else:
					_change_state(GlobalDefine.PlayerState.IDLE)
			else:
				# 空中攻击结束后回到跳跃状态
				_change_state(GlobalDefine.PlayerState.JUMP)

func _handle_input() -> void:
	# attack/dash/skill 已迁移到 InputManager.game_action 信号
	# (由 _on_game_action 回调处理)
	# 保留: 跳跃按住检测(需 is_action_pressed 连续状态)
	# ui_pause(ESC) 已迁移到 InputManager 独占处理
	pass

## 阶段3: InputManager 游戏操作信号回调
## 处理 attack/dash/skill（跳跃保留在状态机的轮询中）
func _on_game_action(action: StringName, _event: InputEvent) -> void:
	# 死亡状态不响应任何操作
	if current_state == GlobalDefine.PlayerState.DEAD:
		return
	# 受击状态：击退期间锁定输入（防止瞬移式闪避/攻击取消）
	if current_state == GlobalDefine.PlayerState.HURT:
		if _knockback_force != 0.0:
			return  # 击退缓动未结束，不接受任何操作
		if _can_cancel_hurt():
			_cancel_hurt()
	# 攻击/冲刺中不允许发起攻击
	if is_attacking or is_dashing:
		return
	match action:
		&"player_attack":
			if can_attack: perform_attack()
		&"player_dash":
			if can_dash: perform_dash()
		&"player_skill":
			if can_skill: perform_skill()
		# ui_accept 不在此处理，由 Level_01 订阅
		&"ui_accept":
			pass

func _apply_gravity(delta: float) -> void:
	if is_dashing: return
	# 空中攻击时悬浮，不施加重力
	if is_attacking and _attack_started_in_air and not is_on_floor(): return
	var grav = config.gravity if config else 1200.0
	if current_state == GlobalDefine.PlayerState.JUMP and not is_on_floor():
		if is_jump_held and jump_hold_time < max_jump_hold_time:
			jump_hold_time += delta
			grav *= config.jump_hold_gravity_scale if config else 0.35
		else:
			grav *= config.jump_release_gravity_scale if config else 2.5
	if not is_on_floor():
		velocity.y += grav * delta
	else:
		has_double_jumped = false
		is_jump_held = false
		jump_hold_time = 0.0

func _handle_state(delta: float) -> void:
	if is_dashing: velocity = dash_velocity; return
	match current_state:
		GlobalDefine.PlayerState.IDLE: _handle_idle(delta)
		GlobalDefine.PlayerState.RUN: _handle_run(delta)
		GlobalDefine.PlayerState.JUMP: _handle_jump(delta)
		GlobalDefine.PlayerState.FALL: _handle_fall(delta)
		GlobalDefine.PlayerState.ATTACK, GlobalDefine.PlayerState.SKILL: _handle_attack_state(delta)
		GlobalDefine.PlayerState.HURT: _handle_hurt(delta)
		GlobalDefine.PlayerState.DEAD: _handle_dead(delta)

func _update_facing() -> void:
	if is_dashing: return
	if current_state == GlobalDefine.PlayerState.HURT: return
	if velocity.x > 10: is_facing_right = true; scale.x = 1
	elif velocity.x < -10: is_facing_right = false; scale.x = -1

# ---- 闪烁 ----

func _update_blink(delta: float) -> void:
	if not is_invincible: return
	_blink_timer += delta
	if _blink_timer >= 0.08:
		_blink_timer = 0.0
		_blink_visible = !_blink_visible
		if _sprite_node: _sprite_node.visible = _blink_visible

func _restore_visibility() -> void:
	if _sprite_node: _sprite_node.visible = true

# ---- 敌人接触 ----

func _check_enemy_contact(_delta: float) -> void:
	if is_invincible or current_state == GlobalDefine.PlayerState.DEAD: return
	for enemy in GameManager.get_enemies():
		if not is_instance_valid(enemy): continue
		if enemy.has_method("deals_contact_damage") and not enemy.deals_contact_damage():
			continue
		var es = Vector2(36, 36)
		if enemy.has_method("_get_collision_size"): es = enemy._get_collision_size()
		var mr = Rect2(global_position - _get_collision_size() / 2, _get_collision_size())
		var er = Rect2(enemy.global_position - es / 2, es)
		if mr.intersects(er): _take_contact_damage(enemy); return

func _take_contact_damage(enemy: Node2D) -> void:
	var atk = 8
	if enemy.config:
		atk = enemy.config.attack_damage
	current_health = maxi(current_health - atk, 0)
	# 霸体：只扣血，不击退不中断，但仍需无敌帧防止连续受伤
	if _is_super_armor:
		is_invincible = true
		invincible_timer = config.hurt_invincible_time if config else 1.0
		SFXManager.play_pitched(SFXManager.SFX.PLAYER_HURT, 0.92, 1.08)
		EventBus.emit(GlobalDefine.EventName.PLAYER_HURT, {"player": self, "damage": atk, "current_health": current_health})
		EventBus.emit(GlobalDefine.EventName.HEALTH_CHANGED, {"target": self, "current_health": current_health, "max_health": max_health})
		if current_health <= 0:
			die()
		return
	is_invincible = true
	invincible_timer = 1.5
	is_attacking = false
	attack_timer = 0.0
	_attack_started_in_air = false
	_attack_windup_pending = false
	is_dashing = false
	dash_timer = 0.0
	attack_cooldown_timer = 0.0
	var kb_dir = signf(global_position.x - enemy.global_position.x)
	if kb_dir == 0:
		kb_dir = 1.0
	velocity = Vector2(kb_dir * 300.0, -200.0)
	# 受击时推开周围敌人，防止无敌结束后立刻再次被贴身
	_push_nearby_enemies(120.0)
	SFXManager.play_pitched(SFXManager.SFX.PLAYER_HURT, 0.92, 1.08)
	EventBus.emit(GlobalDefine.EventName.PLAYER_HURT, {"player": self, "damage": atk, "current_health": current_health})
	EventBus.emit(GlobalDefine.EventName.HEALTH_CHANGED, {"target": self, "current_health": current_health, "max_health": max_health})
	if current_health <= 0:
		die()
	else:
		_change_state(GlobalDefine.PlayerState.HURT)

## 受击时推开周围敌人，防止贴身连击
func _push_nearby_enemies(push_force: float) -> void:
	for enemy in GameManager.get_enemies():
		if not is_instance_valid(enemy):
			continue
		var dist = global_position.distance_to(enemy.global_position)
		if dist < 80.0:
			var push_dir = signf(enemy.global_position.x - global_position.x)
			if push_dir == 0:
				push_dir = 1.0
			enemy.velocity.x = push_dir * push_force
			enemy.velocity.y = -80.0
			if enemy.has_method("set") and "stun_timer" in enemy:
				enemy.stun_timer = 0.3

func _change_state(new_state: int) -> void:
	if current_state == GlobalDefine.PlayerState.DEAD: return
	if current_state == new_state: return
	current_state = new_state
	EventBus.emit(GlobalDefine.EventName.PLAYER_STATE_CHANGED, {"state": new_state, "player": self})

## 统一冻结/解冻玩家（关卡 _freeze_player 应委托到此方法）
## 修复：旧实现 set_physics_process(false) 会连带禁用子类 _on_physics_process 中的
## _update_animation()，导致 _change_state(IDLE) 后无人切动画，walk 动画持续循环。
## 本方法在禁用 physics_process 后显式调用 _update_animation() 刷新到 idle。
##
## [旧实现 - 保留以备回退]
##   player.velocity = Vector2.ZERO
##   player.set_physics_process(false)
##   player.set_process_input(false)
##   player._change_state(GlobalDefine.PlayerState.IDLE)
## 回退方式：将各关卡 _freeze_player 中的 player.set_frozen(freeze) 替换回上述 4 行
func set_frozen(freeze: bool) -> void:
	if freeze:
		velocity = Vector2.ZERO
		set_physics_process(false)
		set_process_input(false)
		_change_state(GlobalDefine.PlayerState.IDLE)
		# 显式刷新动画到 idle（_physics_process 已禁用，子类 _update_animation 不会再被自动调用）
		if has_method("_update_animation"):
			call("_update_animation")
	else:
		set_physics_process(true)
		set_process_input(true)

## 梯子会临时禁用玩家 physics_process。进入前必须把闪避/受击无敌闪烁
## 归一化，否则可能冻结在 _sprite_node.visible=false 的一帧。
func begin_ladder_climb() -> void:
	velocity = Vector2.ZERO
	is_dashing = false
	dash_timer = 0.0
	dash_velocity = Vector2.ZERO
	is_attacking = false
	attack_timer = 0.0
	has_hit_this_attack = false
	_attack_started_in_air = false
	_attack_windup_pending = false
	_blink_visible = true
	_blink_timer = 0.0
	_restore_visibility()
	_change_state(GlobalDefine.PlayerState.IDLE)
	if has_method("_update_animation"):
		call("_update_animation")
	set_physics_process(false)

func end_ladder_climb() -> void:
	_blink_visible = true
	_blink_timer = 0.0
	_restore_visibility()
	velocity = Vector2.ZERO
	set_physics_process(true)
	if has_method("_update_animation"):
		call("_update_animation")

# ---- 状态处理 ----

func _handle_idle(delta: float) -> void:
	if abs(_get_input_direction().x) > 0.1:
		_change_state(GlobalDefine.PlayerState.RUN)
		return
	velocity.x = move_toward(velocity.x, 0, _get_move_speed() * 10 * delta)
	_walk_sfx_timer = 0.0  # 停止行走，重置计时器
	if not is_on_floor():
		_air_time += delta
		if _air_time > AIR_THRESHOLD:
			_change_state(GlobalDefine.PlayerState.FALL)
	else:
		_air_time = 0.0
	if can_jump and _input_jump_just_pressed():
		_perform_jump()

func _handle_run(delta: float) -> void:
	var id = _get_input_direction()
	if abs(id.x) < 0.1:
		_change_state(GlobalDefine.PlayerState.IDLE)
		return
	velocity.x = move_toward(velocity.x, id.x * _get_move_speed(), _get_move_speed() * 10 * delta)
	# 行走音效：周期性播放脚步声
	if is_on_floor():
		_walk_sfx_timer -= delta
		if _walk_sfx_timer <= 0.0:
			SFXManager.play_pitched(SFXManager.SFX.PLAYER_WALK, 0.92, 1.08, 0.0)
			_walk_sfx_timer = WALK_SFX_INTERVAL
	else:
		_walk_sfx_timer = 0.0  # 空中不响，落地后立即响
	if not is_on_floor():
		_air_time += delta
		if _air_time > AIR_THRESHOLD:
			_change_state(GlobalDefine.PlayerState.FALL)
	else:
		_air_time = 0.0
	if can_jump and _input_jump_just_pressed():
		_perform_jump()

func _handle_jump(delta: float) -> void:
	var id = _get_input_direction()
	velocity.x = move_toward(velocity.x, id.x * _get_move_speed(), _get_move_speed() * 10 * delta)
	if not Input.is_action_pressed("player_jump"):
		is_jump_held = false
	if velocity.y >= 0:
		_change_state(GlobalDefine.PlayerState.FALL)

func _handle_fall(delta: float) -> void:
	var id = _get_input_direction()
	velocity.x = move_toward(velocity.x, id.x * _get_move_speed(), _get_move_speed() * 10 * delta)
	if is_on_floor():
		_air_time = 0.0
		has_double_jumped = false
		is_jump_held = false
		jump_hold_time = 0.0
		if abs(id.x) > 0.1:
			_change_state(GlobalDefine.PlayerState.RUN)
		else:
			_change_state(GlobalDefine.PlayerState.IDLE)
	if can_jump and _input_jump_just_pressed() and not has_double_jumped and can_double_jump:
		_perform_double_jump()

func _handle_attack_state(delta: float) -> void:
	if _attack_started_in_air:
		# 空中攻击：保持横向操控，悬浮
		velocity.x = move_toward(velocity.x, _get_input_direction().x * _get_move_speed(), _get_move_speed() * 3 * delta)
		if not is_on_floor():
			velocity.y = 0.0
			# 空中攻击期间允许二段跳
			if can_jump and can_double_jump and not has_double_jumped and _input_jump_just_pressed():
				_perform_double_jump()
				return
	elif is_on_floor():
		# 地面攻击：行走时保留一半水平速度，站立时减速到0
		var target_x = 0.0
		if abs(velocity.x) > 10.0:
			target_x = signf(velocity.x) * _get_move_speed() * 0.5
		velocity.x = move_toward(velocity.x, target_x, _get_move_speed() * 5 * delta)
	else:
		# 地面攻击但走出悬崖：正常下落
		velocity.x = move_toward(velocity.x, _get_input_direction().x * _get_move_speed(), _get_move_speed() * 3 * delta)

func _handle_hurt(delta: float) -> void:
	# 击退缓动：sin 曲线 0→max→0，避免瞬移
	if _knockback_force != 0.0:
		_knockback_timer += delta
		var t = clampf(_knockback_timer / KNOCKBACK_DURATION, 0.0, 1.0)
		var eased = sin(t * PI)
		velocity.x = _knockback_force * eased
		if t >= 1.0:
			_knockback_force = 0.0
			_knockback_timer = 0.0
			velocity.x = 0.0
	else:
		velocity.x = move_toward(velocity.x, 0, _get_move_speed() * 5 * delta)
	# hit 动画可被跳跃取消
	if _can_cancel_hurt() and can_jump and _input_jump_just_pressed():
		_cancel_hurt()
		_perform_jump()
		return
	# 正常恢复
	if is_on_floor() and abs(velocity.x) < 10:
		_change_state(GlobalDefine.PlayerState.IDLE)

## 判断受击状态是否可被操作取消（子类可覆盖）
func _can_cancel_hurt() -> bool:
	return true

## 取消受击状态，恢复为可操作状态（保留无敌时间，防止立刻再次被击中）
func _cancel_hurt() -> void:
	if is_on_floor():
		if abs(_get_input_direction().x) > 0.1:
			_change_state(GlobalDefine.PlayerState.RUN)
		else:
			_change_state(GlobalDefine.PlayerState.IDLE)
	else:
		_change_state(GlobalDefine.PlayerState.FALL)

func _handle_dead(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0, 500 * delta)

# ---- 动作 ----

func _perform_jump() -> void:
	velocity.y = (config.jump_velocity if config else -650.0) * 1.15
	is_jump_held = true
	jump_hold_time = 0.0
	_air_time = AIR_THRESHOLD + 0.01
	_change_state(GlobalDefine.PlayerState.JUMP)

func _perform_double_jump() -> void:
	has_double_jumped = true
	velocity.y = (config.jump_velocity if config else -650.0) * 0.9
	is_jump_held = true
	jump_hold_time = 0.0
	_change_state(GlobalDefine.PlayerState.JUMP)

func perform_attack() -> void:
	if attack_cooldown_timer > 0 or is_attacking:
		return
	is_attacking = true
	has_hit_this_attack = false
	attack_timer = 0.25 + ATTACK_WINDUP_TIME
	attack_cooldown_timer = config.attack_cooldown if config else 0.4
	_attack_started_in_air = not is_on_floor()
	if _attack_started_in_air:
		velocity.y = 0.0
		attack_timer = 0.35 + ATTACK_WINDUP_TIME
	_change_state(GlobalDefine.PlayerState.ATTACK)
	# 前摇延迟：动画立即播放，0.1s 后才打出伤害
	_attack_windup_pending = true
	_attack_windup_timer = ATTACK_WINDUP_TIME
	# 攻击音效
	SFXManager.play_pitched(SFXManager.SFX.PLAYER_ATTACK, 0.95, 1.08)

func perform_dash() -> void:
	if dash_cooldown_timer > 0 or is_dashing:
		return
	is_dashing = true
	dash_timer = config.dash_duration if config else 0.2
	dash_cooldown_timer = config.dash_cooldown if config else 0.8
	var dir = 1.0 if is_facing_right else -1.0
	dash_velocity = Vector2(dir * _get_dash_speed(), 0)
	is_invincible = true
	invincible_timer = dash_timer + 0.3
	_on_dash()

func perform_skill() -> void:
	if is_attacking or is_dashing:
		return
	_on_skill()

func take_damage(damage: int, knockback_dir: Vector2 = Vector2.ZERO) -> void:
	if is_invincible or current_state == GlobalDefine.PlayerState.DEAD:
		return
	current_health = maxi(current_health - damage, 0)
	# 霸体：只扣血，不击退不中断不进入HURT，但仍需无敌帧防止连续受伤
	if _is_super_armor:
		is_invincible = true
		invincible_timer = config.hurt_invincible_time if config else 1.0
		SFXManager.play_pitched(SFXManager.SFX.PLAYER_HURT, 0.92, 1.08)
		EventBus.emit(GlobalDefine.EventName.PLAYER_HURT, {"player": self, "damage": damage, "current_health": current_health})
		EventBus.emit(GlobalDefine.EventName.HEALTH_CHANGED, {"target": self, "current_health": current_health, "max_health": max_health})
		if current_health <= 0:
			die()
		return
	is_invincible = true
	invincible_timer = config.hurt_invincible_time if config else 1.0
	is_attacking = false
	attack_timer = 0.0
	_attack_started_in_air = false
	_attack_windup_pending = false
	is_dashing = false
	dash_timer = 0.0
	attack_cooldown_timer = 0.0
	if knockback_dir != Vector2.ZERO:
		var kb_speed = config.hurt_knockback if config else 300.0
		_knockback_force = signf(knockback_dir.x) * kb_speed
		_knockback_timer = 0.0
		velocity.y = -120.0
	# 受击时推开周围敌人，防止贴身连击
	_push_nearby_enemies(120.0)
	SFXManager.play_pitched(SFXManager.SFX.PLAYER_HURT, 0.92, 1.08)
	EventBus.emit(GlobalDefine.EventName.PLAYER_HURT, {"player": self, "damage": damage, "current_health": current_health})
	EventBus.emit(GlobalDefine.EventName.HEALTH_CHANGED, {"target": self, "current_health": current_health, "max_health": max_health})
	if current_health <= 0:
		die()
	else:
		_change_state(GlobalDefine.PlayerState.HURT)

func die() -> void:
	_change_state(GlobalDefine.PlayerState.DEAD)
	EventBus.emit(GlobalDefine.EventName.PLAYER_DIED, {"player": self})
	_on_die()

func heal(amount: int) -> void:
	current_health = mini(current_health + amount, max_health)
	EventBus.emit(GlobalDefine.EventName.HEALTH_CHANGED, {"target": self, "current_health": current_health, "max_health": max_health})

# ---- 输入 ----
# 阶段3: attack/dash/skill 已迁移至 InputManager.game_action 信号驱动
# 以下仅保留 jump（需 is_action_pressed 连续状态）和方向键（需 get_vector 每帧向量）

func _get_input_direction() -> Vector2:
	return Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

func _input_jump_just_pressed() -> bool:
	if InputManager.is_action_blocked(&"player_jump"):
		return false
	return Input.is_action_just_pressed("player_jump")

# ---- 取值器 ----

func _get_move_speed() -> float: return (config.move_speed if config else 300.0) * runtime_move_speed_multiplier
func _get_dash_speed() -> float: return config.dash_speed if config else 800.0
func _get_gravity() -> float: return config.gravity if config else 1200.0

func _get_collision_size() -> Vector2:
	return Vector2(40, 60)

# ---- 虚函数 ----

func _on_ready() -> void: pass
func _on_physics_process(_delta: float) -> void: pass
func _on_attack() -> void: pass
func _on_dash() -> void: pass
func _on_skill() -> void: pass
func _on_die() -> void: pass

# ============================================================
# Enemy_Slime.gd - 史莱姆敌人
# 继承 EnemyBase，实现史莱姆特有的跳跃攻击行为
# ============================================================
extends EnemyBase
class_name Enemy_Slime

var jump_velocity: float = -300.0
var jump_timer: float = 0.0
var is_jumping: bool = false

func _on_ready() -> void:
	super._on_ready()
	if not config:
		config = load("res://DataConfig/Enemy/SlimeConfig.tres") as EnemyConfig
		_apply_config()
	jump_timer = randf_range(1.0, 3.0)

func _on_physics_process(delta: float) -> void:
	super._on_physics_process(delta)
	# 史莱姆跳跃行为
	if is_dead or stun_timer > 0:
		return

	jump_timer -= delta
	if jump_timer <= 0 and is_on_floor() and current_state in [GlobalDefine.EnemyState.IDLE, GlobalDefine.EnemyState.PATROL, GlobalDefine.EnemyState.CHASE]:
		_perform_slime_jump()
		jump_timer = randf_range(2.0, 4.0)

	if is_jumping and is_on_floor():
		is_jumping = false

func _perform_slime_jump() -> void:
	is_jumping = true
	velocity.y = jump_velocity
	if current_state == GlobalDefine.EnemyState.CHASE and target:
		var dir = signf(target.global_position.x - global_position.x)
		velocity.x = dir * 150.0
	else:
		velocity.x = patrol_direction * 100.0

func _on_attack() -> void:
	super._on_attack()
	if not target or not is_instance_valid(target):
		return

	if target.has_method("take_damage"):
		var atk = config.attack_damage if config else 8
		var result = DamageCalculator.calculate(atk, 0, GlobalDefine.DamageType.PHYSICAL)
		var kb_dir = DamageCalculator.get_knockback_direction(global_position, target.global_position)
		target.take_damage(result["damage"], kb_dir)

func _on_die() -> void:
	super._on_die()

func _get_placeholder_color() -> Color:
	return Color(0.3, 0.9, 0.4)  # 绿色史莱姆

func _get_placeholder_size() -> Vector2:
	return Vector2(40, 32)

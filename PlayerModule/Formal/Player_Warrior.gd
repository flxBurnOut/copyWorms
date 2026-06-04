# ============================================================
# Player_Warrior.gd - 战士玩家角色
# 继承 PlayerBase，实现战士特有的攻击和技能逻辑
# ============================================================
extends PlayerBase
class_name Player_Warrior

# AnimatedSprite2D 引用（在编辑器中手动创建和配置动画）
var _anim_sprite: AnimatedSprite2D = null
var _last_anim: String = ""

func _on_ready() -> void:
	super._on_ready()
	if not config:
		config = load("res://DataConfig/Player/WarriorConfig.tres") as PlayerConfig
		_apply_config()
	can_double_jump = true

	# 获取编辑器中的 AnimatedSprite2D（需要在 .tscn 中手动添加并命名为 "Sprite"）
	_anim_sprite = get_node_or_null("Sprite")
	if _anim_sprite:
		_sprite_node = _anim_sprite  # 闪烁效果通过 _sprite_node.visible 控制
		_anim_sprite.play("idle")

func _on_physics_process(delta: float) -> void:
	super._on_physics_process(delta)
	_update_animation()

func _update_animation() -> void:
	if not _anim_sprite:
		return

	var target_anim = "idle"

	match current_state:
		GlobalDefine.PlayerState.RUN:
			target_anim = "run"
		GlobalDefine.PlayerState.JUMP, GlobalDefine.PlayerState.FALL:
			target_anim = "jump"
		GlobalDefine.PlayerState.DASH:
			target_anim = "dash"

	# 只在动画名变化时才切换，避免每帧重复调用 play()
	if target_anim != _last_anim:
		_last_anim = target_anim
		_anim_sprite.play(target_anim)

func _on_attack() -> void:
	super._on_attack()
	if has_hit_this_attack:
		return
	has_hit_this_attack = true

	var facing_dir = 1.0 if is_facing_right else -1.0
	var attack_center = global_position + Vector2(facing_dir * 40, -10)
	var attack_range = config.attack_range if config else 80.0

	for enemy in GameManager.get_enemies():
		if not is_instance_valid(enemy):
			continue
		if attack_center.distance_to(enemy.global_position) <= attack_range:
			var result = DamageCalculator.calculate(
				config.attack_damage if config else 25,
				0,
				GlobalDefine.DamageType.PHYSICAL
			)
			var kb_dir = Vector2(facing_dir, -0.3).normalized()
			if enemy.has_method("take_damage"):
				enemy.take_damage(result["damage"], kb_dir)
			EventBus.emit(GlobalDefine.EventName.PLAYER_ATTACK_HIT, {
				"attacker": self,
				"target": enemy,
				"damage": result["damage"],
				"is_crit": result["is_crit"]
			})
			break

func _on_skill() -> void:
	super._on_skill()
	var skill_config = load("res://DataConfig/Skill/SlashConfig.tres") as SkillConfig
	if not skill_config:
		return

	is_attacking = true
	has_hit_this_attack = false
	attack_timer = 0.4
	attack_cooldown_timer = skill_config.cooldown
	_change_state(GlobalDefine.PlayerState.SKILL)

	var facing_dir = 1.0 if is_facing_right else -1.0
	var attack_center = global_position + Vector2(facing_dir * 40, -10)
	for enemy in GameManager.get_enemies():
		if not is_instance_valid(enemy):
			continue
		if attack_center.distance_to(enemy.global_position) <= skill_config.range_x:
			var result = DamageCalculator.calculate(
				skill_config.damage,
				0,
				skill_config.damage_type,
				0.15
			)
			var kb_dir = Vector2(facing_dir, -0.3).normalized()
			if enemy.has_method("take_damage"):
				enemy.take_damage(result["damage"], kb_dir)
			EventBus.emit(GlobalDefine.EventName.PLAYER_ATTACK_HIT, {
				"attacker": self,
				"target": enemy,
				"damage": result["damage"],
				"is_crit": result["is_crit"]
			})

func _get_placeholder_color() -> Color:
	return Color.TRANSPARENT

func _on_die() -> void:
	super._on_die()
	GameManager.trigger_game_over()

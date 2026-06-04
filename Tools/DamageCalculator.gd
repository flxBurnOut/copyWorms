# ============================================================
# DamageCalculator.gd - 伤害计算工具
# 统一处理所有伤害计算逻辑
# ============================================================
extends RefCounted
class_name DamageCalculator

## 计算最终伤害
## attacker_atk: 攻击者攻击力
## target_def: 目标防御力
## damage_type: 伤害类型
## crit_rate: 暴击率 (0.0 ~ 1.0)
## crit_mult: 暴击倍率
## 返回: { "damage": int, "is_crit": bool }
static func calculate(attacker_atk: int, target_def: int = 0, damage_type: int = GlobalDefine.DamageType.PHYSICAL, crit_rate: float = 0.05, crit_mult: float = 1.5) -> Dictionary:
	var base_damage := float(attacker_atk)
	var final_damage := 0.0

	match damage_type:
		GlobalDefine.DamageType.PHYSICAL:
			final_damage = maxf(base_damage - target_def * 0.5, base_damage * 0.3)
		GlobalDefine.DamageType.MAGIC:
			final_damage = maxf(base_damage - target_def * 0.2, base_damage * 0.5)
		GlobalDefine.DamageType.TRUE_DAMAGE:
			final_damage = base_damage  # 真实伤害无视防御

	var is_crit := randf() < crit_rate
	if is_crit:
		final_damage *= crit_mult

	return {
		"damage": int(maxf(final_damage, 1.0)),
		"is_crit": is_crit
	}

## 计算击退方向
## attacker_pos: 攻击者位置
## target_pos: 目标位置
static func get_knockback_direction(attacker_pos: Vector2, target_pos: Vector2) -> Vector2:
	var dir := (target_pos - attacker_pos).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2(1, 0)
	return dir

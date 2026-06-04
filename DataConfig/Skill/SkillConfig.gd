# ============================================================
# SkillConfig.gd - 技能数值配置资源类
# 在编辑器中创建 .tres 实例，填入具体数值
# ============================================================
extends Resource
class_name SkillConfig

@export_group("基础信息")
@export var skill_name: String = "未命名技能"
@export var skill_id: String = ""
@export var skill_icon: Texture2D = null

@export_group("伤害属性")
@export var damage: int = 30
@export var damage_type: int = 0  # 对应 GlobalDefine.DamageType

@export_group("消耗属性")
@export var mana_cost: int = 20
@export var cooldown: float = 3.0

@export_group("范围属性")
@export var range_x: float = 100.0
@export var range_y: float = 80.0

@export_group("特效属性")
@export var knockback: float = 400.0
@export var stun_duration: float = 0.0

# ============================================================
# EnemyConfig.gd - 敌人数值配置资源类
# 在编辑器中创建 .tres 实例，填入具体数值
# ============================================================
extends Resource
class_name EnemyConfig

@export_group("基础属性")
@export var max_health: int = 50
@export var move_speed: float = 100.0
@export var gravity: float = 1200.0
@export var knockback_resistance: float = 0.3

@export_group("战斗属性")
@export var attack_damage: int = 10
@export var attack_cooldown: float = 1.5
@export var attack_range: float = 40.0
@export var detect_range: float = 300.0

@export_group("行为属性")
@export var patrol_wait_time: float = 2.0
@export var chase_speed_multiplier: float = 1.8
@export var wander_radius: float = 100.0

@export_group("死亡掉落")
@export var exp_reward: int = 10
@export var drop_health_chance: float = 0.2

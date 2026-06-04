# ============================================================
# PlayerConfig.gd - 玩家数值配置资源类
# 在编辑器中创建 .tres 实例，填入具体数值
# ============================================================
extends Resource
class_name PlayerConfig

@export_group("基础属性")
@export var max_health: int = 100
@export var move_speed: float = 300.0
@export var jump_velocity: float = -650.0          # 初始跳跃速度
@export var jump_hold_gravity_scale: float = 0.35  # 长按跳跃时重力倍率（越小跳越高）
@export var jump_release_gravity_scale: float = 2.5 # 松开跳跃时重力倍率（快速下落）
@export var gravity: float = 1200.0

@export_group("战斗属性")
@export var attack_damage: int = 25
@export var attack_cooldown: float = 0.4
@export var attack_range: float = 80.0              # 增大攻击范围
@export var knockback_force: float = 200.0

@export_group("冲刺属性")
@export var dash_speed: float = 800.0
@export var dash_duration: float = 0.2
@export var dash_cooldown: float = 0.8

@export_group("无敌帧")
@export var hurt_invincible_time: float = 1.0
@export var hurt_knockback: float = 300.0

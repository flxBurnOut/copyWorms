# ============================================================
# GlobalDefine.gd - 全局常量与枚举定义
# 后续开发不可修改此文件，如需扩展请在子类中实现
# ============================================================
extends Node

# ---- 运行模式 ----
enum RunMode {
	FORMAL,     # 正式模式
	SELF_TEST   # 自测模式
}

# ---- 玩家状态 ----
enum PlayerState {
	IDLE,
	RUN,
	JUMP,
	FALL,
	DASH,
	ATTACK,
	SKILL,
	HURT,
	DEAD
}

# ---- 敌人状态 ----
enum EnemyState {
	IDLE,
	PATROL,
	CHASE,
	ATTACK,
	HURT,
	DEAD
}

# ---- 伤害类型 ----
enum DamageType {
	PHYSICAL,
	MAGIC,
	TRUE_DAMAGE
}

# ---- 事件名称常量（统一管理，避免拼写错误） ----
class EventName:
	# 玩家事件
	const PLAYER_SPAWNED     := "player_spawned"
	const PLAYER_DIED        := "player_died"
	const PLAYER_HURT        := "player_hurt"
	const PLAYER_ATTACK_HIT  := "player_attack_hit"
	const PLAYER_STATE_CHANGED := "player_state_changed"

	# 敌人事件
	const ENEMY_SPAWNED      := "enemy_spawned"
	const ENEMY_DIED         := "enemy_died"
	const ENEMY_HURT         := "enemy_hurt"
	const ENEMY_DETECTED     := "enemy_detected"

	# 游戏事件
	const GAME_START         := "game_start"
	const GAME_PAUSE         := "game_pause"
	const GAME_RESUME        := "game_resume"
	const GAME_OVER          := "game_over"
	const LEVEL_LOADED       := "level_loaded"
	const LEVEL_COMPLETE     := "level_complete"

	# 伤害事件
	const DAMAGE_APPLIED     := "damage_applied"
	const HEALTH_CHANGED     := "health_changed"

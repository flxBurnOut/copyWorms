# ============================================================
# Player_Warrior_Lingnan.gd - 岭南风皮肤 + 专属技能
# 继承 Player_Warrior，覆盖动画映射字典 + 技能系统
#
# 操作设计:
#   长按普攻 → 突进攻击（独立CD，CD中不影响正常普攻）
#   技能短按 (<0.2s) → 小回旋斩：半径80px，1段伤害
#   技能长按 (>0.6s) → 大回旋斩：半径130px，2段伤害，蓄力超0.6s后霸体
# ============================================================
extends Player_Warrior
class_name Player_Warrior_Lingnan

# ---- 蓄力技能状态 ----
var _is_charging: bool = false
var _charge_time: float = 0.0
const LINGNAN_SKILL_CD := 5.0  # 岭南技能CD
const CHARGE_THRESHOLD_SHORT := 0.2    # 短按判定
const CHARGE_THRESHOLD_BIG := 0.6     # 大回旋斩蓄力阈值
const CHARGE_MAX_TIME := 1.1          # 超过此时间自动释放大回旋斩 (0.6 + 0.5)
const CHARGE_FREEZE_FRAME := 2        # 蓄力期间冻结在 attack 第几帧 (0-indexed)

# ---- 长按普攻：突进攻击（独立CD不影响普攻） ----
var _attack_hold_time: float = 0.0
const ATTACK_HOLD_THRESHOLD := 0.25   # 长按阈值
var _dash_attack_cd_timer: float = 0.0 # 突进独立CD
const DASH_ATTACK_CD := 5.0           # 突进CD（原LINGNAN_SKILL_CD）
const DASH_WINDUP_TIME := 0.2         # 突进前摇蓄力时长
var _dash_windup: bool = false        # 突进蓄力中
var _dash_windup_timer: float = 0.0   # 蓄力计时

# ---- 突进攻击状态 ----
var _is_dashing_attack: bool = false
var _dash_attack_timer: float = 0.0
var _dash_attack_speed: float = 1000.0
var _dash_attack_duration: float = 0.2
var _dash_attack_dir: float = 1.0
var _dash_attack_start_pos: Vector2 = Vector2.ZERO
var _dash_attack_hit_enemies: Array = []
var _afterimage_cooldown: float = 0.0
var _dash_was_invincible: bool = false  # 记录突进前无敌状态

# ---- 回旋斩状态 ----
var _is_spinning: bool = false
var _spin_timer: float = 0.0
var _spin_hit_count: int = 0          # 已命中段数
var _spin_max_hits: int = 1           # 总段数（小=1，大=2）
var _spin_range: float = 80.0
var _spin_damage: int = 20
var _spin_hit_enemies: Array = []     # 每段独立防重复

# ---- 蓄力减伤 + 吸附 ----
const CHARGE_DAMAGE_REDUCTION: float = 0.5   # 蓄力期间受伤减半
const SUCK_RANGE: float = 500.0              # 吸附范围
const SUCK_FORCE: float = 800.0              # 吸附力

func _on_ready():
	super._on_ready()
	_anim_map = {
		GlobalDefine.PlayerState.IDLE:    "idle",
		GlobalDefine.PlayerState.RUN:     "walk",
		GlobalDefine.PlayerState.JUMP:    "jump",
		GlobalDefine.PlayerState.FALL:    "jump",
		GlobalDefine.PlayerState.DASH:    "idle",
		GlobalDefine.PlayerState.ATTACK:  "attack",
		GlobalDefine.PlayerState.SKILL:   "attack",
		GlobalDefine.PlayerState.HURT:    "hit",
		GlobalDefine.PlayerState.DEAD:    "defeated",
	}
	# 岭南皮肤有专属 hit / defeated / attack_in_air 动画
	_has_hit_anim = true
	_has_defeated_anim = true

func _on_physics_process(delta: float) -> void:
	super._on_physics_process(delta)

	# 突进CD递减
	if _dash_attack_cd_timer > 0:
		_dash_attack_cd_timer -= delta

	# 长按普攻检测：按下时计时，超过阈值触发突进蓄力
	if can_attack_hold_dash and not _is_charging and not _is_dashing_attack and not _is_spinning and not _dash_windup and not is_attacking and not is_dashing:
		if Input.is_action_pressed("player_attack") and _dash_attack_cd_timer <= 0:
			_attack_hold_time += delta
			if _attack_hold_time >= ATTACK_HOLD_THRESHOLD:
				_attack_hold_time = 0.0
				_start_dash_windup()
		else:
			_attack_hold_time = 0.0
	else:
		_attack_hold_time = 0.0

	# 突进蓄力帧逻辑：最少蓄力 DASH_WINDUP_TIME，之后由玩家松开普攻键释放
	if _dash_windup:
		_dash_windup_timer -= delta
		# 蓄力视觉：震动效果（随蓄力时长增强）
		if _anim_sprite:
			var charge_ratio = clampf(1.0 - _dash_windup_timer / DASH_WINDUP_TIME, 0.0, 1.0)
			var shake_amp = 1.0 + charge_ratio * 3.0
			var shake_x = sin(_dash_windup_timer * 40.0) * shake_amp
			var shake_y = cos(_dash_windup_timer * 52.0) * shake_amp * 0.6
			_anim_sprite.position = Vector2(shake_x, shake_y)
		# 冻结 attack 动画在第3帧
		if _anim_sprite and _anim_sprite.sprite_frames:
			if _anim_sprite.sprite_frames.has_animation("attack"):
				if _anim_sprite.animation != "attack":
					_anim_sprite.play("attack")
				var max_frame = _anim_sprite.sprite_frames.get_frame_count("attack") - 1
				_anim_sprite.frame = mini(CHARGE_FREEZE_FRAME, max(0, max_frame))
				_anim_sprite.pause()
		# 蓄力期间减速
		velocity.x = move_toward(velocity.x, 0, 600.0)
		# 最少蓄力时间过后，玩家松开普攻键 → 突进
		if _dash_windup_timer <= 0:
			if not Input.is_action_pressed("player_attack"):
				_dash_windup = false
				if _anim_sprite:
					_anim_sprite.position = Vector2.ZERO
				_do_dash_attack()
			# 否则继续蓄力，等待玩家释放
		return

	# 蓄力帧逻辑
	if _is_charging:
		_charge_time += delta
		# 蓄力超阈值后进入霸体
		if _charge_time >= CHARGE_THRESHOLD_BIG:
			_is_super_armor = true
		# 冻结 attack 动画在第3帧
		if _anim_sprite and _anim_sprite.animation == "attack":
			var max_frame = _anim_sprite.sprite_frames.get_frame_count("attack") - 1 if _anim_sprite.sprite_frames else 0
			_anim_sprite.frame = mini(CHARGE_FREEZE_FRAME, max(0, max_frame))
			_anim_sprite.pause()
		# 蓄力视觉：震动效果，强度随时间增强
		if _anim_sprite:
			var intensity = clampf(_charge_time / CHARGE_MAX_TIME, 0.0, 1.0)
			var shake_amp = 1.0 + intensity * 4.0  # 1~5px
			var shake_freq = 15.0 + intensity * 25.0  # 频率也加快
			var shake_x = sin(_charge_time * shake_freq) * shake_amp
			var shake_y = cos(_charge_time * shake_freq * 1.3) * shake_amp * 0.6
			_anim_sprite.position = Vector2(shake_x, shake_y)
		# 蓄力临界点闪白（小/大回旋斩分界）
		if _charge_time >= CHARGE_THRESHOLD_BIG and _charge_time - delta < CHARGE_THRESHOLD_BIG:
			if _anim_sprite:
				_anim_sprite.modulate = Color(2, 2, 2, 1)
		if _anim_sprite and _anim_sprite.modulate != Color.WHITE:
			_anim_sprite.modulate = _anim_sprite.modulate.lerp(Color.WHITE, delta * 10)

		# 蓄力期间吸附周围敌人
		_suck_enemies(delta)

		# 超过最大蓄力时间自动释放大回旋斩
		if _charge_time >= CHARGE_MAX_TIME:
			_release_skill()
			return
		# 检测松开：直接轮询 Input
		if not Input.is_action_pressed("player_skill"):
			_release_skill()
		return

	# 突进攻击帧逻辑
	if _is_dashing_attack:
		_dash_attack_timer -= delta
		_afterimage_cooldown -= delta
		velocity.x = _dash_attack_dir * _dash_attack_speed
		velocity.y = 0
		# 残影效果（节流：每0.06s一个）
		if _afterimage_cooldown <= 0:
			_spawn_afterimage()
			_afterimage_cooldown = 0.06
		if _dash_attack_timer <= 0:
			_end_dash_attack()
		return

	# 回旋斩帧逻辑
	if _is_spinning:
		_spin_timer -= delta
		# 旋转视觉：角色微缩放弹跳
		if _anim_sprite:
			var bounce = 1.0 + sin(_spin_timer * 30.0) * 0.05
			_anim_sprite.scale = Vector2(bounce, bounce)
		# 两段判定间隔
		if _spin_max_hits == 2 and _spin_hit_count == 1 and _spin_timer <= 0.1:
			_do_spin_hit()
		if _spin_timer <= 0:
			_end_spin()
		return

# ---- 技能：开始蓄力 ----
func _on_skill() -> void:
	# 不调用 super，完全覆盖
	_is_charging = true
	_charge_time = 0.0
	attack_cooldown_timer = 0.0  # 不占用普攻CD
	# 技能CD在释放时才开始
	_change_state(GlobalDefine.PlayerState.SKILL)
	# 减速，蓄力中缓慢移动
	velocity.x = move_toward(velocity.x, 0, 600.0)
	# 播放 attack 动画并冻结在第3帧
	if _anim_sprite and _anim_sprite.sprite_frames:
		if _anim_sprite.sprite_frames.has_animation("attack"):
			_anim_sprite.play("attack")
			_anim_sprite.frame = CHARGE_FREEZE_FRAME
			_anim_sprite.pause()

# ---- 技能：松开释放 ----
func _release_skill() -> void:
	_is_charging = false
	_is_super_armor = false
	if _anim_sprite:
		_anim_sprite.scale = Vector2.ONE
		_anim_sprite.modulate = Color.WHITE
		_anim_sprite.position = Vector2.ZERO  # 恢复震动偏移
	# 释放时才开始技能CD
	_skill_cooldown_timer = LINGNAN_SKILL_CD

	if _charge_time < CHARGE_THRESHOLD_SHORT:
		# 短按 → 小回旋斩
		_do_spin_slash(false)
	elif _charge_time < CHARGE_THRESHOLD_BIG:
		# 短蓄力 → 小回旋斩
		_do_spin_slash(false)
	else:
		# 长蓄力 → 大回旋斩
		_do_spin_slash(true)

# ---- 突进蓄力 ----

func _start_dash_windup() -> void:
	_dash_windup = true
	_dash_windup_timer = DASH_WINDUP_TIME
	_change_state(GlobalDefine.PlayerState.ATTACK)

# ---- 突进攻击（长按普攻触发） ----
func _do_dash_attack() -> void:
	_is_dashing_attack = true
	_dash_attack_timer = _dash_attack_duration
	_dash_attack_dir = 1.0 if is_facing_right else -1.0
	_dash_attack_start_pos = global_position
	_dash_attack_hit_enemies.clear()
	_dash_attack_cd_timer = DASH_ATTACK_CD  # 突进独立CD
	is_attacking = true
	attack_timer = _dash_attack_duration + 0.1
	# 突进期间无敌
	_dash_was_invincible = is_invincible
	is_invincible = true
	invincible_timer = _dash_attack_duration + 0.1 + 0.3
	_change_state(GlobalDefine.PlayerState.ATTACK)

func _end_dash_attack() -> void:
	_is_dashing_attack = false
	# 结束无敌，恢复可见性
	if not _dash_was_invincible:
		is_invincible = false
		_restore_visibility()
	# 对路径上敌人做最终判定（线性距离检测）
	var end_pos = global_position
	for enemy in GameManager.get_enemies():
		if not is_instance_valid(enemy):
			continue
		var eid = enemy.get_instance_id()
		if eid in _dash_attack_hit_enemies:
			continue
		# 点到线段距离检测
		var dist = _point_to_segment_dist(enemy.global_position, _dash_attack_start_pos, end_pos)
		if dist <= 50.0:
			_deal_dash_damage(enemy)
	# 震屏
	var cam = get_node_or_null("SmoothCamera")
	if cam and cam.has_method("shake"):
		cam.shake(4.0, 0.1)

func _deal_dash_damage(enemy: Node2D) -> void:
	_dash_attack_hit_enemies.append(enemy.get_instance_id())
	var result = DamageCalculator.calculate(25, 0, GlobalDefine.DamageType.PHYSICAL, 0.1)
	var kb_dir = Vector2(_dash_attack_dir, -0.3).normalized()
	if enemy.has_method("take_damage"):
		enemy.take_damage(result["damage"], kb_dir)
	EventBus.emit(GlobalDefine.EventName.PLAYER_ATTACK_HIT, {"attacker": self, "target": enemy, "damage": result["damage"], "is_crit": result["is_crit"]})

## 点到线段距离
func _point_to_segment_dist(point: Vector2, seg_a: Vector2, seg_b: Vector2) -> float:
	var ab = seg_b - seg_a
	if ab.dot(ab) < 0.01:
		return point.distance_to(seg_a)
	var ap = point - seg_a
	var t = clampf(ap.dot(ab) / ab.dot(ab), 0.0, 1.0)
	var closest = seg_a + ab * t
	return point.distance_to(closest)

## 突进残影
func _spawn_afterimage() -> void:
	if not _sprite_node:
		return
	var parent = get_parent()
	if not parent:
		return
	var ghost = ColorRect.new()
	ghost.size = _get_placeholder_size()
	ghost.position = parent.to_local(global_position) - ghost.size / 2 + Vector2(0, -10)
	ghost.color = Color(0.9, 0.85, 0.6, 0.4)
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.z_index = -1
	if parent:
		parent.add_child(ghost)
		var tween = ghost.create_tween()
		tween.tween_property(ghost, "color:a", 0.0, 0.2)
		tween.tween_callback(ghost.queue_free)

# ---- 回旋斩 ----
func _do_spin_slash(is_big: bool) -> void:
	_is_spinning = true
	_spin_hit_count = 0
	_spin_hit_enemies.clear()
	is_attacking = true

	if is_big:
		_spin_timer = 0.3
		_spin_max_hits = 2
		_spin_range = 160.0
		_spin_damage = 15
	else:
		_spin_timer = 0.2
		_spin_max_hits = 1
		_spin_range = 100.0
		_spin_damage = 20

	attack_timer = _spin_timer + 0.05
	_change_state(GlobalDefine.PlayerState.SKILL)

	# 第一段立即判定
	_do_spin_hit()

	# 生成环形刀光视觉
	_spawn_ring_slash_effect(is_big)

	# 震屏
	var cam = get_node_or_null("SmoothCamera")
	if cam and cam.has_method("shake"):
		cam.shake(5.0 if is_big else 3.0, 0.15)

func _do_spin_hit() -> void:
	if _spin_hit_count >= _spin_max_hits:
		return
	_spin_hit_enemies.clear()
	for enemy in GameManager.get_enemies():
		if not is_instance_valid(enemy):
			continue
		if global_position.distance_to(enemy.global_position) <= _spin_range:
			var kb_dir = (enemy.global_position - global_position).normalized()
			if kb_dir == Vector2.ZERO:
				kb_dir = Vector2(1 if is_facing_right else -1, 0)
			var result = DamageCalculator.calculate(_spin_damage, 0, GlobalDefine.DamageType.PHYSICAL, 0.1)
			if enemy.has_method("take_damage"):
				enemy.take_damage(result["damage"], kb_dir)
			EventBus.emit(GlobalDefine.EventName.PLAYER_ATTACK_HIT, {"attacker": self, "target": enemy, "damage": result["damage"], "is_crit": result["is_crit"]})
	_spin_hit_count += 1
	# 大回旋斩第二段再生成刀光
	if _spin_hit_count == 2:
		_spawn_ring_slash_effect(true)

func _end_spin() -> void:
	_is_spinning = false
	_is_super_armor = false
	if _anim_sprite:
		_anim_sprite.scale = Vector2.ONE

## 生成环形刀光视觉（复用 SlashEffect 刀光贴图，旋转360°）
func _spawn_ring_slash_effect(is_big: bool) -> void:
	var parent = get_parent()
	if not parent:
		return
	# 多个刀光围绕玩家呈环形
	var count = 6 if is_big else 4
	for i in range(count):
		var angle = (TAU * i / count) + randf_range(-0.2, 0.2)
		var dist = _spin_range * 0.7
		var fx := Sprite2D.new()
		fx.set_script(load("res://Tools/SlashEffect.gd"))
		fx.global_position = global_position + Vector2(cos(angle), sin(angle)) * dist + Vector2(0, -8)
		fx.rotation = angle + TAU / 4  # 刀光切线方向
		if is_big:
			fx.set_meta("size_multiplier", 1.3)
		parent.add_child(fx)

# ---- 覆盖：蓄力期间冻结动画 ----
func _update_animation() -> void:
	if _is_charging or _dash_windup:
		return  # 蓄力期间不更新动画
	super._update_animation()
func _handle_attack_state(delta: float) -> void:
	if _is_dashing_attack or _is_spinning or _dash_windup:
		# 突进/回旋斩/蓄力有自己的速度控制，不做通用攻击减速
		return
	super._handle_attack_state(delta)

# ---- 覆盖：防止蓄力中被其他操作取消 ----
func _on_game_action(action: StringName, _event: InputEvent) -> void:
	if _is_charging or _is_dashing_attack or _is_spinning or _dash_windup:
		return  # 技能执行中不接受其他操作
	super._on_game_action(action, _event)

# ---- 蓄力期间减伤 ----

func take_damage(damage: int, knockback_dir: Vector2 = Vector2.ZERO) -> void:
	# 蓄力期间减伤50%
	if _is_charging:
		damage = max(1, int(round(damage * CHARGE_DAMAGE_REDUCTION)))
	super.take_damage(damage, knockback_dir)

# ---- 蓄力期间吸附周围敌人 ----

func _suck_enemies(delta: float) -> void:
	for enemy in GameManager.get_enemies():
		if not is_instance_valid(enemy):
			continue
		var dist = global_position.distance_to(enemy.global_position)
		if dist < SUCK_RANGE and dist > 10.0:
			var suck_dir = (global_position - enemy.global_position).normalized()
			# 吸附力随距离衰减（越近吸力越小，避免抖动）
			var strength = SUCK_FORCE * clampf(1.0 - dist / SUCK_RANGE, 0.2, 1.0)
			enemy.velocity.x = move_toward(enemy.velocity.x, suck_dir.x * strength, strength * delta * 10.0)
			enemy.velocity.y = move_toward(enemy.velocity.y, suck_dir.y * strength * 0.5, strength * delta * 5.0)

# ---- 死亡时清理技能状态 ----
func _on_die() -> void:
	_is_charging = false
	_is_dashing_attack = false
	_is_spinning = false
	_dash_windup = false
	_attack_hold_time = 0.0
	_is_super_armor = false
	if _anim_sprite:
		_anim_sprite.scale = Vector2.ONE
		_anim_sprite.modulate = Color.WHITE
		_anim_sprite.position = Vector2.ZERO
	super._on_die()

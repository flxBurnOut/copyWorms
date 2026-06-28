extends Player_Warrior
class_name Player_Warrior_Cyber

var _hit_pending: bool = false

# ---- 长按普攻：闪电突进（原技能突进逻辑，独立CD不影响普攻） ----
var _attack_hold_time: float = 0.0
const ATTACK_HOLD_THRESHOLD := 0.25   # 长按阈值
var _dash_cd_timer: float = 0.0        # 突进独立CD（不影响普攻）
const DASH_CD := 4.0                   # 突进CD（原CYBER_SKILL_CD）
const DASH_WINDUP_TIME := 0.2          # 突进前摇蓄力时长
var _dash_windup: bool = false         # 突进蓄力中
var _dash_windup_timer: float = 0.0    # 蓄力计时

# ---- 技能蓄力（I键）：短按1发，0.2-0.5s蓄力3发，超0.5s蓄力5发 ----
var _skill_charging: bool = false
var _skill_charge_time: float = 0.0
const SKILL_CHARGE_TIER1 := 0.2   # 3发阈值
const SKILL_CHARGE_TIER2 := 0.5   # 5发阈值

# ---- 闪电突进状态 ----
var _is_lightning_dash: bool = false
var _dash_timer: float = 0.0
var _dash_dir: float = 1.0
var _dash_speed: float = 1200.0
var _dash_duration: float = 0.25
var _dash_start_pos: Vector2 = Vector2.ZERO
var _dash_hit_enemies: Array = []
var _lightning_cooldown: float = 0.0
var _was_invincible: bool = false

func _on_ready():
	super._on_ready()
	_anim_map = {
		GlobalDefine.PlayerState.IDLE:   "idle",
		GlobalDefine.PlayerState.RUN:    "walk",
		GlobalDefine.PlayerState.JUMP:   "jump",
		GlobalDefine.PlayerState.FALL:   "jump",
		GlobalDefine.PlayerState.DASH:   "idle",
		GlobalDefine.PlayerState.ATTACK: "attack",
		GlobalDefine.PlayerState.SKILL:  "attack",
		GlobalDefine.PlayerState.HURT:   "hit",
		GlobalDefine.PlayerState.DEAD:   "defeated",
	}
	_has_hit_anim = true
	_has_defeated_anim = true

func _on_attack() -> void:
	_hit_pending = true
	get_tree().create_timer(0.1).timeout.connect(_do_delayed_hit)

func _do_delayed_hit() -> void:
	if not _hit_pending:
		return
	_hit_pending = false
	if not is_attacking or has_hit_this_attack:
		return
	has_hit_this_attack = true

	var attack_dir := _get_attack_direction()
	var attack_center = global_position + attack_dir * 40
	var attack_range = config.attack_range if config else 80.0

	for enemy in GameManager.get_enemies():
		if not is_instance_valid(enemy):
			continue
		if attack_center.distance_to(enemy.global_position) <= attack_range:
			var result = DamageCalculator.calculate(
				config.attack_damage if config else 25, 0, GlobalDefine.DamageType.PHYSICAL
			)
			var kb_dir = attack_dir.normalized() if attack_dir != Vector2.ZERO else Vector2(1, 0)
			if enemy.has_method("take_damage"):
				enemy.take_damage(result["damage"], kb_dir)
			EventBus.emit(GlobalDefine.EventName.PLAYER_ATTACK_HIT, {
				"attacker": self, "target": enemy, "damage": result["damage"], "is_crit": result["is_crit"]
			})
			break

# ---- 长按普攻：闪电突进 ----

func _on_physics_process(delta: float) -> void:
	super._on_physics_process(delta)

	# 技能蓄力检测：按住 I 键蓄力，松开按蓄力时长决定子弹数
	if _skill_charging:
		_skill_charge_time += delta
		# 蓄力视觉：角色微闪烁，强度随蓄力时间增强
		if _anim_sprite:
			var intensity = clampf(_skill_charge_time / SKILL_CHARGE_TIER2, 0.0, 1.0)
			var blink = 0.8 + 0.2 * abs(sin(_skill_charge_time * 25.0))
			_anim_sprite.modulate = Color(blink, blink, 1.0 + 0.3 * intensity, 1.0)
		# 松开释放
		if not Input.is_action_pressed("player_skill"):
			_release_skill()
		return

	# 突进CD递减
	if _dash_cd_timer > 0:
		_dash_cd_timer -= delta

	# 长按普攻检测：按下时计时，超过阈值触发突进蓄力
	if can_attack_hold_dash and not _is_lightning_dash and not _dash_windup and not is_attacking and not is_dashing:
		if Input.is_action_pressed("player_attack") and _dash_cd_timer <= 0:
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
		# 蓄力视觉：角色微闪烁（随蓄力时长增强）
		if _anim_sprite:
			var charge_ratio = clampf(1.0 - _dash_windup_timer / DASH_WINDUP_TIME, 0.0, 1.0)
			var blink = 0.7 + 0.3 * abs(sin(_dash_windup_timer * 30.0))
			_anim_sprite.modulate = Color(blink, blink, 1.2 + 0.3 * charge_ratio, 1.0)
		# 冻结 attack 动画在第2帧
		if _anim_sprite and _anim_sprite.sprite_frames:
			if _anim_sprite.sprite_frames.has_animation("attack"):
				if _anim_sprite.animation != "attack":
					_anim_sprite.play("attack")
				var max_frame = _anim_sprite.sprite_frames.get_frame_count("attack") - 1
				_anim_sprite.frame = mini(2, max(0, max_frame))
				_anim_sprite.pause()
		# 蓄力期间减速
		velocity.x = move_toward(velocity.x, 0, 600.0)
		# 最少蓄力时间过后，玩家松开普攻键 → 突进
		if _dash_windup_timer <= 0:
			if not Input.is_action_pressed("player_attack"):
				_dash_windup = false
				if _anim_sprite:
					_anim_sprite.modulate = Color.WHITE
				_do_lightning_dash()
			# 否则继续蓄力，等待玩家释放
		return

	# 闪电突进帧逻辑
	if _is_lightning_dash:
		_dash_timer -= delta
		_lightning_cooldown -= delta
		velocity.x = _dash_dir * _dash_speed
		velocity.y = 0
		# 闪电特效（节流：每0.04s一道）
		if _lightning_cooldown <= 0:
			_spawn_lightning_bolt()
			_lightning_cooldown = 0.04
		# 突进中持续检测路径上敌人
		_check_dash_hit()
		if _dash_timer <= 0:
			_end_lightning_dash()
		return

# ---- 技能（I键）：蓄力释放远程剑气 ----

func _on_skill() -> void:
	# 开始蓄力，由玩家选择释放时机（松开I键释放）
	_skill_charging = true
	_skill_charge_time = 0.0
	attack_cooldown_timer = 0.0
	# 技能CD在释放时才开始
	_change_state(GlobalDefine.PlayerState.SKILL)
	# 减速蓄力
	velocity.x = move_toward(velocity.x, 0, 600.0)

func _release_skill() -> void:
	_skill_charging = false
	if _anim_sprite:
		_anim_sprite.modulate = Color.WHITE
	# 释放时才开始技能CD
	_skill_cooldown_timer = CYBER_SKILL_CD
	# 根据蓄力时长决定子弹数
	var count: int
	if _skill_charge_time < SKILL_CHARGE_TIER1:
		count = 1
	elif _skill_charge_time < SKILL_CHARGE_TIER2:
		count = 3
	else:
		count = 5
	is_attacking = true
	has_hit_this_attack = false
	attack_timer = 0.6
	# 连发剑气弹体（散射+追踪Boss）
	var facing_dir := 1.0 if is_facing_right else -1.0
	# Boss战时散射中心朝向Boss，否则朝面向方向
	var base_dir = Vector2(facing_dir, 0)
	if GameManager.boss_target and is_instance_valid(GameManager.boss_target):
		var to_boss = GameManager.boss_target.global_position - global_position
		if to_boss.length() > 10:
			base_dir = to_boss.normalized()
	var projectile_script = load("res://Tools/SwordQiProjectile.gd")
	var parent = get_parent()
	for i in range(count):
		var projectile = Area2D.new()
		projectile.set_script(projectile_script)
		if parent:
			parent.add_child(projectile)
			# 扇形散布，散射后追踪Boss
			var spread_angle = deg_to_rad(-30 + i * (60.0 / max(count - 1, 1))) if count > 1 else 0.0
			var dir = base_dir.rotated(spread_angle)
			projectile.global_position = global_position + Vector2(facing_dir * 25, -10) + Vector2(0, (i - (count - 1) / 2.0) * 8)
			projectile.setup_homing(dir, 20 - 1, self, 600.0, true)
	# 扇形电弧视觉
	_spawn_arc_effect(Vector2(facing_dir, -0.2).normalized(), facing_dir)
	# 震屏
	var cam = get_node_or_null("SmoothCamera")
	if cam and cam.has_method("shake"):
		cam.shake(6.0, 0.15)

const CYBER_SKILL_CD := 4.0  # 技能CD（保持不变）

# ---- 突进蓄力 ----

func _start_dash_windup() -> void:
	_dash_windup = true
	_dash_windup_timer = DASH_WINDUP_TIME
	_change_state(GlobalDefine.PlayerState.ATTACK)

# ---- 闪电突进 ----

func _do_lightning_dash() -> void:
	_is_lightning_dash = true
	_dash_timer = _dash_duration
	_dash_dir = 1.0 if is_facing_right else -1.0
	_dash_start_pos = global_position
	_dash_hit_enemies.clear()
	_lightning_cooldown = 0.0
	_dash_cd_timer = DASH_CD  # 突进独立CD
	is_attacking = true
	attack_timer = _dash_duration + 0.1
	# 全程无敌
	_was_invincible = is_invincible
	is_invincible = true
	invincible_timer = _dash_duration + 0.1 + 0.3
	_change_state(GlobalDefine.PlayerState.ATTACK)
	# 起手闪电爆发
	_spawn_lightning_burst()

func _end_lightning_dash() -> void:
	_is_lightning_dash = false
	# 恢复无敌状态
	if not _was_invincible:
		is_invincible = false
		_restore_visibility()
	# 终点再检测一次路径敌人
	var end_pos = global_position
	for enemy in GameManager.get_enemies():
		if not is_instance_valid(enemy):
			continue
		var eid = enemy.get_instance_id()
		if eid in _dash_hit_enemies:
			continue
		var dist = _point_to_segment_dist(enemy.global_position, _dash_start_pos, end_pos)
		if dist <= 55.0:
			_deal_dash_damage(enemy)
	# 终点闪电爆发
	_spawn_lightning_burst()
	# 震屏
	var cam = get_node_or_null("SmoothCamera")
	if cam and cam.has_method("shake"):
		cam.shake(5.0, 0.12)

func _check_dash_hit() -> void:
	for enemy in GameManager.get_enemies():
		if not is_instance_valid(enemy):
			continue
		var eid = enemy.get_instance_id()
		if eid in _dash_hit_enemies:
			continue
		if global_position.distance_to(enemy.global_position) <= 50.0:
			_deal_dash_damage(enemy)

func _deal_dash_damage(enemy: Node2D) -> void:
	_dash_hit_enemies.append(enemy.get_instance_id())
	var result = DamageCalculator.calculate(30, 0, GlobalDefine.DamageType.MAGIC, 0.15)
	var kb_dir = Vector2(_dash_dir, -0.3).normalized()
	if enemy.has_method("take_damage"):
		enemy.take_damage(result["damage"], kb_dir)
	EventBus.emit(GlobalDefine.EventName.PLAYER_ATTACK_HIT, {
		"attacker": self, "target": enemy, "damage": result["damage"], "is_crit": result["is_crit"]
	})

## 点到线段距离
func _point_to_segment_dist(point: Vector2, seg_a: Vector2, seg_b: Vector2) -> float:
	var ab = seg_b - seg_a
	if ab.dot(ab) < 0.01:
		return point.distance_to(seg_a)
	var ap = point - seg_a
	var t = clampf(ap.dot(ab) / ab.dot(ab), 0.0, 1.0)
	var closest = seg_a + ab * t
	return point.distance_to(closest)

# ---- 闪电视觉特效 ----

## 突进路径闪电（纵向短折线）
func _spawn_lightning_bolt() -> void:
	var parent = get_parent()
	if not parent:
		return
	var line = Line2D.new()
	line.width = 2.5
	line.default_color = Color(0.3, 0.6, 1.0, 0.9)
	line.z_index = 9
	var start = global_position + Vector2(0, -5)
	var points = [parent.to_local(start)]
	var pos = start
	var seg_count = 3 + randi_range(0, 2)
	for i in range(seg_count):
		var seg_len = 8.0 + randf() * 6.0
		var jitter_x = randf_range(-12.0, 12.0)
		pos += Vector2(jitter_x, seg_len)
		points.append(parent.to_local(pos))
	for pt in points:
		line.add_point(pt)
	parent.add_child(line)
	# 闪电淡出
	var tween = line.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.2)
	tween.tween_callback(line.queue_free)

## 起手/终点闪电爆发（放射状折线）
func _spawn_lightning_burst() -> void:
	var parent = get_parent()
	if not parent:
		return
	for i in range(5):
		var angle = TAU * i / 5.0 + randf_range(-0.3, 0.3)
		var arc_dir = Vector2.from_angle(angle)
		var line = Line2D.new()
		line.width = 2.0
		line.default_color = Color(0.5, 0.8, 1.0, 0.85)
		line.z_index = 9
		var start = global_position + Vector2(0, -10)
		var points = [parent.to_local(start)]
		var pos = start
		var seg_count = 3 + randi_range(0, 2)
		for j in range(seg_count):
			var seg_len = 15.0 + randf() * 10.0
			var jitter = randf_range(-0.3, 0.3)
			pos += arc_dir * seg_len + Vector2(jitter * 15, randf_range(-8, 8))
			points.append(parent.to_local(pos))
		for pt in points:
			line.add_point(pt)
		parent.add_child(line)
		var tween = line.create_tween()
		tween.tween_property(line, "modulate:a", 0.0, 0.25)
		tween.tween_callback(line.queue_free)

# ---- 扇形电弧视觉（技能用） ----

func _spawn_arc_effect(attack_dir: Vector2, facing_dir: float) -> void:
	var parent = get_parent()
	if not parent:
		return
	for i in range(3):
		var arc_angle = attack_dir.angle() + deg_to_rad(-40 + i * 40) + randf_range(-0.1, 0.1)
		var arc_dir = Vector2.from_angle(arc_angle)
		var line = Line2D.new()
		line.width = 2.0
		line.default_color = Color(0.4, 0.7, 1.0, 0.9)
		line.z_index = 9
		var start = global_position + Vector2(facing_dir * 15, -10)
		var points = [start]
		var pos = start
		var seg_count = 5 + randi_range(0, 3)
		for j in range(seg_count):
			var seg_len = 20.0 + randf() * 15.0
			var jitter = randf_range(-0.3, 0.3)
			pos += arc_dir * seg_len + Vector2(jitter * 20, randf_range(-10, 10))
			points.append(pos)
		for pt in points:
			line.add_point(parent.to_local(pt))
		parent.add_child(line)
		var tween = line.create_tween()
		tween.tween_property(line, "modulate:a", 0.0, 0.3)
		tween.tween_callback(line.queue_free)

# ---- 覆盖：突进期间不更新动画 ----

func _update_animation() -> void:
	if _is_lightning_dash or _dash_windup or _skill_charging:
		return  # 突进/蓄力有自己的动画控制
	super._update_animation()

func _handle_attack_state(delta: float) -> void:
	if _is_lightning_dash or _dash_windup or _skill_charging:
		return  # 突进/蓄力有自己的速度控制
	super._handle_attack_state(delta)

# ---- 覆盖：突进/蓄力中不接受其他操作 ----

func _on_game_action(action: StringName, _event: InputEvent) -> void:
	if _is_lightning_dash or _dash_windup or _skill_charging:
		return
	super._on_game_action(action, _event)

# ---- 死亡时清理状态 ----

func _on_die() -> void:
	_is_lightning_dash = false
	_dash_windup = false
	_skill_charging = false
	_skill_charge_time = 0.0
	_attack_hold_time = 0.0
	if _anim_sprite:
		_anim_sprite.modulate = Color.WHITE
		_anim_sprite.position = Vector2.ZERO
	super._on_die()

# ============================================================
# HUD.gd - 游戏抬头显示（纯代码构建UI）
# 显示血条、状态、返回主界面按钮
# ============================================================
extends CanvasLayer

var health_bar: ColorRect          # 血条填充（改为ColorRect）
var health_label: Label
var health_bar_max_width: float = 280.0
var state_label: Label
var mode_label: Label
var pause_panel: Panel
var game_over_panel: Panel

func _ready() -> void:
	_build_ui()
	_connect_events()
	_update_mode_label()

func _build_ui() -> void:
	# === 左上角：血条容器 ===
	var bar_container = Control.new()
	bar_container.name = "HealthBarContainer"
	bar_container.position = Vector2(20, 20)
	bar_container.size = Vector2(280, 36)
	add_child(bar_container)

	# 背景
	var bar_bg = ColorRect.new()
	bar_bg.name = "BarBackground"
	bar_bg.size = Vector2(280, 36)
	bar_bg.color = Color(0.15, 0.15, 0.15, 0.9)
	bar_container.add_child(bar_bg)

	# 填充条（用 ColorRect 手动控制宽度）
	var bar_fill = ColorRect.new()
	bar_fill.name = "BarFill"
	bar_fill.size = Vector2(280, 36)
	bar_fill.color = Color(0.85, 0.15, 0.15, 0.95)
	bar_container.add_child(bar_fill)
	health_bar = bar_fill  # 赋值给变量，后续更新用

	# 文字标签（直接放在容器上，不在 ProgressBar 内）
	health_label = Label.new()
	health_label.name = "HealthLabel"
	health_label.size = Vector2(280, 36)
	health_label.position = Vector2(0, 0)
	health_label.text = "100 / 100"
	health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	health_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	health_label.add_theme_font_size_override("font_size", 16)
	health_label.add_theme_color_override("font_color", Color.WHITE)
	bar_container.add_child(health_label)

	# 把 health_bar 变量重新指向 bar_fill 用于后续更新
	health_bar = bar_fill

	# === 状态文字 ===
	state_label = Label.new()
	state_label.name = "StateLabel"
	state_label.position = Vector2(20, 62)
	state_label.text = "待机"
	state_label.add_theme_font_size_override("font_size", 14)
	state_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	add_child(state_label)

	# === 模式标签 ===
	mode_label = Label.new()
	mode_label.name = "ModeLabel"
	mode_label.position = Vector2(20, 82)
	mode_label.text = "[模式]"
	mode_label.add_theme_font_size_override("font_size", 12)
	mode_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	add_child(mode_label)

	# === 返回主界面按钮（右上角） ===
	var back_btn = Button.new()
	back_btn.name = "BackButton"
	back_btn.text = "返回主界面"
	back_btn.position = Vector2(1120, 20)
	back_btn.size = Vector2(140, 36)
	back_btn.add_theme_font_size_override("font_size", 14)
	back_btn.pressed.connect(_on_back_pressed)
	add_child(back_btn)

	# === 暂停面板 ===
	pause_panel = Panel.new()
	pause_panel.name = "PausePanel"
	pause_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.hide()
	var pause_style = StyleBoxFlat.new()
	pause_style.bg_color = Color(0, 0, 0, 0.6)
	pause_panel.add_theme_stylebox_override("panel", pause_style)
	add_child(pause_panel)

	var pause_label = Label.new()
	pause_label.text = "游戏已暂停"
	pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_label.add_theme_font_size_override("font_size", 28)
	pause_label.add_theme_color_override("font_color", Color.WHITE)
	pause_label.position = Vector2(440, 270)
	pause_label.size = Vector2(400, 50)
	pause_panel.add_child(pause_label)

	var resume_btn = Button.new()
	resume_btn.text = "继续游戏"
	resume_btn.position = Vector2(540, 340)
	resume_btn.size = Vector2(200, 44)
	resume_btn.add_theme_font_size_override("font_size", 16)
	resume_btn.pressed.connect(_on_resume_pressed)
	pause_panel.add_child(resume_btn)

	var back_btn2 = Button.new()
	back_btn2.text = "返回主界面"
	back_btn2.position = Vector2(540, 400)
	back_btn2.size = Vector2(200, 44)
	back_btn2.add_theme_font_size_override("font_size", 16)
	back_btn2.pressed.connect(_on_back_pressed)
	pause_panel.add_child(back_btn2)

	# === 游戏结束面板 ===
	game_over_panel = Panel.new()
	game_over_panel.name = "GameOverPanel"
	game_over_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_over_panel.hide()
	var go_style = StyleBoxFlat.new()
	go_style.bg_color = Color(0, 0, 0, 0.7)
	game_over_panel.add_theme_stylebox_override("panel", go_style)
	add_child(game_over_panel)

	var go_label = Label.new()
	go_label.text = "游戏结束"
	go_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	go_label.add_theme_font_size_override("font_size", 40)
	go_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	go_label.position = Vector2(390, 240)
	go_label.size = Vector2(500, 60)
	game_over_panel.add_child(go_label)

	var restart_btn = Button.new()
	restart_btn.text = "重新开始"
	restart_btn.position = Vector2(540, 340)
	restart_btn.size = Vector2(200, 44)
	restart_btn.add_theme_font_size_override("font_size", 16)
	restart_btn.pressed.connect(_on_restart_pressed)
	game_over_panel.add_child(restart_btn)

	var back_btn3 = Button.new()
	back_btn3.text = "返回主界面"
	back_btn3.position = Vector2(540, 400)
	back_btn3.size = Vector2(200, 44)
	back_btn3.add_theme_font_size_override("font_size", 16)
	back_btn3.pressed.connect(_on_back_pressed)
	game_over_panel.add_child(back_btn3)

func _connect_events() -> void:
	EventBus.subscribe(GlobalDefine.EventName.HEALTH_CHANGED, self, "_on_health_changed")
	EventBus.subscribe(GlobalDefine.EventName.PLAYER_STATE_CHANGED, self, "_on_player_state_changed")
	EventBus.subscribe(GlobalDefine.EventName.GAME_PAUSE, self, "_on_game_pause")
	EventBus.subscribe(GlobalDefine.EventName.GAME_RESUME, self, "_on_game_resume")
	EventBus.subscribe(GlobalDefine.EventName.GAME_OVER, self, "_on_game_over")

func _update_mode_label() -> void:
	var mode_text = "[自测模式]" if GameManager.is_self_test() else "[正式模式]"
	mode_label.text = mode_text

# ---- 事件回调 ----

func _on_health_changed(data: Dictionary) -> void:
	if data.get("target") == GameManager.player_ref:
		var hp = data.get("current_health", 100)
		var max_hp = data.get("max_health", 100)
		var ratio = clampf(float(hp) / float(max_hp), 0.0, 1.0)
		health_bar.size.x = health_bar_max_width * ratio
		health_label.text = "%d / %d" % [hp, max_hp]

func _on_player_state_changed(data: Dictionary) -> void:
	state_label.text = _state_to_string(data.get("state", 0))

func _on_game_pause(_data: Dictionary = {}) -> void:
	pause_panel.show()

func _on_game_resume(_data: Dictionary = {}) -> void:
	pause_panel.hide()

func _on_game_over(_data: Dictionary = {}) -> void:
	game_over_panel.show()

func _state_to_string(state: int) -> String:
	match state:
		GlobalDefine.PlayerState.IDLE: return "待机"
		GlobalDefine.PlayerState.RUN: return "奔跑"
		GlobalDefine.PlayerState.JUMP: return "跳跃"
		GlobalDefine.PlayerState.FALL: return "下落"
		GlobalDefine.PlayerState.DASH: return "冲刺"
		GlobalDefine.PlayerState.ATTACK: return "攻击"
		GlobalDefine.PlayerState.SKILL: return "技能"
		GlobalDefine.PlayerState.HURT: return "受伤"
		GlobalDefine.PlayerState.DEAD: return "死亡"
	return "未知"

# ---- 按钮回调 ----

func _on_resume_pressed() -> void:
	GameManager.toggle_pause()

func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_back_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://UI/TitleScreen.tscn")

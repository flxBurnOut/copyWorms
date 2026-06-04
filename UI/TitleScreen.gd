# ============================================================
# TitleScreen.gd - 开始游戏界面
# 所有 UI 用代码构建，确保按钮事件可靠触发
# ============================================================
extends Control

func _ready() -> void:
	print("[TitleScreen] 标题画面加载")
	_build_ui()

func _build_ui() -> void:
	# 深色背景
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.08, 0.08, 0.15, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# 垂直布局容器
	var vbox = VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.position = Vector2(-160, -180)
	vbox.size = Vector2(320, 360)
	vbox.add_theme_constant_override("separation", 15)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(vbox)

	# 标题
	var title = Label.new()
	title.text = "黑客松动作游戏"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 1, 1))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)

	# 副标题
	var sub = Label.new()
	sub.text = "Hackathon Action Game"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.5, 0.5, 0.7, 1))
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sub)

	# 间隔
	vbox.add_child(_make_spacer(30))

	# 开始游戏按钮
	var btn_start = _make_button("开始游戏 (正式模式)", 50, 18, _on_start_game)
	vbox.add_child(btn_start)

	# 分隔线
	var sep = HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	# 自测标签
	var test_label = Label.new()
	test_label.text = "--- 自测模式 (打包时删除) ---"
	test_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	test_label.add_theme_font_size_override("font_size", 12)
	test_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	test_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(test_label)

	# 自测按钮
	vbox.add_child(_make_button("玩家模块自测", 40, 14, _on_test_player))
	vbox.add_child(_make_button("敌人模块自测", 40, 14, _on_test_enemy))
	vbox.add_child(_make_button("关卡模块自测", 40, 14, _on_test_level))

	# 间隔
	vbox.add_child(_make_spacer(15))

	# 退出按钮
	vbox.add_child(_make_button("退出游戏", 40, 14, _on_quit))

func _make_spacer(height: int) -> Control:
	var c = Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func _make_button(text: String, min_height: int, font_size: int, callback: Callable) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, min_height)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.pressed.connect(callback)
	return btn

# ---- 按钮回调 ----

func _on_start_game() -> void:
	print("[TitleScreen] >>> 开始正式游戏按钮被点击 <<<")
	GameManager.run_mode = GlobalDefine.RunMode.FORMAL
	get_tree().change_scene_to_file("res://Global/MainEntry.tscn")

func _on_test_player() -> void:
	print("[TitleScreen] >>> 玩家自测按钮被点击 <<<")
	GameManager.run_mode = GlobalDefine.RunMode.SELF_TEST
	get_tree().change_scene_to_file("res://PlayerModule/SelfTest/PlayerTest.tscn")

func _on_test_enemy() -> void:
	print("[TitleScreen] >>> 敌人自测按钮被点击 <<<")
	GameManager.run_mode = GlobalDefine.RunMode.SELF_TEST
	get_tree().change_scene_to_file("res://EnemyModule/SelfTest/EnemyTest.tscn")

func _on_test_level() -> void:
	print("[TitleScreen] >>> 关卡自测按钮被点击 <<<")
	GameManager.run_mode = GlobalDefine.RunMode.SELF_TEST
	get_tree().change_scene_to_file("res://LevelModule/SelfTest/LevelTest.tscn")

func _on_quit() -> void:
	print("[TitleScreen] >>> 退出按钮被点击 <<<")
	get_tree().quit()

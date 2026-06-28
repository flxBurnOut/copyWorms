# ============================================================
# KeybindSettingsScreen.gd - 按键设置界面
# 纯代码构建 UI，由 HUD 实例化并添加到 CanvasLayer
# 变暗遮罩由 HUD 在外部创建（与暂停面板完全一致的方式）
# 支持键盘/鼠标/手柄按键重绑定，ESC取消或关闭
# ============================================================
extends Control

## 关闭信号（HUD 监听，用于重新显示暂停面板）
signal closed()

var _listening_action: StringName = &""
var _action_rows: Dictionary = {}
var _list_vbox: VBoxContainer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	# 阻止 ESC 在此界面触发暂停切换
	InputManager.set_pause_allowed(false)

func _exit_tree() -> void:
	# 安全清理：确保退出时恢复所有状态（场景切换等异常情况）
	if _listening_action != &"":
		_finish_listening()
	if is_instance_valid(InputManager):
		InputManager.set_pause_allowed(true)

## ================================================================
##  UI 构建
## ================================================================

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var main_panel := Panel.new()
	main_panel.name = "DreamSettingsPanel"
	main_panel.position = Vector2(260, 36)
	main_panel.size = Vector2(900, 626)
	main_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameUIStyle.apply_pressed_button_panel(main_panel)
	add_child(main_panel)

	# 标题
	var title := Label.new()
	title.text = "按键设置"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.position = Vector2(460, 102)
	title.size = Vector2(500, 46)
	add_child(title)

	# 提示文字
	var hint := Label.new()
	hint.text = "点击 [修改] 后按下新按键，ESC 取消"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 21)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	hint.position = Vector2(420, 146)
	hint.size = Vector2(580, 26)
	add_child(hint)

	# 滚动区域
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(330, 194)
	scroll.size = Vector2(780, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_list_vbox = VBoxContainer.new()
	_list_vbox.name = "ActionList"
	_list_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(_list_vbox)

	# 构建每行动作
	for action: StringName in KeybindManager.REBINDABLE_ACTIONS:
		_add_action_row(action)

	# 底部按钮
	var reset_btn := _make_btn("恢复默认", Vector2(510, 540), Vector2(180, 54), true, 31)
	reset_btn.pressed.connect(_on_reset_pressed)
	add_child(reset_btn)

	var back_btn := _make_btn("返回", Vector2(730, 540), Vector2(180, 54), true, 31)
	back_btn.pressed.connect(_on_back_pressed)
	add_child(back_btn)

## 创建统一梦境赛博皮肤按钮
func _make_btn(text: String, pos: Vector2, size: Vector2, force_simple: bool = false, font_size: int = 24) -> TextureButton:
	var btn := TextureButton.new()
	btn.position = pos
	btn.custom_minimum_size = size
	btn.size = size
	# 文字标签
	var lbl := Label.new()
	lbl.name = "Label"
	lbl.text = text
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(lbl)
	GameUIStyle.apply_texture_button(btn, font_size, force_simple)
	return btn

func _add_action_row(action: StringName) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)

	# 动作名称
	var name_label := Label.new()
	name_label.text = KeybindManager.get_action_display_name(action)
	name_label.custom_minimum_size = Vector2(100, 38)
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	row.add_child(name_label)

	# 当前绑定显示
	var bind_label := Label.new()
	bind_label.custom_minimum_size = Vector2(400, 38)
	bind_label.add_theme_font_size_override("font_size", 22)
	bind_label.add_theme_color_override("font_color", Color(0.65, 0.82, 1.0))
	row.add_child(bind_label)

	# 修改按钮
	var rebind_btn := _make_btn("修改", Vector2.ZERO, Vector2(118, 44), true, 29)
	rebind_btn.pressed.connect(_on_rebind_pressed.bind(action))
	row.add_child(rebind_btn)

	_list_vbox.add_child(row)
	_action_rows[action] = {"label": bind_label, "button": rebind_btn}
	_update_binding_display(action)

func _update_binding_display(action: StringName) -> void:
	var row_data: Dictionary = _action_rows.get(action, {})
	if row_data.is_empty():
		return
	var bind_label: Label = row_data["label"]
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	var texts: Array = []
	for ev: InputEvent in events:
		if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
			continue
		texts.append(KeybindManager.get_event_display_text(ev))
	bind_label.text = ", ".join(texts) if texts.size() > 0 else "未绑定"

## ================================================================
##  监听模式
## ================================================================

func _on_rebind_pressed(action: StringName) -> void:
	# 如果已在监听另一个动作，先取消
	if _listening_action != &"":
		_cancel_listening()
	_listening_action = action
	var row_data: Dictionary = _action_rows.get(action, {})
	if not row_data.is_empty():
		var bind_label: Label = row_data["label"]
		bind_label.text = "< 请按键... (ESC取消) >"
		bind_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
		var rebind_btn: TextureButton = row_data["button"]
		GameUIStyle.set_texture_button_disabled(rebind_btn, true)
	# 屏蔽游戏输入，防止按键被游戏消费
	InputManager.block_input("按键设置-监听中", self)

func _input(event: InputEvent) -> void:
	# 非监听状态下，ESC 关闭设置界面
	if _listening_action == &"":
		if event is InputEventKey and event.pressed and not event.echo:
			if event.physical_keycode == KEY_ESCAPE:
				_on_back_pressed()
				get_viewport().set_input_as_handled()
				return
		return

	# ---- 监听模式 ----

	# 键盘事件
	if event is InputEventKey:
		if not event.pressed or event.echo:
			return
		# ESC 取消监听
		if event.physical_keycode == KEY_ESCAPE:
			_cancel_listening()
			get_viewport().set_input_as_handled()
			return
		_apply_binding(event)
		get_viewport().set_input_as_handled()
		return

	# 鼠标事件（仅当鼠标不在按钮上时才绑定）
	if event is InputEventMouseButton:
		if not event.pressed:
			return
		if _is_click_on_button(event):
			return
		_apply_binding(event)
		get_viewport().set_input_as_handled()
		return

	# 手柄按钮事件
	if event is InputEventJoypadButton:
		if not event.pressed:
			return
		_apply_binding(event)
		get_viewport().set_input_as_handled()
		return

func _apply_binding(event: InputEvent) -> void:
	var action: StringName = _listening_action
	KeybindManager.rebind_action(action, event)
	_finish_listening()
	_update_binding_display(action)

func _cancel_listening() -> void:
	var action: StringName = _listening_action
	_finish_listening()
	_update_binding_display(action)

func _finish_listening() -> void:
	if _listening_action == &"":
		return
	var row_data: Dictionary = _action_rows.get(_listening_action, {})
	if not row_data.is_empty():
		var bind_label: Label = row_data["label"]
		bind_label.add_theme_color_override("font_color", Color(0.65, 0.82, 1.0))
		var rebind_btn: TextureButton = row_data["button"]
		GameUIStyle.set_texture_button_disabled(rebind_btn, false)
	_listening_action = &""
	InputManager.unblock_input("按键设置-监听结束")

## 检查鼠标点击是否落在按钮上（避免把点击按钮误绑定为按键）
func _is_click_on_button(event: InputEventMouse) -> bool:
	var pos := event.global_position
	return _find_button_at_pos(self, pos)

func _find_button_at_pos(node: Node, pos: Vector2) -> bool:
	if node is BaseButton:
		var btn := node as BaseButton
		if btn.visible and btn.get_global_rect().has_point(pos):
			return true
	for child in node.get_children():
		if _find_button_at_pos(child, pos):
			return true
	return false

## ================================================================
##  按钮回调
## ================================================================

func _on_reset_pressed() -> void:
	if _listening_action != &"":
		_cancel_listening()
	KeybindManager.reset_to_defaults()
	for action: StringName in KeybindManager.REBINDABLE_ACTIONS:
		_update_binding_display(action)

func _on_back_pressed() -> void:
	if _listening_action != &"":
		_cancel_listening()
	InputManager.set_pause_allowed(true)
	closed.emit()
	queue_free()

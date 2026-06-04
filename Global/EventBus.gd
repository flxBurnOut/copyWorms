# ============================================================
# EventBus.gd - 全局事件总线 (Autoload)
# 模块间通信的唯一通道，禁止跨模块直接引用节点
# ============================================================
extends Node

# 存储所有监听者: { event_name: [ { "node": Node, "method": String }, ... ] }
var _listeners := {}

# 待处理的延迟事件（一帧内收集，帧末统一触发）
var _pending_events := []

# ---- 公开 API ----

## 注册监听事件
func subscribe(event_name: String, node: Node, method: String) -> void:
	if not _listeners.has(event_name):
		_listeners[event_name] = []
	_listeners[event_name].append({ "node": node, "method": method })

## 取消注册
func unsubscribe(event_name: String, node: Node) -> void:
	if not _listeners.has(event_name):
		return
	_listeners[event_name] = _listeners[event_name].filter(
		func(item): return item["node"] != node
	)

## 发射事件（立即执行）
func emit(event_name: String, data: Dictionary = {}) -> void:
	if not _listeners.has(event_name):
		return
	# 复制列表防止回调中修改
	var listeners_copy = _listeners[event_name].duplicate()
	for item in listeners_copy:
		if is_instance_valid(item["node"]) and item["node"].has_method(item["method"]):
			item["node"].call(item["method"], data)

## 延迟发射（下一帧处理）
func emit_deferred(event_name: String, data: Dictionary = {}) -> void:
	_pending_events.append({ "event": event_name, "data": data })

func _process(_delta: float) -> void:
	if _pending_events.is_empty():
		return
	var events = _pending_events
	_pending_events = []
	for evt in events:
		emit(evt["event"], evt["data"])

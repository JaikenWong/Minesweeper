extends Control
class_name Cell

## 单个格子的视觉与交互。
## 状态机: COVERED -> FLAGGED / QUESTIONED -> REVEALED
## 数字/问号用 Label 子节点居中显示, 旗子/雷/高亮用 _draw 自定义绘制。

signal revealed(cell: Cell)                ## 格子被揭开
signal flag_changed(cell: Cell, delta: int)    ## 旗子数变化量 (+1 / -1)
signal chord_requested(cell: Cell)         ## 在数字格上左+右键(双击)触发连锁

enum State { COVERED, FLAGGED, QUESTIONED, REVEALED }

const SIZE: int = 32

@export var row: int = 0
@export var col: int = 0
@export var is_mine: bool = false
@export var adjacent_mines: int = 0

var state: int = State.COVERED
var board: Control = null  ## 指向 Board 的弱引用, 用于回调
var _wrong_flag: bool = false  ## 失败时, 标错位置的红 X

# 经典扫雷数字配色 (1-8)
const NUMBER_COLORS: Array[Color] = [
	Color(0, 0, 0, 0),          # 0 不用
	Color(0.0, 0.0, 1.0),       # 1 蓝
	Color(0.0, 0.55, 0.0),      # 2 绿
	Color(0.85, 0.0, 0.0),      # 3 红
	Color(0.0, 0.0, 0.55),      # 4 深蓝
	Color(0.55, 0.0, 0.0),      # 5 暗红
	Color(0.0, 0.55, 0.55),     # 6 青
	Color(0.0, 0.0, 0.0),       # 7 黑
	Color(0.4, 0.4, 0.4),       # 8 灰
]

var _mouse_pressed_button: int = -1  ## -1 / MOUSE_BUTTON_LEFT / MOUSE_BUTTON_RIGHT
var _center_label: Label = null      ## 子节点 Label, 用于数字/问号居中


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 创建居中 Label (用于数字和问号)
	_center_label = Label.new()
	_center_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_center_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_label.add_theme_font_size_override("font_size", 20)
	_center_label.text = ""
	add_child(_center_label)
	_refresh_label()


func _gui_input(event: InputEvent) -> void:
	# REVEALED 状态也能接收输入(用于 chord), 但揭开/插旗判断里再过滤
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			# 检测 chord: 之前按了另一个键, 现在又按一个 -> 左右同时
			if (mb.button_index == MOUSE_BUTTON_LEFT and _mouse_pressed_button == MOUSE_BUTTON_RIGHT) \
				or (mb.button_index == MOUSE_BUTTON_RIGHT and _mouse_pressed_button == MOUSE_BUTTON_LEFT):
				_attempt_chord()
				_mouse_pressed_button = -1
				return
			_mouse_pressed_button = mb.button_index
		else:
			# 释放
			if _mouse_pressed_button == MOUSE_BUTTON_LEFT and mb.button_index == MOUSE_BUTTON_LEFT:
				if state == State.COVERED or state == State.QUESTIONED:
					_on_left_release()
			elif _mouse_pressed_button == MOUSE_BUTTON_RIGHT and mb.button_index == MOUSE_BUTTON_RIGHT:
				if state != State.REVEALED:
					_toggle_flag()
			_mouse_pressed_button = -1
			queue_redraw()


## 在数字格上左右同时按 -> 通知 board 尝试连锁揭开
func _attempt_chord() -> void:
	if state == State.REVEALED and adjacent_mines > 0:
		chord_requested.emit(self)


## 左键释放: 揭开格子
func _on_left_release() -> void:
	if state == State.FLAGGED:
		return  # 旗子上不能左键揭开
	revealed.emit(self)


## 右键: 在 COVERED/QUESTIONED/FLAGGED 之间循环
func _toggle_flag() -> void:
	var was_flagged: bool = (state == State.FLAGGED)
	if state == State.COVERED:
		state = State.FLAGGED
	elif state == State.FLAGGED:
		state = State.QUESTIONED
	elif state == State.QUESTIONED:
		state = State.COVERED
	# REVEALED 不响应
	var is_flagged: bool = (state == State.FLAGGED)
	var delta: int = (1 if is_flagged else 0) - (1 if was_flagged else 0)
	flag_changed.emit(self, delta)
	queue_redraw()
	_refresh_label()


## 外部调用: 揭开这个格子 (由 Board 触发)
func reveal() -> void:
	if state == State.REVEALED or state == State.FLAGGED:
		return
	state = State.REVEALED
	queue_redraw()
	_refresh_label()


## 外部调用: 强制揭开 (游戏失败时, 用于显示所有雷)
func force_reveal_as_mine() -> void:
	state = State.REVEALED
	queue_redraw()
	_refresh_label()


## 外部调用: 标记为错误旗子 (失败时)
func mark_wrong_flag() -> void:
	_wrong_flag = true
	queue_redraw()


func is_revealed() -> bool:
	return state == State.REVEALED


func is_flagged() -> bool:
	return state == State.FLAGGED


## 刷新 Label 的内容 (数字/问号/空)
func _refresh_label() -> void:
	if _center_label == null:
		return
	match state:
		State.REVEALED:
			if not is_mine and adjacent_mines > 0:
				_center_label.text = str(adjacent_mines)
				_center_label.add_theme_color_override("font_color", NUMBER_COLORS[adjacent_mines])
			else:
				_center_label.text = ""
		State.QUESTIONED:
			_center_label.text = "?"
			_center_label.add_theme_color_override("font_color", Color.BLACK)
		_:
			_center_label.text = ""


## 绘制
func _draw() -> void:
	var r := Rect2(Vector2.ZERO, Vector2(SIZE, SIZE))
	match state:
		State.COVERED, State.FLAGGED, State.QUESTIONED:
			_draw_covered(r)
		State.REVEALED:
			_draw_revealed(r)
	# 提示高亮: 黄色描边, 覆盖在所有内容之上
	if get_meta("hint_highlight", false):
		draw_rect(Rect2(Vector2(1, 1), Vector2(SIZE - 2, SIZE - 2)),
			Color(1, 0.85, 0.2, 1), false, 2.5)


## 覆盖时: 浅灰凸起方块 + 旗子(问号由 Label 显示)
func _draw_covered(r: Rect2) -> void:
	# 主体浅灰
	draw_rect(r, Color(0.75, 0.75, 0.75), true)
	# 凸起效果: 左/上亮, 右/下暗
	draw_line(Vector2(0, 0), Vector2(SIZE - 1, 0), Color(1, 1, 1), 2)
	draw_line(Vector2(0, 0), Vector2(0, SIZE - 1), Color(1, 1, 1), 2)
	draw_line(Vector2(SIZE - 1, 0), Vector2(SIZE - 1, SIZE - 1), Color(0.4, 0.4, 0.4), 2)
	draw_line(Vector2(0, SIZE - 1), Vector2(SIZE - 1, SIZE - 1), Color(0.4, 0.4, 0.4), 2)

	if state == State.FLAGGED:
		_draw_flag()


## 揭开时: 平坦深灰底 + 雷(数字由 Label 显示)
func _draw_revealed(r: Rect2) -> void:
	# 平坦深灰底
	draw_rect(r, Color(0.55, 0.55, 0.55), true)
	# 1px 内边框
	draw_rect(r, Color(0.45, 0.45, 0.45), false, 1.0)

	if is_mine:
		_draw_mine()


func _draw_flag() -> void:
	# 旗杆
	draw_line(Vector2(9, 7), Vector2(9, 26), Color.BLACK, 1.5)
	# 旗面 (红三角)
	var pts := PackedVector2Array([
		Vector2(9, 7),
		Vector2(22, 12),
		Vector2(9, 17),
	])
	draw_colored_polygon(pts, Color(0.9, 0.1, 0.1))
	# 底座
	draw_line(Vector2(5, 26), Vector2(14, 26), Color.BLACK, 1.5)
	# 如果是错误旗子, 画红色 X
	if _wrong_flag:
		draw_line(Vector2(4, 4), Vector2(SIZE - 5, SIZE - 5), Color(0.85, 0, 0), 2.5)
		draw_line(Vector2(SIZE - 5, 4), Vector2(4, SIZE - 5), Color(0.85, 0, 0), 2.5)


func _draw_mine() -> void:
	# 中心黑圆
	draw_circle(Vector2(SIZE / 2.0, SIZE / 2.0), 7, Color.BLACK)
	# 光芒
	var c := Vector2(SIZE / 2.0, SIZE / 2.0)
	for i in 4:
		var angle := i * PI / 4.0
		var d := Vector2(cos(angle), sin(angle)) * 11
		draw_line(c, c + d, Color.BLACK, 1.5)
	# 白色高光
	draw_circle(c + Vector2(-2, -2), 2, Color.WHITE)

extends Control

## 主场景:
##  - 顶部状态栏: 雷数 / 表情 / 计时 / 最佳成绩 / 剩余提示次数
##  - 中间: 棋盘 (动态创建 Board)
##  - 底部: 难度选择 + 自定义难度 + 提示/重开按钮
##  - 快捷键: R = 重开当前关, H = 用一次提示, M = 鼠标位置插旗
##  - 表情按钮: 失败/游戏中 = 重开, 胜利 = 进入下一关
##  - hover 表情按钮: 😮

const MAX_HINTS: int = 3

var best_times: BestTimes = BestTimes.new()

@onready var _mine_label: Label = %MineLabel
@onready var _time_label: Label = %TimeLabel
@onready var _face_button: Button = %FaceButton
@onready var _face_hint_label: Label = %FaceHintLabel
@onready var _hint_count_label: Label = %HintCountLabel
@onready var _hint_button: Button = %HintButton
@onready var _restart_button: Button = %RestartButton
@onready var _board_container: Control = %BoardContainer
@onready var _best_label: Label = %BestLabel
@onready var _custom_button: Button = %CustomButton
@onready var _custom_dialog: AcceptDialog = %CustomDialog
@onready var _custom_rows: SpinBox = %CustomRowsSpin
@onready var _custom_cols: SpinBox = %CustomColsSpin
@onready var _custom_mines: SpinBox = %CustomMinesSpin
@onready var _difficulty_buttons: Dictionary = {
	"easy": %EasyButton,
	"medium": %MediumButton,
	"hard": %HardButton,
}

var _difficulties: Dictionary = {
	"easy":   {"rows": 9,  "cols": 9,  "mines": 10},
	"medium": {"rows": 16, "cols": 16, "mines": 40},
	"hard":   {"rows": 16, "cols": 30, "mines": 99},
	"custom": {},  # 占位; 实际值存 _custom_cfg
}
var _difficulty_order: Array[String] = ["easy", "medium", "hard"]
var _custom_cfg: Dictionary = {"rows": 9, "cols": 9, "mines": 10}

var _current_difficulty: String = "easy"
var _board: Board = null
var _time: float = 0.0
var _timer_running: bool = false
var _game_over: bool = false
var _won: bool = false
var _hints_left: int = MAX_HINTS
var _face_lock: bool = false  ## hover 时锁住表情, 防 button_down/up 反复切


func _ready() -> void:
	# 难度按钮
	for k in _difficulty_buttons:
		var btn: Button = _difficulty_buttons[k]
		btn.pressed.connect(_on_difficulty_pressed.bind(k))
	# 表情按钮
	_face_button.pressed.connect(_on_face_pressed)
	_face_button.button_down.connect(_on_face_button_down)
	_face_button.button_up.connect(_on_face_button_up)
	_face_button.mouse_entered.connect(_on_face_mouse_entered)
	_face_button.mouse_exited.connect(_on_face_mouse_exited)
	# 底部按钮
	_hint_button.pressed.connect(_on_hint_pressed)
	_restart_button.pressed.connect(_on_restart_pressed)
	# 自定义难度
	_custom_button.pressed.connect(_on_custom_pressed)
	_custom_dialog.confirmed.connect(_on_custom_start)
	# 初始
	_update_hint_label()
	_set_face("smile")
	_face_hint_label.visible = false
	_update_difficulty_buttons()
	_refresh_best_label()
	_start_new_game("easy")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		match key.keycode:
			KEY_R:
				_restart_current()
				get_viewport().set_input_as_handled()
			KEY_H:
				_on_hint_pressed()
				get_viewport().set_input_as_handled()
			KEY_M:
				_toggle_flag_at_mouse()
				get_viewport().set_input_as_handled()


## 快捷键 M: 在鼠标位置的格子上模拟右键 (用于不方便用右键的场景, 比如触摸板)
func _toggle_flag_at_mouse() -> void:
	if _game_over or _board == null:
		return
	var mouse_pos: Vector2 = get_global_mouse_position() - _board_container.global_position
	if mouse_pos.x < 0 or mouse_pos.y < 0:
		return
	var cell_size: int = 32
	var c: int = int(mouse_pos.x / cell_size)
	var r: int = int(mouse_pos.y / cell_size)
	if r < 0 or r >= _board.rows or c < 0 or c >= _board.cols:
		return
	var cell: Cell = _board._cells[r][c]
	cell._toggle_flag()


func _on_difficulty_pressed(difficulty: String) -> void:
	if difficulty == _current_difficulty:
		_start_new_game(difficulty)
		return
	_current_difficulty = difficulty
	_update_difficulty_buttons()
	_refresh_best_label()
	_start_new_game(difficulty)


func _update_difficulty_buttons() -> void:
	for k in _difficulty_buttons:
		var btn: Button = _difficulty_buttons[k]
		if k == _current_difficulty:
			btn.modulate = Color(0.7, 1.0, 0.7)
		else:
			btn.modulate = Color.WHITE
	# custom 按钮单独高亮
	if _custom_button != null:
		if _current_difficulty == "custom":
			_custom_button.modulate = Color(0.7, 1.0, 0.7)
		else:
			_custom_button.modulate = Color.WHITE


func _start_new_game(difficulty: String) -> void:
	if _board != null:
		_board.queue_free()
		_board = null
	var cfg: Dictionary
	if difficulty == "custom":
		cfg = _custom_cfg
	else:
		cfg = _difficulties[difficulty]
	# 先创建, 再设 rows/cols (add_child 会触发 _ready, 那时 columns/rows 已就位)
	_board = Board.new()
	_board.rows = cfg.rows
	_board.cols = cfg.cols
	_board.mine_count = cfg.mines
	_board_container.add_child(_board)
	_board.new_game(cfg.rows, cfg.cols, cfg.mines)
	# 信号
	_board.flag_count_changed.connect(_on_flag_count_changed)
	_board.first_reveal.connect(_on_first_reveal)
	_board.mine_exploded.connect(_on_mine_exploded)
	_board.game_won.connect(_on_game_won)
	# 重置
	_time = 0.0
	_timer_running = false
	_game_over = false
	_won = false
	_hints_left = MAX_HINTS
	_time_label.text = "000"
	_mine_label.text = _format_count(cfg.mines)
	_set_face("smile")
	_face_hint_label.visible = false
	_update_hint_label()
	_hint_button.disabled = false
	_restart_button.disabled = false
	_refresh_best_label()
	_resize_window(cfg)


func _resize_window(cfg: Dictionary) -> void:
	var padding: int = 16
	var top_bar: int = 70
	var bottom_bar: int = 56
	var min_window_w: int = 600       # 容纳顶部+底部所有按钮的最小宽度
	var max_cell_size: int = 32
	# 棋盘宽 = max(棋盘自然宽, 窗口最小宽 - padding*2)
	var natural_w: int = int(cfg.cols) * max_cell_size
	var available_w: int = max(min_window_w, natural_w + padding * 2) - padding * 2
	var cell_size: int = mini(max_cell_size, available_w / int(cfg.cols))
	var board_w: int = int(cfg.cols) * cell_size
	var board_h: int = int(cfg.rows) * cell_size
	var width: int = board_w + padding * 2
	var height: int = board_h + top_bar + bottom_bar
	# 确保最小宽度
	width = max(width, min_window_w)
	get_window().size = Vector2i(width, height)
	var vp: Vector2 = get_viewport_rect().size
	_board_container.size = Vector2(board_w, board_h)
	_board_container.position = Vector2(
		(vp.x - board_w) / 2.0,
		top_bar
	)
	_center_board.call_deferred(board_w, board_h, top_bar)


func _center_board(board_w: float, board_h: float, top_bar: float) -> void:
	var vp: Vector2 = get_viewport_rect().size
	_board_container.size = Vector2(board_w, board_h)
	_board_container.position = Vector2(
		(vp.x - board_w) / 2.0,
		top_bar
	)


func _on_flag_count_changed(remaining: int) -> void:
	_mine_label.text = _format_count(remaining)


func _on_first_reveal() -> void:
	_timer_running = true


func _on_mine_exploded() -> void:
	_game_over = true
	_won = false
	_timer_running = false
	_set_face("dead")
	_face_hint_label.visible = false


func _on_game_won() -> void:
	_game_over = true
	_won = true
	_timer_running = false
	# 破纪录检查
	var secs := int(_time)
	if secs > 0 and best_times.is_new_record(_current_difficulty, secs):
		best_times.save(_current_difficulty, secs)
		_animate_new_record()
	_refresh_best_label()
	_set_face("cool")
	_face_hint_label.visible = true
	_face_hint_label.text = "下一关 →"


func _on_face_pressed() -> void:
	# 胜利 -> 下一关; 否则 -> 重开当前
	if _won:
		_go_to_next_level()
	else:
		_restart_current()


func _on_face_button_down() -> void:
	if _face_lock or _game_over:
		return
	_set_face("surprised")


func _on_face_button_up() -> void:
	if _face_lock or _game_over:
		return
	_set_face("smile")


func _on_face_mouse_entered() -> void:
	if _game_over:
		return
	_face_lock = true
	_set_face("surprised")


func _on_face_mouse_exited() -> void:
	if _game_over:
		return
	_face_lock = false
	_set_face("smile")


func _on_hint_pressed() -> void:
	if _game_over or _board == null or _hints_left <= 0:
		return
	# 第一次按提示会先放置雷(因为提示也走 reveal 流程)
	# 但 use_hint 内部已经会 _first_click 检查, 所以安全
	var ok: bool = _board.use_hint()
	if ok:
		_hints_left -= 1
		_update_hint_label()
		if _hints_left <= 0:
			_hint_button.disabled = true


func _on_restart_pressed() -> void:
	_restart_current()


func _restart_current() -> void:
	_start_new_game(_current_difficulty)


func _go_to_next_level() -> void:
	var idx: int = _difficulty_order.find(_current_difficulty)
	var next_idx: int = (idx + 1) % _difficulty_order.size()
	var next_diff: String = _difficulty_order[next_idx]
	_current_difficulty = next_diff
	_update_difficulty_buttons()
	_refresh_best_label()
	_start_new_game(next_diff)


func _set_face(name: String) -> void:
	match name:
		"smile":
			_face_button.text = "🙂"
		"surprised":
			_face_button.text = "😮"
		"cool":
			_face_button.text = "😎"
		"dead":
			_face_button.text = "💀"


func _update_hint_label() -> void:
	_hint_count_label.text = "💡 %d" % _hints_left


func _refresh_best_label() -> void:
	if _best_label == null:
		return
	var best: int = best_times.get_best(_current_difficulty)
	if best > 0:
		_best_label.text = "🏆 %03d" % best
	else:
		_best_label.text = "🏆 ---"


## 自定义难度: 打开对话框, 预填上次值
func _on_custom_pressed() -> void:
	_custom_rows.value = _custom_cfg.rows
	_custom_cols.value = _custom_cfg.cols
	_custom_mines.value = _custom_cfg.mines
	_custom_dialog.popup_centered()


## 自定义难度: 校验 + 启动新游戏
func _on_custom_start() -> void:
	var r := int(_custom_rows.value)
	var c := int(_custom_cols.value)
	var m := int(_custom_mines.value)
	if m < 1 or m >= r * c:
		OS.alert("雷数 (%d) 必须 >= 1 且 < 行数 × 列数 (%d)" % [m, r * c], "参数错误")
		return
	_custom_cfg = {"rows": r, "cols": c, "mines": m}
	_current_difficulty = "custom"
	_update_difficulty_buttons()
	_start_new_game("custom")


## 破纪录动效: 抖动 + 变金色, FaceHintLabel 改 "新纪录!"
func _animate_new_record() -> void:
	if _best_label == null:
		return
	_best_label.pivot_offset = _best_label.size / 2.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_best_label, "modulate", Color(1, 0.85, 0.2), 0.25)
	tw.tween_property(_best_label, "scale", Vector2(1.3, 1.3), 0.25)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished
	var tw2 := create_tween().set_parallel(true)
	tw2.tween_property(_best_label, "modulate", Color.WHITE, 0.25)
	tw2.tween_property(_best_label, "scale", Vector2(1.0, 1.0), 0.25)
	_face_hint_label.text = "🏆 新纪录！"


func _format_count(n: int) -> String:
	if n < 0:
		return "-%02d" % min(-n, 99)
	return "%03d" % min(n, 999)


func _process(delta: float) -> void:
	if _timer_running and not _game_over:
		_time += delta
		_time_label.text = _format_count(int(_time))
		if int(_time) >= 999:
			_timer_running = false
extends GridContainer
class_name Board

## 棋盘逻辑:
##  - 维护 cells 二维数组
##  - 首次点击时再生成雷(保护首次点击不中雷)
##  - 处理揭开/旗子/连锁(chord)
##  - 胜负判定

signal mine_exploded()                          ## 踩雷 -> 失败
signal game_won()                               ## 胜利
signal first_reveal()                           ## 首次揭开(用于启动计时)
signal flag_count_changed(remaining: int)      ## 旗子数变化(用于显示剩余雷数)
signal hint_used(cell: Cell)                    ## 提示用掉, 高亮某个格子

const CELL_SCENE := preload("res://scenes/cell.tscn")

var rows: int = 9
var cols: int = 9
var mine_count: int = 10

var _cells: Array = []                          ## 二维数组 _cells[row][col] -> Cell
var _first_click: bool = true
var _game_over: bool = false
var _flag_count: int = 0


func _ready() -> void:
	columns = cols
	add_theme_constant_override("h_separation", 0)
	add_theme_constant_override("v_separation", 0)


## 开始新游戏: 清空旧的, 重新生成格子
func new_game(p_rows: int, p_cols: int, p_mines: int) -> void:
	rows = p_rows
	cols = p_cols
	mine_count = p_mines
	columns = cols
	_first_click = true
	_game_over = false
	_flag_count = 0
	# 清空旧格子
	for child in get_children():
		child.queue_free()
	_cells.clear()
	# 创建新格子
	for r in rows:
		var row_arr: Array[Cell] = []
		for c in cols:
			var cell: Cell = CELL_SCENE.instantiate()
			cell.row = r
			cell.col = c
			cell.board = self
			cell.revealed.connect(_on_cell_revealed)
			cell.flag_changed.connect(_on_cell_flag_changed)
			cell.chord_requested.connect(_on_cell_chord_requested)
			add_child(cell)
			row_arr.append(cell)
		_cells.append(row_arr)
	# 触发一次旗子数更新 (让 UI 显示初始的 mine_count)
	flag_count_changed.emit(mine_count)


## 首次点击时调用: 在避开 (safe_row, safe_col) 周围 3x3 的区域随机放雷
##
## 规则 (详见 README "雷的分布规则" 章节):
##  1. 首次点击才生成雷 (保证首次点击 + 周围 8 格都安全)
##  2. 候选池 = 棋盘所有格 − 3×3 安全区
##  3. Array.shuffle() 洗牌 → 取前 mine_count 个标 is_mine
##  4. 紧接计算所有非雷格的 adjacent_mines (8 邻居雷数)
func _place_mines(safe_row: int, safe_col: int) -> void:
	# 收集所有候选位置 (排除 3×3 安全区)
	var candidates: Array[Vector2i] = []
	for r in rows:
		for c in cols:
			if abs(r - safe_row) <= 1 and abs(c - safe_col) <= 1:
				continue  # 跳过安全区
			candidates.append(Vector2i(r, c))
	# 洗牌 + 取前 mine_count 个标雷
	candidates.shuffle()
	var placed := 0
	for pos in candidates:
		if placed >= mine_count:
			break
		var cell: Cell = _cells[pos.x][pos.y]
		cell.is_mine = true
		placed += 1
	# 计算每个非雷格的 adjacent_mines (用于揭开时显示数字)
	for r in rows:
		for c in cols:
			var cell: Cell = _cells[r][c]
			if cell.is_mine:
				continue
			cell.adjacent_mines = _count_adjacent_mines(r, c)


func _count_adjacent_mines(r: int, c: int) -> int:
	var n: int = 0
	for dr: int in [-1, 0, 1]:
		for dc: int in [-1, 0, 1]:
			if dr == 0 and dc == 0:
				continue
			var nr: int = r + dr
			var nc: int = c + dc
			if nr < 0 or nr >= rows or nc < 0 or nc >= cols:
				continue
			if _cells[nr][nc].is_mine:
				n += 1
	return n


func _on_cell_revealed(cell: Cell) -> void:
	if _game_over:
		return

	# 首次点击: 先生成雷, 通知 main 启动计时
	if _first_click:
		_first_click = false
		_place_mines(cell.row, cell.col)
		first_reveal.emit()

	# 旗子不能揭开
	if cell.is_flagged():
		return

	# 踩雷 -> 失败
	if cell.is_mine:
		_game_over = true
		cell.force_reveal_as_mine()
		# 揭开其他雷, 标错旗子画 X
		_reveal_all_mines(cell)
		mine_exploded.emit()
		return

	# BFS 展开: 揭开当前 + 空白区域所有邻居
	_flood_reveal(cell.row, cell.col)

	# 胜利判定
	if _check_win():
		_game_over = true
		# 胜利: 把所有非雷格子自动插旗
		_auto_flag_remaining()
		game_won.emit()


## BFS 揭开: 如果是空白(adj=0) 连锁揭开周围, 否则只揭开自己
func _flood_reveal(start_r: int, start_c: int) -> void:
	var stack: Array[Vector2i] = [Vector2i(start_r, start_c)]
	while not stack.is_empty():
		var pos: Vector2i = stack.pop_back()
		var r := pos.x
		var c := pos.y
		if r < 0 or r >= rows or c < 0 or c >= cols:
			continue
		var cell: Cell = _cells[r][c]
		if cell.is_revealed() or cell.is_flagged() or cell.is_mine:
			continue
		cell.reveal()
		# 空白: 邻居继续展开
		if cell.adjacent_mines == 0:
			for dr in [-1, 0, 1]:
				for dc in [-1, 0, 1]:
					if dr == 0 and dc == 0:
						continue
					stack.append(Vector2i(r + dr, c + dc))


func _on_cell_flag_changed(cell: Cell, delta: int) -> void:
	_flag_count += delta
	flag_count_changed.emit(mine_count - _flag_count)


## 数字格上左右同时按: 若周围旗子数 == adjacent_mines, 揭开周围所有非旗格子
func _on_cell_chord_requested(cell: Cell) -> void:
	if _game_over or not cell.is_revealed() or cell.adjacent_mines == 0:
		return
	var adj_flags: int = 0
	for dr: int in [-1, 0, 1]:
		for dc: int in [-1, 0, 1]:
			if dr == 0 and dc == 0:
				continue
			var nr: int = cell.row + dr
			var nc: int = cell.col + dc
			if nr < 0 or nr >= rows or nc < 0 or nc >= cols:
				continue
			if _cells[nr][nc].is_flagged():
				adj_flags += 1
	if adj_flags != cell.adjacent_mines:
		return
	# 揭开周围 8 个非旗格子
	for dr: int in [-1, 0, 1]:
		for dc: int in [-1, 0, 1]:
			if dr == 0 and dc == 0:
				continue
			var nr: int = cell.row + dr
			var nc: int = cell.col + dc
			if nr < 0 or nr >= rows or nc < 0 or nc >= cols:
				continue
			var n: Cell = _cells[nr][nc]
			if n.is_revealed() or n.is_flagged():
				continue
			# 走 _on_cell_revealed 以触发胜负判定 / 踩雷
			_on_cell_revealed(n)


## 失败时: 揭开所有未揭开的雷, 错误旗子画 X
func _reveal_all_mines(red_cell: Cell) -> void:
	for r in rows:
		for c in cols:
			var cell: Cell = _cells[r][c]
			if cell.is_mine and cell != red_cell:
				cell.force_reveal_as_mine()
			elif not cell.is_mine and cell.is_flagged():
				cell.mark_wrong_flag()


func _check_win() -> bool:
	# 胜利: 所有非雷格子都揭开
	for r in rows:
		for c in cols:
			var cell: Cell = _cells[r][c]
			if not cell.is_mine and not cell.is_revealed():
				return false
	return true


func _auto_flag_remaining() -> void:
	for r in rows:
		for c in cols:
			var cell: Cell = _cells[r][c]
			if cell.is_mine and not cell.is_flagged():
				# 模拟一次插旗
				if cell.state == Cell.State.COVERED:
					cell.state = Cell.State.FLAGGED
					_flag_count += 1
					cell.queue_redraw()
	flag_count_changed.emit(mine_count - _flag_count)


## 用一次提示: 智能找一个安全格子揭开, 并 emit hint_used(cell) 高亮它
## 返回 true 表示成功, false 表示没格子可揭 (game over / 全揭开 / 全部都是雷/旗)
func use_hint() -> bool:
	if _game_over or _first_click:
		return false

	# 优先: 找"旗子数 == 数字"的数字格, 揭开它周围一个未揭非旗
	for r: int in rows:
		for c: int in cols:
			var cell: Cell = _cells[r][c]
			if not cell.is_revealed() or cell.adjacent_mines == 0:
				continue
			var flags: int = _count_adjacent_flags(r, c)
			if flags != cell.adjacent_mines:
				continue
			# 找周围一个安全未揭非旗格子
			var safe_target: Cell = _find_adjacent_safe_unrevealed(r, c)
			if safe_target != null:
				_reveal_with_hint(safe_target)
				return true

	# 回退: 任意一个非雷、未揭、非旗的格子
	for r: int in rows:
		for c: int in cols:
			var cell: Cell = _cells[r][c]
			if not cell.is_revealed() and not cell.is_flagged() and not cell.is_mine:
				_reveal_with_hint(cell)
				return true
	return false


func _count_adjacent_flags(r: int, c: int) -> int:
	var n: int = 0
	for dr: int in [-1, 0, 1]:
		for dc: int in [-1, 0, 1]:
			if dr == 0 and dc == 0:
				continue
			var nr: int = r + dr
			var nc: int = c + dc
			if nr < 0 or nr >= rows or nc < 0 or nc >= cols:
				continue
			if _cells[nr][nc].is_flagged():
				n += 1
	return n


func _find_adjacent_safe_unrevealed(r: int, c: int) -> Cell:
	for dr: int in [-1, 0, 1]:
		for dc: int in [-1, 0, 1]:
			if dr == 0 and dc == 0:
				continue
			var nr: int = r + dr
			var nc: int = c + dc
			if nr < 0 or nr >= rows or nc < 0 or nc >= cols:
				continue
			var n: Cell = _cells[nr][nc]
			if not n.is_revealed() and not n.is_flagged() and not n.is_mine:
				return n
	return null


func _reveal_with_hint(cell: Cell) -> void:
	# 先标记高亮 (用 meta), 然后揭开
	cell.set_meta("hint_highlight", true)
	cell.queue_redraw()
	hint_used.emit(cell)
	# 走标准揭开流程
	_on_cell_revealed(cell)
	# 0.6 秒后取消高亮
	var t: SceneTreeTimer = get_tree().create_timer(0.6)
	t.timeout.connect(func() -> void:
		if is_instance_valid(cell):
			cell.set_meta("hint_highlight", false)
			cell.queue_redraw()
	)

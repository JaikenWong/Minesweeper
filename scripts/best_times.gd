extends RefCounted
class_name BestTimes

## 最佳成绩持久化:
##  - 用 ConfigFile 存 user://best_times.cfg
##  - 按难度分别记最快通关秒数 (0 = 无记录)
##  - 提供加载/保存/破纪录判定

const _SAVE_PATH := "user://best_times.cfg"
const _SECTION := "records"

var _records: Dictionary = {"easy": 0, "medium": 0, "hard": 0, "custom": 0}


func _init() -> void:
	_records = load_all()


## 加载全部记录. 缺失文件/字段视为 0.
func load_all() -> Dictionary:
	var out := {"easy": 0, "medium": 0, "hard": 0, "custom": 0}
	var cfg := ConfigFile.new()
	var err := cfg.load(_SAVE_PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("[BestTimes] load failed: %s" % error_string(err))
		return out
	for k in out:
		out[k] = int(cfg.get_value(_SECTION, k, 0))
	return out


## 保存某难度的新最佳秒数.
func save(difficulty: String, seconds: int) -> void:
	_records[difficulty] = seconds
	var cfg := ConfigFile.new()
	# 先加载已有内容避免覆盖其他难度
	cfg.load(_SAVE_PATH)
	cfg.set_value(_SECTION, difficulty, seconds)
	var err := cfg.save(_SAVE_PATH)
	if err != OK:
		push_warning("[BestTimes] save failed: %s" % error_string(err))


## 取某难度的最佳秒数 (0 = 无记录).
func get_best(difficulty: String) -> int:
	if not _records.has(difficulty):
		return 0
	return int(_records[difficulty])


## 判定是否破纪录:
##  - seconds <= 0 永远 false
##  - 无记录且 seconds > 0 -> true
##  - 有记录且新秒数 < 旧秒数 -> true
func is_new_record(difficulty: String, seconds: int) -> bool:
	if seconds <= 0:
		return false
	var current: int = get_best(difficulty)
	return current == 0 or seconds < current
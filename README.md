# Minesweeper (Godot 4)

经典扫雷游戏的 Godot 4 复刻。

[![Release Build](https://github.com/JaikenWong/Minesweeper/actions/workflows/release.yml/badge.svg)](https://github.com/JaikenWong/Minesweeper/actions/workflows/release.yml)

## 运行

1. 打开 [Godot 4.2+](https://godotengine.org/download) (用 **Godot 4.x**, 不是 Godot 3)
2. 点击 `Import` → 选这个目录里的 `project.godot`
3. 第一次导入时 Godot 会自动建 `.godot/` 缓存目录
4. 按 `F5` 或工具栏 ▶ 按钮开始游戏

主场景已经设为 `res://scenes/main.tscn`, 不需要再选。

## 项目结构

```
Minesweeper/
├── project.godot          # Godot 项目配置
├── icon.svg               # 项目图标
├── scenes/
│   ├── main.tscn          # 主场景: 状态栏 + 棋盘容器 + 难度按钮 + 自定义难度
│   └── cell.tscn          # 单个格子的场景
└── scripts/
    ├── main.gd            # 主场景脚本: UI/计时/重开/难度/最佳成绩/自定义
    ├── board.gd           # 棋盘逻辑: 雷区生成/连锁/胜负
    ├── cell.gd            # 格子: 绘制 + 鼠标事件 + 状态机
    └── best_times.gd      # 最佳成绩持久化 (ConfigFile @ user://best_times.cfg)
```

## 玩法

- **左键**: 揭开格子 (数字 = 周围 8 格的雷数, 0 = 自动展开周围空白)
- **右键** 或 **M 键** (在鼠标位置): 在 空白 → 红旗 → 问号 → 空白 之间循环标记 (红旗 = 标记雷)
- **数字格上左+右键同时**: chord, 当周围旗子数等于数字时, 自动揭开周围剩余格
- **顶部状态栏**: 雷数 (= 总雷数 - 旗子数) / 表情 / 时间 / `🏆 最佳成绩` / `💡 剩余提示次数`
- **表情按钮**:
  - **鼠标悬停**: 即时变 😮 (失败/胜利时锁定)
  - **鼠标按下**: 😮 (悬停已激活时不重复切换)
  - **游戏中/失败**: 点击重开当前关 (快捷键 `R`)
  - **胜利**: 点击进入下一关 (简单 → 中等 → 困难 → 简单 循环)
- **底部**:
  - 难度切换: 简单 9×9/10雷, 中等 16×16/40雷, 困难 30×16/99雷
  - `🎚 自定义`: 弹出输入面板, 设置 行数 (1-30) / 列数 (1-30) / 雷数 (1-200), 校验 `雷数 < 行 × 列`
  - `💡 提示 (H)`: 智能找一个安全格子自动揭开, 目标格子黄色高亮 0.6 秒, 每局 3 次
  - `🔄 重开 (R)`: 重新开始当前难度
- 首次点击永远不中雷 (经典规则)
- 窗口最小宽度 600, 容纳所有按钮; cell_size 在窄空间下自动缩小

## 提示算法

按优先级找:
1. 找"周围旗子数 == 数字"的数字格, 揭开其周围一个未揭非旗的格子 (100% 安全)
2. 找不到则回退: 任意一个非雷 / 未揭 / 非旗的格子

## 最佳成绩

- 每个难度独立记录最快通关秒数, 存 `user://best_times.cfg`
- 无记录显示 `🏆 ---`, 有记录显示 `🏆 123` (三位数, 秒)
- **破纪录时**: 最佳成绩文字 0.5 秒金色 + 放大抖动, FaceHintLabel 切到 `🏆 新纪录！`
- 切换难度时自动显示对应最佳成绩

## 实现要点

- 格子用 `Control + _draw` 自定义绘制, 数字/问号用 Label 子节点居中
- 经典配色: 1=蓝 2=绿 3=红 4=深蓝 5=暗红 6=青 7=黑 8=灰
- 揭开时格子变平坦 + 1px 内边框, 覆盖时凸起 3D 效果
- 失败时揭开所有雷, 错标的旗子画红色 X
- 胜利时所有未揭开的雷自动插旗
- 表情按钮用 `_face_lock` 标志防止 hover/按下事件互相覆盖

## 已知限制

- 没有"重置所有最佳成绩"按钮 (可手动删 `user://best_times.cfg`)
- 自定义难度的最佳成绩只保留一份 (覆盖式)

## 发布

每次打 tag 自动出桌面三件包：

```bash
git tag v0.1.0
git push --tags
```

会触发 `.github/workflows/release.yml`，并行构建：

| 平台 | 产物 | GitHub Runner |
|------|------|---------------|
| Linux | `Minesweeper-Linux.AppImage` (单文件, 直接 chmod +x 运行) | ubuntu-latest |
| Windows | `Minesweeper-Windows.exe` (单文件) | windows-latest |
| macOS | `Minesweeper-macOS.zip` (内含 .app, 解压即可) | macos-latest |

构建完成后自动创建 GitHub Release，附变更日志。可在 Actions 页面右上角 **Run workflow** 手动触发。

> 本地手工出包：Godot 编辑器 → Project → Manage Export Presets (已预设) → Project → Export... → 选 preset。
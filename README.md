# Law Thief

窃律者 Godot MVP 项目 — 8×8 战术嫁祸战棋原型。

## 环境

- Godot 4.6+（本仓库用 `Godot → 项目管理器 → 导入` 打开本目录；命令行可先装 Homebrew 版：**`brew install --cask godot`**，随后在终端使用 `/opt/homebrew/bin/godot`）
- GDScript：**比较请用 `==` / `!=`**（不支持 `===` / `!==`，误入代码会导致解析失败、项目无法启动）
- UI 单位头像/列表色与棋盘骑士贴图：`UnitLooks` Autoload（`scripts/services/unit_looks.gd`）。**不要用 `preload("…/unit_visuals.gd").静态方法`**——引擎对 `preload` 返回值调静态方法不可靠，应走 Autoload 实例方法。
- 含 `assets/demo/doodle-rpg` 时，**至少用编辑器完整打开一次工程**，让 PNG 完成导入；否则无头或未生成 `.godot/imported` 时可能看到 `Failed loading resource … Forward0.png`，属资源未导入而非逻辑错误。

## 运行

先在终端进入本仓库根目录（与本 README 同级、内含 `project.godot`）；在 Godot 里「导入」该目录等价。

```bash
godot --path .
```

## 验证

同样在仓库根目录执行。

AI / 日常开发优先使用统一入口：

```bash
./tools/context 爆炸
./tools/snapshot --gems gem_explosion,gem_explosion,gem_explosion
./tools/verify test explosion_test
./tools/verify changed --list
./tools/verify changed
```

`snapshot` 会将行动前后状态、差异、事件、不变量和数值计算 trace 写入
`artifacts/verify/snapshot.json`。详细约定见 `AGENTS.md`。

`verify test` 是日常首选，只运行明确指定的测试；`verify changed` 按改动领域选择测试。无参数执行 `verify` 也等价于 `changed`，不会默认跑大套件。`fast` 仅用于有明确跨系统风险的改动，`all` 默认只在 CI 或明确要求时运行，`manual` 只运行压力/调试探针。加 `--list` 可只查看选择结果而不启动 Godot。所有 `verify` 模式都会执行语义覆盖检查；需要单独审计时，可用 `SEMANTIC_COVERAGE_MIN=50 ./tools/coverage` 设置最低覆盖率门禁。

主场景无头启动：

```bash
godot --headless --path . --quit-after 2
```

战斗场景无头启动：

```bash
godot --headless --path . res://scenes/battle/battle_scene.tscn --quit-after 3
```

聚焦诊断仍可直接执行单个测试，例如：

```bash
godot --headless --path . --script res://scripts/tests/explosion_test.gd
```

手动探针 / 压力验证（不包含在 `changed`、`fast` 或 `all` 中）：

```bash
./tools/verify manual
godot --headless --path . --script res://scripts/tests/manual/damage_debug_test.gd
godot --headless --path . --script res://scripts/tests/manual/battle_stress_test.gd
```

约定：不要在修改前先跑测试。修改后优先执行单个相关测试；涉及数个相关文件时才用 `verify changed`。不要固定串行重复执行 `changed`、`fast`、`all` 和手工测试；本地 `all` 只在明确要求时运行。

教学关冒烟测试（拔爆炸 → 嵌黑槽 → 击杀引爆）：

```bash
godot --headless --path . --script res://scripts/tests/smoke_test.gd
```

遭遇战加载测试：

```bash
godot --headless --path . --script res://scripts/tests/encounter_load_test.gd
```

## Editor CLI

战斗场景按 **F9** 打开上半屏 `Editor CLI`（半透明遮罩），用于临时改图、刷单位、挂宝石和导出关卡配置。当前规范如下：

- 命令以 `/` 开头，例如 `/spawn`、`/set`、`/remove`；不带 `/` 的旧写法仍兼容
- 生成类命令直接使用资源 `id`，不再额外写对象类型
- `spawn <object_id>` 会自动识别 `unit id` / `gem id` / `tile id`
- 坐标统一使用 `x,y`，可选参数统一使用 `--option value`

命令总览：

```text
/help

/list units
/list gems
/list tiles

/spawn <object_id> <pos> [--team enemy|player]
/spawn-many <unit_id> <pos> <pos> ... [--team enemy|player]
/move [unit] <from_pos> <to_pos>
/remove unit <pos>
/remove gem <pos> [--slot red|blue|black] [--target unit|tile]
/set tile <pos> <tile_id>
/set stat <pos> <field> <value>
/set spawn <pos>
/export [encounter] [encounter_id]
```

含义说明：

- `list`: 查看当前可用的单位、宝石、地块 `id`
- `spawn`: 按 `id` 生成对象；单位生成到棋盘，宝石会默认优先塞单位槽，否则塞地块槽，地块则直接替换当前位置
- `spawn-many`: 批量生成同一种单位，适合快速铺怪
- `move`: 移动单位；也可写 `move unit 1,1 2,1`
- `remove unit`: 删除指定位置的单位（玩家不可删）
- `remove gem`: 删除指定位置槽位内的宝石，可用 `--slot` / `--target` 精确指定
- `set tile`: 把指定坐标替换为目标地块 `id`
- `set stat`: 修改单位属性，支持 `hp`、`max_hp`、`move_points`、`speed`、`base_attack`、`armor`、`alive`
- `set spawn`: 修改玩家出生点
- `export encounter`: 导出当前运行时战场为 encounter 配置片段

示例：

```text
spawn unit_bomb_rat 2,4 --team enemy
spawn gem_poison 2,4 --slot red --target tile
spawn tile_altar 4,4
spawn-many unit_patrol_guard 0,0 1,0 2,0 --team enemy
move 2,4 3,4
remove unit 3,4
remove gem 2,4 --slot red --target unit
set tile 4,4 tile_water
set stat 2,4 hp 12
set spawn 1,6
export encounter custom_level_001
```

对应回归脚本：

```bash
godot --headless --path . --script res://scripts/tests/hook_test.gd
```

## MVP 内容

- 8×8 棋盘、单角色、4 种怪物、6 种宝石、2 种地块
- 三色槽位：红（行为）/ 蓝（属性）/ 黑（死亡）
- 操作：移动、攻击、拔出、嵌入、触发
- 敌人意图预览、危险格高亮
- 1 场教学 + 3 场模板战斗

## 美术

原型阶段不需要专门美术。使用色块、Control UI 和高亮格子表达战场信息。

若要做更接近「游戏感」的快速 demo（可选），可用的外部素材备忘见：**[docs/demo-assets.md](./docs/demo-assets.md)**。

## 目录

```
scripts/
  battle/       # 回合流程
  data/         # 状态模型
  rules/        # 规则引擎
  services/     # Autoload 服务（存档/成就等为壳）
  ui/           # 战斗 UI
  tests/        # 无头测试
scenes/
  main/         # 主菜单
  battle/       # 战斗场景
```

设计文档见 learning-notes 仓库：`game/design/law-thief/`。

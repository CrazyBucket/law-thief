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

主场景无头启动：

```bash
godot --headless --path . --quit-after 2
```

战斗场景无头启动：

```bash
godot --headless --path . res://scenes/battle/battle_scene.tscn --quit-after 3
```

教学关冒烟测试（拔爆炸 → 嵌黑槽 → 击杀引爆）：

```bash
godot --headless --path . --script res://scripts/tests/smoke_test.gd
```

遭遇战加载测试：

```bash
godot --headless --path . --script res://scripts/tests/encounter_load_test.gd
```

## MVP 内容

- 8×8 棋盘、单角色、6 种怪物、6 种宝石、2 种地块
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

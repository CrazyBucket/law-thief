# Law Thief

窃律者 Godot MVP 项目 — 8×8 战术嫁祸战棋原型。

## 环境

- Godot 4.6+
- GDScript

## 运行

在 Godot 编辑器中打开本目录，或命令行：

```bash
godot --path /Users/tylorwu/code/law-thief
```

## 验证

主场景无头启动：

```bash
godot --headless --path /Users/tylorwu/code/law-thief --quit-after 2
```

战斗场景无头启动：

```bash
godot --headless --path /Users/tylorwu/code/law-thief res://scenes/battle/battle_scene.tscn --quit-after 3
```

教学关冒烟测试（拔爆炸 → 嵌黑槽 → 击杀引爆）：

```bash
godot --headless --path /Users/tylorwu/code/law-thief --script res://scripts/tests/smoke_test.gd
```

遭遇战加载测试：

```bash
godot --headless --path /Users/tylorwu/code/law-thief --script res://scripts/tests/encounter_load_test.gd
```

## MVP 内容

- 8×8 棋盘、单角色、6 种怪物、6 种宝石、2 种地块
- 三色槽位：红（行为）/ 蓝（属性）/ 黑（死亡）
- 操作：移动、攻击、拔出、嵌入、触发
- 敌人意图预览、危险格高亮
- 1 场教学 + 3 场模板战斗

## 美术

原型阶段不需要专门美术。使用色块、Control UI 和高亮格子表达战场信息。

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

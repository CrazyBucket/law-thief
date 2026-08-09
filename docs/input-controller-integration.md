# 键盘与手柄接入调研

调研日期：2026-08-06。当前工程声明 Godot 4.6。

## 结论

当前阶段优先使用 Godot 自带的 `InputMap`，不安装输入框架插件。战斗规则只读取动作名，
键盘、鼠标和手柄事件都挂到同一个动作上；这样加入手柄时不需要再写一套战斗调用链。

本阶段已经落地：

- `pause_menu`：`Esc` 打开战斗菜单；
- `end_turn`：物理键位 `E` 结束回合；
- 战斗菜单提供继续、设置、保存并返回，设置是菜单的二级页面；
- 二级设置直接读写现有 `SettingsService`，与主菜单设置共用持久化数据。

## 推荐接入顺序

1. **动作层**：继续把所有战斗命令放在 `InputMap`，代码只判断动作，不判断具体按键。
2. **棋盘焦点层**：为六边形/等距棋盘增加一个独立的焦点格；方向键、D-pad、左摇杆只移动焦点，
   `ui_accept` 执行与鼠标左键相同的选择，`ui_cancel` 回退一层。
3. **设备提示层**：记录最近一次输入设备，并在 HUD 上切换键盘或 Xbox / PlayStation / Switch 图标。
4. **重映射层**：监听新的 `InputEventKey` / `InputEventJoypadButton`，用 `InputMap` 替换动作事件，
   再把差异保存到 `SettingsService`。需要处理重复键、保留取消键和恢复默认值。
5. **手柄体验层**：补摇杆死区、焦点循环、热插拔、断连提示和可关闭/调强度的震动。

Godot 官方建议使用动作系统统一键盘和控制器路径；运行时重映射也由 `InputMap` 支持，
但动态修改不会自动持久化，游戏需要自行保存：

- https://docs.godotengine.org/en/stable/tutorials/inputs/inputevent.html
- https://docs.godotengine.org/en/latest/tutorials/inputs/controllers_gamepads_joysticks.html
- https://docs.godotengine.org/en/stable/classes/class_inputmap.html

Godot 4.5 起桌面端控制器输入基于 SDL 3。官方文档同时提醒要处理摇杆死区、手柄按住不产生键盘式
echo、失焦时仍可能收到手柄输入、平台差异和震动可访问性选项。

## 可用插件

插件不是必需项，但下面几类可以减少后续 UI 工作：

| 需求 | 现成方案 | 适用性 | 当前建议 |
| --- | --- | --- | --- |
| 显示键鼠/手柄提示图标 | Godot Input Prompts 2.3.0 | Godot 4.1+；含键鼠、Xbox、PlayStation、Switch 图标 | 可做原型，正式接入前先验证 4.6 与像素 UI 风格 |
| 显示并自动切换动作图标 | Action Icon | 当前商店版本面向 Godot 4.6，可按设备自动切换并在重映射后刷新 | 最适合后续 HUD 动态提示 |
| 保存键盘/手柄重映射 | Controls Remap 1.2 | 当前商店版本面向 Godot 4.6，含默认恢复与重复绑定检测 | 可以评估，但它不支持物理键码，若坚持物理键位需自研薄层 |

来源：

- https://godotengine.org/asset-library/asset/2140
- https://store.godotengine.org/asset/kobewi/action-icon/
- https://store.godotengine.org/asset/kobewi/controls-remap/

这些条目属于社区资产，不是 Godot 核心的一部分。当前项目的动作数量不多，先用原生
`InputMap + SettingsService` 成本更低；当开始制作完整“控制”设置页时，再决定是否引入
`Action Icon`，以及自研或采用 `Controls Remap`。

## 战斗手柄映射建议

建议先做一套可试玩默认值，再开放重映射：

| 动作 | 键盘 | 手柄 |
| --- | --- | --- |
| 打开战斗菜单 | Esc | Start / Options |
| 移动棋盘焦点 | 方向键 / WASD | D-pad / 左摇杆 |
| 确认格子或目标 | Enter / Space | A / Cross |
| 返回一层 | Esc | B / Circle |
| 结束回合 | E | Y / Triangle（需二次确认或长按保护） |
| 切换战斗命令 | 数字键或 Q/R | 肩键 |

“结束回合”在手柄上应避免放到容易误触且没有保护的主确认键。完整手柄接入前，HUD 不应显示
尚未生效的手柄提示。

# UI 视觉回归

视觉回归流程会在三个物理分辨率下捕获两个固定 UI 场景：

- 战斗 HUD：同时显示移动、攻击范围、危险区、爆炸范围和敌方意图路线；
- 冒险地图：使用固定 seed，悬停一条可选路线并展开房间卡；
- 每个场景分别生成 1280×720、1600×900、2048×1152 截图。

截图必须使用可读 renderer。捕获命令不会添加 `--headless`，生成六张截图后自动退出。headless 捕获会明确失败，不会被记作“跳过但成功”。

## 捕获与对比

PowerShell：

```powershell
.\tools\ui_visual_regression.cmd capture before
# 修改 UI。
.\tools\ui_visual_regression.cmd capture after
.\tools\ui_visual_regression.cmd compare before after
```

Bash/WSL：

```bash
./tools/ui_visual_regression capture before
# 修改 UI。
./tools/ui_visual_regression capture after
./tools/ui_visual_regression compare before after
```

产物写入 `artifacts/verify/ui-visual/`：

```text
before/                         六张 PNG + capture report.json
after/                          六张 PNG + capture report.json
compare-before-vs-after/        六张增强 diff PNG + report.json
```

每份捕获报告记录 renderer、请求的图像尺寸、逻辑布局视口、SHA-256 和布局违规。以下情况会令捕获失败：关键 HUD 控件离开视口、可见按钮内容超过分配尺寸、图像缺失或 Godot 日志出现运行时错误。

对比报告记录精确匹配状态、变化像素数量与占比、归一化 RGB 平均差、最大通道差异和 diff 图片路径。动画 shader 与 GPU 插值可能产生少量非零差异，因此应同时检查截图、diff 和指标，不把任意一个变化像素直接视为回归。

生成的截图属于评审产物，不是入库视觉素材。交付较大的 UI 改动时，应附上相关 before/after 截图和 comparison report。

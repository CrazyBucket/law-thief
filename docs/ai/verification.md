# AI 验证

## 命令

```bash
./tools/context 爆炸
./tools/snapshot --gems gem_explosion,gem_explosion,gem_explosion
./tools/coverage
./tools/verify changed
./tools/verify fast
./tools/verify all
```

在 Windows PowerShell 中，建议使用 `.cmd` 包装器：

```powershell
.\tools\context.cmd explosion
.\tools\snapshot.cmd --gems gem_explosion,gem_explosion,gem_explosion
.\tools\coverage.cmd
.\tools\verify.cmd changed
```

不要输入 `bash .\tools\verify changed`；PowerShell 会将反斜杠当作转义符传递给 bash。虽然有针对该错误的兼容性垫片，但 `.cmd` 包装器是官方支持的 Windows 入口。

`tools/verify` 会自动从常见的 macOS 和 Windows 可执行文件名中检测 Godot。仅当自动检测无法找到编辑器时，才设置 `GODOT=/path/to/godot`。验证器仍会显式设置 `LAW_THIEF_SAVE_ROOT=artifacts/verify/userdata/...`；此外，所有通过 `--script` 直接启动的 `scripts/tests/` 与 `scripts/tools/` 脚本也会自动获得独立沙箱。运行存档、历史记录和设置文件共享该沙箱，不会触及正常玩家数据；正常游戏启动仍使用默认 `user://` 路径。

`snapshot.json` 旨在作为最快的调试产物。它记录了确定性操作前后的状态、紧凑的差异、事件、不变量失败以及权威设计文档路径。

`semantic-coverage.json` 是信任边界。只有当设计文档中的独立期望存在于 `tests/contracts/gem_semantics.json` 中，并通过 `gem_semantic_contract_test.gd` 的验证时，宝石/槽位/等级才会被标记为 `VERIFIED`。其他所有内容都会报告为 `UNVERIFIED`。

## 添加聚焦测试

使用 `ScenarioBuilder` 创建确定性状态，执行公共规则入口点，然后使用 `StateSnapshot.capture()` 和 `StateDiff.between()` 来解释结果。避免添加另一份私有辅助函数副本，如 `_spawn_guard` 或 `_mount_gems`。

## 语义

该仓库有意将实现和现有测试视为当前行为的证据，而非最终的语义权威。位于 `/Users/jinhuiwu/code/learning-notes/game/design/law-thief/详细设计` 下的详细设计文档默认优先。任何冲突都必须被揭露，而非被静默地归一化。

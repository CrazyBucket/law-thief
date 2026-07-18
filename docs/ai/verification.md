# AI 验证

## 命令

```bash
./tools/context 爆炸
./tools/snapshot --gems gem_explosion,gem_explosion,gem_explosion
./tools/verify test explosion_test
./tools/verify changed --list
./tools/verify changed
./tools/coverage
```

执行层级：

| 入口 | 用途 | 运行时机 |
| --- | --- | --- |
| `verify test TEST_NAME` | 通过统一日志和存档沙箱运行指定测试 | 修改后的默认选择 |
| `verify changed` | 根据实际改动合并相关领域测试 | 多个相关文件改动时 |
| `verify fast` | 共享战斗、宝石、冒险和 UI 的快速回归 | 有无法被聚焦测试覆盖的明确风险时 |
| `verify all` | 所有自动测试，不含手动压力探针 | CI 或用户明确要求 |
| `verify manual` | 压力、调试和编辑器探针 | 明确需要时 |

不要在修改前例行跑测试。修改后先选择最小的相关测试；无参数执行 `verify` 等价于 `verify changed`，不会默认启动 `fast`。`verify changed --list` 只显示变更文件和将执行的测试，不启动 Godot。`verify` 结束时已经执行语义覆盖检查，因此常规流程不需要再单独运行 `coverage`；单独的 `coverage` 仅用于只审计宝石语义覆盖率。

在 Windows PowerShell 中，建议使用 `.cmd` 包装器：

```powershell
.\tools\context.cmd explosion
.\tools\snapshot.cmd --gems gem_explosion,gem_explosion,gem_explosion
.\tools\verify.cmd test explosion_test
.\tools\verify.cmd changed --list
.\tools\verify.cmd changed
```

不要输入 `bash .\tools\verify changed`；PowerShell 会将反斜杠当作转义符传递给 bash。虽然有针对该错误的兼容性垫片，但 `.cmd` 包装器是官方支持的 Windows 入口。

`tools/verify` 会自动从常见的 macOS 和 Windows 可执行文件名中检测 Godot。仅当自动检测无法找到编辑器时，才设置 `GODOT=/path/to/godot`。Windows 的变更探测会忽略 WSL Git 看到的纯 CRLF/LF 差异，避免把整棵工作区误判为已修改。生成翻译只在缺失或源 CSV/生成器更新时重建。验证器仍会显式设置 `LAW_THIEF_SAVE_ROOT=artifacts/verify/userdata/...`；此外，所有通过 `--script` 直接启动的 `scripts/tests/` 与 `scripts/tools/` 脚本也会自动获得独立沙箱。运行存档、历史记录和设置文件共享该沙箱，不会触及正常玩家数据；正常游戏启动仍使用默认 `user://` 路径。

每次执行都会在 `artifacts/verify/verify.log` 记录选择数量、变更文件和单项耗时，并在 `report.json` 写入 `selected`、通过数、失败数和总耗时。

`snapshot.json` 旨在作为最快的调试产物。它记录了确定性操作前后的状态、紧凑的差异、事件、不变量失败以及权威设计文档路径。

`semantic-coverage.json` 是信任边界。只有当设计文档中的独立期望存在于 `tests/contracts/gem_semantics.json` 中，并通过 `gem_semantic_contract_test.gd` 的验证时，宝石/槽位/等级才会被标记为 `VERIFIED`。其他所有内容都会报告为 `UNVERIFIED`。

## 添加聚焦测试

使用 `ScenarioBuilder` 创建确定性状态，执行公共规则入口点，然后使用 `StateSnapshot.capture()` 和 `StateDiff.between()` 来解释结果。避免添加另一份私有辅助函数副本，如 `_spawn_guard` 或 `_mount_gems`。

## 语义

该仓库有意将实现和现有测试视为当前行为的证据，而非最终的语义权威。位于 `/Users/jinhuiwu/code/learning-notes/game/design/law-thief/详细设计` 下的详细设计文档默认优先。任何冲突都必须被揭露，而非被静默地归一化。

# 事件动画系统：结算顺序与批处理指南

## 架构概览

战斗规则层（`scripts/rules/`）不直接播放动画，只产出 **事件数组（`Array[Dictionary]`）**。UI 层（`battle_scene.gd`）的 `_play_presented_events` 函数逐条消费事件，通过 `await` 控制时序。

```
规则层  →  events[]  →  _play_presented_events  →  逐条/批量 await
```

每条事件的基本结构：

```gdscript
{"type": "damage", "pos": Vector2i, "damage": int, ...}
{"type": "move_step", "uid": String, "from": Vector2i, "to": Vector2i}
{"type": "explode", "pos": Vector2i, ...}
{"type": "projectile", "from": Vector2i, "to": Vector2i}
```

---

## 何时需要批处理

**批处理的判断标准：这些事件在现实中是否同时发生？**

| 场景 | 是否批处理 | 原因 |
|------|-----------|------|
| 多个弹射物同时飞出 | ✅ 批处理 | 分裂射击各弹同时在空中 |
| 多个单位同时被击退 | ✅ 批处理 | 爆炸冲击波同时作用于所有人 |
| 爆炸波及的所有伤害 | ✅ 批处理 | 同一爆炸瞬间伤害所有目标 |
| A 攻击 B、B 受伤后反弹伤害给 C | ❌ 顺序 | 存在因果依赖，必须先有命中才有反弹 |
| 单位移动的每一步 | ❌ 顺序（除非并排跑） | 每步后面可能触发地块效果 |
| 中毒 tick 伤害 | ❌ 顺序 | 不同单位 tick 时机不同 |

**核心原则**：无因果依赖、来源相同、发生时刻相同 → 批处理。

---

## 规则层：控制事件顺序

事件顺序由规则层代码决定，UI 层只负责消费。**在规则层就要把"同时发生的事"排在一起。**

### 常见问题：交替输出

❌ 错误写法（每个目标各自输出 damage + move，导致 UI 逐个结算）：
```gdscript
for unit in targets:
    events.append(damage_event(unit))
    Displacement.knockback(state, unit, center, 1, source, events)  # 在此处追加 move_step
```

✅ 正确写法（先收集所有 knockback 目标，统一在所有 damage 后追加）：
```gdscript
var kb_targets: Array = []
for unit in targets:
    events.append(damage_event(unit))
    if unit.alive:
        kb_targets.append(unit)
# 所有 damage 输出完毕后，统一输出 move_step
for unit in kb_targets:
    Displacement.knockback(state, unit, center, 1, source, events)
```

这样产出的事件流：
```
damage(A) → damage(B) → damage(C) → move_step(A) → move_step(B) → move_step(C)
```

---

## UI 层：批处理实现方式

`_play_presented_events` 使用 `_collect_consecutive_events(events, i, types)` 收集从位置 `i` 开始、类型在 `types` 列表内的连续事件，返回批次并推进 `i`。

### 已有的批处理模式

**1. 投射物齐射（`projectile`）**
```gdscript
if ev_type in ["projectile", "projectile_deflect"]:
    var batch := _collect_consecutive_events(events, i, ["projectile", "projectile_deflect"])
    i += batch.size()
    await _play_projectile_volley(batch)
```

**2. 并行移动（`move_step`，多单位同向）**
```gdscript
if ev_type == "move_step":
    var batch := _collect_consecutive_events(events, i, ["move_step"])
    if _move_batch_is_parallel(batch):
        _board.animate_moves_parallel(batch)
        await _board.animation_finished
```

**3. 爆炸（`explode` + 后续 `damage` + `move_step`）**
```gdscript
if ev_type == "explode":
    _board.play_explosion(pos)
    # 同帧弹出所有 damage
    var dmg_batch := _collect_consecutive_events(events, i, ["damage"])
    for dmg_ev in dmg_batch: _board.play_damage_effect(...)
    # 并行播放所有 knockback
    var kb_batch := _collect_consecutive_events(events, i, ["move_step"])
    if not kb_batch.is_empty():
        _board.animate_moves_parallel(kb_batch)
        await _board.animation_finished
    await timer(0.75)
```

### 新增批处理模式的步骤

1. **规则层**：确保同时发生的事件类型连续排列（参考上一节）
2. **UI 层**：在 `_play_presented_events` 的 `while` 循环顶部，用 `if ev_type == "..."` 拦截，调用 `_collect_consecutive_events` 收集批次，并行处理后 `continue`
3. 批处理块必须在通用 fallback（`_prime_event_state` → `await _play_anim_event` → `_apply_event_state`）**之前**

---

## `_prime_event_state` / `_apply_event_state` 的作用

| 函数 | 时机 | 作用 |
|------|------|------|
| `_prime_event_state(ev)` | 动画**开始前** | 把事件涉及的状态变化预写入 `_display_state`（表现层快照），使动画读到正确的起始位置 |
| `_apply_event_state(ev)` | 动画**结束后** | 把事件的最终结果同步到 `_display_state`，驱动棋盘重绘 |

批处理时，所有事件的 `_prime_event_state` 应在动画启动**前**全部调用，`_apply_event_state` 应在动画**结束后**全部调用。

---

## 常见陷阱

- **`_collect_consecutive_events` 只收连续的**：两个 `damage` 中间插了一个 `move_step`，就只收到第一个 `damage`。解决方法：规则层保证同类事件紧邻。
- **`animation_finished` 信号必须等待**：调用 `animate_moves_parallel` 后要 `await _board.animation_finished`，否则下一帧事件会在动画未完成时开始，导致位置跳变。
- **死亡结算顺序**：`CombatRules.begin_deferred_death_hooks` / `end_deferred_death_hooks` 会把死亡触发的连锁事件攒到最后统一处理；死亡钩子产出的事件会追加在主事件流末尾，天然是顺序的，不需要批处理。

# JSON 事件系统

事件内容统一定义在 `resources/adventure/event_defs.json`。地图只保存 `event_id`，运行时由
`EventService` 读取事件、恢复当前节点、判断选项条件并执行选择。当前节点和选择历史保存在房间
快照中，因此读档后会回到同一段事件，而不会重复发放前面节点的奖励。

## 基本结构

```json
{
  "event_example": {
    "entry": "start",
    "nodes": {
      "start": {
        "title": "事件标题",
        "body": "事件正文",
        "options": [
          {
            "id": "take_gold",
            "label": "获得 {amount_ref:event_example_gold} 金币",
            "conditions": [],
            "calls": [
              {
                "function": "grant_resource",
                "args": {
                  "resource_id": "gold",
                  "amount_ref": "event_example_gold"
                }
              }
            ],
            "next": "gold_taken"
          }
        ]
      },
      "gold_taken": {
        "title": "结果标题",
        "body": "结果正文。",
        "options": [
          {
            "id": "leave",
            "label": "离开",
            "conditions": [],
            "calls": [],
            "finish": true
          }
        ]
      }
    }
  }
}
```

- `entry` 是首次进入事件时显示的节点。
- `next` 跳到另一个节点；`finish: true` 结束并结算房间。每个选项必须二选一。
- `conditions` 决定选项是否可用。当前支持金币、生命比例、遗物、手持宝石和章节条件。
- `calls` 按顺序执行受控函数。函数名经过配置校验和白名单分派，不允许调用任意 Godot 方法。
- 所有可调数值应写进 `economy_config.json` 的 `amount_refs`，文案用
  `{amount_ref:引用名}` 显示同一个数值，避免效果与描述不一致。

## 可调用函数

`grant_resource`、`spend_resource`、`heal_player`、`heal_player_percent`、`damage_player`、
`grant_relic`、`grant_gem`、`add_adventure_rule`、`remove_adventure_rule`。

旧的单节点 `title/body/options/effects` 数据仍可读取，便于存档和内容渐进迁移；新事件应使用节点式
`entry/nodes/calls` 格式。

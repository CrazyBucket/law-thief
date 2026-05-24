class_name TileEffects
extends RefCounted
## 地块槽位效果系统
## 祭坛（红槽）：嵌入宝石后立即触发一次全场效果
## 机关柱（蓝槽）：嵌入宝石后施加持续光环（每回合生效）


## 祭坛激活：嵌入宝石时立即触发一次强力效果
static func on_altar_activated(state: GameState, tile: TileState, gem: GemState) -> void:
	state.log("祭坛激活！宝石 %s 释放能量" % gem.gem_id)
	match gem.gem_id:
		Constants.GEM_EXPLOSION:
			# 全场爆炸：对所有敌人造成 1 点伤害
			for unit in state.units.values():
				if unit.alive and unit.team == Constants.TEAM_ENEMY:
					CombatRules.apply_damage(state, unit, 1, "", "altar_explosion")
		Constants.GEM_POISON:
			# 全场毒雾：在祭坛周围 2 格制造毒雾
			for cell in BoardUtils.cells_in_radius(tile.pos, 2):
				TileRules.create_poison_fog(state, cell)
		Constants.GEM_GRAVITY:
			# 引力漩涡：将所有敌人拉向祭坛 1 格
			GemEffects.pull_around(state, tile.pos, 4, 1)
		Constants.GEM_HEAVY_ARMOR:
			# 铁壁祝福：给玩家加 4 点护甲
			var player := state.get_player()
			if player != null:
				StatusRules.apply_armor(state, player, 4, 3)
		Constants.GEM_CONDUCTIVE:
			# 电磁脉冲：对所有水洼上的单位造成 2 点伤害
			for key in state.tiles.keys():
				var t: TileState = state.tiles[key]
				if t.tile_id == Constants.TILE_WATER:
					var unit := state.get_unit_at(t.pos)
					if unit != null:
						CombatRules.apply_damage(state, unit, 2, "", "altar_emp")
		Constants.GEM_FRAGILE:
			# 碎裂波：对所有敌人造成 2 点伤害，但宝石碎裂
			for unit in state.units.values():
				if unit.alive and unit.team == Constants.TEAM_ENEMY:
					CombatRules.apply_damage(state, unit, 2, "", "altar_shatter")
			# 宝石碎裂消失
			for s in tile.slots:
				if s.gem_uid == gem.uid:
					s.gem_uid = ""
					break
			state.gems.erase(gem.uid)
			state.log("易碎宝石在祭坛中碎裂！")


## 机关柱激活：嵌入宝石后施加持续光环效果
static func on_pillar_activated(state: GameState, tile: TileState, gem: GemState) -> void:
	state.log("机关柱激活！宝石 %s 产生光环" % gem.gem_id)
	# 给地块添加一个 modifier 标记光环类型，每回合 tick 时生效
	tile.add_modifier("pillar_aura", 99, {"gem_id": gem.gem_id})


## 机关柱每回合 tick：根据嵌入的宝石产生持续效果
static func tick_pillar_aura(state: GameState, tile: TileState) -> void:
	for modifier in tile.modifiers:
		if modifier.get("type", "") != "pillar_aura":
			continue
		var gem_id: String = modifier.get("payload", {}).get("gem_id", "")
		match gem_id:
			Constants.GEM_HEAVY_ARMOR:
				# 每回合给范围内友方加 1 点护甲
				var player := state.get_player()
				if player != null and BoardUtils.manhattan(player.pos, tile.pos) <= 2:
					StatusRules.apply_armor(state, player, 1, 1)
			Constants.GEM_POISON:
				# 每回合对范围内敌人施加毒
				for unit in state.units.values():
					if unit.alive and unit.team == Constants.TEAM_ENEMY and BoardUtils.manhattan(unit.pos, tile.pos) <= 2:
						StatusRules.apply_poison(state, unit)
			Constants.GEM_EXPLOSION:
				# 每回合对范围内敌人造成 1 点伤害
				for unit in state.units.values():
					if unit.alive and unit.team == Constants.TEAM_ENEMY and BoardUtils.manhattan(unit.pos, tile.pos) <= 1:
						CombatRules.apply_damage(state, unit, 1, "", "pillar_burn")
			Constants.GEM_GRAVITY:
				# 每回合拉拽范围内敌人
				for unit in state.units.values():
					if unit.alive and unit.team == Constants.TEAM_ENEMY and BoardUtils.chebyshev(tile.pos, unit.pos) <= 2:
						GemEffects.pull_around(state, tile.pos, 2, 1)
						break  # pull_around 已经处理所有范围内单位
			Constants.GEM_CONDUCTIVE:
				# 每回合电击水洼上的单位
				for key in state.tiles.keys():
					var t: TileState = state.tiles[key]
					if t.tile_id == Constants.TILE_WATER and BoardUtils.manhattan(t.pos, tile.pos) <= 3:
						var unit := state.get_unit_at(t.pos)
						if unit != null:
							CombatRules.apply_damage(state, unit, 1, "", "pillar_shock")


## 手动触发地块槽位中的宝石
static func on_tile_trigger(state: GameState, tile: TileState, gem: GemState) -> void:
	state.log("触发 %s 地块的 %s" % [tile.tile_id, gem.gem_id])
	match tile.tile_id:
		Constants.TILE_ALTAR:
			on_altar_activated(state, tile, gem)
		Constants.TILE_PILLAR:
			# 触发机关柱 = 立即释放一次光环效果
			tick_pillar_aura(state, tile)

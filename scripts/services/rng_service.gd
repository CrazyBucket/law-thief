extends Node

const _HASH_OFFSET := 1469598103934665603
const _HASH_PRIME := 1099511628211

var _master_seed: int = 0
var _active_seed: int = 0
var _active_context: String = ""
var _domain_counters: Dictionary = {}
var _visual_rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_visual_rng.randomize()


## 开启一局游戏，master seed 由外部确定性传入（存档/回放必须提供固定值）
func start_run(seed_value: int) -> void:
	_master_seed = _sanitize_seed(seed_value)
	_reset_active_context(_master_seed, "run")
	_visual_rng.randomize()


## 兼容旧调用（单场战斗直接启动时使用）；新路径请用 start_run + derive 系列
func set_seed(seed_value: int) -> void:
	if _master_seed == 0:
		_master_seed = _sanitize_seed(seed_value)
	_reset_active_context(_sanitize_seed(seed_value), "adhoc")


## 切换活跃上下文并重置 domain 计步（进入房间、进入战斗时调用）
func reset_state(seed_value: int, context_key: String) -> void:
	var sanitized_seed := _sanitize_seed(seed_value)
	if _master_seed == 0:
		_master_seed = sanitized_seed
	_reset_active_context(sanitized_seed, context_key)


func get_master_seed() -> int:
	return _master_seed


func get_seed() -> int:
	return _active_seed


func get_step() -> int:
	var total := 0
	for value in _domain_counters.values():
		total += int(value)
	return total


func get_active_context() -> String:
	return _active_context


func get_domain_steps() -> Dictionary:
	return _domain_counters.duplicate(true)


# ─── 种子衍生 ────────────────────────────────────────────────────────────────

## 从 master seed + 任意部件衍生确定性子种子（SL 安全：相同入参永远得相同结果）
func derive_seed(parts: Array) -> int:
	_ensure_master_seed()
	var payload: Array = [_master_seed]
	payload.append_array(parts)
	return _hash_parts(payload)


## 衍生房间种子：room_type 如 "NORMAL_COMBAT"，room_id 如坐标字符串 "3_2"
func derive_room_seed(room_type: String, room_id: String) -> int:
	return derive_seed(["room", room_type, room_id])


## 衍生战斗种子（进入战斗时调用，SL 重进后传入相同参数即可复现）
func derive_combat_seed(encounter_id: String, room_id: String = "") -> int:
	return derive_seed(["combat", encounter_id, room_id])


## 衍生商店种子（地图节点固定，进入/重进商店均产生相同货架）
func derive_shop_seed(room_id: String) -> int:
	return derive_seed(["shop", room_id])


## 衍生遗物奖励候选种子（用于战斗后奖励三选一）
func derive_relic_offer_seed(room_id: String, offer_index: int = 0) -> int:
	return derive_seed(["relic_offer", room_id, offer_index])


## 衍生宝石奖励候选种子
func derive_gem_offer_seed(room_id: String, offer_index: int = 0) -> int:
	return derive_seed(["gem_offer", room_id, offer_index])


# ─── Scoped RNG ──────────────────────────────────────────────────────────────

## 创建一个隔离的有状态 RNG 实例（商店/战斗内各自持有，互不污染全局 domain counter）
## seed_value 应来自 derive_*seed 系列，保证 SL 安全
func create_scoped_rng(seed_value: int) -> ScopedRng:
	return ScopedRng.new(seed_value, _HASH_OFFSET, _HASH_PRIME)


## 用 master seed 和 salt 创建任意确定性 RNG（无状态，每次从 0 步开始）
func create_rng(seed_value: int, salt: String = "") -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = _hash_parts([_sanitize_seed(seed_value), salt])
	return rng


# ─── 全局有状态 roll（战斗规则共用流，domain 隔离步进） ──────────────────────

func roll_int(domain: String, min_value: int, max_value: int) -> int:
	_ensure_active_seed()
	var rng := _rng_for_roll(domain)
	return rng.randi_range(min_value, max_value)


func roll_float(domain: String, min_value: float = 0.0, max_value: float = 1.0) -> float:
	_ensure_active_seed()
	var rng := _rng_for_roll(domain)
	return rng.randf_range(min_value, max_value)


func chance(domain: String, probability: float) -> bool:
	if probability <= 0.0:
		return false
	if probability >= 1.0:
		return true
	return roll_float(domain) < probability


func pick(domain: String, items: Array):
	if items.is_empty():
		return null
	var index := roll_int(domain, 0, items.size() - 1)
	return items[index]


## 加权随机选取，weights 与 items 等长，每项为非负 float
## 返回选中 item；items 为空或权重全零时返回 null
func weighted_pick(domain: String, items: Array, weights: Array):
	if items.is_empty():
		return null
	var total := 0.0
	for w in weights:
		total += maxf(0.0, float(w))
	if total <= 0.0:
		return pick(domain, items)
	var roll := roll_float(domain, 0.0, total)
	var cumulative := 0.0
	for i in range(items.size()):
		cumulative += maxf(0.0, float(weights[i]))
		if roll < cumulative:
			return items[i]
	return items.back()


## 加权随机，返回 {item, index}；无候选时返回 null
func weighted_pick_with_index(domain: String, items: Array, weights: Array) -> Variant:
	if items.is_empty():
		return null
	var total := 0.0
	for w in weights:
		total += maxf(0.0, float(w))
	if total <= 0.0:
		var idx := roll_int(domain, 0, items.size() - 1)
		return {"item": items[idx], "index": idx}
	var roll := roll_float(domain, 0.0, total)
	var cumulative := 0.0
	for i in range(items.size()):
		cumulative += maxf(0.0, float(weights[i]))
		if roll < cumulative:
			return {"item": items[i], "index": i}
	return {"item": items.back(), "index": items.size() - 1}


func shuffle_in_place(domain: String, items: Array) -> void:
	if items.size() <= 1:
		return
	for i in range(items.size() - 1, 0, -1):
		var swap_index := roll_int("%s#%d" % [domain, i], 0, i)
		var temp = items[i]
		items[i] = items[swap_index]
		items[swap_index] = temp


func shuffle_copy(domain: String, items: Array) -> Array:
	var copy := items.duplicate(true)
	shuffle_in_place(domain, copy)
	return copy


# ─── 视觉 RNG（UI/特效专用，与游戏逻辑完全隔离） ─────────────────────────────

func visual_randf() -> float:
	return _visual_rng.randf()


func visual_randf_range(min_value: float, max_value: float) -> float:
	return _visual_rng.randf_range(min_value, max_value)


func visual_randi_range(min_value: int, max_value: int) -> int:
	return _visual_rng.randi_range(min_value, max_value)


# ─── 存档支持 ────────────────────────────────────────────────────────────────

func export_state() -> Dictionary:
	return {
		"master_seed": _master_seed,
		"active_seed": _active_seed,
		"active_context": _active_context,
		"domain_counters": _domain_counters.duplicate(true),
	}


func import_state(snapshot: Dictionary) -> void:
	_master_seed = _sanitize_seed(int(snapshot.get("master_seed", 0)))
	_active_seed = _sanitize_seed(int(snapshot.get("active_seed", _master_seed)))
	_active_context = str(snapshot.get("active_context", "restored"))
	_domain_counters = {}
	var raw_counters: Variant = snapshot.get("domain_counters", {})
	if raw_counters is Dictionary:
		for key in raw_counters.keys():
			_domain_counters[str(key)] = int(raw_counters[key])


# ─── 内部 ────────────────────────────────────────────────────────────────────

func _rng_for_roll(domain: String) -> RandomNumberGenerator:
	var roll_index := _next_domain_step(domain)
	var rng := RandomNumberGenerator.new()
	rng.seed = _hash_parts([_active_seed, _active_context, domain, roll_index])
	return rng


func _next_domain_step(domain: String) -> int:
	var key := str(domain)
	var step := int(_domain_counters.get(key, 0))
	_domain_counters[key] = step + 1
	return step


func _reset_active_context(seed_value: int, context_key: String) -> void:
	_active_seed = _sanitize_seed(seed_value)
	_active_context = context_key
	_domain_counters.clear()


func _ensure_master_seed() -> void:
	if _master_seed != 0:
		return
	_master_seed = _sanitize_seed(int(Time.get_unix_time_from_system()))


func _ensure_active_seed() -> void:
	if _active_seed != 0:
		return
	_ensure_master_seed()
	_reset_active_context(_master_seed, "implicit")


func _hash_parts(parts: Array) -> int:
	var hash_value: int = _HASH_OFFSET
	for part in parts:
		hash_value = _hash_text(hash_value, str(part))
		hash_value = _hash_text(hash_value, "|")
	if hash_value < 0:
		hash_value = -hash_value
	return _sanitize_seed(hash_value)


func _hash_text(seed_value: int, text: String) -> int:
	var hash_value := seed_value
	for i in range(text.length()):
		hash_value = int((hash_value ^ text.unicode_at(i)) * _HASH_PRIME)
	return hash_value


func _sanitize_seed(seed_value: int) -> int:
	var value := seed_value
	if value < 0:
		value = -value
	if value == 0:
		value = 1
	return value


# ─── ScopedRng：隔离有状态 RNG，不共享全局 domain counter ─────────────────────

## 持有自己的步进计数器，商店/战斗 SL 安全的随机流
## 典型用法：
##   var shop_rng = RngService.create_scoped_rng(RngService.derive_shop_seed(room_id))
##   shop_rng.roll_int(0, 9)  # 同种子+同操作序列 = 同结果
class ScopedRng:
	var _seed: int = 0
	var _step: int = 0
	var _hash_offset: int = 0
	var _hash_prime: int = 0

	func _init(seed_value: int, hash_offset: int, hash_prime: int) -> void:
		_seed = seed_value
		_step = 0
		_hash_offset = hash_offset
		_hash_prime = hash_prime

	func roll_int(min_value: int, max_value: int) -> int:
		var rng := _make_rng()
		return rng.randi_range(min_value, max_value)

	func roll_float(min_value: float = 0.0, max_value: float = 1.0) -> float:
		var rng := _make_rng()
		return rng.randf_range(min_value, max_value)

	func chance(probability: float) -> bool:
		if probability <= 0.0:
			return false
		if probability >= 1.0:
			return true
		return roll_float() < probability

	func pick(items: Array):
		if items.is_empty():
			return null
		return items[roll_int(0, items.size() - 1)]

	func weighted_pick(items: Array, weights: Array):
		if items.is_empty():
			return null
		var total := 0.0
		for w in weights:
			total += maxf(0.0, float(w))
		if total <= 0.0:
			return pick(items)
		var roll := roll_float(0.0, total)
		var cumulative := 0.0
		for i in range(items.size()):
			cumulative += maxf(0.0, float(weights[i]))
			if roll < cumulative:
				return items[i]
		return items.back()

	func get_step() -> int:
		return _step

	## 重置步进至起点（SL 重进时调用，保证序列一致性）
	func reset() -> void:
		_step = 0

	func _make_rng() -> RandomNumberGenerator:
		var rng := RandomNumberGenerator.new()
		var hash_value: int = _hash_offset
		for part in [_seed, _step]:
			for ch in str(part):
				hash_value = int((hash_value ^ ch.unicode_at(0)) * _hash_prime)
			hash_value = int((hash_value ^ int("|".unicode_at(0))) * _hash_prime)
		if hash_value < 0:
			hash_value = -hash_value
		if hash_value == 0:
			hash_value = 1
		rng.seed = hash_value
		_step += 1
		return rng

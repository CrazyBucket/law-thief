extends SceneTree


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Shop Service Test ===")
	var adventure_service: Node = root.get_node("AdventureService")
	var run_service: Node = root.get_node("RunService")
	var economy_service: Node = root.get_node("EconomyService")
	var shop_service: Node = root.get_node("ShopService")
	var room_flow_service: Node = root.get_node("RoomFlowService")
	adventure_service.start_new_run(20260610)
	adventure_service.current_pos = Vector2i.ZERO
	adventure_service.pending_room_type = "SHOP"
	adventure_service.pending_room_label = "商店"
	var node = adventure_service.get_current_node()
	assert(node != null, "current node should exist")
	node.room_type = "SHOP"
	economy_service.grant("gold", 100, "test_reward", {"transaction_id": "shop_seed_gold"})
	var room_id: String = str(adventure_service.current_room_id())
	var room_view: Dictionary = room_flow_service.enter_room(room_id)
	var shop_view: Dictionary = room_view.get("payload", {}).get("shop", {})
	var offers: Array = shop_view.get("offers", [])
	assert(offers.size() >= 1, "shop should offer at least one item")
	var offer: Dictionary = offers[0]
	var offer_id: String = str(offer.get("offer_id", ""))
	var before_gold: int = int(economy_service.get_balance("gold"))
	var purchase: Dictionary = room_flow_service.submit_room_command(room_id, {
		"action": "purchase",
		"offer_id": offer_id,
	})
	assert(purchase.get("ok", false), "purchase should succeed")
	assert(str(purchase.get("state", "")) == "AWAITING_DECISION", "shop should stay open after purchase")
	assert(economy_service.get_balance("gold") < before_gold, "purchase should spend gold")
	var after_first: int = int(economy_service.get_balance("gold"))
	var purchase_again: Dictionary = room_flow_service.submit_room_command(room_id, {
		"action": "purchase",
		"offer_id": offer_id,
	})
	assert(purchase_again.get("ok", false), "repeat same purchase should replay")
	assert(economy_service.get_balance("gold") == after_first, "repeat same purchase should not spend twice")
	var refreshed_shop: Dictionary = shop_service.get_shop_view(room_id)
	var refreshed_offers: Array = refreshed_shop.get("offers", [])
	var sold_out: bool = false
	for refreshed_offer in refreshed_offers:
		if refreshed_offer is Dictionary and str(refreshed_offer.get("offer_id", "")) == offer_id:
			sold_out = bool(refreshed_offer.get("sold_out", false))
	assert(sold_out, "purchased offer should be sold out")
	run_service.end_run()
	print("SHOP_SERVICE_TEST_PASS")
	quit()

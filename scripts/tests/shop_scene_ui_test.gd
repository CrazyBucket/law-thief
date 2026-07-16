extends SceneTree


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var adventure_service: Node = root.get_node("AdventureService")
	var economy_service: Node = root.get_node("EconomyService")
	var run_service: Node = root.get_node("RunService")
	adventure_service.start_new_run(20260716)
	adventure_service.current_pos = Vector2i.ZERO
	adventure_service.pending_room_type = "SHOP"
	adventure_service.pending_room_label = "商店"
	var map_node = adventure_service.get_current_node()
	assert(map_node != null, "shop UI test needs a current map node")
	map_node.room_type = "SHOP"
	economy_service.grant("gold", 100, "test_reward", {"transaction_id": "shop_ui_seed_gold"})

	var packed := load("res://scenes/adventure/shop_scene.tscn") as PackedScene
	assert(packed != null, "dedicated shop scene should load")
	var shop := packed.instantiate()
	root.add_child(shop)
	await process_frame

	var portrait := shop.get_node("SafeArea/Layout/Main/InfoRail/InfoVBox/PortraitFrame/MerchantPortrait") as TextureRect
	assert(portrait.texture == null, "merchant portrait slot should stay empty until approved art exists")
	assert(not portrait.get_parent().visible, "empty portrait space should collapse instead of leaving a black hole")
	var gem_offers := shop.get_node("SafeArea/Layout/Main/CatalogFrame/CatalogVBox/GemShelf/GemVBox/GemOffers") as GridContainer
	assert(gem_offers.get_child_count() >= 1, "shop should render gem cards")
	assert(gem_offers.get_child_count() >= 8, "unified shelf should render four gems and four relics without empty category slots")
	var detail_icon := shop.get_node("SafeArea/Layout/Main/InfoRail/InfoVBox/DetailPanel/DetailVBox/DetailIconFrame/DetailIcon") as TextureRect
	assert(detail_icon.texture != null, "selected offer should also show a large detail icon")

	var purchasable_card: PanelContainer = null
	var purchasable_button: Button = null
	var relic_seen := false
	for child in gem_offers.get_children():
		if not child is PanelContainer:
			continue
		if str(child.get_meta("item_type", "")) == "relic":
			relic_seen = true
		var icon := child.find_child("Icon", true, false) as TextureRect
		var button := child.find_child("BuyButton", true, false) as Button
		assert(icon != null and icon.texture != null, "every item card should show an icon")
		assert(button != null and button.icon != null, "every item card should show a coin icon beside its price")
		assert(button.text.is_valid_int(), "available item cards should keep the numeric price visible")
		if purchasable_button == null and not button.disabled:
			purchasable_card = child as PanelContainer
			purchasable_button = button
	assert(relic_seen, "unified shelf should include relic offers")
	assert(purchasable_button != null, "funded shop should expose a purchasable card")
	var offer_id := str(purchasable_card.get_meta("offer_id", ""))
	var before_gold: int = int(economy_service.get_balance("gold"))
	var purchase_fx := shop.get_node("PurchaseFx") as Control
	purchasable_button.emit_signal("pressed")
	await process_frame
	assert(purchase_fx.get_child_count() >= 5, "purchase should immediately emit visible coin particles")
	await create_timer(0.8).timeout
	assert(economy_service.get_balance("gold") < before_gold, "purchase animation path should complete the purchase")
	var sold_out := false
	for offer in root.get_node("ShopService").get_shop_view(adventure_service.current_room_id()).get("offers", []):
		if offer is Dictionary and str(offer.get("offer_id", "")) == offer_id:
			sold_out = bool(offer.get("sold_out", false))
	assert(sold_out, "animated purchase should leave the purchased offer sold out")

	shop.queue_free()
	run_service.end_run()
	print("SHOP_SCENE_UI_TEST_PASS")
	quit()

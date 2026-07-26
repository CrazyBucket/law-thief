extends Control

const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")
const CoinTexture = preload("res://assets/ui/coin_gold.png")
const RunPlayerGemService = preload("res://scripts/services/run_player_gem_service.gd")
const RunGemEmbedDialog = preload("res://scripts/ui/run_gem_embed_dialog.gd")

const CARD_SIZE := Vector2(0, 150)
const SHOP_BG := Color("#19130f")
const SHOP_PANEL := Color("#211812")
const SHOP_INSET := Color("#0c0c11")
const WOOD_DARK := Color("#352114")
const WOOD_MID := Color("#684422")
const WOOD_LIGHT := Color("#a17438")
const BRASS := Color("#b78338")

@onready var _leave_button: Button = $SafeArea/Layout/TopBar/Row/LeaveButton
@onready var _title: Label = $SafeArea/Layout/TopBar/Row/TitleGroup/Title
@onready var _subtitle: Label = $SafeArea/Layout/TopBar/Row/TitleGroup/Subtitle
@onready var _balance_panel: PanelContainer = $SafeArea/Layout/TopBar/Row/BalancePanel
@onready var _balance_label: Label = $SafeArea/Layout/TopBar/Row/BalancePanel/BalanceRow/BalanceLabel
@onready var _info_rail: PanelContainer = $SafeArea/Layout/Main/InfoRail
@onready var _portrait_frame: PanelContainer = $SafeArea/Layout/Main/InfoRail/InfoVBox/PortraitFrame
@onready var _merchant_portrait: TextureRect = $SafeArea/Layout/Main/InfoRail/InfoVBox/PortraitFrame/MerchantPortrait
@onready var _counter: PanelContainer = $SafeArea/Layout/Main/InfoRail/InfoVBox/Counter
@onready var _speech_panel: PanelContainer = $SafeArea/Layout/Main/InfoRail/InfoVBox/SpeechPanel
@onready var _merchant_name: Label = $SafeArea/Layout/Main/InfoRail/InfoVBox/SpeechPanel/SpeechVBox/MerchantName
@onready var _speech_line: Label = $SafeArea/Layout/Main/InfoRail/InfoVBox/SpeechPanel/SpeechVBox/SpeechLine
@onready var _catalog_frame: PanelContainer = $SafeArea/Layout/Main/CatalogFrame
@onready var _catalog_title: Label = $SafeArea/Layout/Main/CatalogFrame/CatalogVBox/Header/CatalogTitle
@onready var _stock_label: Label = $SafeArea/Layout/Main/CatalogFrame/CatalogVBox/Header/StockLabel
@onready var _gem_shelf: PanelContainer = $SafeArea/Layout/Main/CatalogFrame/CatalogVBox/GemShelf
@onready var _gem_section: Label = $SafeArea/Layout/Main/CatalogFrame/CatalogVBox/GemShelf/GemVBox/Section
@onready var _gem_offers: GridContainer = $SafeArea/Layout/Main/CatalogFrame/CatalogVBox/GemShelf/GemVBox/GemOffers
@onready var _gem_plank: PanelContainer = $SafeArea/Layout/Main/CatalogFrame/CatalogVBox/GemShelf/GemVBox/Plank
@onready var _utility_dock: PanelContainer = $SafeArea/Layout/Main/CatalogFrame/CatalogVBox/UtilityDock
@onready var _services_panel: PanelContainer = $SafeArea/Layout/Main/CatalogFrame/CatalogVBox/UtilityDock/UtilityRow/ServicesPanel
@onready var _services_title: Label = $SafeArea/Layout/Main/CatalogFrame/CatalogVBox/UtilityDock/UtilityRow/ServicesPanel/ServicesVBox/ServicesTitle
@onready var _services_text: Label = $SafeArea/Layout/Main/CatalogFrame/CatalogVBox/UtilityDock/UtilityRow/ServicesPanel/ServicesVBox/ServicesText
@onready var _loadout_panel: PanelContainer = $SafeArea/Layout/Main/CatalogFrame/CatalogVBox/UtilityDock/UtilityRow/LoadoutPanel
@onready var _loadout_vbox: VBoxContainer = $SafeArea/Layout/Main/CatalogFrame/CatalogVBox/UtilityDock/UtilityRow/LoadoutPanel/LoadoutVBox
@onready var _loadout_title: Label = $SafeArea/Layout/Main/CatalogFrame/CatalogVBox/UtilityDock/UtilityRow/LoadoutPanel/LoadoutVBox/LoadoutTitle
@onready var _loadout_icon: TextureRect = $SafeArea/Layout/Main/CatalogFrame/CatalogVBox/UtilityDock/UtilityRow/LoadoutPanel/LoadoutVBox/LoadoutRow/LoadoutIcon
@onready var _loadout_label: Label = $SafeArea/Layout/Main/CatalogFrame/CatalogVBox/UtilityDock/UtilityRow/LoadoutPanel/LoadoutVBox/LoadoutRow/LoadoutLabel
@onready var _relic_shelf: PanelContainer = $SafeArea/Layout/Main/CatalogFrame/CatalogVBox/RelicShelf
@onready var _relic_section: Label = $SafeArea/Layout/Main/CatalogFrame/CatalogVBox/RelicShelf/RelicVBox/Section
@onready var _relic_offers: HBoxContainer = $SafeArea/Layout/Main/CatalogFrame/CatalogVBox/RelicShelf/RelicVBox/RelicOffers
@onready var _relic_plank: PanelContainer = $SafeArea/Layout/Main/CatalogFrame/CatalogVBox/RelicShelf/RelicVBox/Plank
@onready var _detail_panel: PanelContainer = $SafeArea/Layout/Main/InfoRail/InfoVBox/DetailPanel
@onready var _detail_icon_frame: PanelContainer = $SafeArea/Layout/Main/InfoRail/InfoVBox/DetailPanel/DetailVBox/DetailIconFrame
@onready var _detail_icon: TextureRect = $SafeArea/Layout/Main/InfoRail/InfoVBox/DetailPanel/DetailVBox/DetailIconFrame/DetailIcon
@onready var _detail_eyebrow: Label = $SafeArea/Layout/Main/InfoRail/InfoVBox/DetailPanel/DetailVBox/DetailHeader/DetailEyebrow
@onready var _detail_name: Label = $SafeArea/Layout/Main/InfoRail/InfoVBox/DetailPanel/DetailVBox/DetailName
@onready var _detail_body: RichTextLabel = $SafeArea/Layout/Main/InfoRail/InfoVBox/DetailPanel/DetailVBox/DetailBody
@onready var _feedback_label: Label = $SafeArea/Layout/Main/InfoRail/InfoVBox/DetailPanel/DetailVBox/FeedbackLabel
@onready var _detail_buy_button: Button = $SafeArea/Layout/Main/InfoRail/InfoVBox/DetailPanel/DetailVBox/DetailBuyButton
@onready var _fx_layer: Control = $PurchaseFx

var _room_id: String = ""
var _current_gold: int = 0
var _purchase_in_progress: bool = false
var _selected_offer: Dictionary = {}
var _selected_card: PanelContainer = null
var _embed_button: Button = null
var _gem_embed_overlay: RunGemEmbedDialog = null


func _ready() -> void:
	theme = BattleUiTheme.build_theme()
	_apply_theme()
	# The persistent adventure HUD owns the single gold/health display in this scene.
	_balance_panel.visible = false
	_apply_copy()
	_create_loadout_embed_button()
	_detail_buy_button.pressed.connect(_on_detail_purchase_pressed)
	_room_id = AdventureService.current_room_id()
	var room_view := RoomFlowService.enter_room(_room_id)
	var shop_view: Dictionary = (room_view.get("payload", {}) as Dictionary).get("shop", {})
	_render_shop_view(shop_view)


func _apply_theme() -> void:
	$SafeArea/Layout/TopBar.add_theme_stylebox_override("panel", _panel_style(SHOP_PANEL, BRASS, 10, 1))
	_balance_panel.add_theme_stylebox_override("panel", _panel_style(Color("#30230f"), UiPalette.TEXT_GOLD, 8, 1))
	_info_rail.add_theme_stylebox_override("panel", _panel_style(SHOP_PANEL.darkened(0.12), WOOD_LIGHT.darkened(0.18), 10, 1))
	_portrait_frame.add_theme_stylebox_override("panel", _portrait_slot_style())
	_counter.add_theme_stylebox_override("panel", _plank_style(true))
	_speech_panel.add_theme_stylebox_override("panel", _panel_style(Color("#1c1611"), BRASS.darkened(0.12), 10, 1))
	_catalog_frame.add_theme_stylebox_override("panel", _panel_style(SHOP_BG, WOOD_LIGHT.darkened(0.28), 10, 1))
	_gem_shelf.add_theme_stylebox_override("panel", _shelf_style())
	_relic_shelf.add_theme_stylebox_override("panel", _shelf_style())
	_gem_plank.add_theme_stylebox_override("panel", _plank_style(false))
	_relic_plank.add_theme_stylebox_override("panel", _plank_style(false))
	_utility_dock.add_theme_stylebox_override("panel", _panel_style(Color("#151219"), WOOD_LIGHT.darkened(0.32), 9, 1))
	_services_panel.add_theme_stylebox_override("panel", _panel_style(Color("#1b1511"), WOOD_MID, 9, 1))
	_loadout_panel.add_theme_stylebox_override("panel", _panel_style(Color("#11131a"), UiPalette.EDGE_MID, 9, 1))
	_detail_panel.add_theme_stylebox_override("panel", _panel_style(Color("#101117"), BRASS.darkened(0.2), 12, 1))
	_detail_icon_frame.add_theme_stylebox_override("panel", _panel_style(SHOP_INSET, UiPalette.EDGE_MID, 5, 1))
	BattleUiTheme.apply_button(_leave_button, "ghost")
	BattleUiTheme.apply_button(_detail_buy_button, "end")
	_title.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	_subtitle.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	_balance_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	_merchant_name.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	_speech_line.add_theme_color_override("font_color", BattleUiTheme.TEXT)
	_catalog_title.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	_stock_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	_gem_section.add_theme_color_override("font_color", UiPalette.RARITY_UNCOMMON)
	_relic_section.add_theme_color_override("font_color", UiPalette.RARITY_RARE)
	_services_title.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	_services_text.add_theme_color_override("font_color", BattleUiTheme.TEXT_HINT)
	_loadout_title.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	_loadout_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_HINT)
	_detail_eyebrow.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	_detail_name.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	_detail_body.add_theme_color_override("default_color", BattleUiTheme.TEXT_HINT)
	_feedback_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	_merchant_portrait.texture = null
	_merchant_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_detail_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _apply_copy() -> void:
	_leave_button.text = "←  " + _t("shop.leave")
	_title.text = _t("shop.title")
	_subtitle.text = _t("shop.subtitle")
	_merchant_name.text = _t("shop.merchant.name")
	_speech_line.text = _t("shop.merchant.greeting")
	_catalog_title.text = _t("shop.catalog.title")
	_gem_section.text = _t("shop.section.market")
	_relic_section.text = _t("shop.section.relics")
	_services_title.text = _t("shop.services.title")
	_services_text.text = _t("shop.services.coin_only")
	_loadout_title.text = _t("shop.loadout.title")
	_feedback_label.text = _t("shop.feedback.idle")
	_show_default_detail()


func _render_shop_view(shop_view: Dictionary) -> void:
	_clear_offer_nodes(_gem_offers)
	_clear_offer_nodes(_relic_offers)
	_selected_offer = {}
	_selected_card = null
	_current_gold = int(shop_view.get("gold", 0))
	_set_balance_value(_current_gold)
	var available_count := 0
	var first_offer: Dictionary = {}
	var first_card: PanelContainer = null
	for raw_offer in shop_view.get("offers", []):
		if not raw_offer is Dictionary:
			continue
		var offer := (raw_offer as Dictionary).duplicate(true)
		var card := _create_offer_card(offer)
		_gem_offers.add_child(card)
		if first_card == null:
			first_offer = offer
			first_card = card
		if not bool(offer.get("sold_out", false)):
			available_count += 1
	if _gem_offers.get_child_count() == 0:
		_add_empty_shelf(_gem_offers)
	_stock_label.text = _t("shop.stock", {"count": available_count})
	if first_card != null:
		_select_offer(first_offer, first_card)
	else:
		_show_default_detail()
	_render_loadout()


func _render_loadout() -> void:
	var snapshot := RunService.get_player_run_snapshot()
	var carried_id := str(snapshot.get("carried_gem_id", ""))
	if carried_id.is_empty():
		_loadout_icon.texture = null
		_loadout_label.text = _t("shop.loadout.empty")
		_update_embed_button(false)
		return
	_loadout_icon.texture = UnitLooks.get_gem_texture(carried_id)
	_loadout_label.text = str(snapshot.get("carried_gem_name", carried_id))
	_update_embed_button(true)


func _create_loadout_embed_button() -> void:
	_embed_button = Button.new()
	_embed_button.name = "EmbedButton"
	_embed_button.custom_minimum_size = Vector2(0, 32)
	_embed_button.text = _t("shop.loadout.embed")
	_embed_button.pressed.connect(_on_embed_pressed)
	BattleUiTheme.apply_button(_embed_button, "end")
	_loadout_vbox.add_child(_embed_button)


func _update_embed_button(has_carried_gem: bool) -> void:
	if _embed_button == null:
		return
	_embed_button.visible = has_carried_gem
	_embed_button.disabled = not has_carried_gem or RunPlayerGemService.embed_options(RunService.get_run()).is_empty()
	_embed_button.tooltip_text = _t("shop.loadout.no_slot") if has_carried_gem and _embed_button.disabled else ""
	BattleUiTheme.apply_button(_embed_button, "end")


func _on_embed_pressed() -> void:
	_show_gem_embed_choice()


func _embed_options() -> Array[Dictionary]:
	return RunPlayerGemService.embed_options(RunService.get_run())


func _show_gem_embed_choice() -> bool:
	var options := _embed_options()
	if options.is_empty():
		return false
	if _gem_embed_overlay != null and is_instance_valid(_gem_embed_overlay):
		_gem_embed_overlay.configure(options)
		return true
	_gem_embed_overlay = RunGemEmbedDialog.new()
	_gem_embed_overlay.embed_requested.connect(_on_gem_embed_slot_pressed)
	_gem_embed_overlay.postponed.connect(_close_gem_embed_overlay)
	add_child(_gem_embed_overlay)
	_gem_embed_overlay.configure(options)
	return true


func _on_gem_embed_slot_pressed(slot_index: int, force_overload: bool = false) -> void:
	var result := RunPlayerGemService.embed_carried_gem(RunService.get_run(), slot_index, force_overload)
	if not bool(result.get("ok", false)):
		_feedback_label.text = _t("gem_embed.unavailable")
		if _gem_embed_overlay != null and is_instance_valid(_gem_embed_overlay):
			_gem_embed_overlay.unlock_after_failure()
		return
	RunService.save_run(false)
	_close_gem_embed_overlay()
	_feedback_label.text = _t("shop.feedback.embedded")
	_feedback_label.add_theme_color_override("font_color", UiPalette.HP_HIGH)
	_refresh_shop_view()


func _close_gem_embed_overlay() -> void:
	if _gem_embed_overlay != null and is_instance_valid(_gem_embed_overlay):
		_gem_embed_overlay.dismiss()
	_gem_embed_overlay = null


func _refresh_shop_view() -> void:
	_render_shop_view(ShopService.get_shop_view(_room_id))


func _create_offer_card(offer: Dictionary) -> PanelContainer:
	var item_id := str(offer.get("item_id", ""))
	var rarity := str(offer.get("rarity", "common"))
	var rarity_color := UiPalette.rarity_color(rarity)
	var sold_out := bool(offer.get("sold_out", false))
	var disabled_code := str(offer.get("disabled_reason_code", ""))
	var disabled := sold_out or not disabled_code.is_empty() or not str(offer.get("disabled_reason", "")).is_empty()

	var card := PanelContainer.new()
	card.name = "Offer_%s" % str(offer.get("offer_id", ""))
	card.custom_minimum_size = Vector2(0, CARD_SIZE.y)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.add_theme_stylebox_override("panel", _offer_card_style(rarity_color, sold_out, false))
	card.set_meta("offer_id", str(offer.get("offer_id", "")))
	card.set_meta("item_type", str(offer.get("item_type", "gem")))
	card.set_meta("rarity_color", rarity_color)
	card.set_meta("sold_out", sold_out)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.mouse_entered.connect(_on_card_mouse_entered.bind(card, offer))
	card.mouse_exited.connect(_on_card_mouse_exited.bind(card))

	var buy_button := _build_gem_card(card, offer, rarity_color, disabled_code, sold_out, disabled)
	if not disabled:
		buy_button.pressed.connect(_on_purchase_pressed.bind(offer, card))

	if sold_out:
		card.modulate = Color(0.5, 0.5, 0.54, 0.72)
	return card


func _build_gem_card(
	card: PanelContainer,
	offer: Dictionary,
	accent: Color,
	disabled_code: String,
	sold_out: bool,
	disabled: bool
) -> Button:
	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 3)
	card.add_child(content)
	var item_type := str(offer.get("item_type", "gem"))
	var item_id := str(offer.get("item_id", ""))
	content.add_child(_card_type_label(item_type, str(offer.get("rarity", "common")), accent, true))
	content.add_child(_card_icon(item_type, item_id, Vector2(80, 80)))
	content.add_child(_card_name_label(str(offer.get("display_name", item_id)), accent, true))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)
	var buy_button := _card_buy_button(offer, disabled_code, sold_out, disabled)
	content.add_child(buy_button)
	return buy_button


func _card_type_label(item_type: String, rarity: String, accent: Color, centered: bool) -> Label:
	var label := Label.new()
	label.text = "%s · %s" % [_t("shop.item.%s" % item_type), _rarity_name(rarity)]
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", accent)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	return label


func _card_icon(item_type: String, item_id: String, minimum: Vector2) -> TextureRect:
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = minimum
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon.texture = _offer_texture(item_type, item_id)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _card_name_label(text: String, accent: Color, centered: bool) -> Label:
	var label := Label.new()
	label.name = "Name"
	label.text = text
	label.add_theme_font_size_override("font_size", 17 if not centered else 16)
	label.add_theme_color_override("font_color", accent.lightened(0.18))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


func _card_buy_button(offer: Dictionary, disabled_code: String, sold_out: bool, disabled: bool) -> Button:
	var button := Button.new()
	button.name = "BuyButton"
	button.custom_minimum_size = Vector2(0, 30)
	button.icon = CoinTexture
	button.expand_icon = true
	button.text = _price_button_text(offer, sold_out)
	button.disabled = disabled
	button.tooltip_text = _offer_tooltip(offer, disabled_code, sold_out)
	BattleUiTheme.apply_button(button, "end")
	return button


func _on_card_mouse_entered(card: PanelContainer, offer: Dictionary) -> void:
	if not is_instance_valid(card) or _purchase_in_progress:
		return
	_select_offer(offer, card)
	card.pivot_offset = card.size * 0.5
	card.z_index = 5
	var tween := create_tween()
	tween.tween_property(card, "scale", Vector2(1.015, 1.015), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_card_mouse_exited(card: PanelContainer) -> void:
	if not is_instance_valid(card):
		return
	card.z_index = 0
	var tween := create_tween()
	tween.tween_property(card, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _select_offer(offer: Dictionary, card: PanelContainer) -> void:
	if is_instance_valid(_selected_card) and _selected_card != card:
		_set_card_selected(_selected_card, false)
	_selected_offer = offer.duplicate(true)
	_selected_card = card
	_set_card_selected(card, true)
	var item_type := str(offer.get("item_type", "gem"))
	var item_id := str(offer.get("item_id", ""))
	var rarity := str(offer.get("rarity", "common"))
	_detail_icon.texture = _offer_texture(item_type, item_id)
	_detail_eyebrow.text = "%s · %s" % [_t("shop.item.%s" % item_type), _rarity_name(rarity)]
	_detail_name.text = str(offer.get("display_name", item_id))
	_detail_name.add_theme_color_override("font_color", UiPalette.rarity_color(rarity))
	_detail_body.text = _offer_description(item_type, item_id)
	_update_detail_purchase(offer)


func _set_card_selected(card: PanelContainer, selected: bool) -> void:
	if not is_instance_valid(card):
		return
	var accent: Color = card.get_meta("rarity_color", UiPalette.RARITY_COMMON)
	var sold_out := bool(card.get_meta("sold_out", false))
	card.add_theme_stylebox_override("panel", _offer_card_style(accent, sold_out, selected))


func _update_detail_purchase(offer: Dictionary) -> void:
	var sold_out := bool(offer.get("sold_out", false))
	var disabled_code := str(offer.get("disabled_reason_code", ""))
	var disabled := sold_out or not disabled_code.is_empty() or not str(offer.get("disabled_reason", "")).is_empty()
	_detail_buy_button.disabled = disabled
	_detail_buy_button.text = _price_button_text(offer, sold_out)
	_detail_buy_button.tooltip_text = _offer_tooltip(offer, disabled_code, sold_out)
	BattleUiTheme.apply_button(_detail_buy_button, "end")


func _on_detail_purchase_pressed() -> void:
	if _selected_offer.is_empty() or not is_instance_valid(_selected_card):
		return
	_on_purchase_pressed(_selected_offer, _selected_card)


func _on_purchase_pressed(offer: Dictionary, card: PanelContainer) -> void:
	if _purchase_in_progress:
		return
	_purchase_in_progress = true
	_set_offer_buttons_disabled(true)
	var before_gold := _current_gold
	var response := RoomFlowService.submit_room_command(_room_id, {
		"action": "purchase",
		"offer_id": str(offer.get("offer_id", "")),
	})
	var shop_view: Dictionary = (response.get("payload", {}) as Dictionary).get("shop", {})
	if not bool(response.get("ok", false)):
		_feedback_label.text = str(response.get("summary", _t("shop.feedback.failed")))
		_feedback_label.add_theme_color_override("font_color", UiPalette.HP_LOW)
		await _play_failed_purchase(card)
		_purchase_in_progress = false
		_render_shop_view(shop_view)
		return
	var result: Dictionary = response.get("result", {})
	var price := int(result.get("price", offer.get("final_price", 0)))
	var after_gold := int(shop_view.get("gold", before_gold - price))
	_feedback_label.text = _t("shop.feedback.purchased", {
		"item": str(offer.get("display_name", offer.get("item_id", ""))),
		"price": price,
	})
	_feedback_label.add_theme_color_override("font_color", UiPalette.HP_HIGH)
	await _play_purchase_animation(card, price, before_gold, after_gold)
	_purchase_in_progress = false
	_render_shop_view(shop_view)
	if str(offer.get("item_type", "gem")) == "gem":
		_show_gem_embed_choice()


func _play_purchase_animation(card: Control, price: int, before_gold: int, after_gold: int) -> void:
	_spawn_coin_stream(card)
	card.pivot_offset = card.size * 0.5
	var price_fx := Label.new()
	price_fx.text = "-%d" % price
	price_fx.add_theme_font_override("font", BattleUiTheme.pixel_font())
	price_fx.add_theme_font_size_override("font_size", 26)
	price_fx.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	price_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(price_fx)
	var global_center := card.get_global_rect().get_center()
	price_fx.position = _fx_layer.get_global_transform().affine_inverse() * global_center - Vector2(28, 12)

	var card_tween := create_tween()
	card_tween.tween_property(card, "scale", Vector2(0.9, 0.9), 0.08)
	card_tween.parallel().tween_property(card, "modulate", Color(1.45, 1.2, 0.55, 1.0), 0.08)
	card_tween.tween_property(card, "scale", Vector2(1.07, 1.07), 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	card_tween.parallel().tween_property(card, "modulate", Color.WHITE, 0.13)
	card_tween.tween_interval(0.1)
	card_tween.tween_property(card, "scale", Vector2(0.94, 0.94), 0.16)
	card_tween.parallel().tween_property(card, "modulate", Color(0.42, 0.42, 0.46, 0.24), 0.16)

	var fx_tween := create_tween().set_parallel(true)
	fx_tween.tween_property(price_fx, "position", price_fx.position - Vector2(0, 62), 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	fx_tween.tween_property(price_fx, "modulate:a", 0.0, 0.42).set_delay(0.12)
	fx_tween.chain().tween_callback(price_fx.queue_free)

	var balance_tween := create_tween()
	balance_tween.tween_method(_set_balance_value, before_gold, after_gold, 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_speech_panel.pivot_offset = _speech_panel.size * 0.5
	var speech_tween := create_tween()
	speech_tween.tween_property(_speech_panel, "scale", Vector2(1.015, 1.015), 0.12)
	speech_tween.tween_property(_speech_panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)
	await card_tween.finished


func _spawn_coin_stream(card: Control) -> void:
	var inverse := _fx_layer.get_global_transform().affine_inverse()
	var start := inverse * _balance_panel.get_global_rect().get_center() - Vector2(10, 10)
	var finish := inverse * card.get_global_rect().get_center() - Vector2(10, 10)
	for index in range(5):
		var coin := TextureRect.new()
		coin.texture = CoinTexture
		coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		coin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		coin.size = Vector2(20, 20)
		coin.position = start + Vector2(index * 3, 0)
		coin.scale = Vector2(0.45, 0.45)
		coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fx_layer.add_child(coin)
		var target := finish + Vector2((index - 2) * 8, abs(index - 2) * -5)
		var tween := create_tween()
		tween.tween_interval(index * 0.035)
		tween.tween_property(coin, "position", target, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(coin, "scale", Vector2(0.9, 0.9), 0.3)
		tween.tween_property(coin, "modulate:a", 0.0, 0.07)
		tween.tween_callback(coin.queue_free)


func _play_failed_purchase(card: Control) -> void:
	card.pivot_offset = card.size * 0.5
	var tween := create_tween()
	for scale_value in [Vector2(0.96, 1.03), Vector2(1.03, 0.96), Vector2.ONE]:
		tween.tween_property(card, "scale", scale_value, 0.07)
	await tween.finished


func _offer_description(item_type: String, item_id: String) -> String:
	match item_type:
		"gem":
			return _t("shop.detail.gem")
		"relic":
			var relic_def := DataRegistry.get_relic_def(item_id)
			return str(relic_def.get("desc", _t("shop.detail.relic.empty")))
	return _t("shop.detail.consumable")


func _show_default_detail() -> void:
	_detail_icon.texture = null
	_detail_eyebrow.text = _t("shop.detail.eyebrow")
	_detail_name.text = _t("shop.detail.title")
	_detail_name.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	_detail_body.text = _t("shop.detail.default")
	_detail_buy_button.disabled = true
	_detail_buy_button.text = "—"
	BattleUiTheme.apply_button(_detail_buy_button, "end")


func _offer_texture(item_type: String, item_id: String) -> Texture2D:
	match item_type:
		"gem":
			return UnitLooks.get_gem_texture(item_id)
		"relic":
			return UnitLooks.get_relic_texture(item_id)
	return null


func _panel_style(bg: Color, edge: Color, margin: int, border: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = edge
	style.set_border_width_all(border)
	style.set_corner_radius_all(0)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	style.shadow_color = Color(0, 0, 0, 0.75)
	style.shadow_size = 3
	style.shadow_offset = Vector2(0, 2)
	return style


func _portrait_slot_style() -> StyleBoxFlat:
	var style := _panel_style(Color("#080809"), WOOD_DARK, 0, 1)
	style.border_width_top = 6
	style.border_width_left = 5
	style.border_width_right = 5
	style.border_width_bottom = 2
	style.shadow_size = 5
	return style


func _shelf_style() -> StyleBoxFlat:
	var style := _panel_style(Color("#201913"), WOOD_MID, 9, 0)
	style.shadow_size = 1
	return style


func _plank_style(counter: bool) -> StyleBoxFlat:
	var style := _panel_style(WOOD_MID if not counter else WOOD_DARK.lightened(0.08), WOOD_LIGHT, 3, 1)
	style.border_width_top = 2
	style.border_width_bottom = 4
	style.border_color = WOOD_LIGHT if not counter else BRASS.darkened(0.26)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 3)
	return style


func _offer_card_style(accent: Color, sold_out: bool, selected: bool) -> StyleBoxFlat:
	var edge := accent.lightened(0.18) if selected else accent.darkened(0.2)
	var style := _panel_style(SHOP_INSET.darkened(0.1 if sold_out else 0.0), edge, 10, 0)
	style.border_width_top = 3 if selected else 2
	style.border_width_left = 1 if selected else 0
	style.border_width_right = 1 if selected else 0
	style.border_width_bottom = 1
	style.shadow_size = 5 if selected else 2
	style.shadow_offset = Vector2(0, 3)
	return style


func _price_button_text(offer: Dictionary, sold_out: bool) -> String:
	if sold_out:
		return _t("shop.offer.sold_out")
	return str(int(offer.get("final_price", 0)))


func _offer_tooltip(offer: Dictionary, disabled_code: String, sold_out: bool) -> String:
	if sold_out or disabled_code == "sold_out":
		return _t("shop.offer.sold_out")
	if disabled_code == "insufficient_gold":
		return _t("shop.offer.insufficient")
	if disabled_code == "carried_gem_occupied":
		return _t("shop.offer.hand_full")
	if int(offer.get("base_price", 0)) != int(offer.get("final_price", 0)):
		return _t("shop.price.discount", {
			"base": int(offer.get("base_price", 0)),
			"final": int(offer.get("final_price", 0)),
		})
	return ""


func _set_offer_buttons_disabled(disabled: bool) -> void:
	for container in [_gem_offers, _relic_offers]:
		for card in (container as Control).get_children():
			var button := card.find_child("BuyButton", true, false)
			if button is Button and not (button as Button).disabled:
				(button as Button).disabled = disabled
				BattleUiTheme.apply_button(button as Button, "end")
	_detail_buy_button.disabled = disabled
	BattleUiTheme.apply_button(_detail_buy_button, "end")
	if _embed_button != null:
		_embed_button.disabled = disabled or RunPlayerGemService.embed_options(RunService.get_run()).is_empty()
		BattleUiTheme.apply_button(_embed_button, "end")


func _set_balance_value(value: int) -> void:
	_current_gold = value
	_balance_label.text = str(value)


func _add_empty_shelf(container: Control) -> void:
	var label := Label.new()
	label.custom_minimum_size = Vector2(220, 48)
	label.text = _t("shop.shelf.empty")
	label.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	container.add_child(label)


func _clear_offer_nodes(container: Control) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _rarity_name(rarity: String) -> String:
	var key := "gem.rarity.%s" % rarity
	var translated := tr(key)
	return rarity.capitalize() if translated == key else translated


func _t(key: String, values: Dictionary = {}) -> String:
	var translated := tr(key)
	if translated == key:
		translated = key
	return translated.format(values)


func _on_leave_pressed() -> void:
	if _purchase_in_progress:
		return
	AdventureService.finish_room_and_return()

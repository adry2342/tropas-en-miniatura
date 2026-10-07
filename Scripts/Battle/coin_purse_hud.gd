class_name CoinPurseHud
extends CanvasLayer
## Monedero del combate (abajo a la izquierda, donde está la ficha de recursos en la planificación).
## Cada baja enemiga lanza sus monedas 💰: saltan desde el enemigo y vuelan hasta el monedero, que
## suma la cifra al llegar cada una y da un pequeño "latido".

const MAX_FLYING_PER_KILL := 5   # como mucho 5 monedas visibles por baja (el valor se reparte entre ellas)
const POP_TIME := 0.18
const FLY_TIME := 0.55
const STAGGER := 0.07

var _panel: PanelContainer
var _label: Label
var _shown: float = 0.0   # cifra mostrada (va por detrás de gsm.coins mientras vuelan monedas)
var _root: Control


func _ready() -> void:
	layer = 8
	_build()
	visible = false
	EventBus.battle_fight_started.connect(_on_fight_started)
	EventBus.enemy_reward.connect(_on_enemy_reward)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_panel = UiKit.panel(Color(0.075, 0.085, 0.11, 0.92), Color(1.0, 0.82, 0.25, 0.85), 10, 2, 8)
	_panel.name = "Purse"
	_panel.anchor_left = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 20.0
	_panel.offset_right = 196.0
	_panel.offset_top = -64.0
	_panel.offset_bottom = -16.0
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_panel.tooltip_text = "💰 Monedas: se ganan por cada baja enemiga y al vencer. Compran equipo y reclutas en la Intendencia."
	_root.add_child(_panel)
	_label = UiKit.label("💰 0", 22, UiKit.GOLD)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_panel.add_child(_label)


func _gsm() -> Node:
	return get_node_or_null("/root/GameStateManager")


func _on_fight_started() -> void:
	var gsm = _gsm()
	_shown = float(gsm.coins) if gsm else 0.0
	_refresh_label()
	visible = true


func _refresh_label() -> void:
	_label.text = "💰 %d" % roundi(_shown)


## Centro del monedero en coordenadas de pantalla.
func purse_center() -> Vector2:
	return _panel.get_global_rect().get_center()


func _on_enemy_reward(world_pos: Vector2, coins: int) -> void:
	if coins <= 0 or not is_inside_tree():
		return
	visible = true
	var screen_pos: Vector2 = get_viewport().get_canvas_transform() * world_pos
	var n: int = clampi(coins, 1, MAX_FLYING_PER_KILL)
	var per: float = float(coins) / float(n)
	for i in n:
		_launch_coin(screen_pos, per, i)


func _launch_coin(from: Vector2, value: float, index: int) -> void:
	var c := Label.new()
	c.text = "💰"
	c.add_theme_font_size_override("font_size", 20)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size = Vector2(28, 28)
	c.pivot_offset = c.size * 0.5
	c.position = from - c.size * 0.5
	_root.add_child(c)
	var hop := from + Vector2(randf_range(-26.0, 26.0), randf_range(-46.0, -30.0)) - c.size * 0.5
	var target := purse_center() - c.size * 0.5
	var t := c.create_tween()
	t.tween_interval(index * STAGGER)
	# 1) salto desde el enemigo
	t.tween_property(c, "position", hop, POP_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(c, "scale", Vector2(1.25, 1.25), POP_TIME)
	# 2) vuelo al monedero acelerando
	t.tween_property(c, "position", target, FLY_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(c, "scale", Vector2(0.7, 0.7), FLY_TIME)
	t.tween_callback(_on_coin_arrived.bind(value))
	t.tween_callback(c.queue_free)


func _on_coin_arrived(value: float) -> void:
	_shown += value
	_refresh_label()
	_panel.pivot_offset = _panel.size * 0.5
	var p := _panel.create_tween()
	p.tween_property(_panel, "scale", Vector2(1.12, 1.12), 0.06)
	p.tween_property(_panel, "scale", Vector2.ONE, 0.12)

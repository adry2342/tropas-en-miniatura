extends Node
## Comprobaciones de la munición (hueco propio, sustitución, solo armas de bala, guardado).

func _ready() -> void:
	var ok := true
	var c := TroopCard.new()
	c.weapons = [GameContent.find_weapon("cuchillo"), GameContent.find_weapon("fusil_asalto")]
	var poi := GameContent.find_item("balas_venenosas")
	var stun := GameContent.find_item("balas_aturdidoras")
	var ap := GameContent.find_item("balas_perforantes")
	ok = _check("tipos borrados ya no existen", GameContent.find_item("balas_huecas") == null and GameContent.find_item("balas_incendiarias") == null) and ok
	var base := TroopStats.compute(c, c.weapons[1])
	ok = _check("carga venenosas", c.add_item(poi) and c.ammo == poi and c.items.is_empty()) and ok
	ok = _check("cuchillo no envenena", TroopStats.compute(c, c.weapons[0]).poison_pct == 0.0) and ok
	var sp := TroopStats.compute(c, c.weapons[1])
	ok = _check("fusil envenena", sp.poison_pct > 0.0 and sp.poison_duration > 0.0) and ok
	ok = _check("venenosas: menos daño directo", sp.direct_dps < base.dps) and ok
	ok = _check("DPS de la ficha incluye el veneno", is_equal_approx(sp.dps, sp.direct_dps * (1.0 + sp.poison_pct))) and ok
	ok = _check("estimate_dps coincide", is_equal_approx(TroopStats.estimate_dps(sp), sp.dps)) and ok
	ok = _check("misma munición no repite", not c.can_add_item(poi)) and ok
	ok = _check("perforantes: atraviesa y pega menos", c.add_item(ap) and TroopStats.compute(c, c.weapons[1]).pierce == 1 \
			and TroopStats.compute(c, c.weapons[1]).dps < base.dps) and ok
	ok = _check("aturdidoras sustituyen", c.add_item(stun) and c.ammo == stun) and ok
	ok = _check("ya no envenena", TroopStats.compute(c, c.weapons[1]).poison_pct == 0.0) and ok
	var s := TroopStats.compute(c, c.weapons[1])
	ok = _check("suprime al impactar", s.suppress_hit > 0.0) and ok
	ok = _check("cuchillo no suprime", TroopStats.compute(c, c.weapons[0]).suppress_hit == 0.0) and ok
	ok = await _check_poison_runtime() and ok
	for id in ["chaleco_tactico", "granada", "botiquin"]:
		c.add_item(GameContent.find_item(id))
	ok = _check("3 objetos + munición", c.items.size() == 3 and c.ammo == stun) and ok
	var d := ProfileManager.card_to_dict(c)
	var c2 := ProfileManager.card_from_dict(d)
	ok = _check("guardado conserva munición", c2.ammo == stun and c2.items.size() == 3) and ok
	ok = _check("duplicado conserva munición", c.duplicate_card().ammo == stun) and ok
	c.ammo = null
	ok = _check("normales por defecto", c.get_ammo_name() == TroopCard.NORMAL_AMMO_NAME) and ok
	print("AMMO_TEST ", "OK" if ok else "FALLO")


## El veneno en combate: hace justo la reserva acumulada en POISON_DURATION s, reinicia con cada impacto,
## tiñe de verde y reduce la curación.
func _check_poison_runtime() -> bool:
	var ok := true
	var t = preload("res://Scenes/Troops/troop.tscn").instantiate()
	t.set_meta("no_snap", true)
	var e: TroopCard = UnitFactory.make_recruit()
	e.base_health = 1000.0
	t.card = e
	t.team = 1
	t.ai_enabled = false
	t.force_dodge = 0
	add_child(t)
	await get_tree().process_frame
	var hp0: float = t.health
	t.receive_hit({"damage": 20.0, "poison_pct": 0.5, "poison_duration": TroopStats.POISON_DURATION})
	t.receive_hit({"damage": 20.0, "poison_pct": 0.5, "poison_duration": TroopStats.POISON_DURATION})
	ok = _check("veneno acumulado = 50 % de cada impacto", t.statuses.has("poison") and is_equal_approx(float(t.statuses.poison.pool), 20.0)) and ok
	ok = _check("veneno no daña al instante", is_equal_approx(t.health, hp0 - 40.0)) and ok
	var spr: Sprite2D = t.get_node_or_null("Sprite2D")
	ok = _check("tinte verde", spr == null or spr.modulate.g > spr.modulate.r) and ok
	var hp1: float = t.health
	t.health = hp1 - 100.0
	var healed: float = t.heal(40.0, false)
	ok = _check("envenenado se cura la mitad", is_equal_approx(healed, 40.0 * (1.0 - TroopStats.POISON_HEAL_CUT))) and ok
	t.health = hp1
	for i in int(TroopStats.POISON_DURATION / t.POISON_TICK) + 2:
		t._tick_poison(t.POISON_TICK)
	ok = _check("veneno hace exactamente 20 en %.0f s" % TroopStats.POISON_DURATION, is_equal_approx(t.health, hp1 - 20.0) and not t.statuses.has("poison")) and ok
	t.receive_hit({"damage": 20.0, "poison_pct": 0.5, "poison_duration": 3.0, "friendly_fire": true})
	ok = _check("fuego amigo no envenena", not t.statuses.has("poison")) and ok
	t.queue_free()
	return ok


func _check(name: String, cond: bool) -> bool:
	print(("  ✔ " if cond else "  ✘ ") + name)
	return cond

extends Node2D
## Vista previa de las habilidades generales (2026-10-10). Monta un combate con tropas que llevan
## varias habilidades cada una (cambia GROUP para ver otra categoría) contra enemigos normales y un jefe.
##   0 = △ Daño · 1 = □ Tanque · 2 = S Movilidad · 3 = ○ Trampas y munición · 4 = todas mezcladas
## No forma parte del juego.

const TROOP := preload("res://Scenes/Troops/troop.tscn")
@export var GROUP: int = 4

const SETS := [
	[["ruleta_rusa"], ["bala_rebote", "todo_al_rojo"], ["gatillo_destino"], ["cadena_polvora"], ["deuda_sangre"], ["todo_al_rojo"]],
	[["ni_muerto"], ["venganza"], ["imaginate_yo", "problema_matarme"], ["carne_canon"], ["ojo_por_ojo"], ["te_llevas_parte"]],
	[["ultimo_en_pie"], ["esquiva"], ["no_me_pillas"], ["cambio_sitio"], ["panico_util"], ["paso_fantasma", "esquiva"]],
	[["doble_recarga", "cargador_veloz"], ["efecto_mariposa", "trampas"], ["municion_fantasma", "pildora"], ["cable_trampa", "senuelo"], ["hacerse_muerto", "recarga_desesperada"], ["robo_cargador"]],
	[["ruleta_rusa", "cadena_polvora"], ["carne_canon", "ni_muerto"], ["paso_fantasma", "esquiva"], ["senuelo", "cable_trampa"], ["deuda_sangre", "te_llevas_parte"], ["todo_al_rojo", "bala_rebote"]],
]


func _ready() -> void:
	add_child(BattlefieldBackground.new())
	var ws := ["fusil_asalto", "pistola", "rifle_francotirador", "escopeta", "subfusil", "ametralladora"]
	var set_: Array = SETS[clampi(GROUP, 0, SETS.size() - 1)]
	for i in set_.size():
		var c: TroopCard = UnitFactory.make_recruit()
		c.weapons = [GameContent.find_weapon(ws[i % ws.size()])]
		c.equipped_weapon = 0
		for id in set_[i]:
			var s := GameContent.find_skill(id)
			if s:
				c.skills.append(s)
		c.unit_name = (GameContent.find_skill(set_[i][0]).display_name if GameContent.find_skill(set_[i][0]) else "?").left(14)
		_spawn(c, Vector2(160, 70 + i * 70), 0)
	if GROUP == 3 or GROUP == 4:
		var g: TroopCard = UnitFactory.make_recruit()
		g.weapons = [GameContent.find_weapon("pistola")]
		g.items = [GameContent.find_item("granada_cegadora"), GameContent.find_item("granada_gas")]
		g.unit_name = "Granadero"
		_spawn(g, Vector2(240, 300), 0)
	for j in 5:
		var e: TroopCard = UnitFactory.make_recruit()
		e.is_enemy = true
		_spawn(e, Vector2(1000, 80 + j * 90), 1)
	var b: TroopCard = UnitFactory.make_recruit()
	b.is_boss = true
	b.is_enemy = true
	b.base_health *= 6.0
	b.unit_name = "Jefe"
	_spawn(b, Vector2(1080, 300), 1)
	await get_tree().create_timer(1.0).timeout
	EventBus.battle_fight_started.emit()


func _spawn(c: TroopCard, p: Vector2, team: int) -> void:
	var t = TROOP.instantiate()
	t.set_meta("no_snap", true)
	t.team = team
	t.card = c
	add_child(t)
	t.global_position = p

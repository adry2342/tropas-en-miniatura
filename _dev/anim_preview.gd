extends Node2D
## Vista previa de animaciones: una tropa con cada arma contra unos enemigos y un jefe.

const TROOP := preload("res://Scenes/Troops/troop.tscn")

func _ready() -> void:
	add_child(BattlefieldBackground.new())
	var ws: Array = GameContent.weapons()
	for i in ws.size():
		var c: TroopCard = UnitFactory.make_recruit()
		c.weapons = [ws[i]]
		c.equipped_weapon = 0
		c.unit_name = ws[i].display_name
		if i % 2 == 0:
			c.items = [GameContent.find_item("granada")]
		if i == 5 or i == 2:
			c.specialty = GameContent.find_specialty("vigia")
		if i == 1:
			c.weapons = [ws[i], ws[0]]  # con dos armas: se ve el cambio al vaciar el cargador
		_spawn(c, Vector2(90 + (i % 2) * 90, 60 + i * 46), 0)
	for j in 4:
		var e: TroopCard = UnitFactory.make_recruit()
		_spawn(e, Vector2(1000, 120 + j * 100), 1)
	var b: TroopCard = UnitFactory.make_recruit()
	b.is_boss = true
	b.base_health *= 8.0
	b.unit_name = "Jefe"
	_spawn(b, Vector2(1060, 300), 1)
	b.unit_name = "Jefe"
	await get_tree().create_timer(1.0).timeout
	EventBus.battle_fight_started.emit()


func _spawn(c: TroopCard, p: Vector2, team: int) -> void:
	var t = TROOP.instantiate()
	t.set_meta("no_snap", true)
	t.team = team
	t.card = c
	add_child(t)
	t.global_position = p


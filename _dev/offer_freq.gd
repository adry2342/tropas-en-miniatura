extends SceneTree
## Cuenta cuántas veces se OFRECE cada especialidad/habilidad al subir de nivel (Nv1→10), 3000 tropas.
func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var offered := {}
	var spec_by := {}
	for n in 3000:
		var c := UnitFactory.make_recruit(rng)
		while c.level < TroopCard.MAX_LEVEL:
			var offers := LevelUpSystem.roll_offers(c, rng)
			for o in offers:
				var id: String = o.resource.id if o.resource else "training"
				offered[id] = int(offered.get(id, 0)) + 1
			var pick: Dictionary = offers[rng.randi_range(0, offers.size() - 1)]
			LevelUpSystem.apply_offer(c, pick, false)
			c.level += 1
		if c.specialty:
			spec_by[c.specialty.id] = int(spec_by.get(c.specialty.id, 0)) + 1
	print("ESPECIALIDADES elegidas: ", spec_by)
	for s in GameContent.skills():
		print("HAB %-22s %-14s rareza %d ofrecida %d" % [s.id, s.specialty_id, s.rarity, int(offered.get(s.id, 0))])
	for sp in GameContent.specialties():
		print("ESP %-15s ofrecida %d" % [sp.id, int(offered.get(sp.id, 0))])
	print("training ", offered.get("training", 0))
	quit()

extends Node
## Equilibrio de la munición: DPS (directo + veneno) de cada arma de bala con cada munición contra un
## blanco, y tiempo para matar (TTK) a un enemigo normal y a un jefe (500 de vida, 20 % de armadura). Sin especialidad ni
## nivel (tropa base, daño ×1). Imprime una tabla en la salida.

const WEAPONS := ["pistola", "subfusil", "fusil_asalto", "escopeta", "rifle_francotirador", "ametralladora"]
const AMMO := ["", "balas_venenosas", "balas_perforantes", "balas_aturdidoras"]
const WEAK_HP := 50.0     # enemigo ya tocado o bajo fuego de varias tropas (lo normal)
const SOLDIER_HP := 100.0
const BOSS_HP := 500.0
const BOSS_ARMOR := 0.2
const DT := 0.01


func _ready() -> void:
	print("AMMO_BALANCE  (tropa base; precisión a distancia óptima; TTK con daño esperado por disparo)")
	print("%-22s %-18s %7s %7s %7s %6s %7s %7s %8s %9s" % ["Arma", "Munición", "Directo", "Veneno", "Total", "%", "2 fila", "TTK 50", "TTK 100", "TTK jefe"])
	for wid in WEAPONS:
		var w := GameContent.find_weapon(wid)
		var ref := 0.0
		for aid in AMMO:
			var c := TroopCard.new()
			c.weapons = [w]
			if aid != "":
				c.add_item(GameContent.find_item(aid))
			var s := TroopStats.compute(c, w)
			if aid == "":
				ref = s.dps
			var line: float = s.dps * (2.0 if int(s.pierce) > 0 else 1.0) # dos enemigos en fila
			var t0 := _ttk(s, WEAK_HP, 0.0)
			var t1 := _ttk(s, SOLDIER_HP, 0.0)
			var t2 := _ttk(s, BOSS_HP, BOSS_ARMOR)
			print("%-22s %-18s %7.1f %7.1f %7.1f %5d%% %7.1f %6.1fs %7.1fs %8.1fs" % [w.display_name, c.get_ammo_name(),
					s.direct_dps, s.poison_dps, s.dps, roundi(s.dps / ref * 100.0), line, t0, t1, t2])
	print("AMMO_BALANCE FIN")


## Tiempo para matar a un blanco quieto: dispara al ritmo del arma (cargador y recarga), cada disparo hace el
## daño esperado (precisión × perdigones), la armadura reduce el daño directo y el veneno se reparte en ticks
## como en troop.gd (reserva que se vacía en POISON_DURATION s, reiniciada con cada impacto).
func _ttk(s: Dictionary, hp: float, armor: float) -> float:
	var w: WeaponData = s.weapon
	var landed: float = s.pellets * s.accuracy
	var stack: float = 1.0 + w.pellet_stack_bonus * maxf(0.0, landed - 1.0)
	var per_shot: float = s.hit_damage * landed * stack
	var t := 0.0
	var cd := 0.0
	var mag: int = int(s.magazine)
	var reload := 0.0
	var pool := 0.0
	var left := 0.0
	var tick := 0.0
	var tick_len := 0.5
	while hp > 0.0 and t < 600.0:
		if reload > 0.0:
			reload -= DT
			if reload <= 0.0:
				mag = int(s.magazine)
		elif cd <= 0.0:
			hp -= per_shot * (1.0 - armor)
			if s.poison_pct > 0.0:
				pool += per_shot * s.poison_pct
				left = maxf(left, s.poison_duration)
			cd = 1.0 / s.fire_rate
			if int(s.magazine) > 0:
				mag -= 1
				if mag <= 0:
					reload = s.reload_time
		cd -= DT
		if pool > 0.0:
			tick += DT
			if tick >= tick_len:
				tick -= tick_len
				var d: float = pool * minf(1.0, tick_len / maxf(left, tick_len))
				pool -= d
				left -= tick_len
				hp -= d
		t += DT
	return t

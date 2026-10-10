extends Node2D
## Captura en movimiento del muñeco (TroopRig): varias situaciones a la vez, fotograma a fotograma.
## Cada situación es una fila; guarda _dev/art_tmp/motion/f_XX.png y luego se montan en una hoja.

const H := 165.0          # altura del muñeco en la captura (≈2× la del juego)
const CELL := Vector2(215, 212)
const STEP := 0.1         # segundos entre capturas
const SHOTS := 16

var rigs: Array = []
var scen: Array = []
var t := 0.0
var slip: Array = []   # máxima separación mano-agarre por situación
var labels: Array = []


func _ready() -> void:
	var bg := ColorRect.new(); bg.color = Color(0.78, 0.84, 0.74); bg.size = Vector2(4000, 4000); add_child(bg)
	var rifle := GameContent.find_weapon("fusil_asalto")
	var pistol := GameContent.find_weapon("pistola")
	var knife := GameContent.find_weapon("cuchillo")
	var baz := GameContent.find_weapon("bazuca")
	var shot := GameContent.find_weapon("escopeta")
	_add(rifle, "apunta arriba", func(r, k): r.aim_at(r.to_global(Vector2(900, -900)) ); r.animate(k, false, 0, false))
	_add(rifle, "apunta abajo", func(r, k): r.aim_at(r.to_global(Vector2(900, 900))); r.animate(k, false, 0, false))
	_add(rifle, "anda", func(r, k): r.animate(k, true, 90, false))
	_add(rifle, "dispara", func(r, k): _fire_every(r, 0.15); r.animate(k, false, 0, false))
	_add(rifle, "recarga", func(r, k): r.animate(k, false, 0, t > 0.2 and t < 1.2))
	_add(rifle, "cambia arma", func(r, k): _once(r, "sw", 0.3, func(): r.swap_weapon(pistol)); r.animate(k, false, 0, false))
	_add(rifle, "granada", func(r, k): _once(r, "gr", 0.2, func(): r.throw_grenade(func(_p): pass)); r.animate(k, false, 0, false))
	_add(rifle, "muere", func(r, k): _once(r, "d", 0.3, func(): r.play_death()); r.animate(k, false, 0, false))
	_add(pistol, "pistola anda+disp", func(r, k): _fire_every(r, 0.3); r.animate(k, true, 90, false))
	_add(knife, "cuchillo", func(r, k): _fire_every(r, 0.6); r.animate(k, false, 0, false))
	_add(baz, "bazuca", func(r, k): _fire_every(r, 0.7); r.animate(k, false, 0, false))
	_add(shot, "escopeta anda", func(r, k): r.animate(k, true, 70, false))
	_add(rifle, "enemigo anda", func(r, k): r.animate(k, true, 90, false), true)
	_add(rifle, "jefe anda", func(r, k): r.animate(k, true, 60, false), false, true)
	for i in SHOTS:
		for f in 6:
			_tick(STEP / 6.0)
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://_dev/art_tmp/motion/f_%02d.png" % i)
	for i in rigs.size():
		print("SLIP %s: %.1f" % [labels[i], slip[i]])
	print("MOTION_SAVED ", rigs.size())


func _add(w: WeaponData, _label: String, fn: Callable, enemy := false, boss := false) -> void:
	var i := rigs.size()
	var r := TroopRig.new()
	add_child(r)
	r.configure(H * (1.15 if boss else 1.0), enemy, boss)
	r.set_weapon(w)
	var col := i % 5
	var row := i / 5
	r.position = Vector2(col * CELL.x + CELL.x * 0.42, row * CELL.y + CELL.y * 0.48)
	rigs.append(r)
	scen.append(fn)
	slip.append(0.0)
	labels.append(_label)


func _tick(k: float) -> void:
	t += k
	for i in rigs.size():
		scen[i].call(rigs[i], k)
		slip[i] = maxf(slip[i], rigs[i].debug_slip)


func _fire_every(r: TroopRig, period: float) -> void:
	var n := int(t / period)
	if n != int(r.get_meta("fired", -1)):
		r.set_meta("fired", n)
		r.fire()


func _once(r: TroopRig, key: String, at: float, fn: Callable) -> void:
	if t >= at and not r.has_meta(key):
		r.set_meta(key, true)
		fn.call()

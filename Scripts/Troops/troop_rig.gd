class_name TroopRig
extends Node2D
## Muñeco animado de la tropa: piezas recortadas del sprite del recluta (piernas, cuerpo y los dos
## brazos, que giran en el hombro) y el arma en las manos.
##  - Armas cortas (pistola, cuchillo, subfusil): a una mano, con el brazo delantero extendido.
##  - Armas largas (fusil, escopeta, francotirador, ametralladora, lanzagranadas, bazuca): a dos
##    manos; la mano trasera en la empuñadura y la delantera bajo el cañón/guardamanos.
## Animaciones por código: reposo, caminar, disparo (retroceso + fogonazo), cuchillada, recarga
## (casi igual que el reposo), cambio de arma (guarda una y saca otra), lanzar granada (guarda el
## arma, saca la granada, la lanza y vuelve a empuñar) y muerte. El jefe tiene variantes propias.
##
## Todas las medidas están en píxeles del sprite ORIGINAL (1086x1448); el nodo se escala entero.

const SRC_H := 1448.0
const DOWN := 0.5                       # las texturas de las piezas están a la mitad
const FEET_Y := 672.0                   # de centro del sprite a la suela
const HIP_BACK := Vector2(-73, 316)
const HIP_FRONT := Vector2(137, 316)
const SH_FRONT := Vector2(197, 112)     # hombro del brazo delantero (el más cercano)
const SH_BACK := Vector2(-221, 104)
const FIST_FRONT := Vector2(252, 288)   # puños en reposo
const FIST_BACK := Vector2(-225, 291)
const WEAPON_SCALE := 0.95
const SWAP_TIME := 0.35
const THROW_TIME := 0.8
const THROW_RELEASE := 0.56             # fracción de THROW_TIME en que suelta la granada

const BODY_TEX = preload("res://Assets/Troop/body.png")
const LEG_BACK_TEX = preload("res://Assets/Troop/leg_back.png")
const LEG_FRONT_TEX = preload("res://Assets/Troop/leg_front.png")
const ARM_FRONT_TEX = preload("res://Assets/Troop/arm_front.png")
const ARM_BACK_TEX = preload("res://Assets/Troop/arm_back.png")
const SLEEVE_FRONT_TEX = preload("res://Assets/Troop/sleeve_front.png")
const SLEEVE_BACK_TEX = preload("res://Assets/Troop/sleeve_back.png")
const GRENADE_TEX = preload("res://Assets/Troop/grenade.png")

## id → [empuñadura en la textura (px de textura), bocacha y apoyo de la mano delantera
## (px originales relativos a la empuñadura; apoyo = Vector2.ZERO → arma a una mano)]
const WEAPON_RIG := {
	"pistola": [Vector2(65, 82.5), Vector2(300, -68), Vector2.ZERO],
	"cuchillo": [Vector2(70, 60), Vector2(330, -10), Vector2.ZERO],
	"subfusil": [Vector2(145, 87.5), Vector2(380, -62), Vector2.ZERO],
	"fusil_asalto": [Vector2(200, 112.5), Vector2(560, -66), Vector2(390, -40)],
	"escopeta": [Vector2(200, 85), Vector2(600, -82), Vector2(330, -30)],
	"rifle_francotirador": [Vector2(220, 132.5), Vector2(700, -70), Vector2(420, -55)],
	"ametralladora": [Vector2(195, 122.5), Vector2(720, -62), Vector2(430, -45)],
	"lanzagranadas": [Vector2(195, 117.5), Vector2(520, -78), Vector2(400, -40)],
	"bazuca": [Vector2(250, 155), Vector2(640, -110), Vector2(180, 20)],
}

var is_boss: bool = false
var weapon_id: String = ""
var dead: bool = false

var _root: Node2D        # en los pies: gira al caer
var _hips: Node2D
var _upper: Node2D       # tronco + brazos + arma: se balancea al andar
var _leg_back: Sprite2D
var _leg_front: Sprite2D
var _body: Sprite2D
var _arm_f: Node2D       # pivote en el hombro delantero
var _arm_b: Node2D
var _sleeve_f: Sprite2D
var _sleeve_b: Sprite2D
var _wpivot: Node2D      # en la empuñadura
var _weapon: Sprite2D
var _flash: Polygon2D
var _grenade: Sprite2D   # granada en la mano (al lanzar)

var _support: Vector2 = Vector2.ZERO   # apoyo de la mano delantera (local del arma); ZERO = una mano
var _t: float = 0.0
var _walk_phase: float = 0.0
var _walk_amt: float = 0.0
var _reload_amt: float = 0.0
var _recoil: float = 0.0
var _stab: float = 0.0
var _aim: float = 0.0
var _aim_target: float = 0.0
var _flash_t: float = 0.0
var _last_step: int = 0
var _bob: float = 0.0
var _swap_t: float = -1.0
var _swap_to: WeaponData = null
var _throw_t: float = -1.0
var _throw_cb: Callable
var _throw_released: bool = false


func _init() -> void:
	_root = Node2D.new(); _root.name = "Root"; _root.position = Vector2(0, FEET_Y); add_child(_root)
	_hips = Node2D.new(); _hips.position = Vector2(0, -FEET_Y); _root.add_child(_hips)
	_leg_back = _part(LEG_BACK_TEX, HIP_BACK, _hips)
	_leg_front = _part(LEG_FRONT_TEX, HIP_FRONT, _hips)
	_upper = Node2D.new(); _upper.name = "Upper"; _hips.add_child(_upper)
	_arm_b = _arm(ARM_BACK_TEX, SH_BACK)
	_body = _part(BODY_TEX, Vector2.ZERO, _upper)
	_wpivot = Node2D.new(); _wpivot.name = "WeaponPivot"; _upper.add_child(_wpivot)
	_weapon = Sprite2D.new(); _weapon.centered = false; _weapon.scale = Vector2.ONE * (WEAPON_SCALE / DOWN); _wpivot.add_child(_weapon)
	_flash = Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 10:
		var r := 120.0 if i % 2 == 0 else 45.0
		var a := TAU * i / 10.0
		pts.append(Vector2(cos(a) * r * 1.3 + 60.0, sin(a) * r * 0.8))
	_flash.polygon = pts
	_flash.color = Color(1.0, 0.85, 0.35, 0.95)
	_flash.visible = false
	_wpivot.add_child(_flash)
	_sleeve_b = _part(SLEEVE_BACK_TEX, Vector2.ZERO, _upper)
	_arm_f = _arm(ARM_FRONT_TEX, SH_FRONT)
	_sleeve_f = _part(SLEEVE_FRONT_TEX, Vector2.ZERO, _upper)
	_grenade = Sprite2D.new()
	_grenade.texture = GRENADE_TEX
	_grenade.scale = Vector2.ONE * (0.85 / DOWN)
	_grenade.position = FIST_FRONT - SH_FRONT + Vector2(10, -20)
	_grenade.visible = false
	_arm_f.add_child(_grenade)
	_apply_layering(false)


## Pieza con pivote en `pivot` (px originales relativos al centro del sprite).
func _part(tex: Texture2D, pivot: Vector2, parent: Node) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.scale = Vector2.ONE / DOWN
	s.position = pivot
	s.offset = -pivot * DOWN
	parent.add_child(s)
	return s


## Brazo: un Node2D en el hombro con la pieza dentro (girarlo mueve el brazo entero).
func _arm(tex: Texture2D, shoulder: Vector2) -> Node2D:
	var n := Node2D.new()
	n.position = shoulder
	_upper.add_child(n)
	var s := Sprite2D.new()
	s.texture = tex
	s.scale = Vector2.ONE / DOWN
	s.offset = -shoulder * DOWN
	n.add_child(s)
	return n


## Orden de dibujo. A dos manos el brazo trasero pasa por delante del cuerpo para llegar al arma.
func _apply_layering(two_handed: bool) -> void:
	var order: Array = []
	if two_handed:
		order = [_body, _wpivot, _arm_b, _sleeve_b, _arm_f, _sleeve_f]
	else:
		order = [_arm_b, _body, _wpivot, _arm_f, _sleeve_f, _sleeve_b]
	for i in order.size():
		_upper.move_child(order[i], i)
	_sleeve_b.visible = two_handed


## Altura en pantalla y orientación (enemigos miran a la izquierda).
func configure(height_px: float, facing_left: bool, boss: bool) -> void:
	is_boss = boss
	var k := height_px / SRC_H
	scale = Vector2(-k if facing_left else k, k)


func set_weapon(w: WeaponData) -> void:
	var wid: String = w.id if w else ""
	if wid == weapon_id:
		return
	weapon_id = wid
	var rig: Array = WEAPON_RIG.get(wid, [])
	if rig.is_empty():
		_weapon.texture = null
		_flash.position = Vector2(120, 0)
		_support = Vector2.ZERO
		_apply_layering(false)
		return
	_weapon.texture = load("res://Assets/Weapons/%s.png" % wid)
	_weapon.offset = -rig[0]
	_flash.position = rig[1] * WEAPON_SCALE
	_flash.scale = Vector2.ONE * (1.5 if wid in ["bazuca", "lanzagranadas", "ametralladora"] else 1.0)
	_support = rig[2] * WEAPON_SCALE
	_apply_layering(_support != Vector2.ZERO)


## Cambio de arma animado: baja y guarda la actual, saca la nueva.
func swap_weapon(w: WeaponData) -> void:
	if w == null or (w.id == weapon_id and _swap_t < 0.0):
		return
	_swap_to = w
	_swap_t = 0.0


func is_two_handed() -> bool:
	return _support != Vector2.ZERO


## Bocacha en coordenadas globales (de ahí salen las balas).
func muzzle_global() -> Vector2:
	return _wpivot.to_global(_flash.position)


func is_melee_weapon() -> bool:
	return weapon_id == "cuchillo"


func is_throwing() -> bool:
	return _throw_t >= 0.0


## Apunta el arma hacia un punto global (limitado para que no se retuerza).
func aim_at(p: Vector2) -> void:
	var local: Vector2 = _upper.to_local(p) - _grip_pose()
	_aim_target = clampf(local.angle(), -0.35, 0.35) if local.length() > 1.0 else 0.0


func clear_aim() -> void:
	_aim_target = 0.0


func fire() -> void:
	if is_melee_weapon():
		_stab = 1.0
		return
	_recoil = 1.0
	_flash_t = 0.07 if not is_boss else 0.09
	_flash.visible = true
	_flash.rotation = randf_range(-0.25, 0.25)
	_flash.scale.y = absf(_flash.scale.y) * (1.0 if randf() < 0.5 else -1.0)


## Lanza una granada: guarda el arma, saca la granada, toma impulso y la suelta.
## `on_release(pos_global)` se llama en el momento de soltarla (ahí se crea el proyectil).
func throw_grenade(on_release: Callable) -> void:
	_throw_t = 0.0
	_throw_cb = on_release
	_throw_released = false


## Empuñadura del arma en reposo (coordenadas de _upper).
func _grip_pose() -> Vector2:
	if weapon_id == "bazuca":
		return SH_BACK + Vector2.from_angle(deg_to_rad(16.0)) * 180.0
	if is_two_handed():
		return SH_BACK + Vector2.from_angle(deg_to_rad(40.0)) * 180.0
	return SH_FRONT + Vector2.from_angle(deg_to_rad(38.0)) * 172.0


## moving: se desplaza; speed: px/s; reloading: está recargando.
func animate(delta: float, moving: bool, speed: float, reloading: bool) -> void:
	if dead:
		return
	_t += delta
	_walk_amt = move_toward(_walk_amt, 1.0 if moving else 0.0, delta * 6.0)
	_reload_amt = move_toward(_reload_amt, 1.0 if reloading else 0.0, delta * 5.0)
	_recoil = move_toward(_recoil, 0.0, delta * (6.0 if is_boss else 8.0))
	_stab = move_toward(_stab, 0.0, delta * 5.0)
	_aim = lerp_angle(_aim, _aim_target * (1.0 - _reload_amt), minf(1.0, delta * 10.0))
	if _flash_t > 0.0:
		_flash_t -= delta
		_flash.visible = _flash_t > 0.0
	if moving:
		_walk_phase += delta * clampf(speed, 20.0, 160.0) * (0.075 if is_boss else 0.11)
	var s := sin(_walk_phase)
	if is_boss:
		_animate_boss(s, _walk_amt)
	else:
		_animate_trooper(s, _walk_amt)
	# --- cambio de arma: la baja (0 → 0,5), cambia, y la sube (0,5 → 1)
	var hide := 0.0
	if _swap_t >= 0.0:
		_swap_t += delta / SWAP_TIME
		if _swap_t >= 0.5 and _swap_to != null:
			set_weapon(_swap_to)
			_swap_to = null
		hide = sin(clampf(_swap_t, 0.0, 1.0) * PI)
		if _swap_t >= 1.0:
			_swap_t = -1.0
	# --- granada: el arma se guarda mientras dura el lanzamiento
	var throw_u := -1.0
	if _throw_t >= 0.0:
		_throw_t += delta / THROW_TIME
		throw_u = _throw_t
		hide = maxf(hide, clampf(minf(throw_u / 0.18, (1.0 - throw_u) / 0.2), 0.0, 1.0))
		if throw_u >= 1.0:
			_throw_t = -1.0
			throw_u = -1.0
	# --- arma: postura, puntería, retroceso, recarga y "guardado"
	var kick := _recoil * _recoil
	var rot := _aim - kick * (0.22 if is_boss else 0.13) + _reload_amt * 0.22 - sin(_stab * PI) * 0.15 + hide * 1.3
	if weapon_id == "bazuca":
		rot -= 0.05
	var back := -kick * (55.0 if is_boss else 34.0) + sin(_stab * PI) * 110.0
	_wpivot.rotation = rot
	_wpivot.position = _grip_pose() + Vector2(back, 0).rotated(rot) + Vector2(0, _reload_amt * 14.0 + _bob + hide * 90.0)
	_wpivot.modulate.a = 1.0 - hide
	_body.position.x = -kick * (14.0 if is_boss else 7.0)
	# --- brazos
	var holding := hide < 0.5
	if is_two_handed() and holding:
		_reach(_arm_b, SH_BACK, FIST_BACK, _wpivot.position)
		_reach(_arm_f, SH_FRONT, FIST_FRONT, _wpivot.position + _support.rotated(rot))
	else:
		_rest_arm(_arm_b, s)
		if holding:
			_reach(_arm_f, SH_FRONT, FIST_FRONT, _wpivot.position)
		else:
			_rest_arm(_arm_f, -s)
	if throw_u >= 0.0:
		_animate_throw(throw_u)
	else:
		_grenade.visible = false


func _reach(arm: Node2D, shoulder: Vector2, fist: Vector2, target: Vector2) -> void:
	var v0 := fist - shoulder
	var d := target - shoulder
	arm.rotation = v0.angle_to(d)
	arm.scale = Vector2(1.0, clampf(d.length() / v0.length(), 0.55, 1.2))


func _rest_arm(arm: Node2D, s: float) -> void:
	arm.rotation = s * 0.25 * _walk_amt + sin(_t * 2.4) * 0.03
	arm.scale = Vector2.ONE


## Brazo delantero al lanzar: saca la granada, la echa atrás por encima del hombro y la suelta.
func _animate_throw(u: float) -> void:
	var ang := 0.0
	if u < 0.2:
		ang = 0.0
	elif u < 0.48:
		ang = lerpf(0.0, 2.5, smoothstep(0.2, 0.48, u))          # impulso hacia atrás
	elif u < 0.62:
		ang = lerpf(2.5, -1.9, smoothstep(0.48, 0.62, u))        # latigazo hacia delante
	else:
		ang = lerpf(-1.9, 0.0, smoothstep(0.62, 1.0, u))
	_arm_f.rotation = ang
	_arm_f.scale = Vector2.ONE
	_grenade.visible = u >= 0.14 and not _throw_released
	if not _throw_released and u >= THROW_RELEASE:
		_throw_released = true
		_grenade.visible = false
		if _throw_cb.is_valid():
			_throw_cb.call(_grenade.global_position)


func _animate_trooper(s: float, w: float) -> void:
	var breath := sin(_t * 2.4) * 6.0 * (1.0 - w)
	_leg_back.rotation = s * 0.38 * w
	_leg_front.rotation = -s * 0.38 * w
	_upper.position = Vector2(0, -absf(s) * 22.0 * w + breath)
	_upper.rotation = 0.05 * w + sin(_walk_phase * 2.0) * 0.015 * w
	_bob = sin(_walk_phase * 2.0 + 0.6) * 6.0 * w
	_root.position.y = FEET_Y


## Jefe: paso corto y pesado (golpe al apoyar), hombros que suben y bajan despacio.
func _animate_boss(s: float, w: float) -> void:
	var breath := sin(_t * 1.5) * 12.0 * (1.0 - w)
	var stomp := pow(absf(s), 4.0)
	_leg_back.rotation = s * 0.26 * w
	_leg_front.rotation = -s * 0.26 * w
	_upper.position = Vector2(0, (stomp * 26.0 - 18.0) * w + breath)
	_upper.rotation = 0.09 * w + sin(_t * 1.5) * 0.02 * (1.0 - w)
	_bob = stomp * 10.0 * w
	_root.position.y = FEET_Y
	var step := int(floor(_walk_phase / PI))
	if w > 0.5 and step != _last_step:
		_last_step = step
		_stomp_dust()


func _stomp_dust() -> void:
	var p := get_parent()
	if p == null or not p.is_inside_tree() or p.get_parent() == null:
		return
	var fx: Node = p.get_parent()
	var foot := to_global(Vector2((HIP_FRONT.x if _last_step % 2 == 0 else HIP_BACK.x), FEET_Y))
	for i in 3:
		var d := Polygon2D.new()
		var pts := PackedVector2Array()
		for k in 8:
			pts.append(Vector2(cos(TAU * k / 8.0), sin(TAU * k / 8.0) * 0.5) * 4.0)
		d.polygon = pts
		d.color = Color(0.75, 0.68, 0.55, 0.6)
		fx.add_child(d)
		d.global_position = foot + Vector2(randf_range(-8, 8), 0)
		var tw := d.create_tween().set_parallel()
		tw.tween_property(d, "position", d.position + Vector2(randf_range(-14, 14), randf_range(-6, -2)), 0.45)
		tw.tween_property(d, "scale", Vector2.ONE * 2.2, 0.45)
		tw.tween_property(d, "modulate:a", 0.0, 0.45)
		tw.chain().tween_callback(d.queue_free)


## Animación de muerte. Devuelve cuánto dura (la tropa se libera al terminar).
func play_death() -> float:
	if dead:
		return 0.0
	dead = true
	_flash.visible = false
	_grenade.visible = false
	var tw := create_tween()
	# El arma se le cae de las manos y los brazos quedan sueltos
	var wt := create_tween().set_parallel()
	wt.tween_property(_wpivot, "position", _wpivot.position + Vector2(80, 300), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	wt.tween_property(_wpivot, "rotation", 1.4, 0.45)
	wt.tween_property(_arm_f, "rotation", -0.6, 0.4)
	wt.tween_property(_arm_b, "rotation", -0.4, 0.4)
	wt.tween_property(_arm_f, "scale", Vector2.ONE, 0.2)
	wt.tween_property(_arm_b, "scale", Vector2.ONE, 0.2)
	if is_boss:
		# Se tambalea, cae de rodillas y se desploma hacia delante
		tw.tween_property(_root, "rotation", -0.12, 0.18)
		tw.tween_property(_root, "rotation", 0.10, 0.18)
		tw.tween_property(_root, "scale", Vector2(1.08, 0.82), 0.25).set_trans(Tween.TRANS_BACK)
		tw.tween_interval(0.25)
		tw.tween_property(_root, "rotation", PI * 0.5, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(_root, "position:y", FEET_Y + 40.0, 0.08)
		tw.tween_interval(0.7)
		tw.tween_property(self, "modulate:a", 0.0, 0.6)
		return 2.7
	# Soldado: retrocede por el impacto y cae de espaldas
	_leg_back.rotation = 0.0
	_leg_front.rotation = 0.0
	tw.set_parallel()
	tw.tween_property(_root, "position:x", -90.0, 0.4).set_ease(Tween.EASE_OUT)
	tw.tween_property(_root, "rotation", -PI * 0.5, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_upper, "rotation", -0.15, 0.3)
	tw.chain().tween_property(_root, "position:y", FEET_Y - 25.0, 0.08)
	tw.chain().tween_property(_root, "position:y", FEET_Y, 0.1)
	tw.chain().tween_interval(0.6)
	tw.chain().tween_property(self, "modulate:a", 0.0, 0.45)
	return 1.7

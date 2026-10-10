class_name TroopRig
extends Node2D
## Muñeco animado de la tropa: piezas recortadas del sprite del recluta (piernas, cuerpo, mangas),
## dos brazos articulados (hombro → codo → mano) dibujados por código con el mismo trazo, y el arma.
##
## Reglas (simples a propósito, para que nada quede flotando ni atravesado):
##  1. El ARMA manda: cada fotograma se calcula su pose (puntería, retroceso, recarga, bajarla…) y las
##     manos van a sus puntos de agarre (empuñadura y apoyo). Nunca al revés.
##  2. Brazos con IK de dos huesos de longitud fija: no se estiran. Si la empuñadura quedara fuera de
##     alcance, se acerca el arma a la mano (la mano de disparo nunca se despega).
##  3. El codo siempre queda hacia abajo/atrás. Las manos agarradas giran con el arma; sueltas, con
##     el antebrazo.
##  4. Al cambiar de agarre (cambio de arma, granada) la mano se desliza a su nuevo sitio en ~0,1 s
##     en vez de saltar. El arma nunca se vuelve transparente: se baja a la cadera y se cambia ahí.
##  - Pistola y cuchillo: a una mano (brazo delantero). Resto: a dos manos; la trasera en la
##    empuñadura y la delantera en el apoyo, con el arma a la altura del pecho.
##
## Todas las medidas están en píxeles del sprite ORIGINAL (1086x1448); el nodo se escala entero.

const SRC_H := 1448.0
const DOWN := 0.5                       # las texturas de las piezas están a la mitad
const FEET_Y := 672.0                   # de centro del sprite a la suela
const HIP_BACK := Vector2(-73, 316)
const HIP_FRONT := Vector2(137, 316)
const SH_FRONT := Vector2(162, 64)      # hombro del brazo delantero (el más cercano)
const SH_BACK := Vector2(-186, 68)
const FIST_FRONT := Vector2(236, 272)   # manos en reposo (brazo colgando, algo doblado)
const FIST_BACK := Vector2(-212, 276)
const UPPER_LEN := 118.0                # húmero
const FORE_LEN := 118.0                 # antebrazo
const REACH := UPPER_LEN + FORE_LEN - 4.0
const ARM_W := 62.0                     # grosor del brazo (relleno)
const ARM_OUTLINE := 14.0
const WEAPON_SCALE := 0.95
const TEX_K := WEAPON_SCALE / DOWN      # px de textura del arma → px originales
const AIM_LIMIT := 0.3
const SWAP_TIME := 0.4
const THROW_TIME := 0.8
const THROW_RELEASE := 0.56             # fracción de THROW_TIME en que suelta la granada
const HAND_BLEND := 16.0                # rapidez con que una mano se recoloca al cambiar de agarre
const LOW_ONE_HAND := Vector2(210, 246) # arma bajada (cambio/granada): a una mano, junto a la cadera
const LOW_TWO_HAND := Vector2(-56, 214) #                               a dos manos, cruzada abajo

const OUTLINE_COL := Color8(34, 20, 14)
const SKIN_FRONT := Color8(226, 147, 100)
const SKIN_BACK := Color8(206, 128, 86)

const BODY_TEX = preload("res://Assets/Troop/body.png")
const LEG_BACK_TEX = preload("res://Assets/Troop/leg_back.png")
const LEG_FRONT_TEX = preload("res://Assets/Troop/leg_front.png")
const SLEEVE_FRONT_TEX = preload("res://Assets/Troop/sleeve_front.png")
const SLEEVE_BACK_TEX = preload("res://Assets/Troop/sleeve_back.png")
const HAND_FRONT_TEX = preload("res://Assets/Troop/hand_front.png")
const HAND_BACK_TEX = preload("res://Assets/Troop/hand_back.png")
const GRENADE_TEX = preload("res://Assets/Troop/grenade.png")

## id → {grip, muzzle, support} en px de la TEXTURA del arma (support ausente = a una mano).
## hold: dónde queda la empuñadura respecto al tronco (px originales). Comprobado con
## _dev/motion_preview.tscn: ninguna mano se despega en reposo, andando, apuntando ni disparando.
const WEAPON_RIG := {
	"pistola": {grip = Vector2(64, 92), muzzle = Vector2(215, 48), hold = Vector2(326, 170)},
	"cuchillo": {grip = Vector2(64, 60), muzzle = Vector2(235, 55), hold = Vector2(288, 196)},
	"subfusil": {grip = Vector2(130, 110), muzzle = Vector2(335, 56), support = Vector2(284, 72), hold = Vector2(-36, 160)},
	"fusil_asalto": {grip = Vector2(190, 132), muzzle = Vector2(480, 79), support = Vector2(368, 82), hold = Vector2(-44, 158)},
	"escopeta": {grip = Vector2(182, 100), muzzle = Vector2(500, 44), support = Vector2(352, 64), hold = Vector2(-44, 154)},
	"rifle_francotirador": {grip = Vector2(206, 142), muzzle = Vector2(570, 97), support = Vector2(340, 96), hold = Vector2(-48, 162)},
	"ametralladora": {grip = Vector2(178, 140), muzzle = Vector2(555, 91), support = Vector2(356, 104), hold = Vector2(-40, 168)},
	"lanzagranadas": {grip = Vector2(186, 132), muzzle = Vector2(455, 78), support = Vector2(372, 104), hold = Vector2(-44, 160)},
	"bazuca": {grip = Vector2(230, 160), muzzle = Vector2(570, 100), support = Vector2(328, 158), hold = Vector2(-34, 172)},
}


## Brazo dibujado: dos segmentos con contorno y codo/muñeca redondos (el hombro queda dentro de la manga).
class Limb extends Node2D:
	var shoulder := Vector2.ZERO
	var elbow := Vector2.ZERO
	var hand := Vector2.ZERO
	var skin := Color.WHITE

	func set_pose(s: Vector2, e: Vector2, h: Vector2) -> void:
		shoulder = s; elbow = e; hand = h
		queue_redraw()

	func _draw() -> void:
		var w := TroopRig.ARM_W
		var o := TroopRig.ARM_W + TroopRig.ARM_OUTLINE * 2.0
		var oc := TroopRig.OUTLINE_COL
		draw_line(shoulder, elbow, oc, o, true)
		draw_line(elbow, hand, oc, o, true)
		draw_circle(elbow, o * 0.5, oc, true, -1.0, true)
		draw_circle(hand, o * 0.5, oc, true, -1.0, true)
		draw_line(shoulder, elbow, skin, w, true)
		draw_line(elbow, hand, skin, w, true)
		draw_circle(elbow, w * 0.5, skin, true, -1.0, true)


## Una mano: dónde está, a qué agarre pertenece y el desfase que le queda por recorrer al cambiarlo.
class Hand:
	var pos := Vector2.ZERO
	var key := ""
	var off := Vector2.ZERO
	var attached := false

	## Lleva la mano a `target`. Si cambia de agarre (`k`), parte de donde estaba y se desliza.
	func follow(target: Vector2, k: String, att: bool, delta: float) -> void:
		if k != key:
			off = pos - target if key != "" else Vector2.ZERO
			key = k
		off *= exp(-TroopRig.HAND_BLEND * delta)
		attached = att
		pos = target + off


var is_boss: bool = false
var weapon_id: String = ""
var dead: bool = false

var _root: Node2D        # en los pies: gira al caer
var _hips: Node2D
var _upper: Node2D       # tronco + brazos + arma: se balancea al andar
var _leg_back: Sprite2D
var _leg_front: Sprite2D
var _body: Sprite2D
var _limb_f: Limb
var _limb_b: Limb
var _hand_f: Sprite2D
var _hand_b: Sprite2D
var _sleeve_f: Sprite2D
var _sleeve_b: Sprite2D
var _wpivot: Node2D      # en la empuñadura
var _weapon: Sprite2D
var _flash: Polygon2D
var _grenade: Sprite2D   # granada en la mano (al lanzar)

var _hold: Vector2 = Vector2(326, 170)
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
var _hf := Hand.new()
var _hb := Hand.new()
## Máxima separación mano-agarre del último fotograma (px originales). Lo usa la vista previa.
var debug_slip: float = 0.0


func _init() -> void:
	_root = Node2D.new(); _root.name = "Root"; _root.position = Vector2(0, FEET_Y); add_child(_root)
	_hips = Node2D.new(); _hips.position = Vector2(0, -FEET_Y); _root.add_child(_hips)
	_leg_back = _part(LEG_BACK_TEX, HIP_BACK, _hips)
	_leg_front = _part(LEG_FRONT_TEX, HIP_FRONT, _hips)
	_upper = Node2D.new(); _upper.name = "Upper"; _hips.add_child(_upper)
	_limb_b = Limb.new(); _limb_b.skin = SKIN_BACK; _upper.add_child(_limb_b)
	_hand_b = _hand(HAND_BACK_TEX)
	_body = _part(BODY_TEX, Vector2.ZERO, _upper)
	_wpivot = Node2D.new(); _wpivot.name = "WeaponPivot"; _upper.add_child(_wpivot)
	_weapon = Sprite2D.new(); _weapon.centered = false; _weapon.scale = Vector2.ONE * TEX_K; _wpivot.add_child(_weapon)
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
	_limb_f = Limb.new(); _limb_f.skin = SKIN_FRONT; _upper.add_child(_limb_f)
	_sleeve_f = _part(SLEEVE_FRONT_TEX, Vector2.ZERO, _upper)
	_hand_f = _hand(HAND_FRONT_TEX)
	_grenade = Sprite2D.new()
	_grenade.texture = GRENADE_TEX
	_grenade.scale = Vector2.ONE * (0.85 / DOWN) / _hand_f.scale.x
	_grenade.position = Vector2(14, -26)
	_grenade.visible = false
	_hand_f.add_child(_grenade)
	_apply_layering(false)
	_hf.pos = FIST_FRONT
	_hb.pos = FIST_BACK
	_solve_arms()


## Pieza con pivote en `pivot` (px originales relativos al centro del sprite).
func _part(tex: Texture2D, pivot: Vector2, parent: Node) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.scale = Vector2.ONE / DOWN
	s.position = pivot
	s.offset = -pivot * DOWN
	parent.add_child(s)
	return s


func _hand(tex: Texture2D) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.scale = Vector2.ONE / DOWN * 0.84
	_upper.add_child(s)
	return s


## Orden de dibujo (de atrás adelante).
##  - Dos manos: el brazo trasero cruza por delante del tronco y pasa bajo el arma; su mano se
##    cierra encima de la empuñadura. El delantero va por encima de todo hasta el apoyo.
##  - Una mano: el brazo trasero queda detrás del cuerpo; el delantero bajo el arma y su mano encima.
func _apply_layering(two_handed: bool) -> void:
	var order: Array = []
	if two_handed:
		order = [_body, _limb_b, _sleeve_b, _wpivot, _hand_b, _limb_f, _sleeve_f, _hand_f]
	else:
		order = [_limb_b, _hand_b, _body, _sleeve_b, _limb_f, _sleeve_f, _wpivot, _hand_f]
	for i in order.size():
		_upper.move_child(order[i], i)


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
	var rig: Dictionary = WEAPON_RIG.get(wid, {})
	if rig.is_empty():
		_weapon.texture = null
		_flash.position = Vector2(120, 0)
		_support = Vector2.ZERO
		_hold = Vector2(326, 170)
		_apply_layering(false)
		return
	var grip: Vector2 = rig.grip
	_weapon.texture = load("res://Assets/Weapons/%s.png" % wid)
	_weapon.offset = -grip
	_flash.position = (rig.muzzle - grip) * TEX_K
	_flash.scale = Vector2.ONE * (1.5 if wid in ["bazuca", "lanzagranadas", "ametralladora"] else 1.0)
	_support = (rig.support - grip) * TEX_K if rig.has("support") else Vector2.ZERO
	_hold = rig.hold
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
	return weapon_id == "cuchillo" or weapon_id == "punos" # puños: resucitados por Deuda de sangre


func is_throwing() -> bool:
	return _throw_t >= 0.0


## Apunta el arma hacia un punto global (limitado para que no se retuerza).
func aim_at(p: Vector2) -> void:
	var local: Vector2 = _upper.to_local(p) - _hold
	_aim_target = clampf(local.angle(), -AIM_LIMIT, AIM_LIMIT) if local.length() > 1.0 else 0.0


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

	# --- bajar el arma (cambio de arma y granada). lower: 0 = en posición, 1 = junto a la cadera
	var lower := 0.0
	var front_free := false   # la mano delantera suelta el arma
	var stowed := false       # arma guardada (granada con arma a una mano)
	if _swap_t >= 0.0:
		_swap_t += delta / SWAP_TIME
		if _swap_t >= 0.5 and _swap_to != null:
			set_weapon(_swap_to)
			_swap_to = null
		lower = smoothstep(0.0, 1.0, 1.0 - absf(_swap_t * 2.0 - 1.0))
		front_free = is_two_handed() and lower > 0.35
		if _swap_t >= 1.0:
			_swap_t = -1.0
	var throw_u := -1.0
	if _throw_t >= 0.0:
		_throw_t += delta / THROW_TIME
		throw_u = _throw_t
		var env := smoothstep(0.0, 1.0, clampf(minf(throw_u / 0.16, (1.0 - throw_u) / 0.16), 0.0, 1.0))
		if is_two_handed():
			lower = maxf(lower, env * 0.6)   # la trasera sujeta el arma baja; la delantera lanza
			front_free = true
		else:
			lower = maxf(lower, env)          # la pistola/cuchillo se guarda en la cadera
			stowed = env > 0.98
			front_free = stowed
		if throw_u >= 1.0:
			_throw_t = -1.0
			throw_u = -1.0
	_weapon.visible = not stowed
	_flash.visible = _flash.visible and not stowed

	# --- pose del arma
	var kick := _recoil * _recoil
	var thrust := sin(_stab * PI)
	var rot := _aim * (1.0 - lower) - kick * (0.22 if is_boss else 0.13) + _reload_amt * 0.22 - thrust * 0.12 + lower * 1.05
	if weapon_id == "bazuca":
		rot -= 0.05
	var low := LOW_TWO_HAND if is_two_handed() else LOW_ONE_HAND
	var pos := _hold.lerp(low, lower)
	pos += Vector2(-kick * (55.0 if is_boss else 34.0) + thrust * 55.0, 0).rotated(rot)
	pos += Vector2(0, _reload_amt * 14.0 + _bob * (1.0 - lower))
	# Regla 2: la empuñadura siempre al alcance de su mano
	var grip_sh := SH_BACK if is_two_handed() else SH_FRONT
	var gv := pos - grip_sh
	if gv.length() > REACH:
		pos = grip_sh + gv.normalized() * REACH
	_wpivot.rotation = rot
	_wpivot.position = pos
	_body.position.x = -kick * (14.0 if is_boss else 7.0)

	# --- manos
	var support_pos := pos + _support.rotated(rot)
	var free_f := _throw_hand(throw_u) if throw_u >= 0.0 else _swing(SH_FRONT, FIST_FRONT, -s)
	var free_b := _swing(SH_BACK, FIST_BACK, s)
	var wkey := weapon_id
	if is_two_handed():
		_hb.follow(pos, "grip:" + wkey, true, delta)
		if front_free:
			_hf.follow(free_f, "free", false, delta)
		else:
			_hf.follow(support_pos, "sup:" + wkey, true, delta)
	else:
		_hb.follow(free_b, "free", false, delta)
		if front_free:
			_hf.follow(free_f, "free", false, delta)
		else:
			_hf.follow(pos, "grip:" + wkey, true, delta)
	_solve_arms()
	if throw_u >= 0.0:
		_check_release(throw_u)
	else:
		_grenade.visible = false


## Mano suelta: cuelga junto a la cadera y se balancea con el paso.
func _swing(shoulder: Vector2, fist: Vector2, s: float) -> Vector2:
	var a := s * 0.22 * _walk_amt + sin(_t * 2.4) * 0.03
	return shoulder + (fist - shoulder).rotated(a)


## IK de dos huesos (longitudes fijas). El codo queda hacia abajo/atrás.
func _ik(shoulder: Vector2, target: Vector2) -> PackedVector2Array:
	var a := UPPER_LEN
	var b := FORE_LEN
	var v := target - shoulder
	var d := clampf(v.length(), absf(a - b) + 1.0, a + b - 0.5)
	var dir := v.normalized() if v.length() > 0.01 else Vector2.DOWN
	var cos_s := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var elbow := shoulder + dir.rotated(acos(cos_s)) * a
	return PackedVector2Array([elbow, shoulder + dir * d])


func _solve_arms() -> void:
	debug_slip = 0.0
	for side in 2:
		var sh: Vector2 = SH_FRONT if side == 0 else SH_BACK
		var h: Hand = _hf if side == 0 else _hb
		var limb: Limb = _limb_f if side == 0 else _limb_b
		var spr: Sprite2D = _hand_f if side == 0 else _hand_b
		var r := _ik(sh, h.pos)
		limb.set_pose(sh, r[0], r[1])
		spr.position = r[1]
		if h.attached:
			debug_slip = maxf(debug_slip, r[1].distance_to(h.pos))
		# agarrada gira con el arma; suelta, con el antebrazo
		var fore := (r[1] - r[0]).angle()
		var want := _wpivot.rotation if h.attached and h.off.length() < 20.0 else fore
		spr.rotation = want


## Brazo delantero al lanzar: saca la granada, la echa atrás por encima del hombro y la suelta.
func _throw_hand(u: float) -> Vector2:
	var ang := 0.0
	if u < 0.2:
		ang = 0.0
	elif u < 0.48:
		ang = lerpf(0.0, 2.4, smoothstep(0.2, 0.48, u))          # impulso hacia atrás
	elif u < 0.62:
		ang = lerpf(2.4, -1.7, smoothstep(0.48, 0.62, u))        # latigazo hacia delante
	else:
		ang = lerpf(-1.7, 0.0, smoothstep(0.62, 1.0, u))
	_grenade.visible = u >= 0.14 and u < 0.95 and not _throw_released
	var rest := FIST_FRONT - SH_FRONT
	return SH_FRONT + rest.normalized().rotated(ang) * minf(rest.length(), REACH - 10.0)


func _check_release(u: float) -> void:
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


## Al morir las manos sueltan el arma y quedan sueltas, a lo largo del cuerpo.
func _drop_hands(k: float, from_f: Vector2, from_b: Vector2) -> void:
	_hf.attached = false
	_hb.attached = false
	_hf.off = Vector2.ZERO
	_hb.off = Vector2.ZERO
	var back := 0.3 if is_boss else -0.3   # casi a lo largo del cuerpo, algo hacia el suelo (el jefe cae hacia delante)
	_hf.pos = from_f.lerp(SH_FRONT + (FIST_FRONT - SH_FRONT).rotated(-back * 0.8), k)
	_hb.pos = from_b.lerp(SH_BACK + (FIST_BACK - SH_BACK).rotated(-back), k)
	_solve_arms()


## Animación de muerte. Devuelve cuánto dura (la tropa se libera al terminar).
func play_death() -> float:
	if dead:
		return 0.0
	dead = true
	_flash.visible = false
	_grenade.visible = false
	_weapon.visible = true
	var tw := create_tween()
	# El arma se le cae de las manos antes de que el cuerpo gire (cae recta, hacia los pies) y se
	# desvanece: así no queda "flotando" sobre el cuerpo tumbado. Los brazos quedan sueltos.
	var wt := create_tween().set_parallel()
	wt.tween_property(_wpivot, "position", _wpivot.position + Vector2(50, 230), 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	wt.tween_property(_wpivot, "rotation", _wpivot.rotation + 1.3, 0.26)
	wt.tween_property(_wpivot, "modulate:a", 0.0, 0.2).set_delay(0.22)
	wt.tween_method(_drop_hands.bind(_hf.pos, _hb.pos), 0.0, 1.0, 0.3)
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

extends Node2D
## Vista estática del agarre: un muñeco grande por arma y algunas poses (andar, lanzar, jefe),
## capturados a PNG en _dev/art_tmp (para revisar manos y brazos sin jugar una partida).

func _ready() -> void:
	var bg := ColorRect.new(); bg.color = Color(0.78, 0.84, 0.74); bg.size = Vector2(2000, 1200); add_child(bg)
	var ws: Array = GameContent.weapons()
	for w in ws:
		await _shot(w, "rig_%s" % w.id, func(r: TroopRig) -> void: _run(r, 40, false))
	var rifle: WeaponData = GameContent.find_weapon("fusil_asalto")
	await _shot(rifle, "pose_walk", func(r: TroopRig) -> void: _run(r, 31, true))
	await _shot(rifle, "pose_throw", func(r: TroopRig) -> void:
		_run(r, 20, false)
		r.throw_grenade(func(_p: Vector2) -> void: pass)
		_run(r, 22, false))
	await _shot(rifle, "pose_fire", func(r: TroopRig) -> void:
		_run(r, 20, false)
		r.fire()
		_run(r, 2, false))
	await _shot(rifle, "pose_boss", func(r: TroopRig) -> void:
		r.configure(560.0, false, true)
		_run(r, 40, true))
	print("RIG_PREVIEW_SAVED")


func _run(r: TroopRig, frames: int, moving: bool) -> void:
	for f in frames:
		r.animate(1.0 / 60.0, moving, 90.0, false)


func _shot(w: WeaponData, file: String, pose: Callable) -> void:
	var r := TroopRig.new()
	add_child(r)
	r.configure(560.0, false, false)
	r.position = Vector2(330, 330)
	r.set_weapon(w)
	pose.call(r)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://_dev/art_tmp/%s.png" % file)
	r.queue_free()
	await get_tree().process_frame

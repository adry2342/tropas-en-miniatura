class_name CategoryBadge
extends Control
## Símbolo de la categoría de una habilidad, dibujado por código (no depende de la fuente):
##   △ Daño (rojo) · □ Tanque (verde) · S Movilidad (cian) · ○ Trampas y munición (ámbar).
## Trazo de color con contorno oscuro, como el resto del arte del juego.

const INK := Color(0.06, 0.05, 0.05, 0.95)


var category: int = 0:
	set(v):
		category = v
		queue_redraw()
## Fondo redondo oscuro detrás del símbolo (para ponerlo sobre cualquier celda).
var with_disc: bool = true
## Color del contorno (en el Códice, sobre pergamino, va con tinta marrón).
var ink: Color = INK


static func make(cat: int, px: float = 18.0, disc: bool = true) -> CategoryBadge:
	var b := CategoryBadge.new()
	b.category = cat
	b.with_disc = disc
	b.custom_minimum_size = Vector2(px, px)
	b.size = Vector2(px, px)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.tooltip_text = SkillData.CATEGORY_NAMES[clampi(cat, 0, 3)]
	return b


func _draw() -> void:
	var s: float = minf(size.x, size.y)
	var c := size * 0.5
	var col: Color = SkillData.category_color(category)
	if with_disc:
		draw_circle(c, s * 0.5, ink)
		draw_circle(c, s * 0.5 - 1.5, Color(0.12, 0.12, 0.14))
	var r := s * (0.3 if with_disc else 0.42)
	var w := maxf(1.6, s * 0.11)
	for pass_i in 2:
		var cc: Color = ink if pass_i == 0 else col
		var ww: float = w + 2.2 if pass_i == 0 else w
		match category:
			SkillData.Category.DANO:
				var pts := PackedVector2Array([c + Vector2(0, -r * 1.05), c + Vector2(r * 0.95, r * 0.7), c + Vector2(-r * 0.95, r * 0.7), c + Vector2(0, -r * 1.05)])
				draw_polyline(pts, cc, ww, true)
			SkillData.Category.TANQUE:
				var q := r * 0.82
				draw_polyline(PackedVector2Array([c + Vector2(-q, -q), c + Vector2(q, -q), c + Vector2(q, q), c + Vector2(-q, q), c + Vector2(-q, -q)]), cc, ww, true)
			SkillData.Category.MOVILIDAD:
				var h := r * 0.5
				draw_arc(c + Vector2(0, -h), h, deg_to_rad(-30.0), deg_to_rad(-270.0), 14, cc, ww, true)
				draw_arc(c + Vector2(0, h), h, deg_to_rad(-90.0), deg_to_rad(150.0), 14, cc, ww, true)
			_:
				draw_arc(c, r * 0.85, 0.0, TAU, 24, cc, ww, true)

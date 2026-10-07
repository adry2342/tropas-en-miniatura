class_name EnemyHeatmap
extends Sprite2D
## Mapa de calor de la zona enemiga durante la planificación.
## Cada enemigo aporta una mancha gaussiana; las manchas se SUMAN, así que:
##  - un enemigo solo  -> una mancha roja redonda que se difumina hacia fuera;
##  - varios juntos    -> una mancha más intensa;
##  - varios separados -> una mancha alargada/irregular con el calor repartido.
## Con varios enemigos, buena parte del calor sale de una mancha común que envuelve a todo el
## grupo (una gaussiana ajustada a su dispersión), así las manchas se fusionan y no se distinguen
## posiciones exactas. Un ruido suave deforma los contornos para que sean orgánicos.
## No muestra tipo, nivel ni número exacto de enemigos. Se desvanece al empezar el combate.

const TEXEL: float = 4.0          # Píxeles de pantalla por píxel de la textura (se suaviza con filtro lineal)
const SIGMA: float = 85.0         # Radio de difuminado de cada mancha (px), algo más de una casilla
const GAIN: float = 1.15          # Cuánto calienta cada enemigo antes de saturar
const MAX_ALPHA: float = 0.82
const FLOOR: float = 0.07         # Calor por debajo de esto no se dibuja: sin bordes "cortados"
const FUSION: float = 0.7         # Con 2+ enemigos, parte del calor que va a la mancha común del grupo
const GROUP_SIGMA: float = 95.0   # Difuminado extra de la mancha común
const WARP: float = 26.0          # Desplazamiento máximo (px) del ruido que deforma las manchas
const WARP_FREQ: float = 0.006

# Rampa de color: frío (transparente) -> amarillo -> naranja -> rojo -> carmesí
const RAMP: Array = [
	[0.00, Color(1.0, 0.95, 0.35, 0.0)],
	[0.25, Color(1.0, 0.85, 0.25, 0.35)],
	[0.50, Color(1.0, 0.5, 0.12, 0.65)],
	[0.72, Color(0.95, 0.15, 0.08, 0.85)],
	[1.00, Color(0.6, 0.0, 0.08, 1.0)],
]

var _points: Array[Vector2] = []
var _sigma: float = SIGMA
var _fusion: float = 0.0
var _mean: Vector2 = Vector2.ZERO
var _inv_cov: Transform2D = Transform2D.IDENTITY # Inversa de la covarianza de la mancha común
var _noise := FastNoiseLite.new()
var _origin: Vector2 = Vector2.ZERO
var _pulse: Tween


func _ready() -> void:
	z_index = -1 # Por debajo de tropas y textos
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	centered = false
	var bus = get_node_or_null("/root/EventBus")
	if bus:
		bus.battle_fight_started.connect(dissolve)


## Construye el mapa a partir de las posiciones (globales) de los enemigos.
## `area` es la zona donde puede haber calor (normalmente la cuadrícula enemiga ampliada).
func build(points: Array[Vector2], area: Rect2) -> void:
	_points = points.duplicate()
	_prepare_field()
	area = area.grow(maxf(_sigma, GROUP_SIGMA) * 3.2 + WARP)
	_origin = area.position
	global_position = _origin
	var w: int = maxi(1, ceili(area.size.x / TEXEL))
	var h: int = maxi(1, ceili(area.size.y / TEXEL))
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var world := _origin + Vector2((x + 0.5) * TEXEL, (y + 0.5) * TEXEL)
			var c := _color_for(intensity_at(world))
			# Desvanecido irregular hacia los bordes de la textura: nunca se ve un corte recto
			var edge: float = minf(minf(float(x), float(w - 1 - x)), minf(float(y), float(h - 1 - y))) / (minf(w, h) * 0.18)
			edge *= 1.0 + _noise.get_noise_2d(world.x * 2.0, world.y * 2.0) * 0.35
			c.a *= smoothstep(0.0, 1.0, clampf(edge, 0.0, 1.0))
			img.set_pixel(x, y, c)
	texture = ImageTexture.create_from_image(img)
	scale = Vector2(TEXEL, TEXEL)
	_start_pulse()


func _prepare_field() -> void:
	_noise.seed = randi()
	_noise.frequency = WARP_FREQ
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var n: int = _points.size()
	# Cuantos más enemigos, más grande y difusa es cada mancha y más se fusionan
	_sigma = SIGMA * (1.0 + 0.18 * float(maxi(n - 1, 0)))
	_fusion = 0.0 if n < 2 else FUSION
	_mean = Vector2.ZERO
	for p in _points:
		_mean += p
	if n > 0:
		_mean /= float(n)
	# Covarianza del grupo + difuminado base -> elipse que envuelve a todos los enemigos
	var sxx: float = GROUP_SIGMA * GROUP_SIGMA
	var syy: float = sxx
	var sxy: float = 0.0
	for p in _points:
		var d: Vector2 = p - _mean
		sxx += d.x * d.x / float(n)
		syy += d.y * d.y / float(n)
		sxy += d.x * d.y / float(n)
	var det: float = sxx * syy - sxy * sxy
	_inv_cov = Transform2D(Vector2(syy, -sxy) / det, Vector2(-sxy, sxx) / det, Vector2.ZERO)


## Calor (0..1) en una posición global.
## Mezcla de manchas individuales y una mancha común del grupo, con saturación suave.
func intensity_at(world: Vector2) -> float:
	var n: int = _points.size()
	if n == 0:
		return 0.0
	# Deformación orgánica: se muestrea el campo en un punto ligeramente desplazado
	var q := world + Vector2(_noise.get_noise_2d(world.x, world.y),
			_noise.get_noise_2d(world.x + 913.0, world.y - 377.0)) * WARP
	var own: float = 0.0
	var inv: float = 1.0 / (2.0 * _sigma * _sigma)
	for p in _points:
		own += exp(-q.distance_squared_to(p) * inv)
	var v: float = own
	if _fusion > 0.0:
		var d: Vector2 = q - _mean
		var m: Vector2 = _inv_cov.basis_xform(d)
		var group: float = float(n) * exp(-0.5 * d.dot(m))
		v = own * (1.0 - _fusion) + group * _fusion
	var t: float = 1.0 - exp(-v * GAIN)
	# Quitar el "suelo" de calor: fuera de las manchas queda totalmente transparente
	return clampf((t - FLOOR) / (1.0 - FLOOR), 0.0, 1.0)


func _color_for(t: float) -> Color:
	if t <= 0.003:
		return Color(0, 0, 0, 0)
	for i in range(1, RAMP.size()):
		if t <= RAMP[i][0]:
			var a: Array = RAMP[i - 1]
			var b: Array = RAMP[i]
			var c: Color = (a[1] as Color).lerp(b[1], (t - a[0]) / (b[0] - a[0]))
			c.a *= MAX_ALPHA
			return c
	var last: Color = RAMP[-1][1]
	last.a *= MAX_ALPHA
	return last


func _start_pulse() -> void:
	if _pulse:
		_pulse.kill()
	modulate.a = 1.0
	_pulse = create_tween().set_loops()
	_pulse.tween_property(self, "modulate:a", 0.78, 1.2).set_trans(Tween.TRANS_SINE)
	_pulse.tween_property(self, "modulate:a", 1.0, 1.2).set_trans(Tween.TRANS_SINE)


## Al empezar el combate: el mapa se desvanece (los enemigos se revelan desde battle.gd).
func dissolve() -> void:
	if _pulse:
		_pulse.kill()
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.35)
	t.tween_callback(queue_free)

class_name WeaponData
extends Resource
## Arma: define cómo dispara una tropa. La tropa solo aporta Vida y Daño (multiplicador).

enum Family { PISTOLA, AUTOMATICA, ESCOPETA, PRECISION, PESADA, EXPLOSIVO, CUERPO_A_CUERPO }
enum Projectile { BALA, GRANADA, COHETE, NINGUNO } # NINGUNO = cuerpo a cuerpo (impacto instantáneo)

const FAMILY_NAMES := ["Pistola", "Automática", "Escopeta", "Precisión", "Pesada", "Explosivo", "Cuerpo a cuerpo"]

@export var id: String = ""
@export var display_name: String = "Arma"
@export_multiline var description: String = ""
@export var icon: Texture2D               # opcional (null = la UI dibuja el emoji)
@export var emoji: String = "🔫"
@export var family: Family = Family.PISTOLA
@export var rarity: int = 0               # 0 común, 1 rara, 2 épica, 3 legendaria
@export var damage: float = 10.0          # por impacto (o por perdigón)
@export var fire_rate: float = 1.0        # disparos por segundo
@export var attack_range: float = 250.0   # px
@export var accuracy: float = 0.8         # acierto a distancia óptima (0..1)
@export var optimal_range: float = 150.0  # hasta aquí no hay penalización
@export var accuracy_falloff: float = 0.10 # precisión perdida por cada 100 px más allá de optimal_range
@export var magazine: int = 10            # 0 = infinito (no recarga)
@export var reload_time: float = 1.5
@export var crit_chance: float = 0.05
@export var crit_multiplier: float = 1.8
@export var pellets: int = 1              # perdigones por disparo
@export var aoe_radius: float = 0.0       # >0 = explota y daña a todos los enemigos del radio
@export var burn_dps: float = 0.0         # >0 = deja quemadura
@export var burn_duration: float = 0.0
@export var projectile: Projectile = Projectile.BALA
@export var projectile_speed: float = 650.0
@export var recruit_pool: bool = false    # puede salir como arma inicial de un recluta
@export var min_round: int = 1            # los enemigos solo la llevan desde esta ronda
## v4 — puntería y movimiento
@export var close_bonus: float = 0.0      # precisión extra a quemarropa (crece de 0 en optimal_range a este valor a 0 px); negativa = peor de cerca (mira telescópica)
@export var min_range: float = 0.0        # por debajo de esto no dispara (bazuca: se haría daño)
@export var fire_on_move: bool = false    # puede disparar mientras avanza (con penalización de precisión)
@export var move_speed_mult: float = 1.0  # peso del arma: cuchillo ligero, pesadas lentas
## Escopeta: cada perdigón EXTRA que acierta al mismo blanco en el mismo disparo suma este % al daño
## de todos (1 perdigón = daño normal; 5 = ×(1 + 4·bonus)). Así de cerca destroza y de lejos rasca.
@export var pellet_stack_bonus: float = 0.0


## Icono del arma (dibujo del mismo estilo que el arma que llevan las tropas).
func get_icon() -> Texture2D:
	if icon:
		return icon
	var p := "res://Assets/Weapons/icons/%s.png" % id
	if id != "" and ResourceLoader.exists(p):
		icon = load(p)
	return icon


func get_family_name() -> String:
	return FAMILY_NAMES[family]

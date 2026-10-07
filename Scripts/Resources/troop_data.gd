class_name TroopData
extends Resource

@export_category("Identidad")
@export var display_name: String = "Soldado"
@export var texture: Texture2D
# Altura en pixeles con la que se dibuja el sprite (se escala solo, sea cual sea su resolucion)
@export var sprite_height: float = 80.0
# Oro que cuesta reclutar esta tropa en la tienda de la planificación
@export var recruit_cost: int = 50

@export_category("Atributos Base")
@export var max_health: float = 100.0
@export var damage: float = 10.0
@export var move_speed: float = 100.0
@export var attack_range: float = 150.0
@export var attacks_per_second: float = 1.0

@export_category("Combate Avanzado")
@export_range(0.0, 1.0) var critical_chance: float = 0.0 # Sin crítico de base: solo lo dan los objetos (p. ej. al subir de nivel)
@export var critical_multiplier: float = 1.5

@export_category("Progresion")
# Objeto unico que recibe esta tropa al subir de nivel (recursos ItemData).
# Posicion 0 = Nv. 2, posicion 1 = Nv. 3, y asi sucesivamente.
@export var level_items: Array[ItemData] = []

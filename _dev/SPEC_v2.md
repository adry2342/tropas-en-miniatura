# SPEC v2 — Sistema de tropas únicas (armas, especialidades, niveles, objetos, habilidades)

Contrato común para todos los agentes. Proyecto Godot 4.7.2.
- Ruta en `device_bash`: `$HOME/mnt/tropas-en-miniatura`.
- Ruta en el dispositivo: `C:\Users\adri\Documents\proyectos\tropas-en-miniatura`.
- El juego está en español: textos, comentarios y nombres visibles en español.
- Inspiración: Mini Troopers. **No se copia**: nombres y contenido son propios.

## 0. Reglas de diseño que manda el usuario (NO negociables)
1. **Las estadísticas propias de la tropa son solo Vida y Daño.** Daño = multiplicador del daño del arma (1.0 = 100 %). Todo lo demás sale del arma, los objetos y las habilidades.
2. **Todo se sube con ORO.** No hay XP. Subir de nivel cuesta oro (`level * 30`) y llega hasta el nivel máximo 10.
3. **Cada subida de nivel ofrece 2 opciones al azar y el jugador elige 1.** Estilo Mini Troopers.
4. **Al llegar a Nv. 2** (`SPECIALTY_LEVEL = 2`), la subida ofrece **2 especialidades** al azar. El personaje deja de ser "Recluta" y pasa a ser Soldado, Francotirador, Granadero, Médico o Municionero.
5. **Las subidas posteriores** ofrecen una mezcla de:
   - **Habilidad pasiva** (intrínseca): **NO ocupa hueco**. Es la mayoría (p. ej. "Comando": +15 de vida).
   - **Objeto o equipo activo** (balas especiales, chalecos, granadas, botiquín…): **SÍ ocupa hueco**. Máximo **3 huecos de objeto**.
   - **Arma nueva**: se añade al arsenal de la tropa. Las armas no ocupan huecos de objeto.
6. Se aplican las recomendaciones del GDD:
   - El Daño es un multiplicador.
   - Cualquier tropa puede llevar cualquier arma, pero las de su familia afín dan bonus.
7. **Cada tropa debe sentirse única:**
   - Nombre propio aleatorio.
   - Pequeña variación de Vida y Daño al reclutarla (±10 %).
   - Arma inicial aleatoria.
   - Lo que vaya eligiendo al subir de nivel.

## 1. Archivos y propietarios (cada agente solo edita lo suyo; para cambios ajenos, SendMessage al dueño)

| Propietario | Archivos |
|---|---|
| **nucleo** | `Scripts/Resources/*` (WeaponData, SkillData, ItemData, SpecialtyData, TroopCard), `Scripts/Systems/*` (TroopStats, LevelUpSystem, UnitFactory, GameContent), `Resources/**/*.tres` (contenido), `Scripts/Autoloads/game_state_manager.gd`, `Scripts/Autoloads/event_bus.gd`, `_dev/test_core.*` |
| **combate** | `Scripts/Troops/**`, `Scenes/Troops/**`, `Scripts/Battle/*` (excepto `enemy_heatmap.gd`, que no se toca), `Scenes/Battle/*`, `Scripts/Systems/effects.gd`, `_dev/test_combat.*` |
| **interfaz** | `Scripts/UI/*`, `Scenes/UI/*`, `Scripts/Map/map.gd` (solo si hace falta), `_dev/test_ui.*` |
| **qa** | `_dev/logic_test.*` (actualizarlo al sistema nuevo), `_dev/dev_boot.*`, informes |
| **orquestador** (main) | Esta SPEC, validación final y arbitraje |

## 2. Modelo de datos (lo crea **nucleo**; las firmas son contrato)

### 2.1 `WeaponData` (`Scripts/Resources/weapon_data.gd`, `class_name WeaponData extends Resource`)
```
enum Family { PISTOLA, AUTOMATICA, ESCOPETA, PRECISION, PESADA, EXPLOSIVO, CUERPO_A_CUERPO }
enum Projectile { BALA, GRANADA, COHETE, LLAMA, NINGUNO }  # NINGUNO = cuerpo a cuerpo (impacto instantáneo)
@export var id: String
@export var display_name: String
@export_multiline var description: String
@export var icon: Texture2D               # opcional (null = la UI dibuja un emoji o texto)
@export var emoji: String = "🔫"          # icono de texto para la UI
@export var family: Family
@export var rarity: int = 0               # 0 común, 1 rara, 2 épica, 3 legendaria
@export var damage: float = 10.0          # por impacto (o por perdigón)
@export var fire_rate: float = 1.0        # disparos por segundo
@export var attack_range: float = 250.0   # px
@export var accuracy: float = 0.8         # probabilidad de acierto a distancia óptima (0..1)
@export var optimal_range: float = 150.0  # hasta aquí no hay penalización
@export var accuracy_falloff: float = 0.10 # precisión perdida por cada 100 px más allá de optimal_range
@export var magazine: int = 10            # 0 = infinito (no recarga)
@export var reload_time: float = 1.5
@export var crit_chance: float = 0.05
@export var crit_multiplier: float = 1.8
@export var pellets: int = 1              # perdigones por disparo (cada uno tira acierto y daño por separado)
@export var aoe_radius: float = 0.0       # >0 = explota en el punto de impacto y daña a todos los enemigos del radio
@export var burn_dps: float = 0.0         # >0 = deja quemadura
@export var burn_duration: float = 0.0
@export var projectile: Projectile = Projectile.BALA
@export var projectile_speed: float = 650.0
@export var recruit_pool: bool = false    # true = puede salir como arma inicial de un recluta
@export var min_round: int = 1            # los enemigos solo la llevan desde esta ronda
```

### 2.2 `SpecialtyData` (`specialty_data.gd`, `class_name SpecialtyData`)
```
@export var id: String                    # "soldado","francotirador","granadero","medico","municionero"
@export var display_name: String
@export_multiline var description: String
@export var emoji: String
@export var color: Color                  # color del nombre sobre la tropa y en la UI
@export var texture: Texture2D            # opcional; null = sprite del recluta
@export var affine_families: Array[int]   # valores de WeaponData.Family
@export var passive_name: String
@export_multiline var passive_description: String
@export var passive_effect_id: String     # se resuelve en effects.gd (combate)
@export var modifiers: Dictionary = {}    # modificadores pasivos fijos de la especialidad (sección 3)
```
Bonus de afinidad (en TroopStats): si `weapon.family in affine_families` → +15 % de daño y +0.10 de precisión.

### 2.3 `SkillData` (`skill_data.gd`, `class_name SkillData`) — habilidad PASIVA intrínseca, sin hueco
```
@export var id: String
@export var display_name: String
@export_multiline var description: String
@export var emoji: String = "⭐"
@export var rarity: int = 0
@export var specialty_id: String = ""     # "" = general (cualquiera); si no, solo para esa especialidad
@export var requires: Array[String] = []  # ids de habilidades necesarias
@export var stackable: bool = false
@export var modifiers: Dictionary = {}    # sección 3
@export var effect_id: String = ""        # comportamiento especial (effects.gd); "" = solo modificadores
@export var params: Dictionary = {}
```

### 2.4 `ItemData` (`item_data.gd`, se REESCRIBE; `class_name ItemData`) — ocupa 1 de 3 huecos
```
enum Slot { MUNICION, ARMADURA, UTILIDAD }  # como máximo 1 MUNICION y 1 ARMADURA por tropa; el resto UTILIDAD
@export var id, display_name, description, emoji, rarity, icon
@export var slot: Slot
@export var modifiers: Dictionary = {}
@export var effect_id: String = ""        # p. ej. "granada", "botiquin", "adrenalina", "incendiaria"
@export var params: Dictionary = {}       # p. ej. {cooldown=6.0, damage=25.0, radius=70.0}
```
Desaparecen `health_bonus`, `damage_bonus`, etc. La carpeta `Resources/Items/Unique` queda obsoleta: sus 9 objetos se reconvierten en habilidades.

### 2.5 `TroopCard` (`troop_card.gd`, `class_name TroopCard`) — **estado persistente de UNA tropa** (tablero o reserva)
```
@export var unit_name: String             # nombre propio aleatorio ("Ríos", "Kowalski"…)
@export var base_health: float = 100.0    # Vida base (con variación ±10 % al reclutar)
@export var base_damage: float = 1.0      # Daño = multiplicador (1.0 = 100 %)
@export var level: int = 1
@export var specialty: SpecialtyData = null   # null = Recluta
@export var weapons: Array[WeaponData] = []   # arsenal (≥1)
@export var equipped_weapon: int = 0          # índice en weapons
@export var items: Array[ItemData] = []       # máx. 3 (MAX_ITEM_SLOTS)
@export var skills: Array[SkillData] = []
@export var pending_offers: Array = []        # ofertas ya pagadas y sin elegir (no se pierden si se cierra la UI)
@export var is_boss: bool = false
const MAX_ITEM_SLOTS := 3
const MAX_LEVEL := 10
const SPECIALTY_LEVEL := 2
var display_name: String  (getter → unit_name)
func get_weapon() -> WeaponData
func get_specialty_name() -> String        # "Recluta" si no hay especialidad
func get_title() -> String                 # "Ríos · Soldado"
func has_skill(id) -> bool; func has_item(id) -> bool
func can_add_item(item: ItemData) -> bool  # huecos libres + regla de 1 MUNICION / 1 ARMADURA + sin duplicados
func add_item(item) -> bool; func remove_item(item) -> bool   # al quitarlo vuelve a la reserva (GSM)
func get_level_up_cost() -> int            # level * 30
func can_level_up() -> bool                # level < MAX_LEVEL y sin pending_offers
func duplicate_card() -> TroopCard          # copia profunda segura (los recursos de contenido se comparten)
```
**Regla clave:** el nodo `troop.gd` tiene `var card: TroopCard` y **todo** sale de ahí. Al retirar una tropa a la reserva se guarda el mismo `card`. Al persistir entre rondas se guarda `{card, position}`. Se acaban `troop_data`, `individual_items` y `TroopData` (el archivo `troop_data.gd` y `Resources/Troops/*.tres` pueden quedarse como legado sin uso, o borrarse cuando ya nada los referencie).

## 3. Modificadores (Dictionary, aditivos; los suma TroopStats)
Claves válidas (ausente = 0):
| clave | efecto |
|---|---|
| `health_flat` | +Vida fija |
| `health_pct` | +% de Vida máx. (0.10 = +10 %) |
| `damage_pct` | +% al multiplicador de Daño |
| `fire_rate_pct` | +% de cadencia |
| `accuracy` | +precisión absoluta (0.05 = +5 puntos) |
| `crit_chance` | +probabilidad de crítico absoluta |
| `crit_mult` | +multiplicador de crítico |
| `range_pct` | +% de alcance |
| `magazine_pct` | +% de cargador (redondeo hacia arriba; 0 = infinito sigue infinito) |
| `reload_pct` | −/+ % de tiempo de recarga (−0.25 = 25 % más rápido) |
| `move_speed_pct` | +% de velocidad de movimiento |
| `armor` | reducción de daño recibido (0.15 = −15 %), tope 0.6 |
| `dodge` | probabilidad de esquivar un impacto, tope 0.5 |
| `aoe_pct` | +% de radio de explosión |
| `pierce` | nº de enemigos extra que atraviesa una bala |
| `burn_dps` | añade quemadura a los impactos (dps) durante 3 s |

## 4. `TroopStats` (`Scripts/Systems/troop_stats.gd`, `class_name TroopStats`, funciones estáticas)
`static func compute(card: TroopCard) -> Dictionary`. Es la **única** fuente de verdad para el combate y para la UI. Devuelve:
`max_health, damage_mult, move_speed, attack_range, fire_rate, accuracy, optimal_range, accuracy_falloff, magazine, reload_time, crit_chance, crit_multiplier, pellets, aoe_radius, burn_dps, burn_duration, armor, dodge, pierce, weapon_damage, affinity (bool)`.

Fórmulas:
- `LEVEL_HEALTH = 0.10` y `LEVEL_DAMAGE = 0.06` por nivel por encima del 1.
- `max_health = (base_health * (1 + LEVEL_HEALTH*(level-1)) + health_flat) * (1 + health_pct)`.
- `damage_mult = base_damage * (1 + LEVEL_DAMAGE*(level-1)) * (1 + damage_pct + (0.15 si hay afinidad))`.
- `BASE_MOVE_SPEED = 90` (común a todas), multiplicado por `(1 + move_speed_pct)` y con mínimo 30.
- El resto: valor del arma combinado con los modificadores (precisión sin superar 0.98 ni bajar de 0.05).
- Daño de un impacto = `weapon.damage * damage_mult` (×`crit_multiplier` si hay crítico).
- Fuentes de modificadores: especialidad + habilidades + objetos.
- `static func describe(card) -> Array[String]` devuelve líneas legibles para la UI (opcional).

## 5. `LevelUpSystem` (`Scripts/Systems/level_up_system.gd`, `class_name LevelUpSystem`, estático)
- `static func roll_offers(card, rng := null) -> Array[Dictionary]`: devuelve **2** ofertas distintas. Cada oferta es `{type: "specialty"|"skill"|"item"|"weapon", resource: Resource}`.
  - Si `card.specialty == null` y `card.level + 1 >= SPECIALTY_LEVEL`: 2 especialidades distintas al azar.
  - En otro caso, se tira el tipo con pesos skill 55 / item 25 / weapon 20.
  - Se excluyen los objetos que no caben (`can_add_item`), las armas que ya tiene y las habilidades que ya tiene (salvo las acumulables) o cuyos `requires` no cumple.
  - Habilidades = generales + las de su especialidad. Las armas de su familia afín pesan ×2. La rareza pondera: común 60, rara 30, épica 10.
  - Si un tipo se queda sin candidatos, se rellena con otro tipo.
- `static func begin_level_up(card) -> bool`:
  - Valida `can_level_up()`, cobra el oro (`GameStateManager.spend_gold`) y rellena `card.pending_offers`.
  - **Aún no sube de nivel.**
- `static func choose(card, index) -> void`:
  - Aplica la oferta: especialidad → `card.specialty`; habilidad → `skills.append`; objeto → `add_item`; arma → `weapons.append` y la equipa si la tropa era Recluta o si el jugador lo pide desde la UI.
  - Después `level += 1`, vacía `pending_offers` y emite `EventBus.roster_changed` y `EventBus.troop_leveled(card)`.
- Señales nuevas en EventBus:
  - `level_up_offers_ready(card)`: la UI abre el modal de elección.
  - `troop_leveled(card)`.

## 6. `UnitFactory` (`Scripts/Systems/unit_factory.gd`, `class_name UnitFactory`, estático)
- `static func make_recruit(rng=null) -> TroopCard`:
  - Recluta Nv1 con nombre aleatorio (lista de unos 40 nombres/apellidos variados).
  - `base_health` = 100 ×(0.9–1.1); `base_damage` = 1.0 ×(0.9–1.1).
  - Un arma aleatoria de las que tienen `recruit_pool`.
- `static func recruit_price(card) -> int`: unos 40–70 según el arma y las variaciones.
- `static func make_enemy(round:int, is_elite:bool, is_boss_leader:bool, rng=null) -> TroopCard`:
  - Nivel ≈ 1 + ronda/3 (tope 10).
  - Especialidad aleatoria si nivel ≥ 2.
  - Arma acorde a la especialidad con `min_round <= ronda`.
  - Unas pocas habilidades y objetos al azar según el nivel (aplica `LevelUpSystem` en bucle, eligiendo al azar y sin cobrar).
  - Los multiplicadores de dificultad de `battle.gd difficulty_for` se aplican en combate sobre `base_health`/`base_damage`.
  - Jefe: `is_boss = true`, ×3.5 de vida y ×2 de daño (lo aplica combate).

## 7. `GameContent` (`Scripts/Systems/game_content.gd`, `class_name GameContent`, estático)
Lista explícita con `preload` de todos los recursos (sin escanear carpetas):
`static func weapons() -> Array[WeaponData]`, `specialties()`, `skills()`, `items()`, `find_weapon(id)`, `find_skill(id)`, `find_item(id)`, `find_specialty(id)`.

Contenido inicial en `Resources/Weapons/`, `Resources/Specialties/`, `Resources/Skills/` e `Resources/Items/` (los .tres viejos de Items se reescriben al formato nuevo).

**Armas (10)**:
| id | Familia | Notas |
|---|---|---|
| pistola | PISTOLA | recluta, floja y fiable, recarga rápida |
| subfusil | AUTOMATICA | recluta, mucha cadencia, poca precisión de lejos |
| fusil_asalto | AUTOMATICA | recluta, equilibrado |
| escopeta | ESCOPETA | recluta, 5 perdigones, alcance corto |
| rifle_francotirador | PRECISION | daño alto, 0.95 de precisión, lento, alcance muy largo |
| ametralladora | PESADA | cargador 40, recarga 4 s |
| lanzagranadas | EXPLOSIVO | proyectil GRANADA, área 70 |
| bazuca | EXPLOSIVO | cargador 1, área 90, daño enorme |
| lanzallamas | PESADA | LLAMA, alcance 140, quemadura |
| cuchillo | CUERPO_A_CUERPO | NINGUNO, alcance 45, magazine 0 |

**Especialidades (5)**:
| id | Familia afín | Pasiva |
|---|---|---|
| soldado | AUTOMATICA, ESCOPETA | "Disciplina": +10 % cadencia (`modifiers`) |
| francotirador | PRECISION | "Paciencia": +0.15 de precisión y +0.10 de crítico si lleva ≥1 s quieto (`effect paciencia`) |
| granadero | EXPLOSIVO | "Experto en demoliciones": +25 % de radio de explosión (`aoe_pct`) |
| medico | PISTOLA | "Primeros auxilios": cada 4 s cura un 6 % de la vida máx. al aliado más herido a ≤220 px (`effect primeros_auxilios`) |
| municionero | PESADA | "Suministros": +50 % de cargador y −25 % de recarga |

**Habilidades (unas 20)**:
- Generales:
  - Comando: +15 de vida.
  - Piel dura: +12 % de vida.
  - Pulso firme: +0.08 de precisión.
  - Ojo certero: +0.08 de crítico.
  - Velocista: +20 % de movimiento.
  - Esquiva: +0.12 de esquiva.
  - Gatillo fácil: +15 % de cadencia y −0.05 de precisión.
  - Recarga rápida: −25 % de recarga.
  - Camuflaje (effect): no le apuntan durante los 3 primeros segundos.
  - Último en pie (effect): +40 % de daño si es la última tropa viva de su equipo.
  - Venganza (effect): +30 % de cadencia durante 4 s cuando cae un aliado.
  - Sangre fría: +0.25 de multiplicador de crítico, requiere Ojo certero.
- Soldado:
  - Cargador ampliado: +40 % de cargador.
  - Oficial (effect aura): +15 % de cadencia a los aliados a ≤180 px.
  - Instinto veterano: +0.10 de crítico.
- Francotirador:
  - Mira láser: +0.10 de crítico y +0.10 de precisión.
  - Bala perforante: `pierce` 1.
  - Traje ghillie: effect camuflaje de 6 s.
- Granadero:
  - Carga extra: +20 % de daño.
  - Termobárica: `burn_dps` 4.
  - Blindaje pesado: +20 % de vida y armor 0.1.
- Médico:
  - Cirujano: curación +50 %.
  - Autocuración (effect): se cura un 2 % por segundo.
- Municionero:
  - Cinta de munición: +20 % de cadencia.
  - Balas trazadoras: +0.10 de precisión y +10 % de alcance.

**Objetos (8)**, con huecos:
- MUNICION:
  - Balas de punta hueca: +15 % de daño.
  - Balas incendiarias: `burn_dps` 5.
  - Balas perforantes: `pierce` 1.
- ARMADURA:
  - Chaleco táctico: +25 de vida y −5 % de movimiento.
  - Blindaje pesado: armor 0.2 y −15 % de movimiento.
- UTILIDAD:
  - Granada (effect granada): cada 6 s, área 70 y 30 de daño.
  - Botiquín (effect botiquin): una vez por combate, por debajo del 40 % de vida se cura el 35 %.
  - Inyector de adrenalina (effect adrenalina): al empezar el combate, +40 % de cadencia durante 5 s.
  - Mira telescópica: +15 % de alcance y +0.08 de precisión.

## 8. Combate (lo hace **combate**)
- `troop.gd`:
  - `setup(card: TroopCard)`: si `card.is_boss`, aplica escala visual.
  - Variables `stats` (Dictionary de TroopStats, recalculado en `refresh_stats()`), `ammo`, `reloading`, `reload_left`, `statuses` (quemadura, buffs con tiempo).
  - Getters de compatibilidad para la IA: `get_attack_range()`, `get_move_speed()`, `get_max_health()`.
- **Disparo**:
  - Cada perdigón tira acierto: `p = accuracy - falloff * max(0, dist - optimal)/100`, entre 0.05 y 0.98.
  - Acierto → proyectil hacia el objetivo, que hace daño al impactar.
  - Fallo → proyectil desviado (±0.25–0.45 rad) que no daña a nadie, y texto flotante gris "¡Fallo!".
- **Crítico**: texto "¡Crítico!", o "¡En la cabeza!" con armas PRECISION.
- **Área**: GRANADA y COHETE explotan en el punto del objetivo (o del fallo) y dañan a todos los enemigos dentro de `aoe_radius`, con un círculo visual que se desvanece.
- **LLAMA**: chorro corto y quemadura.
- **NINGUNO**: impacto instantáneo cuerpo a cuerpo.
- **Recarga**: con `ammo == 0`, recarga durante `reload_time` y muestra una barrita amarilla bajo la barra de vida mientras recarga.
- **Daño recibido**: primero esquiva (texto "¡Esquiva!"), luego armor y luego vida.
- **Quemadura**: daño por tick y tinte naranja.
- **Efectos** (`effects.gd`, `class_name Effects`): ganchos `on_fight_start`, `on_process(delta)`, `on_before_shot`, `on_hit`, `on_damaged`, `on_ally_died`, `on_kill`. Los efectos de especialidad, habilidad y objeto se despachan por `effect_id`.
- **Etiqueta** sobre la tropa: "Nombre Nv.X", con el color de la especialidad (blanco si es Recluta), más un emoji del arma.
- **Enemigos**: `battle.gd` usa `UnitFactory.make_enemy` y aplica `difficulty_for` a `base_health`/`base_damage` (una copia del card).
- **Persistencia**: `GameStateManager.save_deployed_troops` guarda `{card, position}` y `_restore_persisted_troops` hace `setup(card)`.
- Se mantienen sin cambios el mapa de calor, la ruleta, la tienda (que adapta interfaz), la cuadrícula y el arrastre.

## 9. UI (lo hace **interfaz**)
- **Submenú de tropa** (`troop_detail_panel.gd`, se reescribe; funciona igual con un nodo tropa o con un card de la reserva):
  - Cabecera: nombre, especialidad con su color y emoji, y nivel.
  - Estadísticas finales de `TroopStats`, con Vida y Daño destacados y el resto en un bloque "Arma".
  - Arsenal: armas con sus datos; clic en una no equipada = equiparla.
  - **3 huecos de objeto**: vacío o con el objeto (botón "Quitar" para devolverlo a la reserva).
  - Lista de objetos sueltos de la reserva que caben, para equiparlos.
  - Habilidades pasivas como chips con tooltip.
  - Pasiva de la especialidad.
  - Botón **"Subir a Nv. X (N 💰)"**: llama a `LevelUpSystem.begin_level_up` y abre el modal.
- **Modal de ascenso** (nuevo `Scripts/UI/level_up_choice.gd`, CanvasLayer, capa 30):
  - Título "¡{nombre} sube a Nv. X! Elige una".
  - 2 cartas grandes, cada una con:
    - Una etiqueta de tipo: ESPECIALIDAD (morado), HABILIDAD (azul, "no ocupa hueco"), OBJETO (naranja, "ocupa 1 hueco"), ARMA (rojo).
    - Emoji, nombre, descripción y rareza (borde de color).
  - **No se puede cerrar sin elegir.** Si se cierra el submenú, `pending_offers` se queda en el card y al reabrir vuelve a salir el modal.
- **Panel de Ejército** (`troop_roster_ui.gd`): cada tarjeta muestra nombre, especialidad (o "Recluta"), Nv., emoji del arma y huecos ocupados (●●○). Los objetos sueltos se siguen mostrando.
- **Tienda de reclutamiento** (`recruit_shop.gd`):
  - Ofrece 3 reclutas generados con `UnitFactory.make_recruit`, cada uno con nombre, arma, Vida, Daño y precio `UnitFactory.recruit_price`.
  - Las ofertas se generan al abrir la tienda por primera vez en la ronda y se guardan en `GameStateManager.shop_offers` (nucleo añade la variable y la limpia en `advance_stage`/`reset_run`).
  - Al comprar, la oferta desaparece.
- **Selección inicial** (`troop_selection_screen.gd`): 3 reclutas aleatorios (gratis), con la misma ficha.
- **Combate**: los textos flotantes son cosa de combate. La interfaz no toca el mapa de calor.

## 10. Coordinación
- **Candado de Godot**: solo un agente puede ejecutar el juego a la vez.
  - Antes de `project_run`, comprueba `_dev/godot.lock` con `cat`. Si contiene `busy:<otro>`, espera (`sleep 30`) y reintenta.
  - Para tomarlo, escribe `busy:<tu-nombre>`. Al terminar (después de `project_manage stop`), escribe `free`.
  - Nunca dejes el juego corriendo.
- **Flujo de edición**:
  - Edita archivos con python read-modify-write o heredoc vía `device_bash`.
  - Después, `filesystem_manage(op="scan")`.
  - Para ver errores de parseo, usa `logs_read(source="editor")`.
- **Pruebas**:
  - Escena propia `_dev/test_<area>.tscn` con un `.gd` que imprime `TEST PASS:` / `TEST FAIL:` y al final `TEST DONE: N fallos`.
  - Ejecuta con `project_run(mode="custom", scene=..., autosave=false)`, espera con `sleep` en `device_bash`, lee con `logs_read(source="game", count=200)` y para con `project_manage(op="stop")`.
- **Capturas**:
  - En el test: `await RenderingServer.frame_post_draw` y luego `get_viewport().get_texture().get_image().save_png("res://_dev/shots/<nombre>.png")`.
  - Para verlas: `device_stage_files` (ruta Windows `C:\Users\adri\Documents\proyectos\tropas-en-miniatura\_dev\shots\x.png`) y después `Read` sobre `stagedPath`.
  - **Mira de verdad las capturas** y corrige lo que se vea mal: solapes, texto cortado, cosas fuera de pantalla.
- **No borrar archivos** con `rm` (no hay permiso). Para retirar un recurso obsoleto, `filesystem_manage(op="remove")` lo manda a la papelera, o se deja sin referencias.
- **Comunicación**:
  - Si necesitas algo de otro agente (un método, un campo, un bug en su código), mándale un `SendMessage` concreto.
  - Al terminar, informa al orquestador (`main`) con un resumen: archivos tocados, API pública nueva, tests (N fallos) y capturas.

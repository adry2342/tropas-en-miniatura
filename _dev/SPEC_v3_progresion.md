# SPEC v3 — Progresión roguelite: Puntos de Mando + Monedas + Intendencia

Contrato técnico para los agentes. Si algo no está aquí, se decide con el orquestador (no se inventa API).
Godot 4.7.2, GDScript con tipos, comentarios y textos en español, estilo del proyecto (UiKit para UI).

## Decisiones cerradas (usuario, 2026-10-05)
- D1 Las armas YA NO salen al subir de nivel: se compran en la Intendencia.
- D2 Nv. 2 sigue ofreciendo especialidad (2 especialidades a elegir).
- D3 Puntos de Mando (PM) en bolsa COMÚN del ejército.
- D4 Interés por ahorrar monedas: +1 por cada 10, máx. +2.
- OMITIDO: hitos Veterano/Élite (Nv. 5/10) y reclutas de nivel alto. NO implementar.
- No hay guardado persistente: sin migración.

## 1. `Scripts/Systems/economy.gd` — `class_name Economy extends RefCounted` (dueño: W-ECO)
Única fuente de constantes de economía (todo `const` o `static func`; el equilibrado F6 solo toca este archivo y `battle.difficulty_for`).
```
const STARTING_COINS := 10
const STARTING_POINTS := 1
# Monedas por baja enemiga
const COINS_PER_KILL := 1          # batalla normal
const COINS_PER_KILL_ELITE := 2    # cualquier enemigo de una Batalla Élite
const COINS_PER_KILL_BOSS := 5     # el líder jefe (card.is_boss); sus escoltas dan COINS_PER_KILL
const WIN_BONUS_COINS := 2
const INTEREST_STEP := 10          # +1 por cada 10 monedas que tengas al ganar (antes del interés)
const INTEREST_MAX := 2
# Puntos de Mando por ronda ganada
const POINTS_PER_WIN := 2
const POINTS_PER_WIN_ELITE := 3
const CLEAN_WIN_BONUS_POINTS := 1  # ninguna tropa del jugador murió en la ronda
# Coste en PM para pasar de nivel L a L+1 (índice = L). Nv.10 es el máximo.
const LEVEL_COST := [0, 1, 2, 2, 3, 3, 4, 4, 5, 5]
# Precios Intendencia (índice = rareza 0..3)
const ITEM_PRICE := [5, 8, 12, 18]
const WEAPON_PRICE := [8, 10, 13, 15]
const SELL_RATIO := 0.5            # venta: floor(precio * 0.5), mínimo 1
const REROLL_BASE := 1             # 1ª renovación de la ronda; cada una más +1
const EQUIPMENT_OFFERS := 4
const WEAPON_OFFER_CHANCE := 0.3   # cada hueco de oferta: 30 % arma, 70 % objeto
# Rareza máxima ofertada en la Intendencia según la ronda
static func max_shop_rarity(round_num: int) -> int  # r<4 → 1, r<8 → 2, si no 3
# Pesos de rareza de HABILIDADES según el nivel al que se sube (target = card.level + 1)
static func skill_rarity_weights(target_level: int) -> Array  # ≤3: [60,30,10,5]; 4–6: [40,35,18,7]; ≥7: [25,35,27,13]
static func level_cost(level: int) -> int            # LEVEL_COST[level]; 0 si level ≥ MAX_LEVEL
static func coins_for_kill(enemy_card: TroopCard, node_type: String) -> int
static func price_of(res: Resource) -> int           # ItemData / WeaponData por rareza; TroopCard → recruit_price
static func sell_price(res: Resource) -> int
static func recruit_price(card: TroopCard) -> int    # clampi(roundi(UnitFactory.recruit_price(card) / 7.0), 6, 10)
static func reroll_price(reroll_count: int) -> int   # REROLL_BASE + reroll_count
static func interest_for(coins: int) -> int
static func points_for_win(node_type: String, clean: bool) -> int
```
Estadísticas por nivel (en `TroopStats`, dueño W-PROG): `LEVEL_HEALTH := 0.12`, `LEVEL_DAMAGE := 0.08`.
Entrenamiento (oferta de respaldo): `TRAINING_BONUS := 0.06` por rango a vida y daño (constante en `Economy`).

## 2. EventBus — señales nuevas (dueño: W-ECO)
```
signal coins_changed(total: int, delta: int)
signal command_points_changed(total: int, delta: int)
signal enemy_reward(world_pos: Vector2, coins: int)   # baja enemiga pagada (para texto flotante)
signal shop_requested(tab: String)                    # "equipo" | "reclutas" — abre la Intendencia
signal shop_changed                                   # ofertas/inventario de la Intendencia cambiaron
```
`recruit_shop_requested` se mantiene (equivale a `shop_requested("reclutas")`).
Toda variación de monedas/PM sigue emitiendo también `roster_changed` (la UI actual escucha esa).

## 3. GameStateManager (dueño: W-ECO)
- `var coins: int` y `var command_points: int`. `gold` queda como **alias** de compatibilidad
  (`var gold: int: get: return coins / set(v): coins = v`), igual que `add_gold`/`spend_gold` → `add_coins`/`spend_coins`.
  Código NUEVO usa siempre `coins`. Ningún texto de UI dice "oro": se dice "monedas" con 🪙.
- `add_coins(n, reason := "")`, `spend_coins(n) -> bool`, `add_points(n, reason := "")`, `spend_points(n) -> bool`.
- `start_new_run()` (o lo que haga `troop_selection_screen` al confirmar) fija `coins = Economy.STARTING_COINS`, `command_points = Economy.STARTING_POINTS`. Se elimina `STARTING_GOLD` (o queda como alias de STARTING_COINS).
- `reset_run()` pone ambos a 0, limpia `equipment_offers`, `reroll_count`, `round_kills`, `last_round_summary`.
- Seguimiento de ronda: `var round_kills := 0`, `var round_kill_coins := 0`, `var round_player_losses := 0`;
  `begin_round_tracking()` los pone a 0 (lo llama battle al empezar el combate).
  `register_enemy_kill(enemy_card, node_type) -> int` suma monedas (Economy.coins_for_kill), kills, devuelve las monedas.
  `register_player_loss()`.
  `apply_victory_rewards(node_type) -> Dictionary` (llamar UNA vez al ganar): suma WIN_BONUS_COINS, interés (calculado sobre `coins` tras bajas y bonus) y PM; guarda y devuelve
  `last_round_summary = {kills, kill_coins, win_coins, interest, points, clean, coins_total, points_total}`.
- Intendencia (estado; la lógica de tiradas es de ShopSystem):
  `var equipment_offers: Array = []` (ItemData / WeaponData / null = vendido), `var reroll_count := 0`.
  `advance_stage()` limpia `shop_offers`, `equipment_offers` y `reroll_count = 0`.
- Inventario: `player_bench` admite ahora también `WeaponData` además de TroopCard e ItemData.
  `get_bench_weapons() -> Array[WeaponData]`;
  `equip_weapon_from_bench(card, weapon) -> bool` (si la tropa no la tiene: la añade al arsenal y la quita del inventario; si ya la tiene: false);
  `sell_from_bench(res) -> int` (quita del inventario y suma `Economy.sell_price`; devuelve monedas ganadas, 0 si no estaba).
- `recruit_troop(card, price)` cobra en monedas (precio `Economy.recruit_price`).

## 4. TroopCard (dueño: W-ECO)
- `get_level_up_cost()` → `Economy.level_cost(level)` (en PM).
- Nuevo `@export var training_ranks: int = 0` (copiado en `duplicate_card`).
- `can_level_up()` sin cambios (nivel < MAX y sin ofertas pendientes).

## 5. Progresión — LevelUpSystem / TroopStats / modal (dueño: W-PROG)
- `begin_level_up(card)`: valida, **cobra PM** (`gsm.spend_points(card.get_level_up_cost())`), tira ofertas, emite `level_up_offers_ready`.
- `roll_offers`: si `card.specialty == null and card.level + 1 >= SPECIALTY_LEVEL` → 2 especialidades (como ahora).
  Si no → 2 **habilidades** distintas válidas (`_skill_ok`), con pesos de rareza `Economy.skill_rarity_weights(card.level + 1)`.
  Si no hay suficientes habilidades válidas → completar con ofertas `{type: "training", resource: null}` (como mucho una de training si hay al menos 1 habilidad).
  NUNCA `item` ni `weapon` (los tipos y TYPE_WEIGHTS de item/weapon desaparecen de la subida de nivel; `candidates()` puede seguir sirviendo a UnitFactory para enemigos — no romper `UnitFactory.make_enemy`).
- `apply_offer` soporta `"training"` → `card.training_ranks += 1`.
- `TroopStats.compute`: aplica `(1 + Economy.TRAINING_BONUS * card.training_ranks)` a vida máxima y multiplicador de daño; LEVEL_HEALTH 0.12 / LEVEL_DAMAGE 0.08.
- `level_up_choice.gd` y `UiKit.OFFER_TYPES`: carta para `"training"` ("ENTRENAMIENTO", +6 % vida y daño, acumulable).
- Enemigos: `UnitFactory.make_enemy` (líneas ~98–107) usa `LevelUpSystem.roll_offers(c, rng, round_num)` + `apply_offer` para subir a los enemigos. Para no cambiar su fuerza, `roll_offers` recibe un 4º parámetro `for_enemy: bool = false`; con `true` conserva EXACTAMENTE el comportamiento actual (pesos 55/25/20 habilidad/objeto/arma y RARITY_WEIGHTS fijos). W-PROG actualiza esa llamada en unit_factory.gd (archivo asignado también a W-PROG).

## 6. Bajas y recompensas (dueño: W-KILL)
- `battle.gd`: al empezar el combate `gsm.begin_round_tracking()`. En `_on_troop_died`: enemigo → `gsm.register_enemy_kill(card, node_type)` y `EventBus.enemy_reward.emit(pos, coins)`; tropa del jugador → `gsm.register_player_loss()`.
  Texto flotante "+N 🪙" dorado sobre el enemigo (reusar CombatFX).
- Al ganar (antes de mostrar la pantalla de recompensa o el panel de victoria final): `gsm.apply_victory_rewards(node_type)` UNA vez.
- `reward_screen.gd`: elimina el oro fijo. Muestra el resumen: "☠️ Bajas: N → +X 🪙", "🏁 Victoria +2 🪙", "📈 Interés +I 🪙" (si > 0), "⭐ +P Puntos de Mando" (+ "Victoria limpia +1" si aplica), totales 🪙/⭐, y la probabilidad de jefe como ahora.

## 7. Intendencia (dueño: W-SHOP)
- `Scripts/Systems/shop_system.gd` — `class_name ShopSystem`: `roll_equipment_offers(round_num, rng := null) -> Array` (EQUIPMENT_OFFERS recursos distintos; 30 % arma; rareza ≤ `Economy.max_shop_rarity`; pesos por rareza `LevelUpSystem.RARITY_WEIGHTS`; armas con `min_round <= round_num`), `ensure_offers()`, `buy_equipment(index) -> bool` (cobra, mete en `player_bench`, deja `null`), `reroll() -> bool`, `sell(res) -> int` (usa gsm.sell_from_bench). Emite `shop_changed`.
- `recruit_shop.gd` (MISMO archivo y nodo, los tests lo buscan por nombre) pasa a ser la **Intendencia**: título "🏪 INTENDENCIA", pestañas **Equipo** y **Reclutas**, `open(tab := "equipo")`. Escucha `shop_requested(tab)` y `recruit_shop_requested` (→ "reclutas"). Se mantienen `buy(card)`, `get_offers()`, `ensure_offers()` (reclutas) y su comportamiento (cerrar con Esc / al combatir / al llenar el ejército en Reclutas).
  - Equipo: 4 cartas (emoji, nombre con color de rareza, tipo/hueco, descripción corta, precio, botón Comprar o "Faltan N 🪙"), botón "🔄 Renovar (N 🪙)", fila "Inventario" con cada objeto/arma suelto y botón "Vender +N 🪙".
  - Cabecera con 🪙 monedas y ⭐ PM.

## 8. Integración de UI (dueño: W-UI)
- `prep_ui` (.gd/.tscn): botón **🏪 INTENDENCIA** abajo a la izquierda (espejo de ¡COMBATIR!: 176×60, offset 20 desde el borde, abajo -16) que emite `shop_requested("equipo")`; encima, ficha de recursos "🪙 N · ⭐ N" que se actualiza con las señales.
- `troop_roster_ui.gd`: cabecera "🪙 N  ⭐ N"; las armas sueltas del inventario aparecen como tarjetas (como los objetos) y se pueden arrastrar a una tropa (→ `gsm.equip_weapon_from_bench`).
- `troop_detail_panel.gd`: botón "⬆ Subir a Nv. N (⭐ c)", desactivado con tooltip "Faltan N ⭐" si no hay PM; cabecera con 🪙/⭐; en la sección de inventario se pueden equipar armas sueltas.
- `map.gd`: estadísticas "🪙 Monedas · ⭐ PM · 🏆 Victorias · 🎖️ Ejército".
- Ningún texto visible dice "oro" ni "💰".
- No se pisa la cuadrícula de despliegue (zona del jugador x 24–444, y 55–475 a 1152×648) ni la barra de Ejército.

## 9. Tests
- Cada fase entrega su test nuevo: `_dev/test_economia.tscn/.gd` (W-ECO, amplía W-KILL), `_dev/test_progresion.tscn/.gd` (W-PROG), `_dev/test_intendencia.tscn/.gd` (W-SHOP). Formato igual que los demás (`TEST PASS/FAIL`, `TEST DONE: N fallos (M ok)`, `get_tree().quit()` al final, capturas con `await RenderingServer.frame_post_draw` en `res://_dev/shots/`).
- Los tests existentes los adapta W-TEST (no los toquéis salvo que vuestra tarea lo diga).
- **Ejecutar Godot SIEMPRE con candado** (nunca dos a la vez):
  ```
  cd /tmp/proj && flock /tmp/godot.lock timeout 400 xvfb-run -a -s "-screen 0 1280x720x24" /tmp/godot --rendering-driver opengl3 --path . res://_dev/<test>.tscn > /tmp/<test>.log 2>&1; grep -E "TEST FAIL|TEST DONE|SCRIPT ERROR|Parse Error" /tmp/<test>.log
  ```
  Comprobar parseo de todo el proyecto: `flock /tmp/godot.lock timeout 200 /tmp/godot --headless --import --path /tmp/proj 2>&1 | grep -E "SCRIPT ERROR|Parse Error"`.
- Los tests deben terminar solos (`get_tree().quit()`); si uno se cuelga más de 6 min es un fallo.

## 10. Reglas de trabajo
- Proyecto de trabajo: `/tmp/proj` (git; NO hagas commits, el orquestador los hace). Solo editas tus archivos asignados.
- Si necesitas un cambio en un archivo ajeno, NO lo hagas: descríbelo en tu respuesta final.
- Respuesta final breve: archivos tocados, API añadida, resultado de tests (líneas TEST DONE), dudas/riesgos.

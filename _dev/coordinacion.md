# Tablón de coordinación entre agentes (añadir al final, no borrar)

## [interfaz] 1 — Qué espera la UI del nodo tropa (troop.gd)
- `troop.card: TroopCard` (lo leo con `troop.get("card")`).
- `troop.setup(card)` con UN argumento (lo uso para la vista previa de arrastre y al desplegar desde la reserva).
- El nodo `Sprite2D` sigue existiendo (tomo su `texture` para el icono).
- `troop.team` / `troop.Team.PLAYER` y grupo "troops" como hasta ahora.
- El nodo tropa se refresca solo al oír `EventBus.roster_changed` (subir de nivel, equipar/quitar objeto, cambiar arma desde el submenú).
- Equipar objeto soltándolo sobre una tropa: lo hago yo con `GameStateManager.equip_item_from_bench(troop.card, item)`; ya no llamo a `troop.equip_item`.
- No cargo `troop.tscn` con preload en mis scripts (uso `load()` en tiempo de ejecución), así un fallo de troop.gd no rompe mis scripts.
- Avisadme por SendMessage o aquí cuando `troop.gd`/`battle.gd` carguen para añadir la prueba integrada.

## 2026-10-03 · combate
- `troop.gd` y `battle.gd` (y bullet.gd, combat_fx.gd, effects.gd) **cargan sin errores**. Ya no usan TroopData.
- API de `troop.gd` para la UI:
  - `var card: TroopCard`, `var stats: Dictionary` (TroopStats.compute), `var health`, `var team`, `level` (getter = card.level).
  - `setup(card)` (vale antes o después de add_child), `refresh_from_card()` (alias `refresh_stats()`).
  - Se refresca SOLA con `EventBus.roster_changed` y `troop_leveled(card)` mientras no haya empezado el combate: la UI no tiene que llamar a nada al equipar/subir de nivel.
  - Getters: `get_max_health()`, `get_attack_range()`, `get_move_speed()`, `get_fire_rate()`, `get_damage()` (= stats.hit_damage), `get_crit_chance()`, `get_next_level_cost()`, `has_custom_sprite()`.
  - `equip_item(item)` existe solo por compatibilidad (hace card.add_item + roster_changed); lo correcto es `GameStateManager.equip_item_from_bench(card, item)`.
  - Ya NO existen: `troop_data`, `individual_items`, `level_up()`, `get_next_level_item()`.
- Arrastre, cuadrícula, retirada a reserva (`gsm.return_troop_to_bench(self)`), clic → `troop_inspect_requested`, `ui_blocking` y meta `is_drag_preview`: sin cambios.
- `battle.tscn` ya no trae el nodo `EnemyTroop`.

## 2026-10-03 · combate (cierre)
- test_combat: 0 fallos (arena propia + battle.tscn). Capturas en `_dev/shots/combat_*.png`.
- Nuevos archivos: `Scripts/Battle/combat_fx.gd` (class_name CombatFX: textos flotantes, explosiones, destellos, apply_hit) y `Scripts/Systems/effects.gd` (class_name Effects).
- `battle.gd`: `static func apply_difficulty(card, diff, is_boss_leader)` (±15 %, jefe ×3.5 vida / ×2 daño).
- Aviso para nucleo/interfaz: los emojis 🪖 (fusil_asalto) y ⛓️ (ametralladora) se ven como "caja" (glifo no soportado por la fuente). Conviene cambiarlos por otros que sí salen (🔫 🎯 🔥 💥 🚀 🧨 🔪 se ven bien).

## [interfaz] 2 — Terminado
- `_dev/test_ui.tscn` → TEST DONE: 0 fallos (78 ok), incluida la prueba integrada con battle.tscn (submenú de tropa del tablero, ascenso, refresco del nodo, retirar).
- Nuevo `Scripts/UI/ui_kit.gd` (class_name UiKit): estilos comunes y `UiKit.emo(e)` que cambia 🪖→🎖️ y ⛓️→🔗 (la fuente no los dibuja). Recluta usa 🔰.
- Nuevo `Scripts/UI/level_up_choice.gd` (CanvasLayer 30), lo crea el submenú y también escucha `level_up_offers_ready`.
- Godot libre (`free`).

## 2026-10-03 · combate
- troop.gd sustituye en la etiqueta 🪖→🎖️ y ⛓️→🔗 (EMOJI_FALLBACK), igual que la UI. test_combat sigue con 0 fallos. Los .tres siguen con los emojis originales (núcleo puede cambiarlos y entonces sobra el mapa).

## 2026-10-03 · qa
- Tests: test_core 0 fallos (68) · test_combat 0 (52) · test_ui 0 (78) · logic_test 0 (103) · test_e2e 0 (41, con Logger: 0 errores/avisos en tiempo de ejecución).
- Nuevos: `_dev/test_e2e.tscn/.gd` (menú → selección → mapa → batalla → ascensos → tienda → combate → recompensas → ronda 2), `_dev/balance_sim.tscn/.gd`.
- Retoques: etiqueta de la tropa dentro de su casilla (troop.gd), descripción real de objetos y pie del submenú (troop_detail_panel.gd), botón de la ruleta con estilo y texto al girar (map.gd), pantalla de recompensas opaca con botones visibles (reward_screen.gd), test_combat acepta el emoji actual del fusil (⚔️).
- Godot libre (`free`).

## 2026-10-03 · qa · pre-balance PROVISIONAL
- Oro inicial 60 (`GameStateManager.STARTING_GOLD`, se aplica en `troop_selection_screen.confirm_selection`).
- `battle.gd difficulty_for`: +4 % vida / +3 % daño por ronda; enemigos 1 + r/5 … 2 + r/4, tope 6 (constantes PROV_*).
- `UnitFactory`: nivel enemigo 1 + ronda/4; sin arma afín especial antes de la ronda 4 (AFFINE_WEAPON_MIN_ROUND). `rifle_francotirador.tres` min_round 3 → 4.
- Menú principal con título y botones UiKit.
- Tests: core 68 · combat 52 · ui 78 · logic 103 · e2e 41 → 0 fallos. Godot libre.

## 2026-10-03 · qa · e2e robusto + panel de fin de partida
- test_e2e: semilla fija + ventaja explícita (oro extra, 3 tropas); derrota forzada y explícita en la ronda 2 (panel → "Reiniciar run" → selección); victoria contra el jefe (panel → menú); autocomprobación del Logger. 3 ejecuciones seguidas: 0 fallos (50 ok).
- Bug real arreglado: `prep_ui._update_start_button` (y `battle._check_battle_status`) se ejecutaban en diferido fuera del árbol al cambiar de escena → "Cannot call method 'get_nodes_in_group' on a null value". Guardas `is_inside_tree()`.
- game_over_panel.gd: estilo UiKit (panel opaco, borde rojo/dorado, botones claros).
- Godot libre.

## 2026-10-05 · despliegue rediseñado
- `deployment_grid.gd`: cuadrícula 5x5 calculada a partir del tamaño de pantalla (casillas de 84 px a 1152x648), de la cabecera (54 px) a la barra de Ejército, pegada al borde (24 px). Zona enemiga ESPEJO dibujada en rojizo (`enemy_cells`, `get_enemy_cells()`, `get_player_rect()/get_enemy_rect()`, `cell_index_of()`, `DeploymentGrid.index_of()`). Paleta oliva/dorada, escuadras, línea de frente, rótulos de zona y resaltado de la casilla de destino al arrastrar (verde libre / naranja intercambio). z_index -2 (debajo del mapa de calor). Se desvanece al combatir. Señal `layout_changed` al redimensionar.
- `battle.gd`: enemigos en `grid.get_enemy_cells()`; recoloca tropas/enemigos y rehace el mapa de calor al redimensionar; guarda `cell` (índice) en `deployed_troops_data` y restaura por índice.
- Nuevo `battlefield_background.gd` (shader procedural de hierba y tierra de nadie, CanvasLayer -10).
- `prep_ui`: cabecera compacta (30 px) y botón ¡COMBATIR! abajo a la derecha.
- Tests: logic_test 106 · test_e2e 50 · test_ui 78 · test_core 68 · test_combat 0 fallos · nuevo `_dev/test_despliegue.tscn` 19 ok. Copias de los originales en `_dev/backup_despliegue/*.bak`.

## v3.2 (2026-10-06) — cambios menores
- Fichas de recluta (primer recluta e Intendencia): línea "🎒 objeto" o "🎒 Sin objeto" y "🎖️ Especialidad" si la trae, con tooltip (`UiKit.recruit_extras_box`).
- Especialidad del jugador en **Nv. 5** (`TroopCard.SPECIALTY_LEVEL`); enemigos siguen en Nv. 2 (`ENEMY_SPECIALTY_LEVEL`).
- Reclutas de la Intendencia: 20 % vienen ya especializados (+4 💰, `Economy.RECRUIT_SPECIALTY_*`). `make_recruit(rng, allow_specialty)`; el primer recluta nunca.
- Menú de mejora: botón 👀 "mantén pulsado para ver la tropa" (`set_peek`); capa invisible bloquea clics; no se puede elegir mirando; COMBATIR e Intendencia ignoran pulsaciones con la elección abierta (grupo `level_up_modal`).
- Jefes más suaves: BOSS_HP_MULT 2.1, BOSS_DMG_MULT 1.5, Jefe de Sector 310/640/1150/1800 (+700). Sim: Sector R10 68 % (antes 43–53 %).
- Rifle de francotirador 0.4 → 0.3 disp/s.
- "¡Fallo!" solo si no acierta ningún perdigón. Balas desviadas (solo BALA) golpean a la primera tropa que crucen: enemigo = acierto (`register_stray_hit`), aliado = fuego amigo (sin efectos del atacante). Explosiones, llamas y cuerpo a cuerpo no hacen fuego amigo.
- Test: `_dev/test_v32.tscn` (42 comprobaciones). Gancho de pruebas `troop.force_hit_pattern`.

## v4 (2026-10-06) — combate táctico, especialidades con mecánicas y partidas de ~30 rondas
- **IA de movimiento** (troop.gd `_ai_step`): objetivo por carril (`LANE_WEIGHT`) con histéresis; distancia de combate por arma (`engage_distance`); aproximación en arco desde su carril; separación entre aliados; retirada breve de armas largas ante cuerpo a cuerpo; disparo en marcha solo armas ligeras (`fire_on_move`, −12 % precisión); límites del campo (grupo `deployment_grid`).
- **Armas**: alcances nuevos (franco 620 > bazuca 500 > ametralladora 360 > fusil 340 > subfusil 230 > pistola 200 > escopeta 175 > llamas 130 > cuchillo 40). `close_bonus`: precisión extra de cerca (pistola, escopeta, fusil, subfusil); franco −0,35 de cerca. Bazuca `min_range` 110 y radio 75. Explosiones con caída hacia el borde (35 %). **Lanzagranadas retirado** del catálogo (el .tres queda sin uso); la granada sigue como objeto.
- **Especialidades** (mecánicas, no solo números; `extra_effects`, `synergy_text`): Soldado = supresión; Francotirador = tirador de élite (+25 % crítico a suprimidos/marcados) + paciencia; Médico = primeros auxilios + estabilizar; Municionero = reparto de munición (aura −30 % recarga); Zapador (id granadero) = minas + carga hueca; **Radioperador** (id comunicaciones, nuevo) = mapa de calor en la planificación solo si está desplegado + marcar + artillería. Habilidades nuevas: coordenadas_precisas, enlace_tactico, campo_minado. Códice con pestaña Especialidades.
- **Progresión**: 1 PM por victoria (2 élite/sector), sin bonus limpio; monedas 1/baja (2 élite, 4 jefe) +2 por victoria; precios objetos 6/10/15/22, armas 9/12/15/18.
- **Dificultad por presupuesto de poder** (battle.gd `power_budget` + `normalize_wave`): Σ vida×DPS de la oleada = 600 + 125·x + 5,4·x² (x = ronda−1) ±10 %; élite ×1,3, sector ×1,5 (vida fija 360/650/1050/1550), final ×3,2. Jefe final desde la ronda 26 (+2 %/ronda).
- **Simulador** (bot sensato, 51 partidas): media 30,8 rondas, mediana 33, p10 17, p90 39. Sector 96 %, jefe final 74 %. Objetos equipados: R10 3,7 · R20 7,5 · R30 15. Nivel máx. R30: 5–7 (el bot reparte; concentrando, una tropa llega a Nv. 10).
- Tests: `_dev/test_v4.tscn` (42). Laboratorio visual: `_dev/ai_lab.tscn -- seed=N round=R elite=1 army=b`.

## v4.1 (2026-10-06)
- Jefe final: ruleta desde la ronda 11 (tras ganar la 10), +0,5 % por ronda (R30 = 10 %). La barra de la ruleta no se ve antes (`map._track_holder`). Porcentajes con decimal (`map.pct_text`).
- Sin pasos atrás: quitada la retirada; la bazuca ya no tiene distancia mínima.
- Enemigos con la misma variedad de armas que los reclutas (`UnitFactory.enemy_weapon_options`, con min_round). Medido con `ai_lab mirror=1`: con ejércitos idénticos ambos bandos se mueven igual (no era un bug); la diferencia venía de la composición (sin tropas de choque) y de que el jugador va a buscarlos.
- Zapador: la mina va en mitad del campo, en su fila.
- "Mueren antes de tiempo": no era un bug (golpes grandes de franco/cohete; medido con `last_damage`). Ahora: números de daño blancos agrupados cada 0,22 s, barra de vida sin redondeo, impacto letal repartido por segundo de fuego (antes por disparo).
- Adrenalina: +30 % de velocidad además de cadencia; aura roja y estelas (`is_frenzied`); venganza también. Velocista: estelas suaves.
- Camuflaje: no dispara mientras dura; quien tiene camuflaje no dispara en marcha (espera a su distancia de combate).
- Sim (56 partidas): media 26,6 rondas, mediana 26, p10 14, p90 37; jefe final 72 % ganado.

## v4.2 (2026-10-06)
- Piel dura: +50 de vida (no acumulable). Comando retirada del catálogo (el .tres queda sin uso).
- Cargadores más cortos (más recargas): pistola 7, subfusil 18, fusil 15, escopeta 4, ametralladora 25, lanzallamas 30, francotirador 3.
- Revisado con `_dev/offer_freq.gd` (3000 tropas): todas las especialidades salen por igual (Radioperador ~1/6 de las elecciones) y todas las habilidades se ofrecen; las de especialidad solo a quien la tiene.

# Equilibrado v3 — progresión y economía (W-SIM)

Simulador de **partida completa** con combates reales: `_dev/run_sim.tscn` (`run_sim.gd`).
Cada partida: `reset_run` → monedas/PM iniciales → elige 1 de 3 reclutas → por ronda: `roll_round_type` (ruleta de jefe +2 %/ronda, élite 20 % desde la ronda 3),
subida de nivel con PM (`LevelUpSystem.begin_level_up` + `choose`), compras en la Intendencia (`ShopSystem.ensure_offers/buy_equipment/reroll`,
`gsm.recruit_troop` con `Economy.recruit_price`, `gsm.equip_item_from_bench`, `gsm.equip_weapon_from_bench`), despliegue en la `DeploymentGrid` 5×5
(frente = última columna) y combate real de `battle.tscn` (`--headless --fixed-fps 60`, tiempo de juego sin límite de 60 FPS reales).
Monedas por baja, bonus, interés y PM salen de las APIs reales (`register_enemy_kill`, `apply_victory_rewards`). Fin: derrota, combate de jefe o ronda 15.

Uso: `flock /tmp/godot.lock timeout 500 /tmp/godot --headless --fixed-fps 60 --path . res://_dev/run_sim.tscn -- policy=ambas runs=400 seconds=330 out=/tmp/x.csv tag=x`
(añade una fila por ronda al CSV; termina con `RUNSIM DONE`).

**Políticas**
- *sensato*: sube primero la tropa más barata (a igualdad, la más fuerte); en la oferta elige especialidad afín a su arma, si no la habilidad de mayor rareza (bonus si es de especialidad), entrenamiento como último recurso. Compra lo que más **poder de ejército por moneda** da (reclutas si hay hueco, objeto/arma equipado en la tropa que más gana); ahorra si algo ≤ 5 🪙 más caro rinde ×1,3; renueva 1 vez si sobran ≥ 12 🪙 y nada sirve. Despliega alcance corto delante.
- *aleatorio*: sube al azar (30 % de guardar PM), elige oferta al azar, compra cosas asequibles al azar (75 % de seguir), equipa al azar, despliega en casillas al azar.

Poder = Σ(vida) × Σ(DPS) (Lanchester) con las estadísticas reales de `TroopStats`; la columna *poder J / E* es Σ vida×DPS.

## Constantes: antes → después

| Archivo | Constante | Antes (HEAD) | Después | Por qué |
|---|---|---|---|---|
| economy.gd | STARTING_COINS | 10 | **16** | permite el primer recluta (13–19 🪙) antes de la ronda 1 → victoria R1 ≥ 90 % |
| economy.gd | WIN_BONUS_COINS | 2 | **4** | sin él, con reclutas más caros, el sensato apenas compraba objetos (≈ 1 en 10 rondas) |
| economy.gd | LEVEL_COST | [0,1,2,2,3,3,4,4,5,5] | **[0,1,1,2,2,3,3,4,4,5]** | Nv 3 llega antes: la primera habilidad real se nota en la ronda 2 |
| economy.gd | recruit_price | /7, entre 6 y 10 | **/3,3, entre 13 y 19** (`RECRUIT_PRICE_DIVISOR/MIN/MAX`) | un recluta valía lo mismo que un objeto común y siempre era la mejor compra: el sensato llenaba 6 huecos y los niveles se diluían |
| battle.gd | PROV_HP_PER_ROUND | 0,04 | **0,035** | curva de enemigos ×10 entre R1 y R8 frente a ×4 del jugador; (logic_test exige > 0,0306) |
| battle.gd | PROV_DMG_PER_ROUND | 0,03 | 0,03 | — |
| battle.gd | enemigos mín. | 1 + r/5 | **1 + r/8** (`PROV_MIN_ENEMIES_EVERY`) | evita el escalón de R6–R8 (coincidía con el salto de nivel enemigo de R8) |
| battle.gd | enemigos máx. | 2 + r/4 | **2 + r/6** (`PROV_MAX_ENEMIES_EVERY`) | ídem; el 3.er enemigo aparece en R7 |
| battle.gd | élite | ×1,3 vida, ×1,2 daño, +1 enemigo | **×1,0 / ×1,0**, +1 enemigo (`PROV_ELITE_*`) | ya llevan +1 nivel y +1 enemigo: el sensato ganaba solo el 41 % de los élites (ahora 64 %) |
| battle.gd | boss_count | min(2 + r/5, 5) | **min(1 + (r+1)/7, 4)** (`PROV_BOSS_*`) | el jefe se ganaba el 0 % de las veces |
| unit_factory.gd | niveles extra del líder jefe | +2 | **+1** (`BOSS_EXTRA_LEVELS`) | ídem; con +1 sigue el tope 10 que exige test_core (`enemy_level(30, élite, jefe) = 10`) |

Sin cambios: monedas por baja (1 / 2 élite / 5 jefe), interés (+1 cada 10, máx. +2), PM (2 / 3 élite / +1 limpia), precios de objetos [5,8,12,18] y armas [8,10,13,15]
(test_economia los comprueba literalmente), renovación, `enemy_level` (test_core fija Nv 1 en R1, Nv 4 en R12 y élite R6 = Nv 3), pesos de rareza.

## Resultado frente a los objetivos (sensato, después)

| Objetivo | Antes | Después |
|---|---|---|
| Victoria R1 ≥ 90 % | 97 % | **94 %** ✔ |
| Victoria R5 ≈ 75 % | 66 % | **76 %** ✔ |
| Victoria R10 ≈ 55–60 % (si llega) | 25 % (n = 8) | **54 %** (n = 13; R9 52 %, n = 25) ≈ ✔ |
| Poder jugador R8 / R1 ≥ ×2,5 | ×4,3 (por acumular 5 tropas) | **×4,3** (3,7 tropas + niveles + equipo) ✔ |
| Nivel máx. medio en R8 entre 4 y 7 | 4,1 | **5,9** ✔ (nivel medio 3,6 → 4,9) |
| 10 rondas: ~2 reclutas | 3,9 + el de la R1 | **2,3 + el de la R1** (3,2 en total) ≈ ✔ |
| 10 rondas: 3–5 objetos/armas | 2,8 | **3,9** ✔ |
| Nunca > 40 🪙 sin gastar | máx. 17 | **máx. 31** ✔ |
| Aleatorio claramente peor | R1 59 %, fin medio R2,7 | **R1 56 %, fin medio R2,9 vs R6,2 del sensato** ✔ |
| Élite / jefe (sensato) | 41 % / 0 % | 64 % / 16 % |

## Tabla por ronda

Lotes: *antes* = `base` (HEAD, 150 + 150 partidas), *después* = `f2` (114 sensato + 113 aleatorio). Columnas “acum.” = compras acumuladas hasta esa ronda (incluido el recluta inicial de la R1).
Datos completos (todas las rondas) en `_dev/balance_v3.csv` (columna `config`: `antes`, `iter1` = este lote f2, `iter2` = iteración 2).

### Sensato — antes
| R | partidas | llegan % | victoria % | 🪙 +/− | PM +/− | 🪙 al final | Nv medio / máx | tropas | objetos eq. | reclutas acum. | equipo acum. | poder J / E |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 150 | 100 | 97 | 3.5 / 6.8 | 2.9 / 1.0 | 6.7 | 1.5 / 2.0 | 2.0 | 0.0 | 1.0 | 0.0 | 2687 / 1698 |
| 2 | 145 | 97 | 99 | 3.6 / 5.9 | 3.0 / 3.0 | 4.5 | 2.13 / 3.0 | 2.74 | 0.23 | 1.74 | 0.23 | 4350 / 1922 |
| 3 | 144 | 96 | 91 | 3.6 / 1.9 | 2.8 / 2.7 | 6.1 | 2.73 / 4.0 | 2.78 | 0.57 | 1.78 | 0.57 | 5255 / 2999 |
| 4 | 131 | 87 | 74 | 2.8 / 4.7 | 2.3 / 2.5 | 4.5 | 2.83 / 4.0 | 3.45 | 0.63 | 2.45 | 0.63 | 6468 / 6229 |
| 5 | 97 | 65 | 66 | 2.9 / 3.1 | 2.1 / 3.3 | 5.0 | 3.17 / 4.06 | 3.77 | 0.87 | 2.77 | 0.87 | 7627 / 9214 |
| 6 | 64 | 43 | 62 | 3.3 / 4.1 | 1.9 / 3.4 | 5.1 | 3.39 / 4.12 | 4.19 | 1.12 | 3.19 | 1.12 | 8914 / 10949 |
| 7 | 40 | 27 | 78 | 3.9 / 4.9 | 2.4 / 2.9 | 5.2 | 3.42 / 4.08 | 4.85 | 1.32 | 3.85 | 1.32 | 10260 / 10207 |
| 8 | 31 | 21 | 48 | 3.1 / 4.5 | 1.6 / 2.9 | 4.4 | 3.58 / 4.06 | 5.23 | 1.74 | 4.23 | 1.74 | 11545 / 15525 |
| 9 | 15 | 10 | 53 | 3.3 / 3.5 | 1.6 / 3.4 | 5.9 | 3.9 / 4.27 | 5.27 | 2.47 | 4.27 | 2.47 | 12545 / 15652 |
| 10 | 8 | 5 | 25 | 2.2 / 7.0 | 0.8 / 2.9 | 3.9 | 3.81 / 4.62 | 5.88 | 2.62 | 4.88 | 2.75 | 13996 / 25705 |

### Sensato — después
| R | partidas | llegan % | victoria % | 🪙 +/− | PM +/− | 🪙 al final | Nv medio / máx | tropas | objetos eq. | reclutas acum. | equipo acum. | poder J / E |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 114 | 100 | 94 | 5.2 / 13.5 | 2.8 / 1.0 | 7.7 | 1.53 / 2.0 | 1.95 | 0.0 | 0.95 | 0.0 | 2598 / 1608 |
| 2 | 107 | 94 | 98 | 5.9 / 3.6 | 2.9 / 3.0 | 9.7 | 3.0 / 3.01 | 2.0 | 0.6 | 1.0 | 0.63 | 4035 / 2019 |
| 3 | 105 | 92 | 96 | 6.2 / 6.0 | 3.1 / 2.0 | 10.0 | 3.29 / 4.0 | 2.26 | 1.02 | 1.26 | 1.09 | 4940 / 2344 |
| 4 | 101 | 89 | 79 | 4.8 / 5.6 | 2.5 / 4.0 | 9.2 | 4.05 / 5.0 | 2.46 | 1.51 | 1.46 | 1.61 | 6477 / 4524 |
| 5 | 80 | 70 | 76 | 4.9 / 5.6 | 2.4 / 2.4 | 9.4 | 4.27 / 5.0 | 2.73 | 1.94 | 1.73 | 2.01 | 7457 / 5912 |
| 6 | 61 | 54 | 89 | 5.8 / 6.2 | 2.8 / 3.4 | 10.2 | 4.61 / 5.33 | 3.02 | 2.3 | 2.02 | 2.43 | 8775 / 5172 |
| 7 | 51 | 45 | 75 | 5.8 / 5.8 | 2.4 / 2.9 | 10.5 | 4.8 / 5.61 | 3.27 | 2.67 | 2.27 | 2.86 | 9898 / 8468 |
| 8 | 36 | 32 | 69 | 4.9 / 6.7 | 2.2 / 3.3 | 9.2 | 4.85 / 5.92 | 3.67 | 2.94 | 2.67 | 3.14 | 11190 / 14352 |
| 9 | 25 | 22 | 52 | 3.9 / 6.0 | 1.6 / 2.8 | 8.3 | 5.04 / 6.12 | 3.88 | 3.4 | 2.88 | 3.64 | 12387 / 16575 |
| 10 | 13 | 11 | 54 | 5.2 / 4.9 | 1.7 / 2.8 | 10.2 | 5.14 / 6.38 | 4.23 | 3.54 | 3.23 | 3.92 | 13887 / 17596 |

### Aleatorio — antes
| R | partidas | llegan % | victoria % | 🪙 +/− | PM +/− | 🪙 al final | Nv medio / máx | tropas | objetos eq. | reclutas acum. | equipo acum. | poder J / E |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 150 | 100 | 59 | 2.1 / 6.0 | 1.8 / 0.6 | 6.0 | 1.48 / 1.59 | 1.38 | 0.39 | 0.38 | 0.51 | 1753 / 1562 |
| 2 | 88 | 59 | 77 | 3.0 / 4.0 | 2.3 / 1.7 | 5.4 | 2.18 / 2.49 | 1.67 | 0.93 | 0.67 | 1.08 | 2602 / 1915 |
| 3 | 68 | 45 | 71 | 2.9 / 3.2 | 2.2 / 1.7 | 5.9 | 2.57 / 3.13 | 2.0 | 1.21 | 1.0 | 1.28 | 3378 / 3380 |
| 4 | 48 | 32 | 62 | 2.3 / 3.5 | 2.0 / 2.3 | 5.7 | 2.97 / 3.77 | 2.27 | 1.44 | 1.27 | 1.54 | 4225 / 5654 |
| 5 | 30 | 20 | 30 | 1.4 / 4.0 | 0.9 / 2.0 | 4.6 | 3.16 / 4.27 | 2.63 | 1.57 | 1.63 | 1.73 | 5118 / 8616 |
| 6 | 9 | 6 | 33 | 1.6 / 3.6 | 1.0 / 2.0 | 5.0 | 3.77 / 5.11 | 2.78 | 2.0 | 1.78 | 2.33 | 6070 / 12010 |
| 7 | 3 | 2 | 67 | 3.0 / 4.3 | 2.0 / 4.3 | 5.0 | 5.75 / 6.33 | 2.33 | 2.67 | 1.33 | 3.67 | 7048 / 5651 |

### Aleatorio — después
| R | partidas | llegan % | victoria % | 🪙 +/− | PM +/− | 🪙 al final | Nv medio / máx | tropas | objetos eq. | reclutas acum. | equipo acum. | poder J / E |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 113 | 100 | 56 | 3.3 / 9.7 | 1.7 / 0.7 | 9.6 | 1.58 / 1.65 | 1.25 | 0.54 | 0.25 | 0.9 | 1701 / 1604 |
| 2 | 63 | 56 | 79 | 4.9 / 6.1 | 2.4 / 1.7 | 9.6 | 2.6 / 2.78 | 1.44 | 1.14 | 0.44 | 1.65 | 2665 / 2114 |
| 3 | 50 | 44 | 76 | 4.9 / 6.5 | 2.4 / 1.8 | 9.0 | 3.4 / 3.74 | 1.56 | 1.66 | 0.56 | 2.46 | 3463 / 2824 |
| 4 | 38 | 34 | 58 | 3.7 / 5.8 | 1.8 / 2.5 | 7.3 | 4.16 / 4.58 | 1.66 | 2.32 | 0.66 | 3.39 | 4317 / 3912 |
| 5 | 22 | 19 | 68 | 4.0 / 6.7 | 2.1 / 2.8 | 7.0 | 4.98 / 5.32 | 1.77 | 2.77 | 0.77 | 4.18 | 5552 / 4140 |
| 6 | 15 | 13 | 67 | 3.8 / 5.4 | 2.1 / 2.5 | 6.3 | 5.86 / 6.33 | 1.67 | 3.2 | 0.67 | 5.4 | 6271 / 9092 |
| 7 | 10 | 9 | 80 | 4.8 / 3.0 | 2.5 / 2.3 | 8.9 | 6.45 / 6.9 | 1.7 | 3.4 | 0.7 | 6.1 | 6774 / 7899 |
| 8 | 8 | 7 | 38 | 2.9 / 7.5 | 1.1 / 0.9 | 5.0 | 6.52 / 7.0 | 1.75 | 3.62 | 0.75 | 7.12 | 7805 / 13944 |
| 9 | 3 | 3 | 33 | 2.7 / 6.0 | 1.3 / 5.0 | 5.0 | 7.56 / 7.67 | 2.0 | 4.0 | 1.0 | 7.67 | 9810 / 11489 |

## Iteraciones (≈ 46 min de simulación, siempre con `flock /tmp/godot.lock`)

| Lote | Cambio principal | Sensato R1/R5/R8 | Reclutas / equipo en R10 | Nota |
|---|---|---|---|---|
| base | HEAD | 97 / 66 / 48 | 4,9 / 2,8 | reclutas baratísimos, élite 41 %, jefe 0 % |
| s1–s3 | 12 🪙 iniciales, +3 victoria, LEVEL_COST más barato, reclutas 9–15, élite ×1,15/×1,1, jefe +0 niveles y menos escoltas | 95–98 / 65–81 / 59–75 | ~5 / 1–2 | apenas compra objetos; caída en R4 |
| s4 | reclutas 12–18, 15 🪙, élite ×1,1/×1,05 | 95 / 60 / 36 | 3,5 / 3 | el ejército más pequeño hace la mitad de la partida demasiado difícil |
| s5–s6 | +3,5 % vida/ronda, élite ×1,0, máx. enemigos cada 5, mín. cada 6→8 | 94 / 80 / 48–54 | ~3 / 2,5 | escalón en R6 y en R8 |
| f1 | máx. enemigos cada 6, escoltas cada 7, +4 victoria | 93 / 89 / 67 (R10 75 %) | 3,7 / 3,1 | algo fácil, demasiados reclutas |
| **f2** | reclutas 13–19 (/3,3), 16 🪙 | **94 / 76 / 69 (R10 54 %)** | **3,2 / 3,9** | elegido |

## Riesgos y propuestas

- **Jefe**: el sensato solo gana el 16 % de los jefes (el 39 % de las partidas sensatas termina en un combate de jefe). Con valores propios ya no puedo bajarlo más sin dejarlo sin escoltas. Propuesta (fuera de mis archivos): `battle.BOSS_HP_MULT` 3,5 → 2,5 (o BOSS_DMG_MULT 2,0 → 1,6), o que la ruleta no pueda sacar el jefe antes de la R5.
- **Rondas altas con poca muestra**: por la ruleta de jefe solo el 11 % de las partidas sensatas llega a la R10 (n = 13); la cifra de R10 tiene ±14 puntos de error.
- **El salto de nivel enemigo de la R8** (1 + ronda/4) sigue marcando un escalón; `enemy_level` no se puede tocar sin romper test_core (Nv 1 en R1, Nv 4 en R12, élite R6 = Nv 3).
- **Reclutas**: el número de tropas sigue siendo la palanca más fuerte (Lanchester). El precio por calidad (13–19) lo controla, pero un jugador que solo ahorre para reclutas puede llenar 6 huecos hacia la R12. Propuesta de mecánica: precio de recluta + N 🪙 por cada tropa que ya tengas (el simulador lo admite con `recruit_step=N`, no medido aún).
- El bot sensato reparte niveles (sube primero la tropa más barata); un jugador que concentre PM en un “héroe” llegará a Nv 7–8 en la R8.
- Los objetos de rareza 0 a 5 🪙 compiten con un recluta de 13–19 🪙: el sensato compra objetos sobre todo cuando le faltan > 5 🪙 para un recluta. Si se quisiera más equipo, bajar ITEM_PRICE[0] a 4 (choca con test_economia).

## Comprobaciones literales de tests que chocan

- `test_economia._test_kill_timing` fija `current_stage = 5` y espera ≥ 3 enemigos: con `max = 2 + r/6` la ronda 5 tiene como máximo 2 (el 3.er enemigo llega en la R7) → **FALLO “batalla real con enemigos (1)”** + `SCRIPT ERROR queue_free` en cadena. Arreglo (W-TEST): usar `current_stage = 7` (o mayor).
- `test_progresion`: 0 fallos (23 ok).
- `test_core` “jefe: nivel con tope 10”: fallaba con el valor intermedio `BOSS_EXTRA_LEVELS = 0`; con el valor final (+1) se cumple (1 + 30/4 + 1 + 1 = 10).
- Revisados sin choque: logic_test (dificultad monótona, R2−R1 < 0,15, R50 vida ×2,72 > 2,5), test_combat (vida R12 > ×1,5 R1: ≈ ×1,9), test_core (`enemy_level`, `recruit_price` en [MIN, MAX]), test_economia (precios de objetos/armas sin cambiar), test_e2e (añade 60 🪙 antes de reclutar).


---

# Iteración 2 (veredicto J-GAME: NO APTO → cambios del orquestador + ajuste fino)

## Cambios

| Archivo | Constante | Iteración 1 | Iteración 2 | Origen |
|---|---|---|---|---|
| game_state_manager.gd | BOSS_MIN_ROUND (nueva) | — | **6** (antes no hay jefe y la probabilidad no sube) | orquestador |
| game_state_manager.gd | BOSS_CHANCE_STEP | 0,02 desde R2 | **0,05** desde R6 (5 % en R6 … 30 % en R11) | orquestador |
| game_state_manager.gd | BOSS_FORCED_ROUND (nueva) | — | **12** (`boss_chance = 1.0`, el mapa muestra 100 %) | orquestador |
| troop_stats.gd | LEVEL_HEALTH / LEVEL_DAMAGE | 0,12 / 0,08 | **0,15 / 0,10** | orquestador |
| economy.gd | COINS_PER_KILL / _ELITE | 1 / 2 | **2 / 3** | orquestador |
| economy.gd | WIN_BONUS_COINS | 4 | **3** | orquestador |
| economy.gd | POINTS_PER_WIN / _ELITE | 2 / 3 | **3 / 4** | W-SIM: con 2 PM el poder por tropa se estancaba desde R6 (los reclutas nuevos entran a Nv 1 y los PM no llegaban) |
| battle.gd | BOSS_HP_MULT | 3,5 | **2,6** | orquestador pidió 2,5: con 2,5 el sensato ganaba el 62 % de los jefes (lote g1, enemigos aún blandos); 3,0 → 24 %; 2,6 → 32–35 % |
| battle.gd | PROV_HP_PER_ROUND / PROV_DMG_PER_ROUND | 0,035 / 0,03 | **0,065 / 0,055** | W-SIM: con más PM, +25 % por nivel y más monedas el juego quedaba fácil (g1: R5 87 %, R8 89 %) |

Código (mínimo): `GameStateManager.boss_chance_for_round(round, prev)` (estática) la usa `advance_stage`; `roll_round_type` no da jefe antes de `BOSS_MIN_ROUND` y lo da siempre desde `BOSS_FORCED_ROUND`;
nueva `next_boss_chance()` para la pantalla de recompensas (ver riesgos). Sin cambios: precios, LEVEL_COST, `enemy_level`, número de enemigos, élite, escoltas.

Simulador: políticas nuevas `heroe` (todos los PM a la tropa inicial; solo si está a Nv 10, a las demás), `solo_reclutas` (como sensato pero solo compra reclutas)
y `ahorrador` (como sensato pero nunca baja de 20 🪙 para cobrar el interés máximo). `policy=` admite una lista separada por comas que se reparte en ciclo.
El CSV de resumen trae por ronda los combates de jefe y élite y su % de victoria, y el poder por tropa.

## Lotes (≈ 50 min, con candado; hubo que repetir un trozo porque el primer `h1` se cortó)

| Lote | Config | Sensato R1 / R5 / R8 / R10 | Jefe | Nota |
|---|---|---|---|---|
| g1 (50 + 49 héroe) | cambios del orquestador (jefe ×2,5) | 96 / 87 / 89 / 67 | 62 % | demasiado fácil |
| g2 (95) | jefe ×3,0, +5,5 % vida / +4,5 % daño por ronda | 96 / 82 / 68 / 75 | 24 % | poder por tropa plano desde R6 |
| g3 + h1–h3 (**final**) | jefe ×2,6, +6,5 % / +5,5 %, PM 3/4 | ver tabla | 32 % | 358 sensato, 106–107 por cada otra política |

## Resultado final frente a objetivos

| Objetivo | Resultado (iteración 2) |
|---|---|
| Victoria R1 ≥ 90 % | **95 %** ✔ |
| R5 ≈ 75 % | **85 %** ✘ (algo fácil) |
| R10 ≈ 55–60 % | **66 %** (n = 67) ≈ (algo fácil) |
| Poder R8 / R1 ≥ ×2,5 | **×5,8** ✔ (R10 ×7,4; enemigo ×13,7) |
| Poder por tropa creciente | **1378 → 2166 → 2670 → 3093 → 3414 → 3702 → 3896 → 4092 → 4211** (R1→R9) ✔ |
| Nivel máx. medio R8 entre 4 y 7 | **6,8** ✔ |
| Jefe 35–45 % | **32 %** (n = 131) ≈ (justo por debajo) |
| 10 rondas: ~2 reclutas / 3–5 equipo | 2,9 (+ inicial) / 3,6 ✔≈ |
| Sensato nunca > 40 🪙 | máx. 37 ✔ (ahorrador 52, por diseño) |
| Ninguna política > sensato +10 en R8 | R8: sensato 71, héroe 68, solo reclutas 74, ahorrador 56, aleatorio 0 (n = 3) ✔ |
| … ni en % de partidas ganadas | sensato 12 %, **héroe 20 %** (+8), solo reclutas 17 %, ahorrador 2 %, aleatorio 0 % ✔ (héroe al límite) |
| Aleatorio claramente peor | R1 53 %, nunca gana ✔ |

## Tablas por ronda (iteración 2)

### Sensato (358 partidas)
| R | partidas | llegan % | victoria % | jefe (n / %) | élite (n / %) | 🪙 +/− | PM + | Nv medio / máx | tropas | reclutas / equipo acum. | poder J / E | poder por tropa |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 358 | 100 | 95 | 0 / – | 0 / – | 6.0 / 13.4 | 3.8 | 1.53 / 2.0 | 1.95 | 0.95 / 0.0 | 2670 / 1645 | 1378 |
| 2 | 339 | 95 | 100 | 0 / – | 0 / – | 6.5 / 3.4 | 4.0 | 2.98 / 3.03 | 2.0 | 1.0 / 0.51 | 4333 / 1789 | 2166 |
| 3 | 339 | 95 | 98 | 0 / – | 78 / 92 | 7.0 / 7.5 | 4.1 | 3.6 / 5.0 | 2.4 | 1.4 / 0.88 | 6184 / 2412 | 2670 |
| 4 | 333 | 93 | 87 | 0 / – | 67 / 63 | 6.2 / 6.5 | 3.6 | 4.28 / 5.0 | 2.68 | 1.68 / 1.32 | 7978 / 4711 | 3093 |
| 5 | 290 | 81 | 85 | 0 / – | 62 / 48 | 6.0 / 6.4 | 3.5 | 4.67 / 5.44 | 3.0 | 2.0 / 1.64 | 9779 / 5450 | 3414 |
| 6 | 246 | 69 | 90 | 11 / 64 | 38 / 84 | 6.3 / 6.8 | 3.7 | 5.0 / 6.02 | 3.33 | 2.33 / 2.05 | 11753 / 6479 | 3702 |
| 7 | 215 | 60 | 76 | 28 / 29 | 26 / 69 | 6.7 / 7.0 | 3.1 | 5.18 / 6.35 | 3.67 | 2.67 / 2.47 | 13542 / 11022 | 3896 |
| 8 | 156 | 44 | 71 | 27 / 19 | 28 / 54 | 6.2 / 7.6 | 2.9 | 5.35 / 6.76 | 3.99 | 2.99 / 2.92 | 15513 / 16656 | 4092 |
| 9 | 106 | 30 | 67 | 14 / 29 | 15 / 53 | 7.0 / 6.4 | 2.8 | 5.51 / 6.98 | 4.34 | 3.34 / 3.34 | 17419 / 18901 | 4211 |
| 10 | 67 | 19 | 66 | 15 / 40 | 8 / 38 | 6.6 / 9.1 | 2.7 | 5.42 / 7.06 | 4.9 | 3.9 / 3.6 | 19649 / 22599 | 4177 |
| 11 | 38 | 11 | 84 | 9 / 56 | 5 / 80 | 8.0 / 10.7 | 3.5 | 5.5 / 7.21 | 5.21 | 4.21 / 4.76 | 21970 / 23950 | 4322 |
| 12 | 27 | 8 | 26 | 27 / 26 | 0 / – | 4.1 / 7.9 | 1.0 | 5.6 / 7.11 | 5.63 | 4.63 / 4.96 | 23800 / 70925 | 4255 |

### Héroe (107)
| R | partidas | llegan % | victoria % | jefe (n / %) | élite (n / %) | 🪙 +/− | PM + | Nv medio / máx | tropas | reclutas / equipo acum. | poder J / E | poder por tropa |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 107 | 100 | 92 | 0 / – | 0 / – | 5.9 / 13.4 | 3.7 | 1.53 / 2.0 | 1.94 | 0.94 / 0.0 | 2651 / 1683 | 1368 |
| 2 | 98 | 92 | 100 | 0 / – | 0 / – | 6.4 / 3.4 | 4.0 | 2.5 / 4.0 | 2.0 | 1.0 / 0.51 | 3961 / 1814 | 1981 |
| 3 | 98 | 92 | 96 | 0 / – | 27 / 85 | 7.1 / 6.7 | 4.1 | 3.2 / 6.0 | 2.36 | 1.36 / 0.86 | 5922 / 2559 | 2590 |
| 4 | 94 | 88 | 89 | 0 / – | 17 / 71 | 6.3 / 7.0 | 3.7 | 3.32 / 7.0 | 2.69 | 1.69 / 1.29 | 7352 / 4573 | 2820 |
| 5 | 84 | 79 | 82 | 0 / – | 19 / 42 | 6.1 / 6.3 | 3.4 | 3.39 / 8.0 | 3.06 | 2.06 / 1.54 | 8891 / 5401 | 3022 |
| 6 | 69 | 64 | 87 | 6 / 67 | 6 / 67 | 5.9 / 7.9 | 3.5 | 3.37 / 9.0 | 3.51 | 2.51 / 1.86 | 10952 / 7003 | 3223 |
| 7 | 56 | 52 | 73 | 9 / 33 | 8 / 50 | 6.4 / 5.2 | 3.0 | 3.67 / 10.0 | 3.7 | 2.7 / 2.34 | 13272 / 11767 | 3731 |
| 8 | 38 | 36 | 68 | 5 / 40 | 6 / 67 | 6.2 / 7.0 | 2.8 | 4.49 / 10.0 | 4.03 | 3.03 / 2.79 | 16254 / 15003 | 4233 |
| 9 | 24 | 22 | 83 | 3 / 33 | 3 / 67 | 8.3 / 9.1 | 3.4 | 4.92 / 10.0 | 4.21 | 3.21 / 3.71 | 18377 / 20197 | 4563 |
| 10 | 19 | 18 | 74 | 7 / 71 | 1 / 100 | 7.8 / 5.8 | 3.0 | 5.43 / 10.0 | 4.26 | 3.26 / 4.42 | 20320 / 26228 | 4963 |
| 11 | 9 | 8 | 89 | 4 / 100 | 1 / 0 | 9.3 / 13.9 | 3.6 | 5.24 / 10.0 | 4.89 | 3.89 / 5.22 | 23857 / 35274 | 4995 |
| 12 | 4 | 4 | 50 | 4 / 50 | 0 / – | 7.2 / 11.8 | 2.0 | 5.41 / 10.0 | 5.25 | 4.25 / 6.25 | 24508 / 67026 | 4798 |

### Solo reclutas (106)
| R | partidas | llegan % | victoria % | jefe (n / %) | élite (n / %) | 🪙 +/− | PM + | Nv medio / máx | tropas | reclutas / equipo acum. | poder J / E | poder por tropa |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 106 | 100 | 96 | 0 / – | 0 / – | 6.2 / 13.9 | 3.8 | 1.51 / 2.0 | 1.98 | 0.98 / 0.0 | 2689 / 1685 | 1362 |
| 2 | 102 | 96 | 100 | 0 / – | 0 / – | 6.7 / 0.1 | 4.0 | 3.0 / 3.01 | 2.0 | 1.0 / 0.0 | 4127 / 1616 | 2064 |
| 3 | 102 | 96 | 99 | 0 / – | 23 / 96 | 7.4 / 9.8 | 4.2 | 3.29 / 5.0 | 2.71 | 1.71 / 0.0 | 6070 / 2464 | 2290 |
| 4 | 101 | 95 | 84 | 0 / – | 27 / 70 | 6.3 / 5.2 | 3.6 | 3.89 / 5.0 | 3.08 | 2.08 / 0.0 | 7859 / 4856 | 2559 |
| 5 | 85 | 80 | 91 | 0 / – | 13 / 62 | 6.5 / 8.4 | 3.7 | 4.15 / 5.0 | 3.71 | 2.71 / 0.0 | 9913 / 5170 | 2710 |
| 6 | 77 | 73 | 96 | 3 / 100 | 15 / 93 | 7.5 / 5.3 | 4.0 | 4.45 / 5.27 | 4.1 | 3.1 / 0.0 | 11614 / 6637 | 2837 |
| 7 | 71 | 67 | 80 | 8 / 50 | 10 / 40 | 6.9 / 8.7 | 3.3 | 4.47 / 5.32 | 4.73 | 3.73 / 0.0 | 13327 / 10282 | 2835 |
| 8 | 53 | 50 | 74 | 6 / 17 | 9 / 67 | 6.4 / 6.2 | 3.1 | 4.7 / 5.62 | 5.13 | 4.13 / 0.0 | 15079 / 13375 | 2947 |
| 9 | 38 | 36 | 58 | 7 / 43 | 7 / 29 | 6.2 / 9.2 | 2.4 | 4.68 / 6.0 | 5.84 | 4.84 / 0.0 | 17165 / 20370 | 2948 |
| 10 | 19 | 18 | 58 | 9 / 67 | 1 / 0 | 6.8 / 0.8 | 2.3 | 4.99 / 6.16 | 6.0 | 5.0 / 0.0 | 18106 / 29243 | 3018 |
| 11 | 5 | 5 | 40 | 1 / 100 | 3 / 0 | 6.0 / 0.0 | 1.6 | 5.27 / 6.6 | 6.0 | 5.0 / 0.0 | 19306 / 28297 | 3218 |

### Ahorrador (106)
| R | partidas | llegan % | victoria % | jefe (n / %) | élite (n / %) | 🪙 +/− | PM + | Nv medio / máx | tropas | reclutas / equipo acum. | poder J / E | poder por tropa |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 106 | 100 | 49 | 0 / – | 0 / – | 4.0 / 0.0 | 2.0 | 2.0 / 2.0 | 1.0 | 0.0 / 0.0 | 1717 / 1612 | 1717 |
| 2 | 52 | 49 | 81 | 0 / – | 0 / – | 6.5 / 0.4 | 3.2 | 4.0 / 4.0 | 1.0 | 0.0 / 0.08 | 2905 / 1766 | 2905 |
| 3 | 42 | 40 | 95 | 0 / – | 7 / 86 | 7.8 / 1.2 | 4.0 | 6.0 / 6.0 | 1.0 | 0.0 / 0.31 | 4533 / 2155 | 4533 |
| 4 | 40 | 38 | 72 | 0 / – | 5 / 0 | 5.9 / 14.0 | 2.9 | 4.53 / 7.0 | 1.82 | 0.82 / 0.75 | 6510 / 4793 | 3906 |
| 5 | 29 | 27 | 83 | 0 / – | 5 / 40 | 6.9 / 4.3 | 3.4 | 5.44 / 7.17 | 2.0 | 1.0 / 1.03 | 8597 / 5315 | 4462 |
| 6 | 24 | 23 | 88 | 1 / 0 | 2 / 100 | 7.7 / 9.8 | 3.6 | 5.63 / 7.25 | 2.46 | 1.46 / 1.54 | 10620 / 7278 | 4703 |
| 7 | 21 | 20 | 76 | 1 / 0 | 3 / 67 | 7.4 / 8.2 | 3.1 | 5.51 / 7.33 | 2.95 | 1.95 / 1.71 | 12343 / 9047 | 4419 |
| 8 | 16 | 15 | 56 | 2 / 0 | 1 / 0 | 6.1 / 8.1 | 2.2 | 5.6 / 7.44 | 3.38 | 2.38 / 1.94 | 14515 / 16347 | 4463 |
| 9 | 9 | 8 | 56 | 3 / 33 | 0 / – | 6.7 / 11.0 | 2.2 | 5.64 / 7.67 | 3.78 | 2.78 / 2.89 | 17695 / 26048 | 4814 |
| 10 | 4 | 4 | 75 | 1 / 0 | 0 / – | 7.8 / 3.2 | 3.0 | 6.27 / 8.0 | 3.75 | 2.75 / 3.25 | 19457 / 24262 | 5482 |
| 11 | 3 | 3 | 67 | 1 / 100 | 1 / 0 | 9.0 / 11.3 | 2.7 | 5.97 / 8.0 | 4.33 | 3.33 / 4.0 | 21500 / 26903 | 5380 |

### Aleatorio (106)
| R | partidas | llegan % | victoria % | jefe (n / %) | élite (n / %) | 🪙 +/− | PM + | Nv medio / máx | tropas | reclutas / equipo acum. | poder J / E | poder por tropa |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 106 | 100 | 53 | 0 / – | 0 / – | 3.4 / 10.3 | 2.1 | 1.66 / 1.75 | 1.21 | 0.21 / 1.05 | 1713 / 1657 | 1456 |
| 2 | 56 | 53 | 80 | 0 / – | 0 / – | 5.3 / 4.6 | 3.2 | 2.89 / 3.05 | 1.3 | 0.3 / 1.88 | 2610 / 1785 | 2090 |
| 3 | 45 | 42 | 87 | 0 / – | 9 / 78 | 6.3 / 4.7 | 3.6 | 3.8 / 4.09 | 1.38 | 0.38 / 2.67 | 3561 / 2326 | 2740 |
| 4 | 39 | 37 | 46 | 0 / – | 12 / 17 | 3.6 / 6.9 | 1.9 | 4.82 / 5.56 | 1.56 | 0.56 / 3.31 | 5140 / 4751 | 3685 |
| 5 | 18 | 17 | 83 | 0 / – | 1 / 100 | 5.5 / 7.9 | 3.4 | 5.32 / 6.5 | 1.72 | 0.72 / 3.94 | 6702 / 4490 | 4402 |
| 6 | 15 | 14 | 67 | 1 / 0 | 2 / 0 | 5.3 / 9.4 | 2.7 | 5.8 / 7.53 | 1.93 | 0.93 / 4.87 | 8666 / 8081 | 5107 |
| 7 | 10 | 9 | 30 | 1 / 0 | 4 / 0 | 4.3 / 7.6 | 1.2 | 6.17 / 8.1 | 2.2 | 1.2 / 5.6 | 10173 / 14235 | 5524 |
| 8 | 3 | 3 | 0 | 1 / 0 | 1 / 0 | 0.0 / 4.3 | 0.0 | 6.11 / 7.67 | 2.33 | 1.33 / 6.33 | 10522 / 29348 | 5951 |

## Riesgos y siguientes pasos

- **R4–R6 siguen fáciles (85–90 %)** y el final se decide en el jefe: en R12 (jefe forzado, enemigos de Nv 4) el sensato gana el 26 %; en R6–R11 gana el 32–40 % de los jefes. Siguiente ajuste propuesto sin validar: enemigos mín./máx. cada 5 rondas en vez de 8/6 (más presión en R5–R8) y/o `PROV_HP_PER_ROUND` 0,075.
- **Héroe**: gana el 55 % de los jefes (un Nv 10 hace mucho daño al líder). Está a +8 puntos del sensato en partidas ganadas; si sube, encarecer el final de LEVEL_COST (p. ej. [.., 4, 5, 6, 7]).
- **Enemigo ×13,7 frente a jugador ×7,4 (R1→R10)** en Σ vida×DPS: el número de enemigos crece al cuadrado en Lanchester. Aun así, el cociente de Lanchester se mantiene > 2 hasta R10 y la victoria media del sensato es del 66–71 % en R8–R10.
- `reward_screen.gd` (W-UXFIX) calcula “probabilidad de jefe en la siguiente ronda” como `boss_chance + BOSS_CHANCE_STEP`, que ahora da 5 % en R1–R4 (es 0 %) y no da 100 % en R12. Cambio de una línea propuesto: `var next_chance: float = gsm.next_boss_chance() if gsm else 0.0`.
- Partidas ganadas (jefe vencido) solo el 12 % con el sensato: la mayoría pierde antes (R7–R11). Si se busca ~25 %, bajar BOSS_HP_MULT a 2,3 o subir algo el PM.

## Tests (iteración 2, con candado)

test_economia 0 fallos (98 ok) · test_progresion 0 (23 ok) · test_core 0 (74 ok) · logic_test 0 (107 ok).
Comprobaciones que tenían el literal antiguo y ahora leen la constante (sin debilitarlas, una línea cada una):
test_economia l. 93–100 (COINS_PER_KILL*, POINTS_PER_WIN*), test_progresion l. 167–168 (LEVEL_HEALTH/DAMAGE), test_core l. 105/107/111 (vida y daño exactos con LEVEL_*),
logic_test l. 446/457/484 (probabilidad de jefe con BOSS_CHANCE_STEP/BOSS_MIN_ROUND; mapa en R16 = 100 %), test_combat l. 409 (BOSS_HP_MULT; no ejecutado en esta iteración).

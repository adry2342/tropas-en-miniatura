# Tropas en miniatura — GDD vivo y estado del proyecto

> **Para quien lea esto (persona u otra IA):** este documento es el "compact" del juego, todo lo necesario para continuar el desarrollo sin el historial de chats. Si algo no cuadra con el código, **manda el código** (y conviene actualizar este archivo).
> Última actualización: **2026-10-09** · versión del proyecto **0.7.3** (+ cambios sin publicar, ver §13).
> El GDD original de la idea está en `_dev/GDD_original_backup.txt/.docx` (solo histórico; está superado por este).

---

## 1. Qué es

- **Género:** auto-battler roguelite 2D. Colocas tus tropas en una cuadrícula y luchan solas contra oleadas.
- **Inspiración:** TFT y MiniTroopers.
- **Motor:** Godot **4.7.2** (GDScript).
- **Pantalla:** horizontal, 1152×648 base, `stretch canvas_items / expand`.
- **Plataformas:** Windows, Linux y Android (ARM64).
- **Autores:**
  - **adry2342** (Adrián) diseña y dirige.
  - **Sergio García Figueiras** es coautor.
  - Claude programa y hace el arte por código.
- **Licencia:** todos los derechos reservados (`LICENSE`). Excepciones: las fuentes OFL de `Assets/Fonts`, Godot (MIT) y el addon `godot_ai`.
- **Repositorio:** https://github.com/adry2342/tropas-en-miniatura, rama `main`.
- **Carpeta local:** `C:\Users\adri\Documents\proyectos\tropas-en-miniatura`.
- **Fase actual:** **alpha jugable**. El bucle completo (run, mapa, batallas, tienda, subidas, jefes, veteranos y meta-progresión) funciona.
- **Pendiente principal:**
  - Equilibrado.
  - Mecánicas de 3 especialidades.
  - Mejoras del árbol de especialidades.
  - Modo Infinito / nuevo modo.
  - Sonido.
  - Interfaz de móvil.

---

## 2. Flujo de pantallas

```
Menú principal (main_menu)
  └─ Centro de mando (command_center) ← hub permanente, escena ilustrada con zonas clicables
       ├─ Mesa de guerra → Nueva run → Selección de recluta (troop_selection_screen) → Mapa
       ├─ Archivo → Códice (libro)
       ├─ Terminal de especialidades → árbol (pantalla CRT)
       ├─ Radio → Configuración
       ├─ 5 tubos criogénicos → ficha del veterano guardado
       ├─ Puerta del hangar → nuevo modo (bloqueado hasta 5 veteranos; "próximamente")
       └─ Cartel SALIDA (arriba a la izquierda) → Menú principal
Mapa (map.tscn): ruleta que decide el tipo de la siguiente ronda → Batalla
Batalla (battle.tscn): planificación (despliegue, Intendencia, subir niveles) → combate → recompensas → mapa
Fin de run (game_over_panel): derrota, o victoria contra el Jefe Final (guardar un veterano con nombre)
```

- **Escena principal:** `Scenes/UI/main_menu.tscn`.
- **Autoloads:**
  - `EventBus`: señales globales.
  - `GameStateManager`: estado de la run.
  - `ProfileManager`: perfil persistente.
  - `SettingsManager`: ajustes.
  - `_mcp_game_helper`: solo para desarrollo con la IA; se quita al exportar.

---

## 3. La run

- **Inicio:**
  - Se ofrecen **3 reclutas** y se elige **uno**.
  - El primero tiene siempre **100 de vida** (sin horquilla) y **ningún objeto**. Su daño varía ±10 %, y cambian también el nombre y el arma.
  - En la ficha de selección solo se ve el arma y su tipo, sin estadísticas del arma.
  - Se empieza con **15 monedas** y **1 PM** (Punto de Mando).
- **Rondas:** cada victoria suma una ronda.
  - **Ronda 3 en adelante:** el 20 % de las rondas son **Batalla Élite**.
  - **Cada 10 rondas** hay un **Jefe de Sector** fijo. Su vida es 360, 650, 1050 o 1550 según el sector, y después +500 por sector.
  - **Desde la ronda 11**, la ruleta del mapa puede sacar al **Jefe Final**: +0,5 % por ronda, unos 10 % en la ronda 30.
  - Ganar al Jefe Final es la **victoria de la run**. Perder el ejército entero es la **derrota**.
- **Ejército:** máximo **6 tropas** contando tablero y reserva. Se pueden **desplegar hasta 6** en la cuadrícula 5×5 de la izquierda.
- **Economía** (`Scripts/Systems/economy.gd`):
  - Por baja enemiga: 1 moneda; élite 2; jefe 4.
  - Por victoria: +2 monedas, más **interés** de +1 por cada 10 monedas (máximo +2).
  - **PM:** 1 por victoria; 2 en élite o Jefe de Sector.
- **Subir de nivel** (`LevelUpSystem`):
  - Cuesta PM. El coste de Nv.1 a Nv.10 está en `LEVEL_COST = [0,1,1,2,2,3,3,4,4,5]`.
  - Cada subida ofrece **2 opciones al azar** y eliges una. Tipos: habilidad (55), objeto (25) o arma (20).
  - En el **Nv. 5** el recluta elige **especialidad** entre 2 al azar de las desbloqueadas.
  - Nivel máximo: **10**.
  - **Entrenamiento:** +6 % de vida y de daño, acumulable.
- **Intendencia (tienda):**
  - Ofrece **4 objetos o armas**. Precios de objeto: 6, 10, 15 o 22 según rareza; de arma: 9, 12, 15 o 18.
  - Se vende al 50 %. La primera tirada nueva cuesta 1.
  - La rareza máxima depende de la ronda: rara antes de la R4, épica hasta la R8 y legendaria después.
  - También se **reclutan tropas** por 13–19 monedas. Estas sí pueden traer objeto (35 %, y entonces cuestan más), arma rara (25 %) o especialidad (20 %, +4 monedas).
- **Mejora de armas:** la ⭐ sube el arma hasta el nivel 4. Cuesta 1, 2 y 3 PM y da +4 % de daño por nivel.

---

## 4. La batalla

### 4.1 Planificación
- Arrastras las tropas de la reserva a tu zona de la cuadrícula 5×5.
- Haciendo clic en una tropa se abre su **ficha**: estadísticas, arsenal, objetos, especialidad, habilidades y el botón de subir nivel.
- Sin **Radioperador** en el tablero, el enemigo queda oculto bajo un **mapa de calor**. Con él, se ve dónde está.
- **Nombre y nivel** («Nombre · Nv.X»):
  - Se ven siempre encima de la barra de vida de **tus** tropas durante la planificación.
  - En combate solo aparecen al pasar el ratón.
  - Los enemigos nunca los muestran en planificación, para no delatar su posición.

### 4.2 Combate (tiempo real, IA automática; ver `Scripts/Troops/troop.gd`)

**Objetivo y movimiento**
- Cada tropa prioriza a los enemigos de **su carril** (la fila donde la desplegaste) y no cambia de objetivo a cada momento.
- Cada arma tiene una **distancia de combate**:
  - El cuchillo pega el cuerpo.
  - La pistola y la escopeta se acercan.
  - El fusil se queda a media distancia.
  - El francotirador y la bazuca disparan desde lejos.
- La aproximación es en arco desde su carril, y las tropas se separan de sus compañeros.
- Las armas con `fire_on_move` disparan andando, con −12 % de precisión. Las pesadas se paran para disparar.

**Precisión y daño**
- La precisión depende de la distancia: hasta `optimal_range` no hay penalización; más allá pierde `accuracy_falloff` por cada 100 px. Más cerca gana hasta `close_bonus`, que en el francotirador es negativo (de cerca falla).
- Hay críticos (`crit_chance`, `crit_multiplier`) y esquiva.
- **Letal:** probabilidad muy baja por segundo de fuego (0,4 %) de un impacto que mata. Contra jefes es ×3.

**Cargador y recarga**
- Cada arma tiene un cargador. **Para recargar hay que estar quieto**: mientras recarga, la tropa no se mueve, y si algo la empuja la recarga se detiene.
- **Varias armas:**
  - Todas las armas del arsenal van equipadas y usa la **principal**.
  - Si se queda sin balas **bajo fuego** (le han disparado en los últimos 2,5 s, o un enemigo le apunta y la alcanza), cambia a la de reserva que tenga balas y alcance, y que haga más DPS. El cambio tarda 0,35 s y se ve en la animación.
  - Tras 3 s sin peligro vuelve a la principal y la recarga.

**Balas falladas y fuego amigo**
- Una bala fallada sale desviada y le da a lo primero que cruce. Si es un enemigo, cuenta como acierto. Si es un compañero, es **«¡Fuego amigo!»**.
- Solo las balas pueden causar fuego amigo. Las explosiones y el cuerpo a cuerpo **nunca** dañan a los aliados.

**Explosivos**
- La bazuca, el lanzagranadas y la granada (objeto) hacen daño en radio, con menos fuerza hacia el borde.
- El impacto letal solo afecta al objetivo principal.

**Marcas en el suelo**
- **Retícula roja:** el objetivo está marcado por un Radioperador.
- **Anillo azul:** el objetivo está suprimido por un Soldado.
- **Anillo azul discontinuo:** el Vigía está En guardia.
- **Aura roja:** frenesí (adrenalina o venganza).

**Textos flotantes**
- Daño, «¡Fallo!», «😰 Suprimido», «¡Granada!», «🔄 cambio de arma», «🔭 En guardia», «🔭 ¡Reacción!».

### 4.3 Recompensas
- Tras ganar se muestra un resumen: monedas, interés, PM y medallas si era un jefe.
- La Intendencia se rellena para la siguiente ronda.

---

## 5. Armas (`Resources/Weapons/*.tres`, clase `WeaponData`)

| id | Familia | Rareza | Daño | Disp/s | Alcance | Precisión | Cargador | Recarga | Notas |
|---|---|---|---|---|---|---|---|---|---|
| pistola | Pistola | común | 9 | 1.6 | 200 | 0.78 | 7 | 1.0 | Dispara andando; arma de recluta |
| subfusil | Automática | común | 4 | 4.5 | 230 | 0.68 | 18 | 1.8 | Dispara andando; arma de recluta |
| fusil_asalto | Automática | común | 7 | 2.2 | 340 | 0.78 | 15 | 2.0 | Dispara andando; arma de recluta |
| escopeta | Escopeta | común | 4.5 ×5 perdigones | 0.75 | 175 | 0.62 | 4 | 2.2 | **`pellet_stack_bonus` 0.2**; dispara andando; arma de recluta |
| cuchillo | Cuerpo a cuerpo | común | 11 | 1.4 | 40 | 0.95 | ∞ | — | Impacto instantáneo; ×1.3 de velocidad |
| rifle_francotirador | Precisión | rara | 45 | 0.3 | 620 | 0.93 | 3 | 2.5 | `close_bonus` −0.35 (de cerca falla); desde la R4 |
| ametralladora | Pesada | rara | 6 | 4.0 | 360 | 0.62 | 25 | 4.0 | ×0.8 de velocidad; desde la R3 |
| bazuca | Explosivo | épica | 70 | 0.5 | 500 | 0.72 | 1 | 3.5 | Radio 75; desde la R6 |
| lanzagranadas | Explosivo | rara | 25 | 0.6 | 300 | 0.75 | 4 | 2.5 | Radio 70. **No está en `GameContent`, así que no sale en el juego**, aunque tiene arte |

- **Escopeta, cómo hace el daño:** cada perdigón que acierta hace su daño, y cada perdigón **extra** que da al mismo blanco en el mismo disparo sube el daño de todos un 20 %. Un perdigón da 4.5; dos, 10.8; tres, 18.9; cinco, 40.5. De lejos rasca y a quemarropa destroza.
- **Lanzallamas: ELIMINADO** (2026-10-09). Ya no existe el proyectil `LLAMA`. El enum actual es `Projectile { BALA, GRANADA, COHETE, NINGUNO }` y el cuchillo usa `projectile = 3`. Las partidas guardadas con lanzallamas lo cargan como escopeta (`GameContent.LEGACY_WEAPON`).
- **Icono de cada arma:** `WeaponData.get_icon()` devuelve `Assets/Weapons/icons/<id>.png`. Se usa en toda la interfaz: ficha, arsenal, tienda, subidas de nivel, Códice, cuartel y fin de run. Los emojis de arma ya no se usan en la interfaz; el campo `emoji` sigue existiendo como dato de respaldo.

---

## 6. Especialidades (`Resources/Specialties/*.tres`, clase `SpecialtyData`; efectos en `Scripts/Systems/effects.gd`)

**Principio de diseño:** una especialidad es una **faceta única del soldado en el campo de batalla** que lo diferencia de los demás. **No** depende del arma que lleve, porque cualquier tropa puede llevar cualquier arma. Las familias afines solo dan +15 % de daño y +10 de precisión.

Se elige al llegar a Nv. 5.

| id interno | Nombre | Pasiva | Estado |
|---|---|---|---|
| soldado | **Soldado** 🪖 | **Fuego de supresión:** cada impacto suprime al blanco 1,5 s (−15 % de precisión, −25 % de velocidad). | ✅ |
| medico | **Doctor** | **Primeros auxilios:** cada 4 s cura un 6 % al aliado más herido a 220 px. **Estabilizar:** una vez por combate salva a un aliado que iba a caer (queda en pie con un 25 %). | ✅ |
| comunicaciones | **Radioperador** | Revela el mapa de calor en la planificación. Cada 4 s **marca** al enemigo más peligroso (+15 % de daño recibido, pierde el camuflaje). Una vez por combate pide **artillería**: 3 proyectiles de 26 sobre el grupo más denso. | ✅ |
| vigia | **Vigía** 🔭 *(rework 2026-10-09; antes "Francotirador")* | **En guardia:** quieto 1,2 s → +15 % de alcance y +10 % de precisión. Cada enemigo que **entra** en su alcance estando en guardia recibe al instante un **disparo de reacción** (+30 % de crítico, +25 % de daño; uno por enemigo y combate; 0,8 s entre reacciones). Apunta al enemigo **más peligroso** a su alcance. +25 % de crítico contra suprimidos o marcados (`tirador_elite`). | ✅ |
| mecanico | **Mecánico** | «Taller de campaña» | ⏳ sin mecánica |
| infiltrado | **Infiltrado** | «Tras las líneas» | ⏳ sin mecánica |
| saboteador | **Saboteador** | «Sabotaje» | ⏳ sin mecánica |

- **Vigía:** id `"vigia"` (`Resources/Specialties/vigia.tres`). Familias afines: Precisión y Automática. El cambio de id rompe a propósito los perfiles viejos con Francotirador (se ignoran); no hay tablas de ids heredados (`LEGACY_*` eliminadas).
- Zapador y Municionero se **borraron** del todo (sus `.tres` y habilidades). El código de minas (`mine.gd`, efecto `minas`/`carga_hueca`) sigue ahí sin uso, por si se recupera.
- **Vigía, código:** `Effects._tick_guard`, `Effects.in_guard`, `troop.reaction_shot()`. El rango extra se aplica con el buff `range_pct`, que `get_attack_range()` ya aplica.

**Desbloqueo por hitos** (`SpecialtyProgression.UNLOCKS`):
- Al cumplir el hito la especialidad queda «lista». Se desbloquea **a mano** en el terminal del Centro de mando.
- Hitos: Soldado desde el principio · Doctor al 1.er Jefe de Sector (R10) · Radioperador al 2.º (R20) · Vigía al 3.º (R30) · Infiltrado al vencer al Jefe Final · Mecánico al 4.º (R40) · Saboteador al completar el Modo Infinito.

**Árbol de especialidad** (`SpecialtyProgression.DEFAULT_TREES`):
- Árbol vertical de 4 rangos que se compran con 🏅 (3, 5, 8 y 12 medallas).
- **Las mejoras están todas sin definir** («Mejora pendiente de definir»).
- Formato de cada nodo: `{name, description, cost, modifiers, effects}`. Se acumulan por rango.

**Medallas de mando 🏅:**
- Se ganan **al momento al derrotar a un jefe**: Jefe de Sector N da 3 + (N−1); el Jefe Final da 8.
- Son persistentes en el perfil. Valores provisionales.

---

## 7. Habilidades y objetos

**Habilidades** (`Resources/Skills/*.tres`)
- No ocupan hueco. Salen en las subidas de nivel.
- **Todas son libres: cualquier tropa puede tener cualquier habilidad** (2026-10-09). Ya no existe `SkillData.specialty_id` ni el filtro de `LevelUpSystem._skill_ok`. Las que antes eran de un especialista se agrupan abajo solo por su origen; las que potencian una pasiva concreta tienen además un efecto útil para cualquiera.
- **Generales:**
  - Piel dura (+50 de vida)
  - Pulso firme (+8 % de precisión) · Ojo certero (+8 % de crítico) · Sangre fría (+0,25 al multiplicador de crítico; requiere Ojo certero)
  - Gatillo fácil (+15 % de cadencia, −5 % de precisión) · Recarga rápida (+25 %)
  - Velocista (+20 % de velocidad) · Esquiva (+12 %)
  - Camuflaje (los enemigos no le apuntan los 3 primeros segundos)
  - Venganza (+30 % de cadencia 4 s cuando cae un aliado)
  - Último en pie (+40 % de daño si es el último vivo)
- **Antes del Soldado:** Cargador ampliado (+40 %) · Instinto veterano (+10 % de crítico) · Oficial (aura de +15 % de cadencia a 180 px).
- **Antes del Doctor:** Cirujano (todas sus curaciones +50 %: botiquín, autocuración y, si es Doctor, las que da) · Autocuración (2 %/s).
- **Antes del Radioperador:** Coordenadas precisas (+20 % de daño contra marcados; con Radioperador, la artillería lanza +2 proyectiles y hace +30 % de daño) · Enlace táctico (sus impactos marcan al blanco 2 s, que recibe +10 % de daño de todos; con Radioperador, las marcas duran 2 s más y pegan +10 % más).
- **Antes del Vigía:** Mira láser (+10 % de crítico y de precisión) · Bala perforante (atraviesa a 1 enemigo) · Traje ghillie (camuflaje de 6 s).

**Objetos** (`Resources/Items/*.tres`)
- Máximo **3 huecos** por tropa.
- Lista:
  - Balas de punta hueca (+15 % de daño)
  - Balas incendiarias (quemadura de 5/s durante 3 s)
  - Balas perforantes (atraviesan a 1 enemigo)
  - Chaleco táctico (+25 de vida, −5 % de movimiento)
  - Blindaje pesado (−20 % de daño recibido, −15 % de movimiento)
  - Botiquín (una vez, por debajo del 40 % de vida, se cura un 35 %)
  - Inyector de adrenalina (frenético 5 s al empezar)
  - Mira telescópica (+15 % de alcance, +8 % de precisión, +6 % de crítico)
  - **Granada**
- **Granada:**
  - Cada 6 s, **solo si hay un enemigo a media distancia, entre 70 y 210 px** (primero su objetivo y si no el más cercano en esa franja).
  - Mientras la lanza **no se mueve ni dispara**: guarda el arma, saca la granada, toma impulso, la lanza y vuelve a empuñar. Dura 0,8 s.
  - Hace 30 de daño en radio 70. Si no hay nadie en la franja, espera.
  - Código: `Effects._throw_grenade`, `GRENADE_MIN_RANGE/MAX_RANGE` y `troop.throw_grenade`.

---

## 8. Enemigos y jefes
- Se generan proceduralmente (`battle.gd`, `UnitFactory.make_enemy`).
- Suben de nivel con la ronda: 1 nivel cada 5 rondas, con especialidad desde el Nv. 2.
- **Escalado por ronda:** +4 % de vida y +3,5 % de daño.
- **Número de enemigos:** mínimo de 1 más 1 cada 10 rondas; máximo de 6. La élite tiene más vida, más daño y más enemigos.
- **Jefe:** se ve 1,8× más grande, con ×2,1 de vida y ×1,5 de daño.
  - Animaciones propias: paso pesado con polvo, respiración lenta, retroceso fuerte y muerte en dos tiempos (se arrodilla y se desploma).
  - Su nombre lleva «☠».

---

## 9. Meta-progresión y perfil (`ProfileManager`)
- **Archivo:** `user://profile.json`, o `profile_dev.json` en el editor. `SAVE_VERSION 2`.
- **Qué guarda:** veteranos, medallas, rangos de especialidad, especialidades desbloqueadas y listas, e hitos.
- **Veteranos (Cuartel / tubos criogénicos):**
  - Al **ganar al Jefe Final** eliges una tropa de la run, incluso caída, para guardarla.
  - Al pulsar «Guardar» **te pide el nombre del veterano**: máximo 16 letras, no puede estar vacío. En PC se escribe con el teclado (Intro guarda, Esc cancela) y en móvil sale el teclado del sistema (`LineEdit.virtual_keyboard_enabled` + `edit()`).
  - Hay **5 tubos**. Con todos llenos, eliges a quién sustituye o no guardas a nadie.
  - Con 5 veteranos se abre el hangar, el «nuevo modo», todavía sin implementar.
- **Configuración:** opciones de vídeo, más una sección **PRUEBAS provisional** (desbloquear todo, borrar partida, no guardar) que hay que **quitar antes de una versión final**.

---

## 10. Interfaz y arte

**Paleta y fuentes**
- La paleta y los componentes están en `Scripts/UI/ui_kit.gd`: `panel`, `label`, `icon_rect`, `icon_label`, `set_weapon_icon` y `make_recruit_card(card, w, show_weapon_stats)`.
- Fuentes (OFL): Cinzel y EB Garamond para el Códice; Share Tech Mono para el terminal.

**Centro de mando** (`command_center.gd`)
- Sala ilustrada (`Assets/CommandCenter/`) con zonas clicables (`cc_hotspot.gd`).
- Cartel **SALIDA** para volver al menú. Cartel «BAHÍA CRIOGÉNICA».

**Códice** (`codex_panel.gd`)
- Un **libro** que se abre desde la tapa. Capítulos en orden: Habilidades → Objetos → Armas → Especialidades.
- Doble página: a la izquierda las casillas, a la derecha la «Ficha de campo».
- Paso de hoja animado; salta varias hojas seguidas al cambiar de capítulo.
- Se maneja con ←/→, la rueda, Esc y las cintas de marcapáginas (A/D eliminadas).
- Arte en `Assets/Codex/`, generado con `_dev/art/gen_codex_book.py`.

**Terminal de especialidades** (`specialty_tree_panel.gd`)
- Pantalla CRT (`Assets/Terminal/terminal_frame.png`) con shader de líneas y animación de encendido.
- Lista de unidades, árbol de hexágonos con circuito, dossier y botón «✕ APAGAR».

**Tropas animadas** (`Scripts/Troops/troop_rig.gd`, clase `TroopRig`)
- El sprite del recluta (`Assets/Sprites/sprite-personaje-basico.png`, estilo chibi con trazo grueso) está **recortado en piezas**: piernas, cuerpo, los dos brazos que giran en el hombro y las mangas por encima (`Assets/Troop/`). Las piezas se generan con `_dev/art/gen_troop_rig.py`.
- Animaciones hechas por código:
  - Reposo (respira) y caminar (piernas alternas, balanceo, el paso va con la velocidad real).
  - Disparo (retroceso y fogonazo en la bocacha; las balas salen de ahí). Cuchillada.
  - Recarga, casi igual que el reposo: el arma baja un poco.
  - Cambio de arma: guarda una y saca la otra.
  - Lanzar granada.
  - Muerte: retrocede, se le cae el arma, cae de espaldas y se desvanece; la tropa se libera al terminar.
  - Variantes del jefe.
- **Cómo sostienen las armas:** a una mano la pistola, el cuchillo y el subfusil. A dos manos el fusil, la escopeta, el francotirador, la ametralladora, el lanzagranadas y la bazuca: una mano en la empuñadura y la otra en el apoyo del cañón.
- Los datos de cada arma (empuñadura, bocacha y apoyo) están en `TroopRig.WEAPON_RIG`.
- Los enemigos se ven en espejo y con tinte rojo.
- Si una especialidad trae `texture` propia, se usa el sprite viejo sin animaciones; ahora mismo ninguna la trae.

**Armas e iconos**
- Arte de lado en `Assets/Weapons/<id>.png` e iconos de 128×128 inclinados en `Assets/Weapons/icons/`, ambos generados con `_dev/art/gen_troop_rig.py`.

**Explosión** (`CombatFX.explosion`)
- Fogonazo blanco muy corto.
- Bola de fuego de dibujos animados, con un solo contorno oscuro, que se vuelve humo gris y sube. Va dentro de un `CanvasGroup`, así no se ven aros de transparencias superpuestas.
- Onda fina y redonda (64 lados) hasta el radio de daño, chispas y una mancha de quemado que se desvanece.

---

## 11. Estructura del código (lo importante)

**Autoloads**
- `Scripts/Autoloads/`:
  - `game_state_manager.gd`: run, monedas, PM, ejército, tipo de ronda, recompensas y `run_medals`.
  - `profile_manager.gd`: perfil y veteranos.
  - `event_bus.gd` y `settings_manager.gd`.

**Sistemas** (`Scripts/Systems/`)
- `economy.gd`: todas las constantes de economía.
- `game_content.gd`: catálogo **explícito** de contenido. Si se añade un `.tres`, hay que añadirlo aquí.
- `troop_stats.gd`: `compute(card, weapon)`, que da las estadísticas finales y el DPS estimado.
- `effects.gd`: pasivas, objetos y habilidades con efecto en combate, mediante ganchos (`on_fight_start`, `on_process`, `on_before_shot`, `on_hit`…).
- `level_up_system.gd`, `shop_system.gd`, `unit_factory.gd` (reclutas, enemigos y precios), `specialty_progression.gd`.

**Recursos** (`Scripts/Resources/`)
- `TroopCard`: estado persistente de una tropa (nivel, armas, objetos, habilidades, especialidad y niveles de arma).
- `WeaponData`, `ItemData`, `SkillData`, `SpecialtyData`.

**Tropas y batalla**
- `Scripts/Troops/troop.gd`: `CharacterBody2D` con la IA de combate, el disparo y la muerte.
- `troop_rig.gd`: el muñeco animado.
- `Scripts/Battle/`: `battle.gd` (fases, oleadas y fin), `bullet.gd` (proyectiles, desvío, fuego amigo, explosiones), `combat_fx.gd` (textos, explosión, destellos y reparto de impactos), `deployment_grid.gd`, `enemy_heatmap.gd`, `mine.gd`.

**Interfaz:** `Scripts/UI/`, una escena por pantalla. `hub.gd` es el Cuartel viejo, sustituido por el Centro de mando y pendiente de borrar.

**Restos sin uso** (propuestos para borrar)
- `Scripts/StateMachine/*` y `Scripts/Troops/States/*`.
- `item_inventory_ui.*` y el código de minas del Zapador.
- *(Ya borrados el 2026-10-09: `troop_data.gd`, `Resources/Troops/*`, `Resources/Items/Unique/*`, Zapador, Municionero y sus habilidades, y Comando.)*
- `extracted_doc.txt`, `Assets/Audio` y `Assets/Effects` (vacíos).

---

## 12. Desarrollo, pruebas y publicación

**Norma de trabajo:** ya **no se escriben tests automáticos** (el usuario lo pidió); se borraron todos.
- Para probar se usa `_dev/anim_preview.tscn`: una tropa con cada arma (algunas con granada, una con dos armas y dos Vigías) contra enemigos y un jefe.
- También `_dev/dev_boot.tscn`, que monta una run con 3 reclutas y salta a la batalla.
- Si `logic_test.tscn` o `test_progresion.tscn` vuelven a aparecer en `_dev`, es porque el editor los recrea desde pestañas abiertas: cerrar las pestañas y borrarlos.

**Con la IA:**
- Se trabaja con el MCP de Godot (`godot-ai`): `project_run custom`, `editor_screenshot source=game`, `logs_read source=game/editor` y `filesystem_manage scan/remove`.
- La IA usa una shell en el VM del usuario. Ahí no se puede borrar con `rm` en la carpeta: se usa `filesystem_manage remove`, que manda a la papelera.

**Arte:** todo es generado con scripts PIL en `_dev/art/` (libro, tubos, salida/terminal, piezas de tropa y armas). Los temporales van a `_dev/art_tmp/`, que está ignorado en git.

**Builds:**
- Al abrir `_dev/release/release_runner.tscn` en el editor (escena `@tool`), se ejecuta `job.json` y se escribe `result.json`. Hace una copia limpia en `%TEMP%`, quita `_mcp_game_helper` y exporta Windows, Linux y Android. También existe `_release/build.bat`.
- Godot de Windows: `C:/Program Files (x86)/Godot_v4.7.2-stable_win64.exe/…`. JDK 25 y Android SDK en `%LOCALAPPDATA%\Android\Sdk`.
- **Keystore de Android:** `…\proyectos\tropas-keystore\tropas-release.keystore`, alias `tropas`. **La contraseña nunca se lee ni se imprime:** solo la usan bats temporales que se autoborran.

**GitHub:**
- `gh` está en `~/bin/gh` dentro del VM, con login por device-flow (puede caducar). Nunca guardar el token en el proyecto.
- El VM bloquea `uploads.github.com`: los assets de las releases se suben con `curl.exe` de Windows desde un bat que se autoborra.
- Los commits van con autor `adry2342 <65015949+adry2342@users.noreply.github.com>`.

**Versionado:**
- Se sube el último número (0.7.2 → 0.7.3…) en `project.godot` y `export_presets.cfg`, junto con `version/code` de Android.
- Hay que actualizar `CHANGELOG.md` (formato Keep a Changelog) y el README, que lleva capturas en `docs/img`.
- La release se publica en GitHub como **release normal**, no pre-release, con los ejecutables de Windows, Android y Linux, el zip del proyecto y `SHA256SUMS`.
- Última publicada: **v0.7.3**.

---

## 13. Historial resumido

- **v4:** combate táctico (carriles, distancias por arma, precisión por distancia, explosiones con caída). Economía más lenta, para partidas de unas 30 rondas.
- **v5:** veteranos (5 tubos), perfil persistente y configuración de vídeo.
- **v6:** sistema de especialidades nuevo (Soldado, Doctor, Radioperador, Francotirador; Mecánico, Infiltrado y Saboteador sin mecánica).
- **v7 / 7.1 / 7.2:** Centro de mando, árbol de especialidades, hitos y desbloqueo manual, candidatos de victoria y sección PRUEBAS.
- **v0.7.2:** primera release pública en GitHub.
- **v0.7.3 (2026-10-08):**
  - Medallas al derrotar a cada jefe.
  - Códice como libro y terminal CRT de especialidades.
  - Cartel SALIDA.
  - Tubos criogénicos corregidos.
  - Varias armas por tropa.
  - Tests eliminados.
  - Licencia y README con autores.
- **Sin publicar (2026-10-09), después de 0.7.3:**
  - Tropas animadas con piezas y brazos (andar, disparar, recargar, cambiar de arma, granada, muerte; jefe con animaciones propias).
  - Arte e iconos nuevos de las armas en toda la interfaz.
  - Lanzallamas eliminado.
  - Escopeta con daño acumulado por perdigón.
  - Granada solo a media distancia y con animación de lanzamiento.
  - Recargar exige estar quieto.
  - Nombre y nivel encima de la barra (siempre en planificación, al pasar el ratón en combate).
  - Explosión nueva.
  - Nombre del veterano al guardarlo, escrito con teclado.
  - Primer recluta con vida fija, sin objeto y sin estadísticas del arma en la ficha.
  - **Francotirador → Vigía (En guardia + disparo de reacción)**, con id `vigia` en todo el código.
  - **Habilidades libres para todos**; se borraron los restos (Zapador, Municionero, `troop_data`, objetos `Unique`).
  - **Hay que añadir todo esto al CHANGELOG en la próxima versión (0.7.4).**

---

## 14. Pendiente / ideas (por orden aproximado)

1. **Equilibrado:** medallas por jefe, curva de enemigos, escopeta nueva y Vigía.
2. **Mejoras del árbol** de las especialidades: los 4 rangos de cada una están sin definir.
3. **Mecánicas** de Mecánico, Infiltrado y Saboteador, con la misma filosofía de «faceta única».
4. **Nuevo modo** del hangar (con los 5 veteranos) y **Modo Infinito** (hito del Saboteador).
5. Vehículos (idea del GDD original). Decidir si se recupera el lanzagranadas como arma.
6. **Sonido** (disparos, explosiones, hoja del Códice…). Icono propio del .exe y de Android.
7. Interfaz pensada para **móvil** (tamaños táctiles).
8. Quitar la sección PRUEBAS antes de la versión final. Borrar los restos sin uso de §11.

# Tropas en miniatura — GDD vivo y estado del proyecto

> **Para quien lea esto (persona u otra IA):** este documento es el "compact" del juego, todo lo necesario para continuar el desarrollo sin el historial de chats. Si algo no cuadra con el código, **manda el código** (y conviene actualizar este archivo).
> Última actualización: **2026-10-10** · versión del proyecto **0.7.5** (+ cambios sin publicar, ver §13).
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
  - **Entrenamiento:** +10 de vida y +6 de daño, acumulable.
- **Intendencia (tienda):**
  - Ofrece **4 objetos o armas**. Precios de objeto: 6, 10, 15 o 22 según rareza; de arma: 9, 12, 15 o 18.
  - Se vende al 50 %. La primera tirada nueva cuesta 1.
  - La rareza máxima depende de la ronda: rara antes de la R4, épica hasta la R8 y legendaria después.
  - También se **reclutan tropas** por 13–19 monedas. Estas sí pueden traer objeto (35 %, y entonces cuestan más), arma rara (25 %) o especialidad (20 %, +4 monedas).
- **Mejora de armas:** la ⭐ sube el arma hasta el nivel 4. Cuesta 1, 2 y 3 PM y da +4 de daño por nivel (y un extra por familia: pistola +3 de precisión, automática +1 de cargador, escopeta +4 de cadencia, precisión +30 de alcance, pesada −0,25 s de recarga, explosivo +4 de radio, cuerpo a cuerpo +5 de movilidad).

---

### Estadísticas en puntos (2026-10-10)
Ninguna estadística se mide en % (`TroopStats.PTS` = 100). Claves de modificador: `health, damage, fire_rate, accuracy, range, magazine, reload, move_speed, armor, dodge, aoe, pierce, poison, heal, suppress_hit`.
- **Daño, Cadencia, Curación, Veneno:** 100 puntos = lo base del arma; cada punto suma una centésima (+15 de daño → pega 115/100). La ficha muestra Daño 115, Cadencia 115 (y en la tarjeta los disparos/s).
- **Precisión, Armadura, Evasión:** 0–100 puntos (de cada 100 disparos/impactos/daño).
- **Vida, Alcance (px), Cargador (balas), Recarga (s), Movilidad, Explosión (px):** se suman tal cual.
- Siguen en % solo las curaciones proporcionales a la vida máxima (botiquín 35 %, autocuración 2 %/s, Doctor 6 %) y los umbrales de vida.

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
- **No hay golpe crítico** (se quitó del todo el 2026-10-10: ni estadística, ni multiplicador, ni armas, habilidades u objetos que lo den). El daño de cada impacto es siempre el mismo (arma × daño); sí hay esquiva.
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
- **Anillo azul:** el objetivo está suprimido (por un Soldado o por balas aturdidoras).
- **Tinte verde:** el objetivo está envenenado (balas venenosas): pierde vida poco a poco, sin que lo pare la armadura, y se cura la mitad.
- **Anillo azul discontinuo:** el Vigía está En guardia.
- **Aura roja:** frenesí (adrenalina o venganza).

**Textos flotantes**
- Daño, «¡Fallo!», «😰 Suprimido», «🧪 Envenenado», «¡Granada!», «🔄 cambio de arma», «🔭 En guardia», «🔭 ¡Reacción!».

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

**Principio de diseño:** una especialidad es una **faceta única del soldado en el campo de batalla** que lo diferencia de los demás. **No** depende del arma que lleve, porque cualquier tropa puede llevar cualquier arma. Las familias afines solo dan +15 de daño y +10 de precisión.

Se elige al llegar a Nv. 5.

| id interno | Nombre | Pasiva | Estado |
|---|---|---|---|
| soldado | **Soldado** 🪖 | **Fuego de supresión:** cada impacto suprime al blanco 1,5 s (−15 de precisión, −22 de movilidad, −20 de cadencia). | ✅ |
| medico | **Doctor** | **Primeros auxilios:** cada 4 s cura un 6 % al aliado más herido a 220 px. **Estabilizar:** una vez por combate salva a un aliado que iba a caer (queda en pie con un 25 %). | ✅ |
| comunicaciones | **Radioperador** | Revela el mapa de calor en la planificación. Cada 4 s **marca** al enemigo más peligroso (+15 de daño recibido, pierde el camuflaje). Una vez por combate pide **artillería**: 3 proyectiles de 26 sobre el grupo más denso. | ✅ |
| vigia | **Vigía** 🔭 *(rework 2026-10-09; antes "Francotirador")* | **En guardia:** quieto 1,2 s → +50 de alcance y +10 de precisión. Cada enemigo que **entra** en su alcance estando en guardia recibe al instante un **disparo de reacción** (+50 de daño; uno por enemigo y combate; 0,8 s entre reacciones). Apunta al enemigo **más peligroso** a su alcance. +20 de daño contra suprimidos o marcados (`tirador_elite`, `damage_vs_pinned`). | ✅ |
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
- **Todas son libres: cualquier tropa puede tener cualquier habilidad** (2026-10-09). El sistema de elección no cambia: al subir de nivel salen 2 al azar (a veces 3).
- **Habilidades generales (2026-10-10, lista definitiva preliminar).** Las antiguas se retiraron de forma **provisional** (`GameContent._LEGACY_SKILLS`: no se ofrecen ni salen en el Códice, pero los veteranos guardados las conservan). Datos en `_dev/gen_skills.py` (genera los `.tres`); mecánicas en `Scripts/Systems/skill_effects.gd` (`Effects.sk`) y efectos visuales en `Scripts/Battle/skill_fx.gd`.
- **Categorías** (`SkillData.category`), con símbolo dibujado por código (`Scripts/UI/category_badge.gd`) en la subida de nivel, la ficha (agrupadas) y el Códice (ordenado por categoría): **△ Daño** (rojo) · **□ Tanque** (verde) · **S Movilidad** (cian) · **○ Trampas y munición** (ámbar).
- Campos nuevos de `SkillData`: `player_only` (los enemigos no la reciben: Ruleta rusa, Deuda de sangre, Señuelo) y `needs` (`"magazine"` / `"bullets"`: solo se ofrece si la tropa lleva un arma con cargador o de bala).
- **Vida máxima permanente por habilidad:** `TroopCard.skill_health` (se guarda en el perfil), la suma `TroopStats`.

| Cat. | Habilidad | Efecto (puntos) | Simplificado/equilibrado respecto al Word |
|---|---|---|---|
| △ | Ruleta rusa (legendaria) | 1 vez por combate, a los 3 s: tambor de 6 recámaras sobre la cabeza, turnos alternos él/enemigo más peligroso. Si sale contra el enemigo, muere (jefe: −35 % de su vida máx.); si sale contra él, muere él | Jefes no mueren de un tiro |
| △ | Bala de rebote | 10 % de que un impacto de bala rebote a otro enemigo a ≤170 px con el mismo daño | — |
| △ | Gatillo del destino | La última bala de cada cargador (cargadores ≥3): acierta seguro, ignora el 50 % de la evasión, 10 % de letal | Cada cargador en vez de 1 vez por ronda (si no, casi nunca se nota) |
| △ | Cadena de pólvora | Al matar, el cuerpo explota a los 0,6 s: 18 + 12 % vida máx. del caído (máx. 70), radio 75, en cadena | Tope de daño para que un jefe no borre la pantalla |
| △ | Todo al rojo | +6 de daño por acierto seguido, sin límite; un fallo lo reinicia | +6 en vez de +10 (el francotirador acierta 93 %) |
| △ | Deuda de sangre (legendaria) | El enemigo que mata a un aliado queda «en deuda»; al morir se levanta de tu lado 10 s a puñetazos; no cae mientras viva el dueño de la habilidad | **Simplificada:** sin elegir soldado antes de la ronda ni condición del 5 % de vida |
| □ | Ni muerto me ganas | Su asesino queda condenado: muere a los 5 s (jefe: pierde la mitad de su vida actual) | — |
| □ | Venganza | Al caer un aliado, disparo inmediato al asesino (+50 de daño); si acierta, +5 vida máx. permanente (máx. +50) | +5 en vez de +1 |
| □ | ¿Bueno con esa arma? Imagínate yo | Si le atacan con su misma arma, +3 vida máx. permanente (1 vez por combate) | +3 en vez de +1 |
| □ | Carne de cañón | Se une al aliado con menos vida máx. y recibe el 30 % de su daño | El aliado se elige solo (sin menú previo) |
| □ | Ojo por ojo | Tras el primer golpe guarda el daño de 3 s; al matar recupera el 50 % (segmento en la barra) | (sin nombre en el Word) |
| □ | Te llevas parte de mí | Al caer reparte el 40 % de su vida máx. + el daño sobrante (máx. otro 40 %) entre los aliados (orbes) | Acotado |
| □ | El problema es matarme | −4 de daño recibido por golpe de cada enemigo concreto, máx. −40 | Con tope (sin él, una ametralladora le haría inmune) |
| S | Último en pie | +40 de daño si es el último vivo | Igual que antes |
| S | Esquive | +10 de evasión y +10 por cada esquiva, hasta +40 | — |
| S | No me pillas dos veces | +5 de evasión contra quien le acierta, máx. +30 por enemigo | Con tope |
| S | Cambio de sitio | 1.ª vez que iba a morir: se cambia con el aliado más cercano, que recibe la mitad del golpe | La mitad, no el golpe entero |
| S | Pánico útil | <20 % de vida: 3,5 s en zigzag disparando, +35 evasión, +25 movilidad, −12 precisión | — |
| S | Paso fantasma | +8 de evasión; cada 3 esquivas desaparece 1 s y reaparece cerca (pierden el objetivo) | +8 base para que pueda activarse |
| ○ | Doble tirada de recarga | La recarga dura entre 60–120 % (tira dos, la mejor); Cargador veloz y Recarga desesperada tiran dos veces | La recarga no tenía tirada: se la doy |
| ○ | Efecto mariposa | Tras la 1.ª baja, cada aliado: nada / +30 vida / +25 % balas / 2 s invisible / 4 s +40 movilidad y evasión | — |
| ○ | Cargador veloz | 35 % de recargar en 0,1 s | 35 % en vez de 75 % |
| ○ | Trampas | Cepos en tierra de nadie en su carril: 0 (50 %), 1 (35 %) o 2 (15 %); 20 de daño y 2 s clavado | Se colocan solos (sin que el jugador los ponga) |
| ○ | Munición fantasma | 10 % de no gastar bala; con cuchillo, 5 % de cuchillada mortal | — |
| ○ | Píldora roja | 6 s con +45 movilidad y +30 evasión; veneno del 30 % de su vida en 10 s que nunca mata | El veneno no mata |
| ○ | Cable trampa | Cable en tierra de nadie: el primer enemigo cae 1,5 s y 4 s con 8 % de letal por bala | — |
| ○ | Señuelo | Muñeco con su aspecto delante de él; aguanta 6 impactos | — |
| ○ | Hacerse el muerto | 1.ª vez <10 % de vida: 60 % de tirarse al suelo 3 s; nadie le apunta | — |
| ○ | Recarga desesperada | 1 vez, recargando con <25 % de vida: recarga instantánea con 1..cargador balas | 25 % en vez de 15 % |
| ○ | Robo de cargador | 30 % al morir un enemigo a ≤220 px: corre al cuerpo y se lleva sus balas (puede pasarse del cargador) | — |

- **Tanda 2 (2026-10-10, ideas propias, 2 por categoría).** Pensadas para funcionar solas y combinar de rebote con otras:

| Cat. | Habilidad | Efecto | Inspiración |
|---|---|---|---|
| △ | Fondo del cargador | Las balas del último tercio del cargador: +25 de daño | Recámaras «calientes» de los shooters |
| △ | Duelo al sol | El primer enemigo que le hace daño es su rival: le apunta, +30 de daño contra él, −10 contra el resto; si cae, el siguiente que le dé | Duelos de western (Red Dead) |
| □ | Segunda piel | Escudo de 15 al empezar (se gasta antes que la vida); la curación que sobra se vuelve escudo (máx. 40); franja azul sobre la barra | Escudos/sobrecuración (Overwatch, Hades) |
| □ | Trinchera | Cada 1,5 s quieto, un saco terrero: −7 de daño recibido por saco, máx. 3; se pierden al moverse (se dibujan) | Coberturas (Gears, XCOM) |
| S | Inercia | Moviéndose gana +10 de evasión/s hasta +25; parado la pierde (−15/s) | Momentum (Titanfall) |
| S | Retirada táctica | Al vaciar el cargador (≥3) salta 70 px lejos del enemigo más cercano y recarga con +25 de evasión | Dash de recarga (Apex, Valorant) |
| ○ | Balas trazadoras | 1 de cada 4 balas es trazadora (estela roja): al acertar marca 2,5 s (+10 de daño recibido de todos) | Trazadoras reales / marcas |
| ○ | Cebo explosivo | Las 2 primeras recargas de cada combate dejan una mina de proximidad a sus pies (25 de daño, radio 60) | Minas de recarga (CoD, TF2) |

- **Munición inicial aleatoria (2026-10-10):** al empezar el combate cada arma con cargador (>1) tiene un 40 % de salir llena (`troop.START_FULL_CHANCE`); si no, sale con `ceil(cargador × √azar)` balas (`START_AMMO_CURVE` 0,5): lo normal es bastante, a veces medio cargador y alguna vez 1 bala. Afecta a los dos bandos. Da juego a Gatillo del destino, Fondo del cargador, recargas, Robo de cargador, Retirada táctica y Cebo explosivo.
- **Granadas como objeto** (el Word las pone aquí): nuevas **Granada cegadora** (Suprimido 3 s en radio 85) y **Granada de gas** (veneno 36 en 4 s, radio 75), con nube/destello propios (`SkillFX.blast`). Cada tipo de granada lleva su propio temporizador.
- **Señuelos y resucitados** (`meta "summon"`): no cuentan para ganar/perder, no dan monedas ni son bajas, no salen en la reserva ni como candidatos a veterano.
- Estados nuevos en `troop.gd`: derribado (`stun_left`, tumbado), clavado (`root_left`), haciéndose el muerto (`feign_left`), pánico, robo, condenado (`doom_left`, cráneo con cuenta atrás). Buffs genéricos nuevos: `dodge` y `accuracy` (puntos).
- Prueba visual: `_dev/skills_preview.tscn` (`GROUP` 0–4: cada categoría o todas mezcladas).
- **Antiguas (retiradas, provisional):** Piel dura, Pulso firme, Ojo certero, Sangre fría, Gatillo fácil, Recarga rápida, Velocista, Camuflaje, Cargador ampliado, Instinto veterano, Oficial, Cirujano, Autocuración, Coordenadas precisas, Enlace táctico, Mira láser, Traje ghillie.

**Objetos** (`Resources/Items/*.tres`)
- **Munición: hueco propio** (`TroopCard.ammo`, objetos con `slot = MUNICION`), aparte de los 3 de objetos. *(2026-10-09)*
  - Sin munición especial = **Balas normales** (`ammo = null`).
  - Cargar otra munición **sustituye** a la que tenía, que **se pierde**. «Quitar» la devuelve a la reserva y vuelve a las normales.
  - **Solo afecta a las armas de bala** (`TroopStats.uses_ammo`: `projectile == BALA`). Cuchillo, bazuca y lanzagranadas la ignoran; con varias armas, cada una calcula sus estadísticas aparte. Las claves `poison_pct`, `pierce` y `suppress_hit` se borran fuera de las armas de bala.
  - **4 tipos** *(rehechos el 2026-10-10)*. Regla: cada especial paga un **handicap** por su ventaja; ninguna es siempre mejor que las normales. Todas las especiales son **rareza 1 (10 💰, `Economy.ITEM_PRICE[1]`)**.

    | Munición | Modificadores | Gana… | Pierde… |
    |---|---|---|---|
    | **Normales** (sin objeto) | — | en el caso general: daño completo e inmediato | — |
    | **Venenosas** 🧪 | `damage −35`, `poison 60` | jefes y blancos con armadura o que se curan (+10 % contra un jefe de 500 de vida y 20 % de armadura) | enemigos débiles o con fuego concentrado: el veneno llega tarde y el que queda al morir se pierde (TTK contra 50 de vida: hasta +20 %) |
    | **Perforantes** 🔩 | `damage −15`, `pierce 1` | grupos en fila: con dos enemigos alineados, ×1,7 de daño | un solo blanco: −15 % |
    | **Aturdidoras** 😰 | `damage −25`, `suppress_hit 1.5` | control: cada impacto deja **Suprimido** 1,5 s (−20 de cadencia, −22 de movilidad, −15 de precisión) | −25 % de daño siempre |

  - **Veneno** (`TroopStats.POISON_DURATION` 3 s, `POISON_HEAL_CUT` 0,5; estado `"poison"` en `troop.gd`): cada impacto añade a la **reserva** del blanco el `poison_pct` × su daño (antes de la armadura). La reserva se le resta en ticks de 0,5 s y se vacía en 3 s; cada impacto nuevo reinicia la cuenta (no se suman duraciones). **Ignora armadura** y el envenenado **se cura un 50 % menos**. Como es proporcional al daño, es igual de justo con la escopeta (5 perdigones) que con el rifle o la ametralladora: no hay tope de acumulaciones porque no hace falta. Tinte verde y texto «🧪 Envenenado». El fuego amigo no envenena (ni suprime).
  - **DPS de la ficha** (`estimate_dps`) = directo × (1 + `poison_pct`); `compute` da también `direct_dps` y `poison_dps`.
  - **Tabla de equilibrio** (`_dev/ammo_balance.tscn`; tropa base, daño ×1, precisión a distancia óptima, TTK con daño esperado por disparo; jefe = 500 de vida y 20 % de armadura):

    | Arma | Munición | Directo | Veneno | Total | 2 en fila | TTK 50 | TTK 100 | TTK jefe |
    |---|---|---|---|---|---|---|---|---|
    | Pistola | Normales | 9.1 | — | 9.1 | 9.1 | 4.8 s | 9.6 s | 60.6 s |
    | | Venenosas | 5.9 | 3.6 | 9.5 | 9.5 | 5.0 s | 10.0 s | **54.0 s** |
    | | Perforantes | 7.8 | — | 7.8 | **15.5** | 5.4 s | 10.8 s | 70.8 s |
    | | Aturdidoras | 6.9 | — | 6.9 | 6.9 | 6.1 s | 12.1 s | 80.4 s |
    | Subfusil | Normales | 8.4 | — | 8.4 | 8.4 | 5.7 s | 11.4 s | 71.6 s |
    | | Venenosas | 5.5 | 3.3 | 8.8 | 8.8 | 6.0 s | 11.7 s | **64.5 s** |
    | | Perforantes | 7.2 | — | 7.2 | **14.4** | 6.4 s | 13.1 s | 85.8 s |
    | | Aturdidoras | 6.3 | — | 6.3 | 6.3 | 7.1 s | 14.4 s | 97.3 s |
    | Fusil de asalto | Normales | 9.3 | — | 9.3 | 9.3 | 4.1 s | 9.8 s | 63.3 s |
    | | Venenosas | 6.0 | 3.6 | 9.7 | 9.7 | 4.6 s | 10.0 s | **56.5 s** |
    | | Perforantes | 7.9 | — | 7.9 | **15.8** | 4.6 s | 11.2 s | 74.1 s |
    | | Aturdidoras | 7.0 | — | 7.0 | 7.0 | 5.5 s | 12.6 s | 85.4 s |
    | Escopeta | Normales | 10.5 | — | 10.5 | 10.5 | 2.7 s | 7.6 s | 47.7 s |
    | | Venenosas | 6.8 | 4.1 | 10.9 | 10.9 | 3.0 s | 7.6 s | **43.5 s** |
    | | Perforantes | 8.9 | — | 8.9 | **17.9** | 2.7 s | 7.6 s | 57.5 s |
    | | Aturdidoras | 7.9 | — | 7.9 | 7.9 | 4.0 s | 8.9 s | 65.1 s |
    | Rifle de francotirador | Normales | 10.0 | — | 10.0 | 10.0 | 3.3 s | 6.7 s | 46.8 s |
    | | Venenosas | 6.5 | 3.9 | 10.4 | 10.4 | 3.3 s | 6.7 s | **43.4 s** |
    | | Perforantes | 8.5 | — | 8.5 | **17.1** | 3.3 s | 6.7 s | 56.8 s |
    | | Aturdidoras | 7.5 | — | 7.5 | 7.5 | 3.3 s | 10.0 s | 63.5 s |
    | Ametralladora | Normales | 9.1 | — | 9.1 | 9.1 | 3.3 s | 10.3 s | 64.6 s |
    | | Venenosas | 5.9 | 3.5 | 9.4 | 9.4 | 4.0 s | 10.3 s | **57.6 s** |
    | | Perforantes | 7.7 | — | 7.7 | **15.4** | 3.8 s | 11.5 s | 75.7 s |
    | | Aturdidoras | 6.8 | — | 6.8 | 6.8 | 4.3 s | 12.5 s | 86.2 s |

    Las proporciones son iguales en todas las armas (venenosas 104 % del DPS a la larga, perforantes 85 % / 170 % en fila, aturdidoras 75 %): ninguna arma sale especialmente favorecida.
  - Solo se ofrece munición en las subidas a quien lleva alguna arma de bala. Se guarda en el perfil (`"ammo"`).
- **Objetos:** máximo **3 huecos** por tropa (máx. 1 armadura, sin repetir).
- Lista:
  - Chaleco táctico (+25 de vida, −5 de movilidad)
  - Blindaje pesado (+20 de armadura, −14 de movilidad)
  - Botiquín (una vez, por debajo del 40 % de vida, se cura un 35 %)
  - Inyector de adrenalina (frenético 5 s al empezar)
  - Mira telescópica (+50 de alcance, +12 de precisión)
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
  - Al pulsar «Guardar» **te pide el nombre del veterano** (propone el que tenga, que se puede cambiar antes en la ficha): máximo 16 letras, no puede estar vacío. En PC se escribe con el teclado (Intro guarda, Esc cancela) y en móvil sale el teclado del sistema (`LineEdit.virtual_keyboard_enabled` + `edit()`).
  - Hay **5 tubos**. Con todos llenos, eliges a quién sustituye o no guardas a nadie.
  - Con 5 veteranos se abre el hangar, el «nuevo modo», todavía sin implementar.
- **Configuración:** opciones de vídeo, más una sección **PRUEBAS provisional** (desbloquear todo, borrar partida, no guardar) que hay que **quitar antes de una versión final**.

---

## 10. Interfaz y arte

**Paleta y fuentes**
- La paleta y los componentes están en `Scripts/UI/ui_kit.gd`: `panel`, `label`, `icon_rect`, `icon_label`, `set_weapon_icon` y `make_recruit_card(card, w, show_weapon_stats)`.
- Fuentes (OFL): Cinzel y EB Garamond para el Códice; Share Tech Mono para el terminal.

**Ficha de tropa** (`troop_detail_panel.gd`, rehecha el 2026-10-09)
- Se abre al pulsar una tropa: del tablero, de la reserva o un veterano del Cuartel. Es compacta (900 px), con paleta oliva, caqui y latón, títulos en `ShareTechMono` y esquinas de visor.
- **Cabecera:** retrato, nombre, nivel (NV n), especialidad, 💰/⭐ y cerrar.
  - **Renombrar:** al tocar el nombre (o el lápiz pequeño a su lado) se vuelve un campo de texto en el mismo sitio, con el nombre seleccionado. Intro o tocar fuera guarda; Esc cancela solo la edición (no cierra la ficha). Máximo `TroopCard.NAME_MAX_LEN` (16) letras, sin espacios en los extremos; si queda vacío se queda el anterior (`TroopCard.clean_name`). En móvil sale el teclado del sistema.
  - Durante la run emite `roster_changed`: se actualizan al momento la tarjeta de la reserva y el rótulo encima de la tropa. Al terminar la run, el diálogo del veterano propone el nombre actual.
  - En el **Cuartel** también se puede (el veterano es tuyo): emite `vault_card_changed` y se guarda en el perfil.
- **Columna izquierda:**
  - **Arsenal:** celdas con icono y nombre; la principal tiene borde verde y la etiqueta PRINCIPAL; ★n es el nivel de mejora y ▲ avisa de que se puede mejorar. Con «+» se añade un arma de la reserva.
  - **Munición:** un hueco propio, **solo con el icono** (de forma distinta a los objetos: redondeado y azul). Cada munición tiene su icono de 3 cartuchos con la punta de su color y un distintivo (gota verde con burbujas, escudo, rayo; las normales, sin distintivo): `Assets/Items/Ammo/*.png`, generados con `_dev/art/gen_ammo_icons.py` y puestos en el `icon` de cada `.tres`.
  - **Objetos:** 3 celdas con icono y nombre. «+» sale si hay algo equipable en la reserva; «—» si no hay nada.
  - **Estadísticas:** cuadrícula de 6×3 con **todas**, aunque valgan 0 (salen atenuadas): vida, daño, impacto (daño por impacto), cadencia, precisión, óptimo (distancia óptima), alcance, cargador, recarga, movilidad, evasión, armadura, perfora, veneno (DPS del veneno), supresión, explosión, curación y DPS.
- **Columna derecha:**
  - **Especialidad:** nombre, familias afines como etiquetas y la pasiva (al tocarla, una tarjeta con afinidad y sinergia).
  - **Habilidades:** celdas **iguales** en 2 columnas, con ×N si se repite.
- **Pie:** «Retirar a la reserva» (solo si está en el tablero) y «Subir a Nv. n · ⭐ x». En el Cuartel sale «Eliminar veterano» (mantener pulsado y confirmar).
- **Sin textos de ayuda fijos y sin tooltips** (no se duplica la información): al hacer **clic o tocar** (móvil) cualquier arma, munición, objeto, estadística, pasiva o habilidad sale una **tarjeta flotante** con la explicación y las acciones: hacer principal, mejorar el arma, quitar, cargar munición o equipar desde la reserva. La tarjeta se cierra al tocar fuera o con Esc.
- Vista previa de varios estados: `_dev/detail_preview.tscn` (guarda `detail_*.png` en `_dev/art_tmp/`).
- Renombrado: `_dev/rename_test.tscn` (comprobaciones ✔/✘ y `rename_*.png`) y `_dev/rename_boot.tscn` (como `dev_boot`, pero deja escribir con `game_manage input_key`).

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
- El sprite del recluta (`Assets/Sprites/sprite-personaje-basico.png`, estilo chibi con trazo grueso) está **recortado en piezas**: piernas, cuerpo y mangas (`Assets/Troop/`, con `_dev/art/gen_troop_rig.py` y después `_dev/art/clean_sleeves.py`, que limpia los restos de brazo bajo las mangas y completa el cinturón).
- **Brazos y manos (rehechos el 2026-10-09):** cada brazo es hombro → codo → mano, con **IK de dos huesos de longitud fija** (nunca se estiran), dibujado por código con el mismo trazo (`TroopRig.Limb`). El hombro queda dentro de la manga. Las manos son puños completos con su contorno (`hand_front/back.png`, `_dev/art/gen_hand.py`) y se dibujan **encima** del arma, así que la abrazan sin cortes ni atravesarla.
- **Reglas del agarre (rehechas otra vez el 2026-10-09, más simples):**
  1. El arma manda: cada fotograma se calcula su pose y las manos van a sus agarres. Si la empuñadura quedara fuera de alcance, se acerca el arma a la mano.
  2. El arma de dos manos va a la altura del pecho. El codo siempre queda hacia abajo o hacia atrás.
  3. Una mano agarrada gira con el arma; una suelta, con el antebrazo.
  4. Al cambiar de agarre, la mano se desliza en ~0,1 s en vez de saltar (`TroopRig.Hand.follow`).
  5. El arma nunca se vuelve transparente. **Cambio de arma:** se baja a la cadera, se cambia ahí y se sube. **Granada:** con un arma de dos manos, la trasera la sujeta baja y la delantera lanza; la pistola o el cuchillo se guardan en la cadera. **Muerte:** el arma cae recta, se desvanece y los brazos quedan sueltos hacia el suelo.
  - Prueba en movimiento: `_dev/motion_preview.tscn` (14 situaciones, 16 fotogramas; imprime `SLIP`, la separación mano-agarre, que debe ser 0) y `_dev/art/motion_sheet.py` para montar las hojas.
- Animaciones hechas por código:
  - Reposo (respira) y caminar (piernas alternas, balanceo, el paso va con la velocidad real).
  - Disparo (retroceso y fogonazo en la bocacha; las balas salen de ahí). Cuchillada.
  - Recarga, casi igual que el reposo: el arma baja un poco.
  - Cambio de arma: guarda una y saca la otra.
  - Lanzar granada.
  - Muerte: retrocede, se le cae el arma, cae de espaldas y se desvanece; la tropa se libera al terminar.
  - Variantes del jefe.
- **Cómo sostienen las armas:** a una mano la pistola y el cuchillo (brazo delantero extendido). A dos manos el resto, también el subfusil: la mano trasera en la empuñadura y la delantera en el apoyo (guardamanos, corredera, cañón o segunda empuñadura).
- Los datos de cada arma están en `TroopRig.WEAPON_RIG`, en px de su textura: `grip`, `muzzle`, `support` (si es a dos manos) y `hold` (dónde queda la empuñadura respecto al tronco). Para revisar el agarre sin jugar: `_dev/rig_preview.tscn` guarda capturas grandes de cada arma y poses en `_dev/art_tmp/`.
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
- Última publicada: **v0.7.5** (2026-10-10).

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
- **v0.7.4 (2026-10-09):**
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
- **Sin publicar (2026-10-09), después de 0.7.4:**
  - Brazos y manos rehechos (IK de dos huesos, puños encima del arma, mangas limpias); el subfusil pasa a dos manos.
  - Munición con hueco propio (normales, punta hueca, incendiarias, perforantes y **aturdidoras**); solo en armas de bala; sustituye a la anterior.
  - Suprimido también baja la cadencia un 20 %. Se borró la habilidad Bala perforante.
  - Pruebas de munición: `_dev/ammo_test.tscn`; equilibrio: `_dev/ammo_balance.tscn`.
  - Animaciones de agarre rehechas otra vez (arma manda, sin transparencias, muerte con brazos sueltos).
  - **Ficha de tropa rehecha:** compacta, hueco de munición solo con icono, objetos con icono y nombre, estadísticas en cuadrícula, habilidades uniformes y explicaciones en tooltip o tarjeta al tocar.
  - **Renombrar tropas** desde la ficha durante la run (y en el Cuartel): tocar el nombre o el lápiz, Intro guarda, Esc cancela; límite de 16 letras compartido con el veterano (`TroopCard.NAME_MAX_LEN`).
  - **Munición rehecha (2026-10-10):** las incendiarias pasan a **venenosas** 🧪 (−35 % de daño directo; veneno del 60 % del daño de cada impacto en 3 s, ignora armadura, −50 % de curación al envenenado; estado `"poison"`, tinte verde; desaparece todo lo de quemadura, también `WeaponData.burn_*`). **Fuera las de punta hueca.** Perforantes con handicap (−15 % de daño). Las 3 especiales a rareza 1. Icono nuevo de las venenosas (`gen_ammo_icons.py`) e iconos puestos en el `icon` de cada `.tres`. Tabla de equilibrio: `_dev/ammo_balance.tscn`.
  - **Fuera el golpe crítico** en todo el juego (stats, armas, textos «¡Crítico!»/«¡En la cabeza!», contador). El impacto letal se queda. Rehechas: Ojo certero (+6 % daño), Sangre fría (+8 % daño, +5 % precisión), Instinto veterano (+6 % daño, +5 % esquiva), Mira láser (+15 % precisión), Mira telescópica (+15 % alcance, +12 % precisión); Vigía: reacción +50 % de daño y +20 % de daño a suprimidos/marcados. La ficha cambia Crítico/× Crítico por Impacto y Óptimo.

---

  - **Estadísticas en puntos (2026-10-10):** fuera los % de todas las estadísticas y modificadores (ver §3 «Estadísticas en puntos»). Claves `*_pct`/`health_flat` → `health, damage, fire_rate, range, magazine, reload, move_speed, aoe, poison, heal`. Alcance, cargador, recarga, movilidad y radio pasan a valores fijos (mira telescópica +50, cargador ampliado +3, recarga rápida −0,5 s, velocista +18, blindaje −14, adrenalina +27, venganza +14, guardia del Vigía +50 de alcance, Municionero −0,6 s); supresión −22 de movilidad y −20 de cadencia; entrenamiento +10 de vida y +6 de daño. Sin probar en el motor (prohibido por Adri).

## 14. Pendiente / ideas (por orden aproximado)

1. **Equilibrado:** medallas por jefe, curva de enemigos, escopeta nueva y Vigía.
2. **Mejoras del árbol** de las especialidades: los 4 rangos de cada una están sin definir.
3. **Mecánicas** de Mecánico, Infiltrado y Saboteador, con la misma filosofía de «faceta única».
4. **Nuevo modo** del hangar (con los 5 veteranos) y **Modo Infinito** (hito del Saboteador).
5. Vehículos (idea del GDD original). Decidir si se recupera el lanzagranadas como arma.
6. **Sonido** (disparos, explosiones, hoja del Códice…). Icono propio del .exe y de Android.
7. Interfaz pensada para **móvil** (tamaños táctiles).
8. Quitar la sección PRUEBAS antes de la versión final. Borrar los restos sin uso de §11.

# Changelog

Todas las versiones notables de **Tropas en miniatura**. Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/); versiones con [SemVer](https://semver.org/lang/es/).

## [0.7.2] - 2026-10-07 — Primera release pública (alpha)

### Añadido
- **Centro de mando** en vista ¾ (Jugar → Centro de mando): mesa táctica, tubos criogénicos, archivo (Códice), terminal de especialidades, hangar del Modo Infinito y radio (Configuración). Objetos con silueta clicable y brillo al pasar el ratón; escala a cualquier pantalla (PC y móvil apaisado).
- **Veteranos**: al vencer al Jefe Final guardas a uno de tus soldados (de todo el ejército) en uno de los 5 tubos; ficha de solo lectura y eliminación con pulsación larga + confirmación.
- **Progresión de especialidades**: 🏅 Medallas de mando al terminar cada partida y árbol de 4 mejoras por especialidad (mejoras pendientes de definir).
- **Especialidades por hitos**: solo el Soldado al empezar; Doctor, Radioperador, Francotirador, Infiltrado, Mecánico y Saboteador se consiguen con hitos y se desbloquean a mano en el Centro de mando al acabar la partida.
- Nuevas especialidades **Mecánico**, **Infiltrado** y **Saboteador** (sin mecánica todavía). El Médico pasa a llamarse **Doctor**.
- **Configuración** (PC): modo de pantalla, resolución, VSync y límite de FPS. Sección **Pruebas** provisional (desbloquear todo, borrar partida, no guardar).
- Confirmación antes de empezar una operación y antes de entrar al Modo Infinito.
- Builds de **Windows**, **Linux** y **Android**.

### Cambiado
- Combate táctico v4: IA por carriles, distancia de combate por arma, precisión por distancia, explosiones con caída, disparo en marcha solo con armas ligeras.

### Eliminado
- Especialidades Municionero y Zapador y el lanzagranadas como arma.

### Corregido
- En la victoria contra el Jefe Final solo aparecían los soldados vivos para guardar como veterano.
- El botón «← Menú principal» del Cuartel no respondía en su mitad derecha.

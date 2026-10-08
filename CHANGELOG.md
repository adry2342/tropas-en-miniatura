# Changelog

Todas las versiones notables de **Tropas en miniatura**. Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/); versiones con [SemVer](https://semver.org/lang/es/).

## [0.7.3] - 2026-10-08

### Añadido
- **Códice como libro**: el Archivo abre un libro de cuero con hojas de pergamino. La tapa se levanta al abrirlo y las hojas se pasan con animación (botones de las esquinas, ←/→, rueda del ratón o cintas de marcapáginas). Un capítulo por doble página: Habilidades, Objetos, Armas y Especialidades. Fuentes Cinzel y EB Garamond (OFL).
- **Varias armas en combate**: todas las armas del arsenal van equipadas. La tropa usa la **principal**; si se queda sin balas mientras le disparan y otra arma tiene munición y alcanza al objetivo, cambia a esa en vez de recargar. Cuando pasa el peligro vuelve a la principal y la recarga.
- **Terminal de especialidades** rediseñado: pantalla de fósforo verde con encendido de CRT, fichas de unidad, árbol de hexágonos unidos por circuitos con pulso de energía y expediente con la ficha de cada mejora.
- **Cartel de SALIDA** en la pared del Centro de mando para volver al menú principal (sustituye al botón).

### Cambiado
- **🏅 Medallas de mando**: se ganan al momento al derrotar a cada jefe (Jefe de Sector 3, +1 por cada sector siguiente; Jefe Final 8) en lugar de al terminar la partida. Se muestran en la pantalla de recompensas y en el resumen de fin de partida.
- Cámaras criogénicas redibujadas con una perspectiva coherente (tapa, cristal y base alineados en el mismo eje).
- Arsenal de la ficha de tropa: «PRINCIPAL» y «Reserva · hacer principal».
- El Códice pasa varias hojas seguidas al saltar capítulos; el paso de hoja con A/D se quita (siguen las flechas).
- Las tuberías de las cámaras ya no tapan el letrero «Bahía criogénica».

### Eliminado
- Marcador de medallas y jefes finales del Centro de mando.
- Tests y simuladores de `_dev/` (no aportaban en esta fase).

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

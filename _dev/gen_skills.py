# Genera Resources/Skills/*.tres de las habilidades generales (lista del 2026-10-10).
# Uso: python3 _dev/gen_skills.py  (desde la raíz del proyecto). Fuente de verdad: la tabla de abajo.
import json, os
D, T, M, U = 0, 1, 2, 3  # △ Daño · □ Tanque · S Movilidad · ○ Trampas/munición

SKILLS = [
 # ---------------------------------------------------------------- △ DAÑO
 dict(id="ruleta_rusa", name="Ruleta rusa", emoji="🎲", rarity=3, cat=D, player_only=True, effect="ruleta_rusa",
      params={"delay": 3.0, "pull_time": 0.32, "boss_pct": 0.35},
      desc="Una vez por combate saca un revólver con 1 bala y 6 recámaras y aprieta el gatillo alternando: a sí mismo, al enemigo más peligroso, a sí mismo… Si la bala sale contra el enemigo, lo mata en el acto (a un jefe le quita el 35 % de su vida máxima). Si sale contra él… mala suerte."),
 dict(id="bala_rebote", name="Bala de rebote", emoji="🎱", rarity=1, cat=D, needs="bullets", effect="bala_rebote",
      params={"chance": 0.1, "radius": 170.0, "damage": 1.0},
      desc="Cada impacto de bala tiene un 10 % de probabilidad de rebotar y dar a otro enemigo cercano (hasta 170 px) con el mismo daño."),
 dict(id="gatillo_destino", name="Gatillo del destino", emoji="🎯", rarity=2, cat=D, needs="magazine", effect="gatillo_destino",
      params={"kill_chance": 0.1, "dodge_ignore": 0.5},
      desc="Cuando le queda la última bala del cargador, ese disparo acierta seguro, ignora la mitad de la evasión del blanco y tiene un 10 % de matarlo al instante (a un jefe le hace ×3 de daño)."),
 dict(id="cadena_polvora", name="Cadena de pólvora", emoji="🧨", rarity=2, cat=D, effect="cadena_polvora",
      params={"delay": 0.6, "radius": 75.0, "base": 18.0, "hp_pct": 0.12, "cap": 70.0},
      desc="Cuando mata a un enemigo, el cuerpo explota 0,6 s después: 18 de daño más el 12 % de la vida máxima del caído (máx. 70) en radio 75. Si la explosión mata a otro, ese también explota: reacción en cadena."),
 dict(id="todo_al_rojo", name="Todo al rojo", emoji="🔥", rarity=1, cat=D, effect="todo_al_rojo",
      params={"per_hit": 6.0},
      desc="Cada disparo que acierta seguido suma +6 de daño al siguiente, sin límite, durante todo el combate. Un solo fallo y pierde toda la racha."),
 dict(id="deuda_sangre", name="Deuda de sangre", emoji="🩸", rarity=3, cat=D, player_only=True, effect="deuda_sangre",
      params={"duration": 10.0, "punch_damage": 6.0, "punch_rate": 1.2, "hp_pct": 0.5},
      desc="Si un enemigo mata a un aliado, queda en deuda. Cuando ese enemigo muere, se levanta de tu lado y pelea 10 s a puñetazos contra sus antiguos compañeros. Mientras este soldado siga vivo, el resucitado no puede caer."),
 # ---------------------------------------------------------------- □ TANQUE / VIDA
 dict(id="ni_muerto", name="Ni muerto me ganas", emoji="💀", rarity=2, cat=T, effect="ni_muerto",
      params={"delay": 5.0, "boss_pct": 0.5},
      desc="Si un enemigo lo mata, ese enemigo queda condenado y muere 5 s después. Si es un jefe, pierde la mitad de la vida que le quede."),
 dict(id="venganza", name="Venganza", emoji="😡", rarity=1, cat=T, effect="venganza_tiro",
      params={"damage_pct": 0.5, "hp_gain": 5.0, "hp_cap": 50.0},
      desc="Cuando cae un aliado, dispara al instante contra quien lo mató (+50 de daño). Si acierta, gana +5 de vida máxima para siempre (máx. +50)."),
 dict(id="imaginate_yo", name="¿Bueno con esa arma? Imagínate yo", emoji="😏", rarity=0, cat=T, effect="imaginate_yo",
      params={"hp_gain": 3.0},
      desc="Si un enemigo le ataca con su misma arma, gana +3 de vida máxima para siempre (una vez por combate)."),
 dict(id="carne_canon", name="Carne de cañón", emoji="🛡️", rarity=1, cat=T, effect="carne_canon",
      params={"share": 0.3},
      desc="Al empezar el combate se une al aliado con menos vida máxima. Mientras los dos sigan en pie, recibe el 30 % del daño que iba a recibir su protegido."),
 dict(id="ojo_por_ojo", name="Ojo por ojo", emoji="💢", rarity=1, cat=T, effect="ojo_por_ojo",
      params={"window": 3.0, "heal": 0.5},
      desc="Tras el primer golpe que recibe, guarda el daño de los 3 s siguientes (se ve en la barra de vida). Si mata a un enemigo, recupera el 50 % de lo guardado."),
 dict(id="te_llevas_parte", name="Te llevas parte de mí", emoji="💚", rarity=1, cat=T, effect="te_llevas_parte",
      params={"pct": 0.4, "overkill_cap": 0.4},
      desc="Al caer, reparte el 40 % de su vida máxima como curación entre los aliados vivos, más el daño que sobró del golpe que lo mató (hasta otro 40 %)."),
 dict(id="problema_matarme", name="El problema es matarme", emoji="🧱", rarity=1, cat=T, effect="problema_matarme",
      params={"per_stack": 4.0, "cap": 40.0},
      desc="Cada vez que un enemigo le hace daño sin matarlo, ese enemigo le hace 4 menos de daño (de cada 100) el resto del combate, hasta −40."),
 # ---------------------------------------------------------------- S MOVILIDAD / ESQUIVA
 dict(id="ultimo_en_pie", name="Último en pie", emoji="🗿", rarity=2, cat=M, effect="ultimo_en_pie",
      params={"damage_pct": 0.4},
      desc="+40 de daño si es la última tropa viva de su equipo."),
 dict(id="esquiva", name="Esquive", emoji="💨", rarity=1, cat=M, effect="esquive", mods={"dodge": 10.0},
      params={"per_dodge": 10.0, "cap": 30.0},
      desc="+10 de evasión. Cada ataque que esquiva le da otros +10, hasta +40 en total. Lo ganado se pierde al acabar el combate."),
 dict(id="no_me_pillas", name="No me pillas dos veces", emoji="🙅", rarity=1, cat=M, effect="no_me_pillas",
      params={"per_hit": 5.0, "cap": 30.0},
      desc="Cada vez que un enemigo le acierta, gana +5 de evasión solo contra ese enemigo durante el combate (máx. +30)."),
 dict(id="cambio_sitio", name="Cambio de sitio", emoji="🔀", rarity=2, cat=M, effect="cambio_sitio",
      params={"share": 0.5},
      desc="La primera vez en cada combate que un golpe iba a matarlo, se cambia de sitio con el aliado vivo más cercano. El golpe sigue hacia donde estaba y el aliado se lleva la mitad."),
 dict(id="panico_util", name="Pánico útil", emoji="😱", rarity=1, cat=M, effect="panico_util",
      params={"threshold": 0.2, "duration": 3.5, "dodge": 35.0, "accuracy": -12.0, "speed": 25.0},
      desc="Una vez por combate, al bajar del 20 % de vida entra en pánico 3,5 s: corre en zigzag sin dejar de disparar, con +35 de evasión y +25 de movilidad pero −12 de precisión."),
 dict(id="paso_fantasma", name="Paso fantasma", emoji="👻", rarity=2, cat=M, effect="paso_fantasma", mods={"dodge": 8.0},
      params={"dodges": 3.0, "vanish": 1.0},
      desc="+8 de evasión. Cada 3 ataques esquivados desaparece 1 s y reaparece cerca: los enemigos que le apuntaban pierden el objetivo."),
 # ---------------------------------------------------------------- ○ TRAMPAS / SIGILO / MUNICIÓN
 dict(id="doble_recarga", name="Doble tirada de recarga", emoji="🎲", rarity=1, cat=U, needs="magazine", effect="doble_recarga",
      params={"min": 0.6, "max": 1.2},
      desc="Cada recarga tira dos veces su duración (entre el 60 % y el 120 % de la normal) y se queda la más rápida. Cargador veloz y Recarga desesperada también tiran dos veces."),
 dict(id="efecto_mariposa", name="Efecto mariposa", emoji="🦋", rarity=2, cat=U, effect="efecto_mariposa",
      params={"health": 30.0, "ammo_pct": 0.25, "invis": 2.0, "rush": 4.0, "rush_value": 40.0},
      desc="Tras la primera baja del combate (de cualquier bando), cada aliado recibe algo al azar: nada, +30 de vida, +25 % de balas en el cargador, 2 s de invisibilidad o 4 s con +40 de movilidad y +40 de evasión."),
 dict(id="cargador_veloz", name="Cargador veloz", emoji="⚡", rarity=1, cat=U, needs="magazine", effect="cargador_veloz",
      params={"chance": 0.35},
      desc="Cada recarga tiene un 35 % de probabilidad de hacerse en 0,1 s."),
 dict(id="trampas", name="Trampas", emoji="🪤", rarity=0, cat=U, effect="trampas",
      params={"w0": 50.0, "w1": 35.0, "w2": 15.0, "damage": 20.0, "root": 2.0},
      desc="Al empezar el combate tira cuántos cepos coloca en tierra de nadie, en su carril: 0 (lo más probable), 1 o 2. El enemigo que pisa uno recibe 20 de daño y se queda clavado 2 s."),
 dict(id="municion_fantasma", name="Munición fantasma", emoji="✨", rarity=1, cat=U, effect="municion_fantasma",
      params={"chance": 0.1, "knife_chance": 0.05},
      desc="Cada disparo tiene un 10 % de probabilidad de no gastar bala. Con cuchillo, en cambio, cada cuchillada tiene un 5 % de ser mortal."),
 dict(id="pildora", name="Píldora roja", emoji="💊", rarity=1, cat=U, effect="pildora",
      params={"duration": 6.0, "speed": 45.0, "dodge": 30.0, "poison_time": 10.0, "poison_pct": 0.3},
      desc="Al empezar el combate se toma una píldora: 6 s con +45 de movilidad y +30 de evasión, pero queda envenenado 10 s y pierde el 30 % de su vida máxima (el veneno nunca le mata)."),
 dict(id="cable_trampa", name="Cable trampa", emoji="🧵", rarity=1, cat=U, effect="cable_trampa",
      params={"stun": 1.5, "downed": 4.0, "lethal": 0.08},
      desc="Al empezar el combate tiende un cable en su carril, en tierra de nadie. El primer enemigo que lo cruza cae al suelo 1,5 s y, durante 4 s, cada bala que recibe tiene un 8 % de ser letal."),
 dict(id="senuelo", name="Señuelo", emoji="🎭", rarity=1, cat=U, player_only=True, effect="senuelo",
      params={"hits": 6.0},
      desc="Al empezar el combate planta un muñeco con su aspecto delante de él. Los enemigos pueden confundirlo con un soldado y dispararle; aguanta 6 impactos."),
 dict(id="hacerse_muerto", name="Hacerse el muerto", emoji="😵", rarity=1, cat=U, effect="hacerse_muerto",
      params={"threshold": 0.1, "chance": 0.6, "duration": 3.0},
      desc="La primera vez que baja del 10 % de vida, tiene un 60 % de probabilidad de tirarse al suelo y hacerse el muerto 3 s: nadie le dispara."),
 dict(id="recarga_desesperada", name="Recarga desesperada", emoji="🎰", rarity=1, cat=U, needs="magazine", effect="recarga_desesperada",
      params={"threshold": 0.25},
      desc="Una vez por combate, si recarga por debajo del 25 % de vida, la recarga es instantánea pero con un número de balas al azar entre 1 y el cargador completo."),
 dict(id="robo_cargador", name="Robo de cargador", emoji="🧲", rarity=1, cat=U, needs="magazine", effect="robo_cargador",
      params={"chance": 0.3, "radius": 220.0, "timeout": 3.0},
      desc="Cuando muere un enemigo a menos de 220 px, tiene un 30 % de probabilidad de correr hasta su cuerpo y robarle el cargador: gana las balas que le quedaban (puede pasarse del cargador)."),
 # ---------------------------------------------------------------- tanda 2 (2026-10-10): 2 por categoría
 dict(id="fondo_cargador", name="Fondo del cargador", emoji="🥫", rarity=1, cat=D, needs="magazine", effect="fondo_cargador",
      params={"damage": 25.0},
      desc="Las balas del último tercio del cargador hacen +25 de daño."),
 dict(id="duelo_sol", name="Duelo al sol", emoji="🤠", rarity=1, cat=D, effect="duelo_sol",
      params={"vs": 30.0, "others": -10.0},
      desc="El primer enemigo que le hace daño se convierte en su rival: le apunta a él, +30 de daño contra él y −10 contra el resto. Si el rival cae, el siguiente que le dé ocupa su lugar."),
 dict(id="segunda_piel", name="Segunda piel", emoji="🫧", rarity=1, cat=T, effect="segunda_piel",
      params={"start": 15.0, "cap": 40.0},
      desc="Empieza cada combate con un escudo de 15 que se gasta antes que la vida. Las curaciones que le sobran con la vida llena se convierten en escudo (máx. 40)."),
 dict(id="trinchera", name="Trinchera", emoji="⛺", rarity=1, cat=T, effect="trinchera",
      params={"every": 1.5, "per_stack": 7.0, "stacks": 3.0},
      desc="Cada 1,5 s que pasa quieto apila un saco terrero: −7 de daño recibido (de cada 100) por saco, hasta 3. En cuanto se mueve, los pierde."),
 dict(id="inercia", name="Inercia", emoji="🏃", rarity=1, cat=M, effect="inercia",
      params={"gain": 10.0, "decay": 15.0, "cap": 25.0},
      desc="Mientras se mueve gana +10 de evasión por segundo, hasta +25. Al pararse la va perdiendo poco a poco."),
 dict(id="retirada_tactica", name="Retirada táctica", emoji="↩️", rarity=1, cat=M, needs="magazine", effect="retirada_tactica",
      params={"jump": 70.0, "dodge": 25.0},
      desc="Cuando vacía el cargador, salta hacia atrás alejándose del enemigo más cercano y recarga con +25 de evasión."),
 dict(id="balas_trazadoras", name="Balas trazadoras", emoji="🔴", rarity=1, cat=U, needs="bullets", effect="trazadoras",
      params={"every": 4.0, "mark": 2.5, "bonus": 10.0},
      desc="Una de cada 4 balas es trazadora: si acierta, marca al blanco 2,5 s y recibe +10 de daño de todos."),
 dict(id="cebo_explosivo", name="Cebo explosivo", emoji="🎁", rarity=1, cat=U, needs="magazine", effect="cebo_explosivo",
      params={"count": 2.0, "damage": 25.0, "radius": 60.0},
      desc="Las 2 primeras veces que recarga en cada combate deja a sus pies una mina de proximidad (25 de daño en radio 60)."),
]

def val(v):
    if isinstance(v, bool): return "true" if v else "false"
    if isinstance(v, (int, float)): return repr(float(v))
    return json.dumps(v, ensure_ascii=False)

def dct(d):
    return "{" + ", ".join('%s: %s' % (json.dumps(k), val(v)) for k, v in d.items()) + "}"

os.makedirs("Resources/Skills", exist_ok=True)
for s in SKILLS:
    lines = ['[gd_resource type="Resource" script_class="SkillData" format=3]', "",
             '[ext_resource type="Script" path="res://Scripts/Resources/skill_data.gd" id="1_script"]', "",
             "[resource]", 'script = ExtResource("1_script")',
             "id = %s" % json.dumps(s["id"]), "display_name = %s" % json.dumps(s["name"], ensure_ascii=False),
             "description = %s" % json.dumps(s["desc"], ensure_ascii=False),
             "emoji = %s" % json.dumps(s["emoji"], ensure_ascii=False),
             "rarity = %d" % s["rarity"], "category = %d" % s["cat"]]
    if s.get("player_only"): lines.append("player_only = true")
    if s.get("needs"): lines.append("needs = %s" % json.dumps(s["needs"]))
    if s.get("mods"): lines.append("modifiers = " + dct(s["mods"]))
    if s.get("effect"): lines.append("effect_id = %s" % json.dumps(s["effect"]))
    if s.get("params"): lines.append("params = " + dct(s["params"]))
    open("Resources/Skills/%s.tres" % s["id"], "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
print("\n".join('\tpreload("res://Resources/Skills/%s.tres"),' % s["id"] for s in SKILLS))

# Generador de contenido .tres (nucleo). Ejecutar desde la raíz del proyecto.
import os, json
ROOT = os.path.expanduser("~/mnt/tropas-en-miniatura")

def fmt(v):
    if isinstance(v, bool): return "true" if v else "false"
    if isinstance(v, int): return str(v)
    if isinstance(v, float): return repr(float(v))
    if isinstance(v, str): return json.dumps(v, ensure_ascii=False)
    if isinstance(v, dict):
        return "{" + ", ".join(f"{json.dumps(k)}: {fmt(float(x) if isinstance(x,int) and not isinstance(x,bool) else x)}" for k, x in v.items()) + "}"
    if isinstance(v, tuple) and v[0] == "color":
        return "Color(%s, %s, %s, 1)" % v[1:]
    if isinstance(v, tuple) and v[0] == "arr_int":
        return "Array[int]([" + ", ".join(str(x) for x in v[1]) + "])"
    if isinstance(v, tuple) and v[0] == "arr_str":
        return "Array[String]([" + ", ".join(json.dumps(x, ensure_ascii=False) for x in v[1]) + "])"
    raise ValueError(v)

def write(folder, cls, script, props):
    path = os.path.join(ROOT, "Resources", folder, props["id"] + ".tres")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    lines = [f'[gd_resource type="Resource" script_class="{cls}" format=3]', "",
             f'[ext_resource type="Script" path="res://Scripts/Resources/{script}" id="1_script"]', "",
             "[resource]", 'script = ExtResource("1_script")']
    for k, v in props.items():
        if isinstance(v, dict) and not v: continue
        lines.append(f"{k} = {fmt(v)}")
    open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
    return path

# Family: PISTOLA0 AUTOMATICA1 ESCOPETA2 PRECISION3 PESADA4 EXPLOSIVO5 CUERPO6
# Projectile: BALA0 GRANADA1 COHETE2 LLAMA3 NINGUNO4
W = [
 dict(id="pistola", display_name="Pistola", emoji="🔫", family=0, rarity=0,
      description="Floja pero fiable. Recarga muy rápido.",
      damage=9.0, fire_rate=1.6, attack_range=200.0, accuracy=0.85, optimal_range=140.0, accuracy_falloff=0.10,
      magazine=12, reload_time=1.0, crit_chance=0.05, crit_multiplier=1.8, projectile_speed=700.0, recruit_pool=True, min_round=1),
 dict(id="subfusil", display_name="Subfusil", emoji="💨", family=1, rarity=0,
      description="Mucha cadencia, poca precisión de lejos.",
      damage=4.0, fire_rate=4.5, attack_range=190.0, accuracy=0.72, optimal_range=100.0, accuracy_falloff=0.18,
      magazine=30, reload_time=1.8, crit_chance=0.03, crit_multiplier=1.6, projectile_speed=700.0, recruit_pool=True, min_round=1),
 dict(id="fusil_asalto", display_name="Fusil de asalto", emoji="⚔️", family=1, rarity=0,
      description="Equilibrado a media distancia.",
      damage=7.0, fire_rate=2.2, attack_range=260.0, accuracy=0.80, optimal_range=180.0, accuracy_falloff=0.10,
      magazine=24, reload_time=2.0, crit_chance=0.05, crit_multiplier=1.8, projectile_speed=750.0, recruit_pool=True, min_round=1),
 dict(id="escopeta", display_name="Escopeta", emoji="💥", family=2, rarity=0,
      description="5 perdigones. Devastadora de cerca, inútil de lejos.",
      damage=4.5, fire_rate=0.75, attack_range=140.0, accuracy=0.75, optimal_range=70.0, accuracy_falloff=0.35,
      magazine=6, reload_time=2.2, crit_chance=0.05, crit_multiplier=1.5, pellets=5, projectile_speed=650.0, recruit_pool=True, min_round=1),
 dict(id="cuchillo", display_name="Cuchillo", emoji="🔪", family=6, rarity=0,
      description="Cuerpo a cuerpo. No recarga y es muy certero, pero hay que llegar.",
      damage=11.0, fire_rate=1.4, attack_range=45.0, accuracy=0.95, optimal_range=45.0, accuracy_falloff=0.0,
      magazine=0, reload_time=0.0, crit_chance=0.15, crit_multiplier=2.0, projectile=4, projectile_speed=0.0, min_round=1),
 dict(id="rifle_francotirador", display_name="Rifle de francotirador", emoji="🎯", family=3, rarity=1,
      description="Daño alto y alcance muy largo. Lento.",
      damage=45.0, fire_rate=0.4, attack_range=480.0, accuracy=0.95, optimal_range=400.0, accuracy_falloff=0.05,
      magazine=5, reload_time=2.5, crit_chance=0.15, crit_multiplier=2.0, projectile_speed=1100.0, min_round=3),
 dict(id="ametralladora", display_name="Ametralladora", emoji="🔗", family=4, rarity=1,
      description="Cargador de 40. Tarda 4 s en recargar.",
      damage=6.0, fire_rate=4.0, attack_range=270.0, accuracy=0.70, optimal_range=170.0, accuracy_falloff=0.12,
      magazine=40, reload_time=4.0, crit_chance=0.03, crit_multiplier=1.6, projectile_speed=750.0, min_round=3),
 dict(id="lanzagranadas", display_name="Lanzagranadas", emoji="🧨", family=5, rarity=1,
      description="Granadas con explosión de radio 70.",
      damage=25.0, fire_rate=0.6, attack_range=300.0, accuracy=0.75, optimal_range=220.0, accuracy_falloff=0.10,
      magazine=4, reload_time=2.5, crit_chance=0.0, crit_multiplier=1.5, aoe_radius=70.0, projectile=1, projectile_speed=380.0, min_round=4),
 dict(id="lanzallamas", display_name="Lanzallamas", emoji="🔥", family=4, rarity=1,
      description="Chorro corto que quema: 4 de daño/s durante 3 s.",
      damage=3.0, fire_rate=6.0, attack_range=140.0, accuracy=0.90, optimal_range=120.0, accuracy_falloff=0.30,
      magazine=50, reload_time=3.0, crit_chance=0.0, crit_multiplier=1.5, burn_dps=4.0, burn_duration=3.0, projectile=3, projectile_speed=420.0, min_round=4),
 dict(id="bazuca", display_name="Bazuca", emoji="🚀", family=5, rarity=2,
      description="Un cohete por recarga. Daño enorme en radio 90.",
      damage=80.0, fire_rate=0.5, attack_range=340.0, accuracy=0.70, optimal_range=260.0, accuracy_falloff=0.10,
      magazine=1, reload_time=3.5, crit_chance=0.0, crit_multiplier=1.5, aoe_radius=90.0, projectile=2, projectile_speed=450.0, min_round=6),
]

S = [
 dict(id="soldado", display_name="Soldado", emoji="🎖️", color=("color",0.45,0.85,0.45), affine_families=("arr_int",[1,2]),
      description="Infantería versátil. Afín a automáticas y escopetas.",
      passive_name="Disciplina", passive_description="+10 % de cadencia.", modifiers={"fire_rate_pct":0.10}),
 dict(id="francotirador", display_name="Francotirador", emoji="🎯", color=("color",0.55,0.75,1.0), affine_families=("arr_int",[3]),
      description="Tirador de élite a larga distancia. Afín a armas de precisión.",
      passive_name="Paciencia", passive_description="Tras 1 s quieto: +15 % de precisión y +10 % de crítico.",
      passive_effect_id="paciencia", passive_params={"still_time":1.0,"accuracy":0.15,"crit_chance":0.10}),
 dict(id="granadero", display_name="Granadero", emoji="💣", color=("color",1.0,0.6,0.25), affine_families=("arr_int",[5]),
      description="Experto en explosivos. Afín a lanzagranadas y bazucas.",
      passive_name="Experto en demoliciones", passive_description="+25 % de radio de explosión.", modifiers={"aoe_pct":0.25}),
 dict(id="medico", display_name="Médico", emoji="🩺", color=("color",0.95,0.45,0.5), affine_families=("arr_int",[0]),
      description="Mantiene vivo al equipo. Afín a pistolas.",
      passive_name="Primeros auxilios", passive_description="Cada 4 s cura un 6 % de su vida máx. al aliado más herido a 220 px o menos.",
      passive_effect_id="primeros_auxilios", passive_params={"interval":4.0,"heal_pct":0.06,"radius":220.0}),
 dict(id="municionero", display_name="Municionero", emoji="🧰", color=("color",0.95,0.85,0.3), affine_families=("arr_int",[4]),
      description="Fuego sostenido. Afín a armas pesadas.",
      passive_name="Suministros", passive_description="+50 % de cargador y recarga un 25 % más rápida.", modifiers={"magazine_pct":0.5,"reload_pct":-0.25}),
]

def sk(id, name, emoji, rarity, desc, mods=None, spec="", requires=None, stackable=False, effect="", params=None):
    d = dict(id=id, display_name=name, description=desc, emoji=emoji, rarity=rarity, specialty_id=spec)
    if requires: d["requires"] = ("arr_str", requires)
    if stackable: d["stackable"] = True
    d["modifiers"] = mods or {}
    if effect: d["effect_id"] = effect
    d["params"] = params or {}
    return d

K = [
 sk("comando","Comando","💪",0,"+15 de vida. Acumulable.",{"health_flat":15},stackable=True),
 sk("piel_dura","Piel dura","🦏",0,"+12 % de vida máxima.",{"health_pct":0.12}),
 sk("pulso_firme","Pulso firme","✋",0,"+8 % de precisión.",{"accuracy":0.08}),
 sk("ojo_certero","Ojo certero","👁️",0,"+8 % de probabilidad de crítico.",{"crit_chance":0.08}),
 sk("velocista","Velocista","👟",0,"+20 % de velocidad de movimiento.",{"move_speed_pct":0.20}),
 sk("esquiva","Esquiva","💨",1,"+12 % de probabilidad de esquivar un impacto.",{"dodge":0.12}),
 sk("gatillo_facil","Gatillo fácil","⚡",0,"+15 % de cadencia, −5 % de precisión.",{"fire_rate_pct":0.15,"accuracy":-0.05}),
 sk("recarga_rapida","Recarga rápida","🔄",0,"Recarga un 25 % más rápido.",{"reload_pct":-0.25}),
 sk("camuflaje","Camuflaje","🌿",1,"Los enemigos no le apuntan durante los 3 primeros segundos.",effect="camuflaje",params={"duration":3.0}),
 sk("ultimo_en_pie","Último en pie","🗿",2,"+40 % de daño si es la última tropa viva de su equipo.",effect="ultimo_en_pie",params={"damage_pct":0.40}),
 sk("venganza","Venganza","😡",1,"+30 % de cadencia durante 4 s cuando cae un aliado.",effect="venganza",params={"fire_rate_pct":0.30,"duration":4.0}),
 sk("sangre_fria","Sangre fría","🧊",1,"+0,25 al multiplicador de crítico. Requiere Ojo certero.",{"crit_mult":0.25},requires=["ojo_certero"]),
 # Soldado
 sk("cargador_ampliado","Cargador ampliado","📦",0,"+40 % de cargador.",{"magazine_pct":0.40},spec="soldado"),
 sk("oficial","Oficial","🎖️",2,"Aura: +15 % de cadencia a los aliados a 180 px o menos.",spec="soldado",effect="oficial",params={"radius":180.0,"fire_rate_pct":0.15}),
 sk("instinto_veterano","Instinto veterano","🧠",1,"+10 % de probabilidad de crítico.",{"crit_chance":0.10},spec="soldado"),
 # Francotirador
 sk("mira_laser","Mira láser","🔴",1,"+10 % de crítico y +10 % de precisión.",{"crit_chance":0.10,"accuracy":0.10},spec="francotirador"),
 sk("bala_perforante","Bala perforante","🏹",1,"Sus balas atraviesan a 1 enemigo más.",{"pierce":1},spec="francotirador"),
 sk("traje_ghillie","Traje ghillie","🍃",1,"Los enemigos no le apuntan durante los 6 primeros segundos.",spec="francotirador",effect="camuflaje",params={"duration":6.0}),
 # Granadero
 sk("carga_extra","Carga extra","🧨",0,"+20 % de daño.",{"damage_pct":0.20},spec="granadero"),
 sk("termobarica","Termobárica","🔥",1,"Sus impactos queman: 4 de daño/s durante 3 s.",{"burn_dps":4},spec="granadero"),
 sk("blindaje_granadero","Blindaje de asalto","🦺",1,"+20 % de vida y −10 % de daño recibido.",{"health_pct":0.20,"armor":0.10},spec="granadero"),
 # Médico
 sk("cirujano","Cirujano","⚕️",1,"Sus curaciones curan un 50 % más.",{"heal_pct":0.50},spec="medico"),
 sk("autocuracion","Autocuración","💚",1,"Se cura un 2 % de su vida máx. por segundo.",spec="medico",effect="autocuracion",params={"pct_per_sec":0.02}),
 # Municionero
 sk("cinta_municion","Cinta de munición","🎗️",0,"+20 % de cadencia.",{"fire_rate_pct":0.20},spec="municionero"),
 sk("balas_trazadoras","Balas trazadoras","✨",0,"+10 % de precisión y +10 % de alcance.",{"accuracy":0.10,"range_pct":0.10},spec="municionero"),
]

def it(id, name, emoji, rarity, slot, desc, mods=None, effect="", params=None):
    d = dict(id=id, display_name=name, description=desc, emoji=emoji, rarity=rarity, slot=slot, modifiers=mods or {})
    if effect: d["effect_id"] = effect
    d["params"] = params or {}
    return d
# Slot: MUNICION0 ARMADURA1 UTILIDAD2
I = [
 it("balas_huecas","Balas de punta hueca","🩸",0,0,"+15 % de daño.",{"damage_pct":0.15}),
 it("balas_incendiarias","Balas incendiarias","🔥",1,0,"Los impactos queman: 5 de daño/s durante 3 s.",{"burn_dps":5}),
 it("balas_perforantes","Balas perforantes","🔩",1,0,"Las balas atraviesan a 1 enemigo más.",{"pierce":1}),
 it("chaleco_tactico","Chaleco táctico","🦺",0,1,"+25 de vida, −5 % de movimiento.",{"health_flat":25,"move_speed_pct":-0.05}),
 it("blindaje_pesado","Blindaje pesado","🛡️",1,1,"−20 % de daño recibido, −15 % de movimiento.",{"armor":0.20,"move_speed_pct":-0.15}),
 it("granada","Granada","💣",1,2,"Cada 6 s lanza una granada: 30 de daño en radio 70.",effect="granada",params={"cooldown":6.0,"damage":30.0,"radius":70.0}),
 it("botiquin","Botiquín","🩹",0,2,"Una vez por combate, por debajo del 40 % de vida, se cura un 35 %.",effect="botiquin",params={"threshold":0.40,"heal_pct":0.35}),
 it("inyector_adrenalina","Inyector de adrenalina","💉",1,2,"Al empezar el combate: +40 % de cadencia durante 5 s.",effect="adrenalina",params={"fire_rate_pct":0.40,"duration":5.0}),
 it("mira_telescopica","Mira telescópica","🔭",0,2,"+15 % de alcance y +8 % de precisión.",{"range_pct":0.15,"accuracy":0.08}),
]

out = {"weapons":[], "specialties":[], "skills":[], "items":[]}
for d in W: write("Weapons","WeaponData","weapon_data.gd",d); out["weapons"].append(d["id"])
for d in S: write("Specialties","SpecialtyData","specialty_data.gd",d); out["specialties"].append(d["id"])
for d in K: write("Skills","SkillData","skill_data.gd",d); out["skills"].append(d["id"])
for d in I: write("Items","ItemData","item_data.gd",d); out["items"].append(d["id"])

# GameContent con preload explícitos
def block(name, folder, ids):
    return f"const _{name.upper()} := [\n" + "".join(f'\tpreload("res://Resources/{folder}/{i}.tres"),\n' for i in ids) + "]\n"
gc = '''class_name GameContent
extends RefCounted
## Catálogo explícito de todo el contenido (preload, sin escanear carpetas).
## Generado por el agente nucleo: si añades un .tres, añádelo también aquí.

''' + block("weapons","Weapons",out["weapons"]) + "\n" + block("specialties","Specialties",out["specialties"]) + "\n" + block("skills","Skills",out["skills"]) + "\n" + block("items","Items",out["items"]) + '''

static func weapons() -> Array[WeaponData]:
	var a: Array[WeaponData] = []
	a.assign(_WEAPONS)
	return a


static func specialties() -> Array[SpecialtyData]:
	var a: Array[SpecialtyData] = []
	a.assign(_SPECIALTIES)
	return a


static func skills() -> Array[SkillData]:
	var a: Array[SkillData] = []
	a.assign(_SKILLS)
	return a


static func items() -> Array[ItemData]:
	var a: Array[ItemData] = []
	a.assign(_ITEMS)
	return a


static func _find(list: Array, id: String) -> Resource:
	for r in list:
		if r and r.id == id:
			return r
	return null


static func find_weapon(id: String) -> WeaponData:
	return _find(_WEAPONS, id) as WeaponData


static func find_specialty(id: String) -> SpecialtyData:
	return _find(_SPECIALTIES, id) as SpecialtyData


static func find_skill(id: String) -> SkillData:
	return _find(_SKILLS, id) as SkillData


static func find_item(id: String) -> ItemData:
	return _find(_ITEMS, id) as ItemData
'''
open(os.path.join(ROOT,"Scripts/Systems/game_content.gd"),"w",encoding="utf-8",newline="\n").write(gc)
print(json.dumps(out))
for d in W:
    dmg=d["damage"]*d.get("pellets",1); fr=d["fire_rate"]; mag=d["magazine"]
    sus = dmg*fr if mag==0 else dmg*mag/(mag/fr+d["reload_time"])
    print(d["id"], d["rarity"], "raw %.1f sus %.1f eff %.1f" % (dmg*fr, sus, sus*d["accuracy"]))

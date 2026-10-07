# API del núcleo (hecho y verificado: test_core 0 fallos)

## Recursos
- WeaponData: campos de la SPEC + FAMILY_NAMES, get_family_name().
- SpecialtyData: campos de la SPEC + passive_params: Dictionary, is_affine(weapon).
- SkillData: los de la SPEC.
- ItemData: enum Slot {MUNICION, ARMADURA, UTILIDAD}; id, display_name, description, emoji, rarity, icon, slot, modifiers, effect_id, params; SLOT_NAMES, get_slot_name().
- TroopCard:
  - Constantes MAX_ITEM_SLOTS=3, MAX_LEVEL=10, SPECIALTY_LEVEL=2.
  - Campos: unit_name, base_health, base_damage, level, specialty, weapons, equipped_weapon, items, skills, pending_offers, is_boss.
  - display_name (getter).
  - get_weapon(), get_specialty_name() ("Recluta" si no hay especialidad), get_title().
  - has_skill(id), has_item(id), has_weapon(id).
  - can_add_item(item); add_item(item) (no toca la reserva); remove_item(item) (devuelve el objeto a la reserva vía GSM.add_item).
  - get_level_up_cost() = level*30; can_level_up(); duplicate_card().

## Sistemas (estáticos)
- TroopStats:
  - compute(card) -> Dictionary con todas las claves de la SPEC + heal_mult, weapon (WeaponData), modifiers, hit_damage, dps.
  - describe(card) -> Array[String]; describe_modifiers(mods) -> String ("+15 de vida, +10 % de cadencia").
  - collect_modifiers(card), has_affinity(card, weapon=null), estimate_dps(stats).
- LevelUpSystem:
  - roll_offers(card, rng=null, round_limit=0) -> [{type: "specialty"|"skill"|"item"|"weapon", resource}].
  - begin_level_up(card, rng=null) -> bool: cobra oro, rellena pending_offers y emite EventBus.level_up_offers_ready(card).
  - choose(card, index, equip_weapon=false): aplica, level+=1, vacía pending_offers y emite roster_changed + troop_leveled(card).
  - apply_offer(card, offer, equip_weapon=false); candidates(...); rarity_weight(r); weighted_index(...).
- UnitFactory:
  - make_recruit(rng=null) -> TroopCard; recruit_price(card) -> int (40–70).
  - make_enemy(round_num, is_elite=false, is_boss_leader=false, rng=null) -> TroopCard (nuevo cada vez; nivel 1+ronda/3, élite +1, jefe +2, tope 10; jefe con is_boss=true).
	- NO aplica ×3.5/×2 del jefe ni difficulty_for: eso lo hace combate.
  - enemy_level(...), random_name(rng), recruit_weapons().
- GameContent: weapons(), specialties(), skills(), items(); find_weapon/find_skill/find_item/find_specialty(id) (null si no existe).

## GameStateManager
- player_bench mezcla TroopCard e ItemData (distinguir con `is TroopCard` / `is ItemData`).
- deployed_troops_data = [{card, position}]; shop_offers: Array (se limpia en advance_stage y reset_run).
- recruit_troop(card, price) -> bool; add_troop_to_army(card).
- return_troop_to_bench(troop): guarda troop.card. save_deployed_troops(troops): guarda {card, position}.
- get_bench_cards() -> Array[TroopCard]; get_bench_items() -> Array[ItemData].
- equip_item_from_bench(card, item) -> bool; get_army_size().
- Ya no existe _make_card.

## EventBus
- Señales nuevas: level_up_offers_ready(card), troop_leveled(card).

## Contenido (ids)
- Armas: pistola, subfusil, fusil_asalto, escopeta (las 4 de recluta), cuchillo, rifle_francotirador, ametralladora, lanzagranadas, lanzallamas, bazuca.
  - Emojis: 🔫 💨 🪖 💥 🔪 🎯 ⛓️ 🧨 🔥 🚀.
- Especialidades:
  - soldado: fire_rate_pct 0.10.
  - francotirador: efecto paciencia {still_time 1.0, accuracy 0.15, crit_chance 0.10}.
  - granadero: aoe_pct 0.25.
  - medico: efecto primeros_auxilios {interval 4.0, heal_pct 0.06, radius 220}.
  - municionero: magazine_pct 0.5, reload_pct -0.25.
- Efectos que debe implementar effects.gd (con sus params):
  - Especialidad: paciencia, primeros_auxilios.
  - Habilidad camuflaje {duration 3}; traje_ghillie usa el efecto camuflaje {duration 6} (si tiene las dos, usar la duración mayor).
  - ultimo_en_pie {damage_pct 0.4}; venganza {fire_rate_pct 0.3, duration 4}; oficial {radius 180, fire_rate_pct 0.15}; autocuracion {pct_per_sec 0.02}.
  - Objetos: granada {cooldown 6, damage 30, radius 70}; botiquin {threshold 0.4, heal_pct 0.35}; adrenalina {fire_rate_pct 0.4, duration 5}.
  - heal_mult (de stats) multiplica las curaciones que hace la tropa.
  - pierce puede sumar 2.
- Habilidades: comando (acumulable), piel_dura, pulso_firme, ojo_certero, velocista, esquiva, gatillo_facil, recarga_rapida, sangre_fria (requiere ojo_certero), camuflaje, ultimo_en_pie, venganza, cargador_ampliado, oficial, instinto_veterano, mira_laser, bala_perforante, traje_ghillie, carga_extra, termobarica, blindaje_granadero, cirujano, autocuracion, cinta_municion, balas_trazadoras.
- Objetos: balas_huecas, balas_incendiarias, balas_perforantes (MUNICION); chaleco_tactico, blindaje_pesado (ARMADURA); granada, botiquin, inyector_adrenalina, mira_telescopica (UTILIDAD).

## Pendiente de otros
- troop.gd, battle.gd y _dev/dev_boot.gd usan TroopData/troop_data (no cargan).
- map.gd:75 y troop_roster_ui.gd:104 usan "troop_data" in res.
- recruit_shop.gd debe usar recruit_troop(card, UnitFactory.recruit_price(card)).
- reward_screen.gd precarga los Resources/Troops/*.tres (legado).
- Equipar un arma = card.equipped_weapon = i.
- Generador de contenido: _dev/gen_content_nucleo.py.

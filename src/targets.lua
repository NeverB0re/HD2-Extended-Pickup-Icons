-- 0.23.0: names not in the game's files (filediver listing, 2026-10-24) taken out.
-- Generated from Extended Pickup Icons 3.0 (pickup_icon_range_test): the units it extended, without
-- equipment and weapons (0.9.0). key: the unit resource name when known, otherwise its 64-bit id as hex.
-- icon: drawn as this shape (samples, supplies); the rest as diamonds (vehicles: chevrons).
-- Rare samples are Crystallized E-710, Legendarium and Black Saffron; the super sample is Super Uranium.
-- near: no marker this close to you (the game's own icon shows); default NEAR_ME of the group. Stims
-- have no icon of the game's: 0, always a marker.
-- groups: samples, supplies, mission (objective items), carry (SEAF shells, carried ammo, warheads),
-- dropoffs (where an SSSD or data goes in), controls (valves, cranks, switches), vehicles.
return {
  {group='samples', hex='a9936cbe561e8180', icon='tube', worn=2.5, near=15},  -- the sample container: worn 2.5 m off
  -- its helldiver too (boarding animations swing it away)
  {group='mission', name='content/objectives/obj_illuminate/il_sarcophagus/il_sarcophagus'},  -- 0.23: its real path
  {group='samples', name='content/env_super_earth/samples/research_tech_sample_01', icon='common'},
  {group='samples', name='content/env_shared/assets/samples/bio_sample_01/bio_sample_01', icon='common'},
  {group='samples', name='content/env_cyborg/samples/automaton_super_sample_01', icon='super', near=20},
  {group='supplies', name='content/fac_helldivers/discoverables/ammo_box_discoverable_01/ammo_box_discoverable_01', icon='ammo'},
  {group='samples', name='content/env_bugs/assets/samples/bug_egg_super_sample_01', icon='egg', near=20},
  {group='samples', name='content/env_super_earth/samples/research_bio_sample_01', icon='common'},
  {group='mission', name='content/objectives/obj_common/black_box/black_box_01', icon='package'},
  {group='samples', name='content/env_cyborg/samples/automaton_enemy_sample_01', icon='rare'},
  {group='samples', name='content/env_shared_forest/assets/samples/plant_sample_01', icon='common'},
  {group='samples', name='content/env_bugs/assets/samples/bug_sample_01', icon='common'},
  {group='samples', name='content/env_super_earth/samples/se_intel_sample_01', icon='common'},
  {group='supplies', name='content/fac_helldivers/hellpod/health_pack_rack/health_pack', icon='stim', near=0},
  {group='samples', name='content/env_shared_desert/assets/samples/mineral_sample_01', icon='common'},
  {group='mission', name='content/objectives/obj_common/carry_data/carry_data', icon='package'},
  {group='mission', name='content/objectives/obj_bugs/retrieve_larva/bug_larva_container_backpack', icon='larva'},
  {group='samples', name='content/env_shared/assets/samples/crystalized_e710_sample_01/crystalized_e710_sample_01', icon='rare'},
  {group='samples', name='content/env_super_earth/samples/research_artifact_sample_01', icon='common'},
  {group='samples', name='content/env_shared/assets/samples/tech_sample_01/tech_sample_01', icon='common'},
  {group='supplies', name='content/fac_helldivers/discoverables/grenade_box_discoverable_01/grenade_box_discoverable_01', icon='grenade'},
  {group='mission', name='content/objectives/obj_cyborgs/cyborg_carry_data/cy_carry_data', icon='package'},
  {group='mission', name='content/objectives/obj_cyborgs/cyborg_airbase_control_tower/cyborg_carry_data', icon='package'},
  {group='mission', name='content/objectives/obj_common/briefcase/briefcase', icon='package'},
  {group='mission', hex='0dc9084e50c051f3'},  -- unresolved_mission_carryable_0dc9084e50c051f3
  {group='supplies', name='content/fac_helldivers/discoverables/health_pack_discoverable_01/health_pack_discoverable_01', icon='stim', near=0},
  {group='samples', name='content/env_shared/assets/samples/super_uranium/super_uranium_sample_01', icon='super'},
  {group='samples', name='content/env_shared_arctic/assets/samples/crystal_sample_01', icon='common'},
  {group='samples', name='content/env_cyborg/samples/automaton_intel_sample_01', icon='common'},
  {group='samples', name='content/env_shared/assets/samples/artifact_sample_01/artifact_sample_01', icon='common'},
  {group='samples', name='content/env_shared/assets/samples/legendarium_sample_01/legendarium_sample_01', icon='rare'},
  {group='samples', name='content/env_bugs/assets/samples/bug_intel_sample_01', icon='common'},
  {group='supplies', name='content/fac_helldivers/hellpod/ammo_rack/ammo_box', icon='supply'},
  {group='mission', hex='2d3bc1683a54298d'},  -- unresolved_mission_carryable_2d3bc1683a54298d
  {group='carry', name='content/objectives/obj_common/carry_warhead/warhead_01'},
  {group='samples', name='content/env_shared/assets/samples/blacksaffron_sample_01/blacksaffron_sample_01', icon='rare'},
  {group='samples', name='content/env_cyborg/samples/automaton_sample_01', icon='common'},
  {group='samples', name='content/env_super_earth/samples/research_sample_01', icon='common'},
  {group='mission', name='content/objectives/obj_cyborgs/cyborg_chemicals_backpack/cy_chemicals_backpack'},
  {group='samples', name='content/env_bugs/assets/samples/bug_enemy_sample_01', icon='rare'},
  {group='samples', name='content/env_illuminate/samples/illuminate_enemy_sample_01', icon='rare'},
  -- 0.11.0: drop-off points (the SSSD upload and such) and vehicles; terminals out in 0.12.1,
  -- names from filediver's hash list. Mech weapon units sit on the mech: one marker per vehicle.
  {group='dropoffs', name='content/objectives/obj_common/dropoff/dropoff_01'},
  {group='dropoffs', name='content/objectives/obj_cyborgs/cyborg_dropoff/cyborg_dropoff_01'},
  {group='vehicles', name='content/fac_helldivers/vehicles/combat_walker/combat_walker', icon='walker', height=4.8},  -- tall: above it
  {group='vehicles', name='content/fac_helldivers/vehicles/frv/frv', icon='car'},
  {group='vehicles', name='content/fac_helldivers/vehicles/frv_heavy/frv_flamer', icon='car'},
  {group='vehicles', name='content/fac_helldivers/vehicles/frv_supply/frv_supply', icon='car'},
  {group='vehicles', name='content/fac_helldivers/vehicles/tank/tank', icon='tank'},
  {group='vehicles', name='content/fac_helldivers/vehicles/tank_storm/tank_storm', icon='tank'},
  -- 0.18.0: mission controls you work by hand (valves, cranks, switches, buttons), names from filediver's hash list
  {group='controls', name='content/objectives/obj_common/oil_pump/oil_pump_valve'},
  {group='controls', name='content/objectives/obj_common/colony_relay/colony_relay_01/objective_colony_relay_antenna_crank_01'},
  {group='controls', name='content/objectives/obj_super_earth/se_orbital_cannon/objective_city_cannon_crank_01'},
  {group='controls', name='content/objectives/obj_super_earth/se_orbital_cannon/objective_city_cannon_crank_02'},
  -- 0.23.0: the SEAF artillery shells as the game has them (seaf_shell itself is not a unit)
  {group='carry', name='content/objectives/obj_common/seaf_artillery/seaf_shell_regular'},
  {group='carry', name='content/objectives/obj_common/seaf_artillery/seaf_shell_high_yield'},
  {group='carry', name='content/objectives/obj_common/seaf_artillery/seaf_shell_napalm'},
  {group='carry', name='content/objectives/obj_common/seaf_artillery/seaf_shell_smoke'},
  {group='carry', name='content/objectives/obj_common/seaf_artillery/seaf_shell_static_field'},
  {group='carry', name='content/objectives/obj_common/seaf_artillery/seaf_shell_mini_nuke'},
  -- 0.24.0: from the wiki's missions, matched to units in the game's files
  {group='carry', name='content/objectives/obj_cyborgs/cyborg_battery_carry_2h/cy_battery_carry_2h'},  -- Confiscate Assets: fusion battery, two-handed
  {group='dropoffs', name='content/objectives/obj_common/cargo_container/cargo_container'},  -- Confiscate Assets, Rapid Acquisition: loaded here
  {group='controls', name='content/objectives/obj_cyborgs/cyborg_generic_valve/cy_generic_valve'},  -- Sabotage Orgo-Plasma Synthesis
  {group='controls', name='content/objectives/obj_cyborgs/cyborg_cooling_structure/cyborg_cooling_pipe_valve'},  -- Halt Cyborg Production
  {group='controls', name='content/objectives/obj_cyborgs/cyborg_cooling_structure/cyborg_cooling_pipe_valve_horizontal'},  -- Halt Cyborg Production
  {group='mission', name='content/objectives/obj_common/generic_intel/generic_intel', taken=true},  -- Launch ICBM: launch codes (picked up)
  {group='mission', name='content/objectives/obj_cyborgs/cyborg_generic_intel/cy_generic_intel', taken=true},  -- Commando: Extract Intel: keycard
  {group='mission', name='content/objectives/obj_common/shoulder_mounted_camera/shoulder_mounted_camera'},  -- Acquire Evidence, Illuminate Lair: video camera
  -- 0.28.0: not drawn; an exosuit within 4 m of its wreck gets no marker
  {group='wrecks', name='content/fac_helldivers/vehicles/combat_walker_wreck/combat_walker_wreck'},
  -- 0.33.0: not drawn; vehicles' weapons, separate units: a vehicle that had some within 5 m and has none
  -- (0.34: only those that go when it is destroyed: turrets and guns, not the supply rack, fuel tank, silo)
  -- now is taken for destroyed
  {group='arms', name='content/fac_helldivers/vehicles/combat_walker_anti_tank_cannon/combat_walker_anti_tank_cannon'},
  {group='arms', name='content/fac_helldivers/vehicles/combat_walker_autocannon/combat_walker_autocannon_left'},
  {group='arms', name='content/fac_helldivers/vehicles/combat_walker_autocannon/combat_walker_autocannon_right'},
  {group='arms', name='content/fac_helldivers/vehicles/combat_walker_flak_cannon/combat_walker_flak_cannon'},
  {group='arms', name='content/fac_helldivers/vehicles/combat_walker_flamethrower/combat_walker_flamethrower'},
  {group='arms', name='content/fac_helldivers/vehicles/combat_walker_missile/combat_walker_missile'},
  {group='arms', name='content/fac_helldivers/vehicles/combat_walker_missle_launcher/combat_walker_missle_launcher'},
  {group='arms', name='content/fac_helldivers/vehicles/combat_walker_shield/combat_walker_shield'},
  {group='arms', name='content/fac_helldivers/vehicles/combat_walker_turret/combat_walker_turret'},
  {group='arms', name='content/fac_helldivers/vehicles/frv/armaments/frv_mg/frv_mg'},
  {group='arms', name='content/fac_helldivers/vehicles/frv_heavy/armaments/frv_flamethrower/frv_flamethrower'},
  {group='arms', name='content/fac_helldivers/vehicles/tank_storm/armaments/tank_storm_maingun/tank_storm_maingun'},
  -- 2.1.0: terminals (off unless switched on). The SEAF objective terminal has no name in filediver's
  -- hash list: its id, found by its 'computer_terminal_screen_new' material, shared by nine objectives.
  {group='terminals', hex='cd5fb5dc997811bb'},
  {group='terminals', name='content/objectives/obj_cyborgs/cyborg_generic_objective_terminal/cy_objective_terminal'},
  -- 2.1.0: not drawn; where artillery shells are loaded: a shell in one is in it (LOADED_NEAR). Not the
  -- artillery itself: it is large, and shells are left beside it to load later.
  {group='loaders', name='content/objectives/obj_common/fire_artillery/ready_rack'},
  -- 2.1.0: the generator you start in a mission (its lever is on it)
  {group='controls', name='content/objectives/obj_common/generator/generator'},
  -- 2.1.0-test.4 (test builds only): unnamed units always packaged with an objective, small and with no
  -- material: an interaction point or a marker's anchor, maybe where its terminal is. Drawn orange with
  -- their name, to be told apart in the game.
  {group='probe', hex='c05cd3cee446b74e', probe='GEN'},
  {group='probe', hex='2735eb320d253dc1', probe='ICBM1'},
  {group='probe', hex='52eee5fa9a598832', probe='ICBM2'},
  {group='probe', hex='d4aeeaec370db018', probe='ROCKET'},
  {group='probe', hex='13366314b782bb4f', probe='POWER1'},
  {group='probe', hex='3a4ee1211fe417e3', probe='POWER2'},
  {group='probe', hex='26cc56708c9be4c2', probe='RELAY1'},
  {group='probe', hex='6f64cb89a1821c53', probe='RELAY2'},
  {group='probe', hex='a986e7a9a3ea02b1', probe='URAN1'},
  {group='probe', hex='f02f7a50424a39d5', probe='URAN2'},
  {group='probe', hex='f271678d4ef17306', probe='DETECT'},
  {group='probe', hex='c57688b74f06ea7d', probe='BUNKER'},
  {group='probe', hex='cd701143c5f25229', probe='BLOCKER'},
  {group='probe', hex='d7060b0baa25cae3', probe='NETWORK'},
  {group='probe', hex='05935410bfefdf1b', probe='GUNSHIP'},
  {group='probe', hex='1e6a154fb692b73b', probe='TURRETS'},
  {group='probe', hex='2098b8c88da23fdb', probe='AMMO'},
  {group='probe', hex='8f003f91628c9330', probe='TOWER1'},
  {group='probe', hex='faa58981003c5550', probe='TOWER2'},
  {group='probe', hex='fe5574ef3273d0c0', probe='TOWER3'},
  {group='probe', hex='8296a50eda0fd438', probe='TRUTH'},
  {group='probe', hex='975dcf577b2d0ec9', probe='CANNON1'},
  {group='probe', hex='02006d9b4a2e49d2', probe='CANNON2'},
  {group='probe', hex='1eb6a3caa5f6af2b', probe='MONOLITH'},
  {group='probe', hex='0b05f0dff4ced64e', probe='SCRAMBLE'},
  {group='probe', hex='803a4d167a769d41', probe='PORTAL1'},
  {group='probe', hex='c89b5e897cb104c4', probe='PORTAL2'},
  {group='probe', hex='257cb2f184459845', probe='TCS'},
  {group='probe', hex='0f4c5c207a72da91', probe='CORE'},
  {group='probe', hex='c37e0be3dd30a3cb', probe='LUNG'},
  {group='probe', hex='92543a3a839f32dd', probe='FILLING'},
  {group='probe', hex='464f4f90f20f5d50', probe='COOL1'},
  {group='probe', hex='8b2c945cfa9a97c3', probe='COOL2'},
  {group='probe', hex='bab746038c52fc7f', probe='RESOURCE'},
  {group='probe', hex='5b3ca501a1663377', probe='WELL'},
  {group='probe', hex='a80f8becb71cc8d5', probe='INVASION'},
  {group='probe', hex='00cd85f0f1113469', probe='FOOTAGE'},
  {group='probe', hex='e69e779d71002ccb', probe='BRIEFCASE'},
  {group='probe', hex='49594476b1b93274', probe='VALVE1'},
  {group='probe', hex='93c06561518ae030', probe='VALVE2'},
  {group='probe', hex='d59c014c02987bbf', probe='EMBRYO'},
  {group='probe', hex='2ff7f86afb488269', probe='CODES'},
}

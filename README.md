# Radar

Radar adds a compact, camera-oriented HUD radar for **Warhammer 40,000: Darktide**. It is built to surface the targets that matter most during live missions, nearby pickups, objective items, deployed support tools, teammates, and high-priority enemies, while keeping the presentation configurable from the mod options menu.

## Feature Overview

- Tracks nearby pickups, materials, mission items, event items, teammates, and priority enemies on a single radar.
- Projects markers relative to your current facing, so the radar rotates with your view instead of acting like a fixed minimap.
- Supports **square** and **circle** radar frames, plus configurable **outline** and **guide** styles for both shapes.
- Lets you adjust **radar size**, **scan range**, and **maximum marker count**.
- Supports optional **icon scaling with radar size**.
- Supports separate marker styles for **enemies** and **teammates**: **Icon only** or **Marked icon**.
- Includes a **toggle radar on or off** keybind, so you can hide or restore the radar during a mission without opening the options menu.
- Supports configurable **radar positioning** with **Radar position X**, **Radar position Y**, **Steps per input**, and dedicated movement keybinds for nudging the radar **left**, **right**, **up**, or **down**.
- Adds dedicated **Expedition POI** support for numbered **Sites of Interest** opportunity markers, plus dedicated icons for **Deadsider Sanctuaries**, **Data Reliquary Harvesters**, **Main Objective**, **Valkyrie Extraction Zone**, and **Valkyrie Arrival Zone**, with an option to ignore the normal range limit for these markers.
- Keeps the radar position clamped to the visible UI space, so moving or resizing it does not push it off-screen.
- Colors the radar center dot from the local player HUD slot color.
- Uses class icons for teammate markers instead of generic dots.
- Exposes category-based toggles for common pickups, materials, objectives, expeditions items, **Expedition POIs**, deployed items, enemies, teammates, and event items.
- Includes optional **debug logs** and an **unknown pickups** toggle for discovery and troubleshooting.
- Includes a groundwork **highlighting** option, but the actual highlighting behavior is currently still under development.

## In-Game Radar Examples

The screenshots below show both radar styles during an expedition mission. They illustrate the camera-oriented layout, mixed pickup categories, teammate markers, and priority targets in live gameplay.

### Circle Radar

<p>
  <img src="doc/img/circle_radar_1.png" width="31%" alt="Circle radar example 1" />
  <img src="doc/img/circle_radar_2.png" width="31%" alt="Circle radar example 2" />
  <img src="doc/img/circle_radar_3.png" width="31%" alt="Circle radar example 3" />
</p>

### Square Radar

<p>
  <img src="doc/img/square_radar_1.png" width="31%" alt="Square radar example 1" />
  <img src="doc/img/square_radar_2.png" width="31%" alt="Square radar example 2" />
  <img src="doc/img/square_radar_3.png" width="31%" alt="Square radar example 3" />
</p>

## Display and Behavior

Both radar shapes support the same outline and guide options, and the frame rendering is tuned so crosshairs fit the active frame, view guides reach the border cleanly, circle range rings stay thin and solid, circle outlines remain visually continuous, and square dotted outlines render as proper dots.

### Square radar variants
| Guide | Solid | Dotted | Off |
|---|---|---|---|
| Crosshair | <img src="doc/img/radar_1_square_solid_crosshair.png" width="200" /> | <img src="doc/img/radar_2_square_dotted_crosshair.png" width="200" /> | <img src="doc/img/radar_1_square_off_crosshair.png" width="200" /> |
| View Guides | <img src="doc/img/radar_2_square_solid_view_guides.png" width="200" /> | <img src="doc/img/radar_2_square_dotted_view_guides.png" width="200" /> | <img src="doc/img/radar_2_square_off_view_guides.png" width="200" /> |
| Rings | <img src="doc/img/radar_3_square_solid_rings.png" width="200" /> | <img src="doc/img/radar_2_square_dotted_rings.png" width="200" /> | <img src="doc/img/radar_3_square_off_rings.png" width="200" /> |
| Off | <img src="doc/img/radar_4_square_solid_off.png" width="200" /> | <img src="doc/img/radar_2_square_dotted_off.png" width="200" /> | <img src="doc/img/radar_4_square_off_off.png" width="200" /> |

### Circle radar variants
| Guide | Solid | Dotted | Off |
|---|---|---|---|
| Crosshair | <img src="doc/img/radar_1_circle_solid_crosshair.png" width="200" /> | <img src="doc/img/radar_2_circle_dotted_crosshair.png" width="200" /> | <img src="doc/img/radar_1_circle_off_crosshair.png" width="200" /> |
| View Guides | <img src="doc/img/radar_2_circle_solid_view_guides.png" width="200" /> | <img src="doc/img/radar_2_circle_dotted_view_guides.png" width="200" /> | <img src="doc/img/radar_2_circle_off_view_guides.png" width="200" /> |
| Rings | <img src="doc/img/radar_3_circle_solid_rings.png" width="200" /> | <img src="doc/img/radar_2_circle_dotted_rings.png" width="200" /> | <img src="doc/img/radar_3_circle_off_rings.png" width="200" /> |
| Off | <img src="doc/img/radar_4_circle_solid_off.png" width="200" /> | <img src="doc/img/radar_2_circle_dotted_off.png" width="200" /> | <img src="doc/img/radar_4_circle_off_off.png" width="200" /> |

### Radar Controls

| Option | What it controls |
| --- | --- |
| Enable radar | Master on or off switch for the HUD element. |
| Toggle radar on or off | Assign a key to switch the radar HUD visibility during gameplay without opening the options menu. |
| Radar size | Adjustable from **100** to **350**. |
| Radar range / filter distance | Adjustable from **25 m** to **100 m**. |
| Max radar markers | Adjustable from **10** to **100**. |
| Scale icons with radar size | Keeps marker size fixed or scales it with the radar. |
| Radar style | **Square** or **Circle**. |
| Radar outline | **Solid**, **Dotted**, or **Off**. |
| Radar guides | **Crosshair**, **View guides**, **Range rings**, or **Off**. |
| Enemy marker style | **Icon only** or **Marked icon**. |
| Player marker style | **Icon only** or **Marked icon**. |
| Radar position X | Sets the radar's horizontal position. The value is clamped to the visible UI space. |
| Radar position Y | Sets the radar's vertical position. The value is clamped to the visible UI space. |
| Steps per input | Sets how far each radar movement key press nudges the radar. |
| Move radar left | Assign a key to move the radar left by the configured step size. |
| Move radar right | Assign a key to move the radar right by the configured step size. |
| Move radar up | Assign a key to move the radar up by the configured step size. |
| Move radar down | Assign a key to move the radar down by the configured step size. |
| Highlight distance | Present in the options menu, but the highlighting feature is currently still under development. |

### Expedition POI Controls

| Option | What it controls |
| --- | --- |
| Expeditions POI | Group of toggles for expedition location markers. |
| Ignore range limit for POI | Lets expedition POI markers bypass the normal radar range filter. |
| Sites of Interest | Shows registered expedition opportunity locations, including numbered scanner-map opportunity markers. |
| Deadsider Sanctuaries | Shows expedition transition or sanctuary locations with the dedicated transition icon. |
| Data Reliquary Harvesters | Shows expedition loot converters with the dedicated harvester icon while inside the sanctuary where they are usable. |
| Main Objective | Shows expedition main objective locations with the dedicated objective icon. |
| Valkyrie Extraction Zone | Shows extraction points with the dedicated extraction icon. |
| Valkyrie Arrival Zone | Shows arrival points with the dedicated arrival icon. |

### Positioning and Toggle Use

- Use **Toggle radar on or off** to quickly hide or restore the radar while staying in the mission.
- Use **Radar position X** and **Radar position Y** when you want to place the radar precisely in a fixed HUD location.
- Use **Move radar left**, **right**, **up**, and **down** when you want to fine-tune the placement in live gameplay with key presses.
- **Steps per input** controls how large each movement increment is, which makes it easier to do either quick repositioning or small adjustments.
- Radar placement is automatically clamped against the current UI space, so the widget stays within the visible screen area even after changing size or resolution scale.

### Marker Rules

- **Enemies** use dedicated danger icons and, in marked mode, red bracket accents.
- **Teammates** use archetype icons and their runtime HUD slot color.
- **The center dot** uses the local player HUD color instead of a fixed green.
- **Objective and event items** reuse a small number of template icons, recolored through ARGB values where needed.
- **Expedition POIs** use numbered scanner-map glyphs for opportunity markers, can also reflect player-marked states in expedition colors, use dedicated icons for transition, harvester, main objective, extraction, and arrival locations, can optionally ignore the normal radar range limit, and are filtered to the active expedition section so outdated location markers do not linger after section changes.

## Target Markers

The legend below follows the option groups exposed by `Radar_data.lua`. The preview tiles were generated from the included `doc/img` templates and the ARGB values used by the HUD presentations.

### High-Priority Enemies

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/enemy_daemonhost.png" width="40" alt="Daemonhost marker" /> | Daemonhost | Separate presentation under the **Monstrosities** toggle. |
| <img src="doc/img/enemy_monstrosity.png" width="40" alt="Monstrosity marker" /> | Monstrosities | Covers the generic monstrosity presentation used for Beast of Nurgle, Plague Ogryn, Chaos Spawn, and Ogryn Houndmaster. |
| <img src="doc/img/enemy_captain.png" width="40" alt="Captain marker" /> | Captains | Red danger marker with bracket accent in marked mode. |
| <img src="doc/img/enemy_karnak_twin.png" width="40" alt="Karnak Twins marker" /> | Karnak Twins | Dedicated presentation for the twins. |

Display style example for enemy markers:

<p>
  <img src="doc/img/enemy_icon_only_sample.png" width="40" alt="Enemy icon only example" />
  <img src="doc/img/enemy_monstrosity.png" width="40" alt="Enemy marked icon example" />
</p>

Left: **Icon only**. Right: **Marked icon**.

### Teammates

| Preview | Marker | Notes                                                                                                                                  |
| --- | --- |----------------------------------------------------------------------------------------------------------------------------------------|
| <img src="doc/img/player_teammate_sample.png" width="40" alt="Teammate marker sample" /> | Teammates | Uses class icons, colored by teammate slot at runtime. Can be shown as **Icon only**, **Marked icon**, **Dot only** or **Marked dot**. |

Display style example for teammate markers:

<p>
  <img src="doc/img/player_teammate_icon_only_sample.png" width="40" alt="Teammate icon only example" />
  <img src="doc/img/player_teammate_sample.png" width="40" alt="Teammate marked icon example" />
  <img src="doc/img/player_teammate_dot_only_sample.png" width="40" alt="Teammate dot only example" />
  <img src="doc/img/player_teammate_marked_dot_sample.png.png" width="40" alt="Teammate marked dot example" />
</p>

Left to the right:
* **Icon only**
* **Marked icon**
* **Dot only**
* **Marked dot**


Supported class icon mappings in the HUD:

<p>
  <img src="doc/img/player_teammates_classes.png" width="320" alt="Supported teammate class icons" />
</p>

From left to right: **Veteran**, **Zealot**, **Psyker**, **Ogryn**, **Arbitrator**, **Hive Scum**.

### Common Pickups

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/crate_unknown.png" width="40" alt="Crate marker" /> | Crates | Generic chest or crate pickup marker. |
| <img src="doc/img/pickup_ammo_small.png" width="40" alt="Ammo tin marker" /> | Ammo Tin | Small ammo pickup. |
| <img src="doc/img/pickup_ammo_big.png" width="40" alt="Ammo stash marker" /> | Ammo Stash | Large ammo pickup. |
| <img src="doc/img/pickup_grenade.png" width="40" alt="Grenade marker" /> | Grenade | Uses the supplied grenade icon. |
| <img src="doc/img/pocketable_ammo_crate.png" width="40" alt="Ammo crate marker" /> | Ammo Crate | Pocketable ammo crate. |
| <img src="doc/img/pocketable_medical_crate.png" width="40" alt="Medical crate marker" /> | Medical Crate | Pocketable medical crate. |
| <img src="doc/img/pocketable_syringe_ability.png" width="40" alt="Concentration Stimm marker" /> | Concentration Stimm | Recolored syringe template. |
| <img src="doc/img/pocketable_syringe_corruption.png" width="40" alt="Med Stimm marker" /> | Med Stimm | Recolored syringe template. |
| <img src="doc/img/pocketable_syringe_power.png" width="40" alt="Combat Stimm marker" /> | Combat Stimm | Recolored syringe template. |
| <img src="doc/img/pocketable_syringe_speed.png" width="40" alt="Celerity Stimm marker" /> | Celerity Stimm | Recolored syringe template. |

### Collectable Materials

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/material_diamantine.png" width="40" alt="Diamantine marker" /> | Diamantine | Uses the supplied item artwork unchanged. |
| <img src="doc/img/material_plasteel.png" width="40" alt="Plasteel marker" /> | Plasteel | Uses the supplied item artwork unchanged. |

### Primary Objective Items

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/luggable_power_cell_teal.png" width="40" alt="Power Cell marker" /> | Power Cell | Teal luggable objective marker. |
| <img src="doc/img/luggable_cryonic_rod.png" width="40" alt="Cryonic Rod marker" /> | Cryonic Rod | Pale ice-blue luggable marker. |
| <img src="doc/img/luggable_moebian_pox_zetaphyte_13_sample.png" width="40" alt="Moebian Pox Zetaphyte-13 Sample marker" /> | Moebian Pox Zetaphyte-13 Sample | Sickly green luggable marker. |
| <img src="doc/img/luggable_vacuum_capsule.png" width="40" alt="Vacuum Capsule marker" /> | Vacuum Capsule | Dark steel-grey luggable marker. |
| <img src="doc/img/luggable_special_issue_ammo.png" width="40" alt="Special Issue Ammo marker" /> | Special Issue Ammo | Olive-green luggable marker. |
| <img src="doc/img/luggable_prismata_crystal_repository.png" width="40" alt="Prismata Crystal Repository marker" /> | Prismata Crystal Repository | Bright red luggable marker. |
| <img src="doc/img/pickup_mortis_relic.png" width="40" alt="Mortis Relic marker" /> | Mortis Relic | Recolored device icon. |
| <img src="doc/img/pickup_coordinates_paper.png" width="40" alt="Coordinates marker" /> | Coordinates | Uses the paper document icon. |

### Secondary Objective Items

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/pocketable_grimoire.png" width="40" alt="Grimoire marker" /> | Grimoire | Secondary objective pocketable. |
| <img src="doc/img/pocketable_scripture.png" width="40" alt="Scripture marker" /> | Scripture | Secondary objective pocketable. |

### Expedition POIs

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/expedition_unmarked_xi_2_4x.png" width="48" alt="Expedition unmarked XI 2 marker" /> <img src="doc/img/expedition_unmarked_n_4_4x.png" width="48" alt="Expedition unmarked N 4 marker" /> <img src="doc/img/expedition_unmarked_m_1_4x.png" width="48" alt="Expedition unmarked M 1 marker" /> | Sites of Interest | Unmarked expedition opportunity markers, using scanner-map glyphs with location numbering. |
| <img src="doc/img/expedition_marked_yellow_n_4_4x.png" width="48" alt="Expedition marked yellow N 4 marker" /> <img src="doc/img/expedition_marked_purple_xi_2_4x.png" width="48" alt="Expedition marked purple XI 2 marker" /> <img src="doc/img/expedition_marked_blue_m_1_4x.png" width="48" alt="Expedition marked blue M 1 marker" /> | Sites of Interest, player-marked | Player-marked expedition opportunity markers, using the same glyph and number combinations with the expedition marked colors. |
| <img src="doc/img/expedition_objective_transition.png" width="40" alt="Expedition transition marker" /> | Deadsider Sanctuaries | Transition marker for sanctuary travel and section movement. |
| <img src="doc/img/expedition_loot_converter.png" width="40" alt="Expedition loot converter marker" /> | Data Reliquary Harvesters | Uses the expedition harvester icon and is only shown while inside the sanctuary where the converter is relevant. |
| <img src="doc/img/expedition_objective_main_objective.png" width="40" alt="Expedition main objective marker" /> | Main Objective | Main expedition objective location marker. |
| <img src="doc/img/expedition_objective_extraction.png" width="40" alt="Expedition extraction marker" /> | Valkyrie Extraction Zone | Extraction location marker. |
| <img src="doc/img/expedition_objective_arrival.png" width="40" alt="Expedition arrival marker" /> | Valkyrie Arrival Zone | Arrival location marker. |

These markers are driven by expedition navigation data rather than standard pickup scanning. **Sites of Interest** can appear as unmarked opportunity markers or player-marked variants, while the remaining expedition POIs use dedicated objective-style icons. They can optionally ignore the normal radar range limit, are filtered to the currently active expedition section, and clear outdated location markers when the active section changes.

### Expeditions-Specific Items

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/material_expeditions_currency.png" width="40" alt="Salvage marker" /> | Salvage | Uses the supplied item artwork unchanged. |
| <img src="doc/img/material_expeditions_loot.png" width="40" alt="Tech-Remnants marker" /> | Tech-Remnants | Uses the supplied item artwork unchanged. |
| <img src="doc/img/material_expeditions_loot_player_drop.png" width="40" alt="Dropped Tech-Remnants marker" /> | Dropped Tech-Remnants | Uses the supplied item artwork unchanged. |
| <img src="doc/img/luggable_data_reliquary.png" width="40" alt="Data Reliquary marker" /> | Data Reliquaries | Gold luggable marker. |
| <img src="doc/img/pocketable_landmine_explosive.png" width="40" alt="Servo-Triggered Mine marker" /> | Servo-Triggered Mine | Explosive landmine. |
| <img src="doc/img/pocketable_landmine_fire.png" width="40" alt="Purgation Snare marker" /> | Purgation Snare | Fire landmine. |
| <img src="doc/img/pocketable_landmine_shock.png" width="40" alt="Voltaic Snare marker" /> | Voltaic Snare | Shock landmine. |
| <img src="doc/img/pocketable_void_shield.png" width="40" alt="Void Shell marker" /> | Void Shell | Uses the supplied item artwork unchanged. |
| <img src="doc/img/pocketable_airstrike.png" width="40" alt="Bombing Run Signal Marker marker" /> | Bombing Run Signal Marker | Airstrike support marker. |
| <img src="doc/img/pocketable_artillery_strike.png" width="40" alt="Artillery Locator Beacon marker" /> | Artillery Locator Beacon | Artillery support marker. |
| <img src="doc/img/pocketable_big_grenade.png" width="40" alt="Modified Grenade marker" /> | Modified Grenade | Special expeditions grenade pickup. |
| <img src="doc/img/pocketable_valkyrie_hover.png" width="40" alt="Fire-Support Signal Marker marker" /> | Fire-Support Signal Marker | Valkyrie hover signal marker. |
| <img src="doc/img/luggable_promethium_barrel.png" width="40" alt="Promethium Barrel marker" /> | Promethium Barrel | Orange explosive barrel marker. |
| <img src="doc/img/pickup_large_ammunition_crate.png" width="40" alt="Large Ammunition Crate marker" /> | Large Ammunition Crate | White ammo container marker. |
| <img src="doc/img/pocketable_anti_rad_stimm.png" width="40" alt="Anti-Rad Stimms marker" /> | Anti-Rad Stimms | Uses the expedition time syringe icon. |

### Martyr's Skull Items

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/pickup_martyr_skull.png" width="40" alt="Martyr's Skull marker" /> | Martyr's Skull | Gold skull marker. |
| <img src="doc/img/luggable_power_cell_orange.png" width="40" alt="Orange Power Cell marker" /> | Power Cell | Orange luggable marker used for the Martyr's Skull group. |

### Deployed Items

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/pickup_ammo_cache_deployable.png" width="40" alt="Deployable ammo crate marker" /> | Ammo Crate | Pale green deployable ammo crate marker. |
| <img src="doc/img/pickup_medkit.png" width="40" alt="Deployable medical crate marker" /> | Medical Crate | Green deployable medical crate marker. |

### Event-Related Items

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/pickup_tainted_skull.png" width="40" alt="Tainted Skull marker" /> | Tainted Skulls | Green skull marker. |
| <img src="doc/img/pocketable_corrupted_auspex_scanner.png" width="40" alt="Tainted Communications Device marker" /> | Tainted Communications Device | Orange auspex scanner marker. |
| <img src="doc/img/pickup_saints.png" width="40" alt="Holy Relics marker" /> | Holy Relics | Gold relic marker. |
| <img src="doc/img/pickup_stolen_rations.png" width="40" alt="Stolen Rations marker" /> | Stolen Rations | Green crate marker. |

### Debug Marker

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/pickup_unknown.png" width="40" alt="Unknown pickup marker" /> | Unknown pickups | Optional fallback marker used when debug discovery is enabled. |

## Icons and Color Rules

The readme preview icons follow the HUD presentations used by the mod.

### Icons Left Unchanged

The following files were kept as-is and were **not** ARGB recolored:

- `diamantine_big.png`
- `empty.png`
- `engram_rarity_04.png`
- `plasteel_big.png`
- `salvage_big.png`
- `tech_dropped.png`
- `tech_remnant_big.png`
- `void_shield.png`

### Recolored Template Families

| Base template | Variants in this readme | ARGB colors |
| --- | --- | --- |
| `lugged.png` | Data Reliquary, Power Cell, Cryonic Rod, Moebian Pox Zetaphyte-13 Sample, Vacuum Capsule, Special Issue Ammo, Prismata Crystal Repository | `(255, 192, 160, 0)`, `(255, 0, 200, 200)`, `(255, 180, 220, 255)`, `(255, 150, 190, 60)`, `(255, 80, 85, 90)`, `(255, 95, 125, 70)`, `(255, 255, 70, 90)` |
| `party_syringe.png` | Concentration, Med, Combat, Celerity Stimms | `(255, 230, 192, 13)`, `(255, 38, 205, 26)`, `(255, 205, 51, 26)`, `(255, 0, 127, 218)` |
| `enemy.png` | Martyr's Skull, Tainted Skulls | `(255, 255, 215, 0)`, `(255, 150, 190, 60)` |
| `pocketable_ammo.png` | Deployable Ammo Crate, Large Ammunition Crate | `(255, 215, 237, 188)`, unchanged white |
| `devices.png` | Mortis Relic | `(255, 110, 95, 125)` |
| `barrel_explosive.png` | Promethium Barrel | `(255, 255, 110, 0)` |
| `auspex_scanner.png` | Tainted Communications Device | `(255, 255, 120, 0)` |
| `live_event_01.png` | Holy Relics | `(255, 192, 160, 0)` |
| Enemy accent brackets | Daemonhost, Monstrosity, Captain, Karnak Twins | `(220, 255, 0, 0)` |

### Runtime-Dynamic Colors

Not every radar marker uses a fixed readme tint:

- **Teammates** use the class icon for the detected archetype and take their color from the active HUD slot color at runtime.
- **The radar center dot** also uses the local player's HUD color.

## Requirements

- **[Darktide Mod Framework](https://www.nexusmods.com/warhammer40kdarktide/mods/8)**
- **[Darktide Mod Loader](https://www.nexusmods.com/warhammer40kdarktide/mods/19)**


## Notes

- The radar is intended for active gameplay and suppresses itself outside valid runtime states such as hub and menu contexts.
- Expedition POIs are filtered to the active expedition section, and **Data Reliquary Harvesters** are only shown inside the relevant **Deadsider Sanctuary** where they can actually be used.
- The highlighting option is visible in the configuration, but the actual highlighting behavior is still work in progress.
- Marker previews in this readme were generated from the included template assets so the legend matches the mod's configured presentations as closely as possible.
- The gameplay screenshots in this readme were captured during an expedition mission and show both radar frame styles in live use.
- Version **1.2.0** adds configurable outline and guide styles for both square and circle radar modes, plus dedicated Expedition POI tracking.

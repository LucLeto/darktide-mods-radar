# Radar

Radar adds a compact, camera-oriented HUD radar for **Warhammer 40,000: Darktide**. It is built to surface the targets that matter most during live missions, nearby pickups, objective items, deployed support tools, environment interactables, expedition points of interest, teammates, and high-priority enemies, while keeping the presentation configurable from the mod options menu.

## Feature Overview

- Tracks nearby pickups, materials, mission items, event items, deployables, environment interactables, expedition POIs, teammates, and priority enemies on a single radar.
- Projects markers relative to your current facing, so the radar rotates with your view instead of acting like a fixed minimap.
- Supports **square** and **circle** radar frames, plus configurable **outline** and **guide** styles for both shapes.
- Lets you adjust **radar size**, **scan range**, and **maximum marker count**.
- Supports optional **icon scaling with radar size**.
- Supports separate marker styles for **enemies** and **teammates**. Enemies support **Icon only** and **Marked icon**, teammates support **Icon only**, **Marked icon**, **Dot only**, and **Marked dot**.
- Includes a **toggle radar on or off** keybind, so you can hide or restore the radar during a mission without opening the options menu.
- Supports configurable **radar positioning** with **Radar position X**, **Radar position Y**, **Steps per input**, and dedicated movement keybinds for nudging the radar **left**, **right**, **up**, or **down**.
- Adds dedicated **Expedition POI** support for numbered **Sites of Interest** opportunity markers, plus dedicated icons for **Deadsider Sanctuaries**, **Data Reliquary Harvesters**, **Main Objective**, **Valkyrie Extraction Zone**, and **Valkyrie Arrival Zone**, with an option to ignore the normal range limit for these markers.
- Adds environment markers for **Medicae Station**, **Power Socket**, and **Heretic Idol**.
- Supports per-marker display mode dropdowns for supported artwork-based markers with **Artwork**, **Icon**, and **Off** modes. **Artwork** remains the default, and older boolean settings are migrated automatically.
- Recolors the remaining formerly white pickup icons with more semantic colors, including ammo, grenades, medicae-related markers, power sockets, and heretic idols.
- Keeps the radar position clamped to the visible UI space, so moving or resizing it does not push it off-screen.
- Colors the radar center dot from the local player HUD slot color.
- Supports class-icon and dot-based teammate presentations instead of a single fixed teammate marker style.
- Exposes category-based checkboxes, style dropdowns, and display mode dropdowns for common pickups, materials, objective items, expedition items, expedition POIs, environment markers, deployed items, enemies, teammates, and event items.
- Includes optional **debug logs** and an **unknown pickups** toggle for discovery and troubleshooting.
- Includes a groundwork **highlighting** option, but the actual highlighting behavior is currently still under development.

## In-Game Radar Examples

The screenshots below show both radar styles during an expedition mission. They illustrate the camera-oriented layout, mixed pickup categories, teammate markers, expedition POIs, and priority targets in live gameplay.

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

## Artwork, Icon, Off display modes

Supported artwork-based markers now use dropdowns instead of simple booleans. Each supported marker can be shown as **Artwork**, **Icon**, or **Off**.

- **Artwork** uses the original item artwork or pickup art.
- **Icon** uses a simplified HUD icon material with an ARGB tint.
- **Off** hides that specific marker entirely.
- Existing saved boolean settings are migrated automatically, with old `true` values becoming **Artwork** and old `false` values becoming **Off**.

### Common pickups and materials

| Marker | Artwork | Icon | Off |
| --- | --- | --- | --- |
| Crates | <img src="doc/img/crate_unknown.png" width="40" alt="Crate artwork mode" /> | <img src="doc/img/crate_unknown_alternative.png" width="40" alt="Crate icon mode" /> | Hidden |
| Diamantine | <img src="doc/img/material_diamantine.png" width="40" alt="Diamantine artwork mode" /> | <img src="doc/img/material_diamantine_alternative.png" width="40" alt="Diamantine icon mode" /> | Hidden |
| Plasteel | <img src="doc/img/material_plasteel.png" width="40" alt="Plasteel artwork mode" /> | <img src="doc/img/material_plasteel_alternative.png" width="40" alt="Plasteel icon mode" /> | Hidden |

### Expeditions-specific items with display modes

| Marker | Artwork | Icon | Off |
| --- | --- | --- | --- |
| Salvage | <img src="doc/img/material_expeditions_currency.png" width="40" alt="Salvage artwork mode" /> | <img src="doc/img/material_expeditions_currency_alternative.png" width="40" alt="Salvage icon mode" /> | Hidden |
| Tech-Remnants | <img src="doc/img/material_expeditions_loot.png" width="40" alt="Tech-Remnants artwork mode" /> | <img src="doc/img/material_expeditions_loot_alternative.png" width="40" alt="Tech-Remnants icon mode" /> | Hidden |
| Dropped Tech-Remnants | <img src="doc/img/material_expeditions_loot_player_drop.png" width="40" alt="Dropped Tech-Remnants artwork mode" /> | <img src="doc/img/material_expeditions_loot_player_drop_alternative.png" width="40" alt="Dropped Tech-Remnants icon mode" /> | Hidden |
| Servo-Triggered Mine | <img src="doc/img/pocketable_landmine_explosive.png" width="40" alt="Explosive mine artwork mode" /> | <img src="doc/img/pocketable_landmine_explosive_alternative.png" width="40" alt="Explosive mine icon mode" /> | Hidden |
| Purgation Snare | <img src="doc/img/pocketable_landmine_fire.png" width="40" alt="Fire mine artwork mode" /> | <img src="doc/img/pocketable_landmine_fire_alternative.png" width="40" alt="Fire mine icon mode" /> | Hidden |
| Voltaic Snare | <img src="doc/img/pocketable_landmine_shock.png" width="40" alt="Shock mine artwork mode" /> | <img src="doc/img/pocketable_landmine_shock_alternative.png" width="40" alt="Shock mine icon mode" /> | Hidden |
| Void Shell | <img src="doc/img/pocketable_void_shield.png" width="40" alt="Void Shell artwork mode" /> | <img src="doc/img/pocketable_void_shield_alternative.png" width="40" alt="Void Shell icon mode" /> | Hidden |
| Bombing Run Signal Marker | <img src="doc/img/pocketable_airstrike.png" width="40" alt="Airstrike artwork mode" /> | <img src="doc/img/pocketable_airstrike_alternative.png" width="40" alt="Airstrike icon mode" /> | Hidden |
| Artillery Locator Beacon | <img src="doc/img/pocketable_artillery_strike.png" width="40" alt="Artillery artwork mode" /> | <img src="doc/img/pocketable_artillery_strike_alternative.png" width="40" alt="Artillery icon mode" /> | Hidden |
| Modified Grenade | <img src="doc/img/pocketable_big_grenade.png" width="40" alt="Modified grenade artwork mode" /> | <img src="doc/img/pocketable_big_grenade_alternative.png" width="40" alt="Modified grenade icon mode" /> | Hidden |
| Fire-Support Signal Marker | <img src="doc/img/pocketable_valkyrie_hover.png" width="40" alt="Valkyrie hover artwork mode" /> | <img src="doc/img/pocketable_valkyrie_hover_alternative.png" width="40" alt="Valkyrie hover icon mode" /> | Hidden |

## Radar Controls

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
| Player marker style | **Icon only**, **Marked icon**, **Dot only**, or **Marked dot**. |
| Radar position X | Sets the radar's horizontal position. The value is clamped to the visible UI space. |
| Radar position Y | Sets the radar's vertical position. The value is clamped to the visible UI space. |
| Steps per input | Sets how far each radar movement key press nudges the radar. |
| Move radar left | Assign a key to move the radar left by the configured step size. |
| Move radar right | Assign a key to move the radar right by the configured step size. |
| Move radar up | Assign a key to move the radar up by the configured step size. |
| Move radar down | Assign a key to move the radar down by the configured step size. |
| Highlight distance | Present in the options menu, but the highlighting feature is currently still under development. |

### Marker display mode controls

| Option group | Markers | Modes |
| --- | --- | --- |
| Common Pickups | Crates | **Artwork**, **Icon**, **Off** |
| Collectable Materials | Diamantine, Plasteel | **Artwork**, **Icon**, **Off** |
| Expeditions-Specific Items | Salvage, Tech-Remnants, Dropped Tech-Remnants, Servo-Triggered Mine, Purgation Snare, Voltaic Snare, Void Shell, Bombing Run Signal Marker, Artillery Locator Beacon, Modified Grenade, Fire-Support Signal Marker | **Artwork**, **Icon**, **Off** |

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

### Environment Controls

| Option | What it controls |
| --- | --- |
| Environment | Group of toggles for interactable world objects that are useful to spot on the radar. |
| Medicae Station | Shows medicae station and equivalent health station interactions. |
| Power Socket | Shows luggable power socket targets. |
| Heretic Idol | Shows active heretic idols while they are still present. |

### Positioning and Toggle Use

- Use **Toggle radar on or off** to quickly hide or restore the radar while staying in the mission.
- Use **Radar position X** and **Radar position Y** when you want to place the radar precisely in a fixed HUD location.
- Use **Move radar left**, **right**, **up**, and **down** when you want to fine-tune the placement in live gameplay with key presses.
- **Steps per input** controls how large each movement increment is, which makes it easier to do either quick repositioning or small adjustments.
- Radar placement is automatically clamped against the current UI space, so the widget stays within the visible screen area even after changing size or resolution scale.

### Marker Rules

- **Enemies** use dedicated danger icons and, in marked mode, red bracket accents.
- **Teammates** use archetype icons or dot presentations, plus their runtime HUD slot color.
- **The center dot** uses the local player HUD color instead of a fixed green.
- **Supported artwork-based markers** can now switch between artwork mode, simplified icon mode, or be disabled entirely.
- **Environment markers** cover medicae stations, power sockets, and heretic idols.
- **Expedition POIs** use numbered scanner-map glyphs for opportunity markers, can also reflect player-marked states in expedition colors, use dedicated icons for transition, harvester, main objective, extraction, and arrival locations, can optionally ignore the normal radar range limit, and are filtered to the active expedition section so outdated location markers do not linger after section changes.

## Target Markers

The legend below follows the option groups exposed by `Radar_data.lua`. The preview tiles were generated from the included `doc/img` assets and the ARGB values used by the HUD presentations.

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

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/player_teammate_sample.png" width="40" alt="Teammate marker sample" /> | Teammates | Uses class icons, colored by teammate slot at runtime. Can be shown as **Icon only**, **Marked icon**, **Dot only**, or **Marked dot**. |

Display style example for teammate markers:

<p>
  <img src="doc/img/player_teammate_icon_only_sample.png" width="40" alt="Teammate icon only example" />
  <img src="doc/img/player_teammate_sample.png" width="40" alt="Teammate marked icon example" />
  <img src="doc/img/player_teammate_dot_only_sample.png" width="40" alt="Teammate dot only example" />
  <img src="doc/img/player_teammate_marked_dot_sample.png.png" width="40" alt="Teammate marked dot example" />
</p>

Left to right:
- **Icon only**
- **Marked icon**
- **Dot only**
- **Marked dot**

Supported class icon mappings in the HUD:

<p>
  <img src="doc/img/player_teammates_classes.png" width="320" alt="Supported teammate class icons" />
</p>

From left to right: **Veteran**, **Zealot**, **Psyker**, **Ogryn**, **Arbitrator**, **Hive Scum**.

### Common Pickups

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/crate_unknown.png" width="40" alt="Crate marker" /> | Crates | Supports **Artwork**, **Icon**, and **Off**. Artwork keeps the pickup art, icon mode uses a simplified loot icon. |
| <img src="doc/img/pickup_ammo_small.png" width="40" alt="Ammo tin marker" /> | Ammo Tin | Small ammo pickup, recolored with an ammo-specific yellow. |
| <img src="doc/img/pickup_ammo_big.png" width="40" alt="Ammo stash marker" /> | Ammo Stash | Large ammo pickup, recolored with an ammo-specific yellow. |
| <img src="doc/img/pickup_grenade.png" width="40" alt="Grenade marker" /> | Grenade | Uses a warm grenade-specific amber tint. |
| <img src="doc/img/pocketable_ammo_crate.png" width="40" alt="Ammo crate marker" /> | Ammo Crate | Pocketable ammo crate, recolored to match the ammo family. |
| <img src="doc/img/pocketable_medical_crate.png" width="40" alt="Medical crate marker" /> | Medical Crate | Pocketable medical crate with a medicae green tint. |
| <img src="doc/img/pocketable_syringe_ability.png" width="40" alt="Concentration Stimm marker" /> | Concentration Stimm | Recolored syringe template. |
| <img src="doc/img/pocketable_syringe_corruption.png" width="40" alt="Med Stimm marker" /> | Med Stimm | Recolored syringe template. |
| <img src="doc/img/pocketable_syringe_power.png" width="40" alt="Combat Stimm marker" /> | Combat Stimm | Recolored syringe template. |
| <img src="doc/img/pocketable_syringe_speed.png" width="40" alt="Celerity Stimm marker" /> | Celerity Stimm | Recolored syringe template. |

### Collectable Materials

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/material_diamantine.png" width="40" alt="Diamantine marker" /> | Diamantine | Supports **Artwork**, **Icon**, and **Off**. Icon mode uses a simplified blue material icon. |
| <img src="doc/img/material_plasteel.png" width="40" alt="Plasteel marker" /> | Plasteel | Supports **Artwork**, **Icon**, and **Off**. Icon mode uses a simplified steel-grey material icon. |

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
| <img src="doc/img/material_expeditions_currency.png" width="40" alt="Salvage marker" /> | Salvage | Supports **Artwork**, **Icon**, and **Off**. Artwork uses the salvage item art, icon mode uses a simplified salvage icon. |
| <img src="doc/img/material_expeditions_loot.png" width="40" alt="Tech-Remnants marker" /> | Tech-Remnants | Supports **Artwork**, **Icon**, and **Off**. |
| <img src="doc/img/material_expeditions_loot_player_drop.png" width="40" alt="Dropped Tech-Remnants marker" /> | Dropped Tech-Remnants | Supports **Artwork**, **Icon**, and **Off**. Icon mode uses a red-tinted simplified icon to distinguish dropped loot. |
| <img src="doc/img/luggable_data_reliquary.png" width="40" alt="Data Reliquary marker" /> | Data Reliquaries | Gold luggable marker. |
| <img src="doc/img/pocketable_landmine_explosive.png" width="40" alt="Servo-Triggered Mine marker" /> | Servo-Triggered Mine | Supports **Artwork**, **Icon**, and **Off**. |
| <img src="doc/img/pocketable_landmine_fire.png" width="40" alt="Purgation Snare marker" /> | Purgation Snare | Supports **Artwork**, **Icon**, and **Off**. |
| <img src="doc/img/pocketable_landmine_shock.png" width="40" alt="Voltaic Snare marker" /> | Voltaic Snare | Supports **Artwork**, **Icon**, and **Off**. |
| <img src="doc/img/pocketable_void_shield.png" width="40" alt="Void Shell marker" /> | Void Shell | Supports **Artwork**, **Icon**, and **Off**. |
| <img src="doc/img/pocketable_airstrike.png" width="40" alt="Bombing Run Signal Marker marker" /> | Bombing Run Signal Marker | Supports **Artwork**, **Icon**, and **Off**. |
| <img src="doc/img/pocketable_artillery_strike.png" width="40" alt="Artillery Locator Beacon marker" /> | Artillery Locator Beacon | Supports **Artwork**, **Icon**, and **Off**. |
| <img src="doc/img/pocketable_big_grenade.png" width="40" alt="Modified Grenade marker" /> | Modified Grenade | Supports **Artwork**, **Icon**, and **Off**. |
| <img src="doc/img/pocketable_valkyrie_hover.png" width="40" alt="Fire-Support Signal Marker marker" /> | Fire-Support Signal Marker | Supports **Artwork**, **Icon**, and **Off**. |
| <img src="doc/img/luggable_promethium_barrel.png" width="40" alt="Promethium Barrel marker" /> | Promethium Barrel | Orange explosive barrel marker. |
| <img src="doc/img/pickup_large_ammunition_crate.png" width="40" alt="Large Ammunition Crate marker" /> | Large Ammunition Crate | Large ammo container, recolored to match the ammo family. |
| <img src="doc/img/pocketable_anti_rad_stimm.png" width="40" alt="Anti-Rad Stimms marker" /> | Anti-Rad Stimms | Uses the expedition time syringe icon. |

### Martyr's Skull Items

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/pickup_martyr_skull.png" width="40" alt="Martyr's Skull marker" /> | Martyr's Skull | Gold skull marker. |
| <img src="doc/img/luggable_power_cell_orange.png" width="40" alt="Orange Power Cell marker" /> | Power Cell | Orange luggable marker used for the Martyr's Skull group. |

### Environment Markers

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/medicae_station.png" width="40" alt="Medicae Station marker" /> | Medicae Station | Green medical interaction marker used for medicae stations and equivalent health-station interactions. |
| <img src="doc/img/luggable_socket.png" width="40" alt="Power Socket marker" /> | Power Socket | Yellow power socket marker for luggable socket targets. |
| <img src="doc/img/heretic_idol.png" width="40" alt="Heretic Idol marker" /> | Heretic Idol | Sickly green idol marker shown while the idol is still active. |

### Deployed Items

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/pickup_ammo_cache_deployable.png" width="40" alt="Deployable ammo crate marker" /> | Ammo Crate | Ammo-yellow deployable ammo crate marker. |
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

## Display Modes and Color Rules

The readme preview icons follow the HUD presentations used by the mod.

### Artwork mode

Artwork mode keeps the original item artwork for supported markers. This is the default mode for all markers that support the new display dropdowns.

Examples:
- Crates use the pickup artwork tile.
- Diamantine, Plasteel, Salvage, Tech-Remnants, and Dropped Tech-Remnants keep their resource artwork.
- Expeditions pocketables such as Void Shell, the landmines, and the strike markers keep their existing item artwork.

### Icon mode

Icon mode swaps supported markers to simplified HUD icon materials with dedicated ARGB colors.

| Marker family | Icon material | ARGB |
| --- | --- | --- |
| Crates | `content/ui/materials/icons/generic/loot` | `(255, 225, 200, 136)` |
| Diamantine | `content/ui/materials/hud/interactions/icons/environment_generic` | `(255, 70, 130, 220)` |
| Plasteel | `content/ui/materials/hud/interactions/icons/environment_generic` | `(255, 130, 135, 140)` |
| Salvage | `content/ui/materials/hud/interactions/icons/expeditions_salvage` | `(255, 120, 160, 140)` |
| Tech-Remnants | `content/ui/materials/hud/interactions/icons/expeditions_loot` | `(255, 192, 160, 0)` |
| Dropped Tech-Remnants | `content/ui/materials/hud/interactions/icons/expeditions_loot` | `(220, 255, 0, 0)` |
| Bombing Run Signal Marker | `content/ui/materials/hud/interactions/icons/valkyrie_payload` | `(255, 95, 125, 70)` |
| Artillery Locator Beacon | `content/ui/materials/hud/interactions/icons/artillery_strike` | `(255, 95, 125, 70)` |
| Modified Grenade | `content/ui/materials/hud/interactions/icons/big_fn_grenade` | `(255, 205, 156, 77)` |
| Fire-Support Signal Marker | `content/ui/materials/hud/interactions/icons/valkyrie_hover` | `(255, 95, 125, 70)` |
| Servo-Triggered Mine | `content/ui/materials/hud/interactions/icons/landmine_explosive` | `(255, 205, 156, 77)` |
| Purgation Snare | `content/ui/materials/hud/interactions/icons/landmine_fire` | `(255, 255, 110, 0)` |
| Voltaic Snare | `content/ui/materials/hud/interactions/icons/landmine_shock` | `(255, 80, 160, 255)` |
| Void Shell | `content/ui/materials/hud/interactions/icons/void_shield` | `(255, 181, 166, 66)` |

### Semantic recolors for regular markers

The remaining formerly white pickup icons were recolored so marker families read more clearly at a glance.

| Marker | ARGB | Note |
| --- | --- | --- |
| Ammo Tin | `(255, 240, 210, 80)` | Small ammo pickup |
| Ammo Stash | `(255, 240, 210, 80)` | Large ammo pickup |
| Large Ammunition Crate | `(255, 240, 210, 80)` | Expeditions ammo container |
| Deployable Ammo Crate | `(255, 240, 210, 80)` | Team deployable ammo |
| Grenade | `(255, 205, 156, 77)` | Grenade pickup |
| Pocketable Ammo Crate | `(255, 240, 210, 80)` | Ammo pickup family tint |
| Pocketable Medical Crate | `(255, 38, 205, 26)` | Medical supply tint |
| Medicae Station | `(255, 38, 205, 26)` | Environment medical interaction |
| Power Socket | `(255, 255, 245, 80)` | Environment power interaction |
| Heretic Idol | `(255, 150, 190, 60)` | Environment idol marker |

### Other recolored template families

| Base template | Variants in this readme | ARGB colors |
| --- | --- | --- |
| `content/ui/materials/icons/player_states/lugged` | Data Reliquary, Power Cell, Cryonic Rod, Moebian Pox Zetaphyte-13 Sample, Vacuum Capsule, Special Issue Ammo, Prismata Crystal Repository, Martyr's Skull Power Cell | `(255, 192, 160, 0)`, `(255, 0, 200, 200)`, `(255, 180, 220, 255)`, `(255, 150, 190, 60)`, `(255, 80, 85, 90)`, `(255, 95, 125, 70)`, `(255, 255, 70, 90)`, `(255, 255, 140, 0)` |
| `party_syringe` family | Concentration, Med, Combat, Celerity Stimms | `(255, 230, 192, 13)`, `(255, 38, 205, 26)`, `(255, 205, 51, 26)`, `(255, 0, 127, 218)` |
| Enemy accent brackets | Daemonhost, Monstrosity, Captain, Karnak Twins | `(220, 255, 0, 0)` |
| `content/ui/materials/icons/item_types/devices` | Mortis Relic | `(255, 110, 95, 125)` |
| `content/ui/materials/hud/interactions/icons/barrel_explosive` | Promethium Barrel | `(255, 255, 110, 0)` |
| `content/ui/materials/icons/circumstances/live_event_01` | Holy Relics | `(255, 192, 160, 0)` |
| `content/ui/materials/hud/interactions/icons/enemy` | Martyr's Skull, Tainted Skulls | `(255, 255, 215, 0)`, `(255, 150, 190, 60)` |

### Runtime-dynamic colors

Not every radar marker uses a fixed readme tint:

- **Teammates** use the class icon for the detected archetype and take their color from the active HUD slot color at runtime.
- **The radar center dot** also uses the local player's HUD color.

## Requirements

- **[Darktide Mod Framework](https://www.nexusmods.com/warhammer40kdarktide/mods/8)**
- **[Darktide Mod Loader](https://www.nexusmods.com/warhammer40kdarktide/mods/19)**

## Notes

- The radar is intended for active gameplay and suppresses itself outside valid runtime states such as hub and menu contexts.
- Expedition POIs are filtered to the active expedition section, and **Data Reliquary Harvesters** are only shown inside the relevant **Deadsider Sanctuary** where they can actually be used.
- Artwork-based markers now use localized **Artwork**, **Icon**, and **Off** dropdowns where supported, and older saved boolean settings are migrated automatically.
- The **Environment** group adds dedicated toggles for **Medicae Station**, **Power Socket**, and **Heretic Idol**.
- The highlighting option is visible in the configuration, but the actual highlighting behavior is still work in progress.
- Marker previews in this readme were generated from the included template assets and documentation images so the legend matches the mod's configured presentations as closely as possible.
- The gameplay screenshots in this readme were captured during an expedition mission and show both radar frame styles in live use.
- Localization entries are included for the new display-mode labels and the environment marker settings, so the new options show up consistently with the rest of the translated mod menu.

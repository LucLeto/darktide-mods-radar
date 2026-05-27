# Radar

Radar adds a compact, camera-oriented HUD radar for **Warhammer 40,000: Darktide**. It is built to surface the targets that matter most during live missions, nearby pickups, objective items, deployed support tools, environment interactables, expedition points of interest, teammates, player smart tags, tagged targets, supported ability-outlined enemies, and high-priority enemies, while keeping the presentation configurable from the mod options menu. A centered overview mode can also be toggled during missions when you need a wider tactical read.

## Feature Overview

- Tracks nearby pickups, materials, mission items, deployables, environment interactables, live-event pickups and objectives, expedition POIs, teammates, player smart tags, tagged targets, supported ability-outlined enemies, and high-priority enemies on a single camera-oriented radar or the temporary centered overview.
- Supports **Square**, **Circle**, and **Auspex** radar styles. Square and Circle use configurable **outline** and **guide** options, including the Auspex background guide, while **Auspex** adds its dedicated scanner frame treatment.
- Lets you tune **radar size**, normal radar **range**, centered overview **zoom range**, **Radar Colors**, **maximum marker count**, **nearby highlight range**, supported vertical arrow and hiding behavior, and the dedicated nearby-highlight presentation settings.
- Supports per-category **Icon size (%)** sliders across item, player, enemy, event, and debug marker groups, plus dedicated enemy sub-category scaling.
- Supports separate display, range, and vertical arrow controls for **bosses**, **enemy groups**, **teammates**, **player smart tags**, **tagged-only enemy and item filtering**, supported **ability outlines**, and the local **player center dot**, including **Infinite** marker range modes for bosses and teammates.
- Includes mission-ready keybinds for **toggle radar on or off**, **toggle overview mode**, temporary radar zoom, and radar movement, plus per-mode enable toggles for **Regular Missions**, **Havoc**, **Mortis Trials**, and **Expeditions**.
- Supports anchor-based **radar positioning** with offsets, movement keybinds, configurable movement step size, and an optional unrestricted positioning fallback for ultrawide or advanced layouts.
- Supports **Artwork**, **Icon**, and **Off** display modes for the supported artwork-based pickup families, with automatic migration from older boolean settings.
- Adds optional nearby screen-space highlight brackets for supported non-enemy marker groups, with configurable thickness, per-marker highlight colors, and optional distance labels on the screen highlight, the radar marker, or both.
- Adds dedicated **Expedition POI** support for numbered **Sites of Interest**, **Deadsider Sanctuaries**, **Data Reliquary Harvesters**, **Main Objective**, **Valkyrie Extraction Zone**, and **Valkyrie Arrival Zone**, with per-category **Icon only**, **Icon + Distance m**, and **Off** display modes.
- Supports tech-remnant loot modes for **Default**, **Scale by value**, and **Merge nearby piles**, plus optional cluster value text and radius tuning.
- Includes optional distance text for bosses, player tags, nearby marker highlights, and expedition POIs, per-enemy-category vertical arrow toggles, **Infinite** boss and teammate range modes, **debug logs**, and an **unknown pickups** toggle for discovery and troubleshooting.

## Optional enhanced settings menu

Radar supports optional menu enhancements from [Alf's Mod Settings Extensions](https://www.nexusmods.com/warhammer40kdarktide/mods/864).

When installed, Radar's settings menu is organized into curated tabs with clearer sub-sections and improved widgets where supported. Radar does not require this extension and continues to work normally with plain [DMF](https://www.nexusmods.com/warhammer40kdarktide/mods/8).

## In-Game Radar Examples

The screenshots below show the live radar styles in gameplay. Together they illustrate the camera-oriented layout, mixed pickup categories, teammate markers, expedition POIs, smart tag support, priority targets, and the optional centered overview mode.

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

### Auspex Radar

The **Auspex** style provides a more diegetic scanner look. It supports the same gameplay marker data as the other radar styles, plus an optional animated sweep that can be disabled independently. In 2.2.0, the Auspex scanner background can also be selected as a guide option for Square and Circle radar styles.

<p>
  <img src="doc/img/auspex_radar_solid.gif" width="24%" alt="Auspex radar solid variant" />
  <img src="doc/img/auspex_radar_dotted.gif" width="24%" alt="Auspex radar dotted variant" />
  <img src="doc/img/auspex_radar_off.gif" width="24%" alt="Auspex radar outline off variant" />
  <img src="doc/img/auspex_radar_no_sweep.gif" width="24%" alt="Auspex radar with sweep disabled" />
</p>

### Centered overview mode

The keybind-based **centered overview mode** temporarily expands the radar into a larger centered tactical view. It uses its own zoom range from **25 m** to **500 m**, can show scale legends beside the radar, and has a separate marker cap so dense overview scans can be tuned independently from the normal radar.

### Nearby highlight example

Nearby highlights add small screen-space brackets for supported non-enemy markers when they are close enough to matter. You can tune their thickness, set per-marker highlight colors with ARGB sliders, and show item distance text on the screen highlight, the radar marker, or both.

<p>
  <img src="doc/img/highlight_example.png" width="70%" alt="Nearby highlight example" />
</p>

### Vertical item and enemy arrows

Vertical arrows add a small **up** or **down** overlay to supported markers when the target is on a different level but still close enough horizontally to matter. Item markers can use this behavior globally, and enemy markers can now use it per enemy category: **Boss**, **Horde**, **Common**, **Shooter**, **Elite**, **Special**, and **Misc**.

The arrow range and vertical hiding threshold remain global, so enemy arrows reuse the same distance behavior as supported item arrows without adding separate per-category hiding rules.

<p>
  <img src="doc/img/material_expeditions_loot.png" width="50" alt="Same-level item marker example" />
  <img src="doc/img/material_expeditions_loot_up.png" width="50" alt="Item marker with up arrow example" />
  <img src="doc/img/material_expeditions_loot_down.png" width="50" alt="Item marker with down arrow example" />
</p>

## Display and Behavior

**Square** and **Circle** radar styles support the same outline and guide options, and the frame rendering is tuned so crosshairs fit the active frame, view guides reach the border cleanly, circle range rings stay thin and solid, circle outlines remain visually continuous, and square dotted outlines render as proper dots.

The **Auspex** style still provides its own frame treatment, and the same scanner background can also be used as an **Auspex background** guide on Square or Circle radar styles. The animated sweep toggle applies to both.

The centered overview mode reuses the active radar presentation but moves it to the center of the screen and expands it up to the available UI space. Overview zoom is separate from the normal radar range, so you can briefly scan a wider area without permanently changing the compact HUD radar.

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

## Expedition POI display modes

Expedition POI settings use dropdown display modes instead of simple on/off toggles. Each supported POI category can be configured independently.

- **Icon only** shows the POI icon without distance text.
- **Icon + Distance m** shows the POI icon together with its current distance in meters.
- **Off** hides that POI category.
- Existing saved boolean settings are migrated automatically, with old `true` values becoming **Icon only** and old `false` values becoming **Off**.

| POI category | Default display mode |
| --- | --- |
| Sites of Interest | **Icon + Distance m** |
| Deadsider Sanctuaries | **Icon only** |
| Data Reliquary Harvesters | **Icon only** |
| Main Objective | **Icon only** |
| Valkyrie Extraction Zone | **Icon only** |
| Valkyrie Arrival Zone | **Icon only** |

## Artwork, Icon, Off display modes

Supported artwork-based markers now use dropdowns instead of simple booleans. Each supported marker can be shown as **Artwork**, **Icon**, or **Off**.

- **Artwork** uses the original item artwork or pickup art.
- **Icon** uses a simplified HUD icon material with a configurable ARGB tint.
- **Off** hides that specific marker entirely.
- Existing saved boolean settings are migrated automatically, with old `true` values becoming **Artwork** and old `false` values becoming **Off**.

### Common pickups and materials

| Marker | Artwork | Icon | Off |
| --- | --- | --- | --- |
| Crates | <img src="doc/img/crate_unknown.png"  width="80" alt="Crate artwork mode" /> | <img src="doc/img/crate_unknown_alternative.png"  width="80" alt="Crate icon mode" /> | Hidden |
| Diamantine | <img src="doc/img/material_diamantine.png"  width="80" alt="Diamantine artwork mode" /> | <img src="doc/img/material_diamantine_alternative.png"  width="80" alt="Diamantine icon mode" /> | Hidden |
| Plasteel | <img src="doc/img/material_plasteel.png"  width="80" alt="Plasteel artwork mode" /> | <img src="doc/img/material_plasteel_alternative.png"  width="80" alt="Plasteel icon mode" /> | Hidden |

### Expeditions-specific items with display modes

| Marker | Artwork | Icon | Off |
| --- | --- | --- | --- |
| Salvage | <img src="doc/img/material_expeditions_currency.png"  width="80" alt="Salvage artwork mode" /> | <img src="doc/img/material_expeditions_currency_alternative.png"  width="80" alt="Salvage icon mode" /> | Hidden |
| Tech-Remnants | <img src="doc/img/material_expeditions_loot.png"  width="80" alt="Tech-Remnants artwork mode" /> | <img src="doc/img/material_expeditions_loot_alternative.png"  width="80" alt="Tech-Remnants icon mode" /> | Hidden |
| Dropped Tech-Remnants | <img src="doc/img/material_expeditions_loot_player_drop.png"  width="80" alt="Dropped Tech-Remnants artwork mode" /> | <img src="doc/img/material_expeditions_loot_player_drop_alternative.png"  width="80" alt="Dropped Tech-Remnants icon mode" /> | Hidden |
| Servo-Triggered Mine | <img src="doc/img/pocketable_landmine_explosive.png"  width="80" alt="Explosive mine artwork mode" /> | <img src="doc/img/pocketable_landmine_explosive_alternative.png"  width="80" alt="Explosive mine icon mode" /> | Hidden |
| Purgation Snare | <img src="doc/img/pocketable_landmine_fire.png"  width="80" alt="Fire mine artwork mode" /> | <img src="doc/img/pocketable_landmine_fire_alternative.png"  width="80" alt="Fire mine icon mode" /> | Hidden |
| Voltaic Snare | <img src="doc/img/pocketable_landmine_shock.png"  width="80" alt="Shock mine artwork mode" /> | <img src="doc/img/pocketable_landmine_shock_alternative.png"  width="80" alt="Shock mine icon mode" /> | Hidden |
| Void Shell | <img src="doc/img/pocketable_void_shield.png"  width="80" alt="Void Shell artwork mode" /> | <img src="doc/img/pocketable_void_shield_alternative.png"  width="80" alt="Void Shell icon mode" /> | Hidden |
| Bombing Run Signal Marker | <img src="doc/img/pocketable_airstrike.png"  width="80" alt="Airstrike artwork mode" /> | <img src="doc/img/pocketable_airstrike_alternative.png"  width="80" alt="Airstrike icon mode" /> | Hidden |
| Artillery Locator Beacon | <img src="doc/img/pocketable_artillery_strike.png"  width="80" alt="Artillery artwork mode" /> | <img src="doc/img/pocketable_artillery_strike_alternative.png"  width="80" alt="Artillery icon mode" /> | Hidden |
| Modified Grenade | <img src="doc/img/pocketable_big_grenade.png"  width="80" alt="Modified grenade artwork mode" /> | <img src="doc/img/pocketable_big_grenade_alternative.png"  width="80" alt="Modified grenade icon mode" /> | Hidden |
| Fire-Support Signal Marker | <img src="doc/img/pocketable_valkyrie_hover.png"  width="80" alt="Valkyrie hover artwork mode" /> | <img src="doc/img/pocketable_valkyrie_hover_alternative.png"  width="80" alt="Valkyrie hover icon mode" /> | Hidden |

### Tech-Remnant cluster example

The example below shows **Tech-Remnant marker mode** set to **Merge nearby piles**. In this mode, nearby piles are combined into a single clustered radar marker, which helps reduce clutter in dense expedition loot areas.
Also for reference **Show tech-remnant value text** is set to **true**.

<p>
  <img src="doc/img/tech-remnants_scale_amount_example.png" width="70%" alt="Tech-Remnant cluster example with Merge nearby piles enabled" />
</p>

## Radar Controls

| Option | What it controls |
| --- | --- |
| Enable radar | Master on or off switch for the HUD element. |
| Enable in Regular Missions | Enables or disables the radar for standard mission runs. |
| Enable in Havoc | Enables or disables the radar in Havoc. |
| Enable in Mortis Trials | Enables or disables the radar in Mortis Trials. |
| Enable in Expeditions | Enables or disables the radar in Expeditions. |
| Toggle radar on or off | Assign a key to switch the radar HUD visibility during gameplay without opening the options menu. |
| Toggle overview mode | Assign a key to switch the centered overview mode on or off during gameplay. |
| Radar zoom modifier | Hold this key to make the radar zoom keybinds control the normal radar instead of only overview mode. While held, shared zoom inputs such as mouse wheel are captured for radar zoom only. |
| Radar zoom in | Zooms the radar in. Works in overview mode, or on the normal radar while the radar zoom modifier is held. |
| Radar zoom out | Zooms the radar out. Works in overview mode, or on the normal radar while the radar zoom modifier is held. |
| Reset radar zoom | In overview mode, fits the overview scale to the currently rendered normal-range markers. On the normal radar, hold the radar zoom modifier and press this key to reset to **10 m / 2.0x**. |
| Show scale legends | Shows overview scale legends next to the radar while centered overview mode is active. |
| Radar size | Adjustable from **100** to **1200**. |
| Radar range / filter distance | Adjustable from **10 m** to **200 m** for the normal radar. |
| Show vertical arrows within range (m) | Adjustable from **25 m** to **100 m**. Supported item markers and enemy markers with vertical arrows enabled show a small **up** or **down** arrow when they are on another level and still within this horizontal range. |
| Hide vertical markers above/below (m) | Adjustable from **8 m** to **50 m**. Supported item markers and enemy markers with vertical arrows enabled are hidden when their vertical separation is larger than this value. |
| Max radar markers | Adjustable from **10** to **200** for the normal radar. |
| Max overview markers | Adjustable from **100** to **300** for centered overview mode. |
| Scale icons with radar size | Keeps marker size fixed or scales it with the radar. The final combined icon size is capped at **4.0x**. |
| Radar style | **Square**, **Circle**, or **Auspex**. |
| Radar outline | **Solid**, **Dotted**, or **Off**. Only used by the **Square** and **Circle** radar styles. |
| Radar guides | **Crosshair**, **View guides**, **Range rings**, **Auspex**, or **Off**. Only used by the **Square** and **Circle** radar styles. |
| Radar Colors | ARGB sliders for Radar UI colors such as background, outline, guides, Auspex layers, marker text, vertical arrows, and overview legend indicators. |
| Animated radar sweep | Enables or disables the animated sweep used by the **Auspex** radar style and **Auspex** guides. |
| Nearby highlight range (m) | Adjustable from **5 m** to **20 m**. Controls how close supported items must be before their screen-space bracket highlights appear. |
| Highlight thickness | Adjusts the line thickness used by nearby screen-space highlight brackets. |
| Show distance above nearby highlights | Shows item distance text above supported nearby screen-space highlights. |
| Show distance on radar markers | Shows distance text on supported nearby radar markers. |
| Boss marker style | **Icon only** or **Marked icon**. |
| Boss marker range | **Normal** or **Infinite**. Lets boss-type markers follow the normal radar range or stay visible at any distance. |
| Show boss distance text | Shows yellow distance text in meters for bosses except the daemonhost. |
| Teammates | Shows or hides teammate markers on the radar. |
| Player marker range | **Normal** or **Infinite**. Lets teammate markers follow the normal radar range or stay visible at any distance. |
| Player center dot | Shows or hides your own center point on the radar. |
| Player marker style | **Icon only**, **Marked icon**, **Dot only**, or **Marked dot**. |
| Player Tags | Shows or hides player smart tags and pings on the radar. |
| Show player tag distance text | Shows the current distance in meters next to player tag markers. |
| Ability-marked enemies | Also includes supported ability-marked and smart-tag outlined enemies such as keystone, passive, and callout-driven outline states. |
| Tagged enemies only | Only shows enemy markers while the enemy has an active in-game tag. Tagged enemies also ignore the normal radar range limit while tagged. |
| Tagged items only | Only shows supported item markers while the item has an active in-game tag. Tagged items also ignore the normal radar range limit while tagged. |
| Player tag display style | **Icon only** or **Marked icon**. |
| Radar anchor | **Top left**, **Top right**, **Bottom left**, or **Bottom right**. Sets the corner the radar offsets from. |
| Allow unrestricted radar positioning | Removes the normal UI-space clamping fallback, which is useful for ultrawide or highly customized layouts. |
| Horizontal offset | Sets the radar's horizontal offset from the selected anchor. |
| Vertical offset | Sets the radar's vertical offset from the selected anchor. |
| Steps per input | Sets how far each radar movement key press nudges the radar. |
| Move radar left | Assign a key to move the radar left by the configured step size. |
| Move radar right | Assign a key to move the radar right by the configured step size. |
| Move radar up | Assign a key to move the radar up by the configured step size. |
| Move radar down | Assign a key to move the radar down by the configured step size. |


### Marker display mode controls

| Option group | Markers | Modes |
| --- | --- | --- |
| Common Pickups | Crates | **Artwork**, **Icon**, **Off** |
| Collectable Materials | Diamantine, Plasteel | **Artwork**, **Icon**, **Off** |
| Expeditions-Specific Items | Salvage, Tech-Remnants, Dropped Tech-Remnants, Servo-Triggered Mine, Purgation Snare, Voltaic Snare, Void Shell, Bombing Run Signal Marker, Artillery Locator Beacon, Modified Grenade, Fire-Support Signal Marker | **Artwork**, **Icon**, **Off** |
| Expedition POIs | Sites of Interest, Deadsider Sanctuaries, Data Reliquary Harvesters, Main Objective, Valkyrie Extraction Zone, Valkyrie Arrival Zone | **Icon only**, **Icon + Distance m**, **Off** |
| Enemy bosses | Daemonhost, Monstrosities, Captains, Karnak Twins | **Icon only**, **Marked icon** |
| Enemy groups | Common enemies and Shooters | **Icon only**, **Marked icon**, **Off** |
| Individual enemy toggles | Elite, Special, and Misc enemies listed below | **Icon only**, **Marked icon**, **Off** |

### Per-category icon size controls

Each major option group now includes an **Icon size (%)** slider. These sliders resize the whole marker family from **50%** to **300%**. When combined with **Scale icons with radar size**, the final rendered icon size is still capped at **4.0x**.

| Option group | Affects |
| --- | --- |
| Common Pickups | Crates, ammo, grenades, portable crates, and stimms |
| Collectable Materials | Diamantine and Plasteel |
| Primary Objective Items | Mission luggables and primary objective pickups |
| Secondary Objective Items | Grimoires and Scriptures |
| Expeditions POI | Sites of Interest, sanctuaries, harvesters, main objective, extraction, and arrival markers |
| Expeditions-Specific Items | Salvage, Tech-Remnants, expedition pocketables, and related expedition pickups |
| Martyr's Skull Items | Martyr's Skull markers and related power cell markers |
| Environment | Medicae Station, Power Socket, and Heretic Idol |
| Deployed Items | Ammo Crate and Medical Crate deployables |
| Enemies | High-priority boss markers |
| Enemy Boss | Daemonhost, Monstrosities, Captains, Karnak Twins |
| Enemy Horde | Horde enemies |
| Enemy Common | Common enemies |
| Enemy Shooter | Shooter enemies |
| Enemy Elite | Elite enemies |
| Enemy Special | Special enemies |
| Enemy Misc | Ritualists |
| Players | Teammate markers |
| Event-Related Items | Event pickups and event objectives, including Dark Rites totems and servo skulls |
| Debugging | Unknown pickup markers and debug visuals |

### Enemy radar controls

| Option | What it controls |
| --- | --- |
| Monstrosities | Shows daemonhost and generic monstrosity markers. |
| Ability-marked enemies | Also includes enemies while they have a supported ability or smart-tag outline, subject to the normal enemy display rules. |
| Captains | Shows captain markers. |
| Karnak Twins | Shows the dedicated Karnak Twins marker. |
| Horde enemies | Single toggle for horde markers. Horde enemies stay on or off rather than using per-unit display modes. |
| Common enemies | Shared display-style dropdown for common enemy markers. |
| Shooters | Shared display-style dropdown for shooter enemy markers. |
| Elite enemies | Per-unit display-style dropdowns for Dreg Gunners, Ragers, Shotgunners, Scab Gunners, Maulers, Plasma Gunners, Ragers, Shotgunners, and Ogryn elites. |
| Special enemies | Per-unit display-style dropdowns for Bombers, Flamers, Mutants, Poxbursters, Hounds, Snipers, and Trappers. |
| Ritualist | Dedicated toggle under the misc enemy category. |

### Enemy vertical arrow controls

Enemy vertical arrows are controlled per enemy category. These options only control whether the **up** or **down** arrow overlay can be shown for that category. They do not change the core marker visibility, display style, range mode, or tagged-only behavior.

| Option | What it controls |
| --- | --- |
| Show boss vertical arrows | Enables vertical arrows for daemonhost, monstrosity, captain, and Karnak Twin markers. |
| Show horde vertical arrows | Enables vertical arrows for horde enemy markers. |
| Show common enemy vertical arrows | Enables vertical arrows for common enemy markers. |
| Show shooter vertical arrows | Enables vertical arrows for shooter enemy markers. |
| Show elite vertical arrows | Enables vertical arrows for elite enemy markers. |
| Show special vertical arrows | Enables vertical arrows for special enemy markers. |
| Show misc enemy vertical arrows | Enables vertical arrows for misc enemy markers, currently Ritualists. |

All enemy vertical arrow options use the shared **Show vertical arrows within range (m)** and **Hide vertical markers above/below (m)** settings.

### Nearby highlight controls

| Option | What it controls |
| --- | --- |
| Highlight thickness | Adjusts the line thickness used by nearby screen-space highlight brackets. |
| Marker highlight color sliders | Set the Opacity, Red, Green, and Blue channels used directly by nearby highlights for a specific supported marker group. |
| Show distance above nearby highlights | Shows item distance text above supported nearby screen-space highlights. |
| Show distance on radar markers | Shows distance text on supported nearby radar markers. |

| Option group | What it controls |
| --- | --- |
| Common Pickups | Highlights nearby ammo, grenades, crates, portable crates, and stimms. |
| Collectable Materials | Highlights nearby diamantine and plasteel. |
| Primary Objective Items | Highlights nearby mission luggables and main objective pickups. |
| Secondary Objective Items | Highlights nearby grimoires and scriptures. |
| Expeditions-Specific Items | Highlights nearby salvage, tech-remnants, expedition pocketables, and related expedition pickups. |
| Martyr's Skull Items | Highlights nearby martyr's skull items and their orange power cell markers. |
| Environment | Highlights nearby medicae stations, power sockets, and heretic idols. |
| Event-Related Items | Highlights nearby event pickups and event objectives, including Dark Rites totems and servo skulls. |

### Tech-Remnant controls

| Option | What it controls |
| --- | --- |
| Tech-Remnant marker mode | **Default**, **Scale by value**, or **Merge nearby piles**. |
| Show cluster value | Shows a value badge on clustered tech-remnant markers. |
| Cluster horizontal radius | Horizontal merge range for clustered tech-remnant markers. |
| Cluster vertical radius | Vertical merge range for clustered tech-remnant markers. |

### Expedition POI Controls

| Option | Modes / default | What it controls |
| --- | --- | --- |
| Expeditions POI | Option group | Contains independent display mode dropdowns for expedition location markers. |
| Ignore range limit for POI | Checkbox, default on | Lets expedition POI markers bypass the normal radar range filter. |
| Sites of Interest | **Icon only**, **Icon + Distance m**, **Off**. Default: **Icon + Distance m**. | Controls registered expedition opportunity locations, including numbered scanner-map opportunity markers. |
| Deadsider Sanctuaries | **Icon only**, **Icon + Distance m**, **Off**. Default: **Icon only**. | Controls expedition transition or sanctuary locations with the dedicated transition icon. |
| Data Reliquary Harvesters | **Icon only**, **Icon + Distance m**, **Off**. Default: **Icon only**. | Controls expedition loot converters with the dedicated harvester icon while inside the sanctuary where they are usable, and clears stale harvester markers across sanctuary transitions. |
| Main Objective | **Icon only**, **Icon + Distance m**, **Off**. Default: **Icon only**. | Controls expedition main objective locations with the dedicated objective icon. |
| Valkyrie Extraction Zone | **Icon only**, **Icon + Distance m**, **Off**. Default: **Icon only**. | Controls extraction points with the dedicated extraction icon. |
| Valkyrie Arrival Zone | **Icon only**, **Icon + Distance m**, **Off**. Default: **Icon only**. | Controls arrival points with the dedicated arrival icon. |

### Environment Controls

| Option | What it controls |
| --- | --- |
| Environment | Group of toggles for interactable world objects that are useful to spot on the radar. |
| Medicae Station | Shows medicae station and equivalent health station interactions. |
| Power Socket | Shows luggable power socket targets. |
| Heretic Idol | Shows active heretic idols while they are still present. |

### Event Controls

| Option | What it controls |
| --- | --- |
| Event-Related Items | Group of toggles for live-event pickups and event objectives. |
| Tainted Skulls | Shows tainted skull pickups from skull live-event circumstances. |
| Dark Rites Totems | Shows destroyable Dark Rites ritual totems while they are still active. |
| Dark Rites Servo Skulls | Shows the spawned Dark Rites servo skull objective interactable. |
| Tainted Communications Device | Shows corrupted auspex scanner event pickups. |
| Holy Relics | Shows Holy Relics event pickups. |
| Stolen Rations | Shows Stolen Rations event pickups. |

### Positioning and Toggle Use

- Use **Toggle radar on or off** for quick in-mission HUD control, or the per-mode enable toggles if you want Radar active only in selected activities.
- Use **Toggle overview mode** when you need a temporary centered tactical scan without changing your normal anchored radar placement.
- Use **Radar zoom in**, **Radar zoom out**, and **Reset radar zoom** in overview mode to control the overview scale. Hold **Radar zoom modifier** to apply those same zoom controls to the normal radar instead.
- Use **Radar anchor**, **Horizontal offset**, and **Vertical offset** for stable placement, then fine-tune with the movement keybinds and **Steps per input**.
- Standard placement stays clamped to the visible UI space, while **Allow unrestricted radar positioning** is available for ultrawide or advanced layouts.

### Marker Rules

- **Enemies**, **teammates**, and **player smart tags** each use their own display rules and style settings. Teammates also have a **Player marker range** mode, so they can follow the normal radar range or remain visible at any distance. The local **center dot** has its own toggle and is not affected by teammate range mode.
- Supported enemies can also be surfaced through active ability-mark or smart-tag outline states when **Ability-marked enemies** is enabled.
- **Tagged enemies only** and **Tagged items only** restrict visibility to actively tagged targets, and those tagged targets ignore the usual radar range limit while the tag remains active.
- Supported item markers and enemy markers from enabled enemy categories can show vertical **up** and **down** arrows. They use the shared vertical arrow range and shared vertical hide threshold, while nearby highlight brackets and optional distance text remain item-focused presentation features.
- Event-related markers use elevated marker priority so event objectives stay visible when dense enemy markers are nearby.
- **Expedition POIs**, **environment markers**, and **tech-remnant clusters** follow their own category-specific rules so outdated markers clear correctly and context-sensitive markers only appear when relevant.
- Expedition POIs can be shown as **Icon only**, **Icon + Distance m**, or **Off** per category. Existing boolean settings migrate to **Icon only** for enabled markers and **Off** for disabled markers.
- Expedition section filtering also handles **Deadsider Sanctuary** transitions. Store fixtures and sanctuary-only markers are cleared when moving back into open expedition zones, while active player-dropped Tech-Remnants remain eligible for radar display.

## Target Markers

The legend below follows the option groups exposed by `Radar_data.lua`. Enemy markers are listed in the same gameplay-oriented order used by the enemy settings: bosses, horde, common, shooters, elites, specials, and misc. Each enemy category can also enable vertical **up** and **down** arrows independently. The preview tiles were generated from the included `doc/img` assets and the default ARGB values used by the HUD presentations.

### Ability outline and smart-tag examples

These examples show supported outline states that can optionally count as radar-visible enemy targets when **Ability-marked enemies** is enabled.

| Preview | Source | Notes                                                                                                                            |
| --- | --- |----------------------------------------------------------------------------------------------------------------------------------|
| <img src="doc/img/adamant_mark_target.png" width="80" alt="Adamant marked target outline" /> | Adamant mark target | Example of Arbitrator's "Execution Order" target outline.                                                                        |
| <img src="doc/img/adamant_smart_tag.png" width="80" alt="Adamant smart tag outline" /> | Adamant smart tag | Example of a Cyber-Mastiff attack order style outline state.                                                                     |
| <img src="doc/img/broker_proximity_target.png" width="80" alt="Broker proximity target outline" /> | Broker proximity target | Example of a Hive Scum's "Enhanced Desperado" outline state.                                                                     |
| <img src="doc/img/psyker_marked_target.png" width="80" alt="Psyker marked target outline" /> | Psyker marked target | Example of a Psyker's "Disrupt Destiny" effect.                                                                                  |
| <img src="doc/img/veteran_smart_tag.png" width="80" alt="Veteran smart tag outline" /> | Veteran smart tag | Example of a Veteran's "Focus Target!" outline state.                                                                            |
| <img src="doc/img/veteran_special_target.png" width="80" alt="Veteran special target outline" /> | Veteran special target | Example of a Veteran's "Executioner's Stance" outline state, with local-owning-context gating to avoid unrelated shared outlines. |

### High-Priority Enemies

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/enemy_daemonhost.png"  width="80" alt="Daemonhost marker" /> | Daemonhost | Separate presentation under the **Monstrosities** toggle. It uses the boss marker style settings, but does **not** show boss distance text. |
| <img src="doc/img/enemy_monstrosity.png"  width="80" alt="Monstrosity marker" /> | Monstrosities | Covers the generic monstrosity presentation used for Beast of Nurgle, Plague Ogryn, Chaos Spawn, and Ogryn Houndmaster. **Boss marker range** can be set to **Normal** or **Infinite**, and optional boss distance text is supported. |
| <img src="doc/img/enemy_captain.png"  width="80" alt="Captain marker" /> | Captains | Red danger marker with bracket accent in marked mode. |
| <img src="doc/img/enemy_karnak_twin.png"  width="80" alt="Karnak Twins marker" /> | Karnak Twins | Dedicated presentation for the twins. |

Display style example for boss and enemy markers:

<p>
  <img src="doc/img/enemy_icon_only_sample.png"  width="80" alt="Enemy icon only example" />
  <img src="doc/img/enemy_monstrosity.png"  width="80" alt="Enemy marked icon example" />
</p>

Left: **Icon only**. Right: **Marked icon**.

### Horde Enemies

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/horde.png"  width="80" alt="Horde enemy marker" /> | Horde enemies | Shared horde presentation used for Groaners, Moebian 21st infantry, Poxwalkers, lesser mutated poxwalkers, mutated poxwalkers, and related horde-only infected. Horde enemies use a single on or off toggle plus the **Enemy Horde** size slider. |

### Common Enemies

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/cultist_melee.png"  width="80" alt="Dreg Bruiser marker" /> | Dreg Bruiser | Individual common enemy display-style dropdown. |
| <img src="doc/img/renegade_melee.png"  width="80" alt="Scab Bruiser marker" /> | Scab Bruiser | Individual common enemy display-style dropdown. |

### Shooter Enemies

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/cultist_assault.png"  width="80" alt="Dreg Stalker marker" /> | Dreg Stalker | Individual shooter enemy display-style dropdown. |
| <img src="doc/img/renegade_assault.png"  width="80" alt="Scab Stalker marker" /> | Scab Stalker | Individual shooter enemy display-style dropdown. |
| <img src="doc/img/renegade_rifleman.png"  width="80" alt="Scab Shooter marker" /> | Scab Shooter | Individual shooter enemy display-style dropdown. |

### Elite Enemies

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/cultist_gunner.png"  width="80" alt="Dreg Gunner marker" /> | Dreg Gunner | Individual elite enemy toggle. |
| <img src="doc/img/cultist_berzerker.png"  width="80" alt="Dreg Rager marker" /> | Dreg Rager | Individual elite enemy toggle. |
| <img src="doc/img/cultist_shocktrooper.png"  width="80" alt="Dreg Shotgunner marker" /> | Dreg Shotgunner | Individual elite enemy toggle. |
| <img src="doc/img/renegade_gunner.png"  width="80" alt="Scab Gunner marker" /> | Scab Gunner | Individual elite enemy toggle. |
| <img src="doc/img/renegade_radio_operator.png"  width="80" alt="Scab Gunner mutator variant marker" /> | Scab Gunner, mutator variant | Uses the same toggle and scale settings as **Scab Gunner**. |
| <img src="doc/img/renegade_executor.png"  width="80" alt="Scab Mauler marker" /> | Scab Mauler | Individual elite enemy toggle. |
| <img src="doc/img/renegade_plasma_gunner.png"  width="80" alt="Scab Plasma Gunner marker" /> | Scab Plasma Gunner | Individual elite enemy toggle. |
| <img src="doc/img/renegade_berzerker.png"  width="80" alt="Scab Rager marker" /> | Scab Rager | Individual elite enemy toggle. |
| <img src="doc/img/renegade_shocktrooper.png"  width="80" alt="Scab Shotgunner marker" /> | Scab Shotgunner | Individual elite enemy toggle. |
| <img src="doc/img/chaos_ogryn_bulwark.png"  width="80" alt="Ogryn Bulwark marker" /> | Ogryn - Bulwark | Individual elite enemy toggle. |
| <img src="doc/img/chaos_ogryn_executor.png"  width="80" alt="Ogryn Crusher marker" /> | Ogryn - Crusher | Individual elite enemy toggle. |
| <img src="doc/img/chaos_ogryn_gunner.png"  width="80" alt="Ogryn Reaper marker" /> | Ogryn - Reaper | Individual elite enemy toggle. |

### Special Enemies

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/renegade_grenadier.png"  width="80" alt="Scab Bomber marker" /> | Scab Bomber | Individual special enemy toggle. |
| <img src="doc/img/cultist_grenadier.png"  width="80" alt="Dreg Tox Bomber marker" /> | Dreg Tox Bomber | Individual special enemy toggle. |
| <img src="doc/img/renegade_flamer.png"  width="80" alt="Scab Flamer marker" /> | Scab Flamer | Individual special enemy toggle. |
| <img src="doc/img/renegade_flamer_mutator.png"  width="80" alt="Scab Flamer mutator variant marker" /> | Scab Flamer, mutator variant | Uses the same toggle and scale settings as **Scab Flamer**. |
| <img src="doc/img/cultist_flamer.png"  width="80" alt="Dreg Tox Flamer marker" /> | Dreg Tox Flamer | Individual special enemy toggle. |
| <img src="doc/img/cultist_mutant.png"  width="80" alt="Mutant marker" /> | Mutant | Individual special enemy toggle. |
| <img src="doc/img/chaos_hound.png"  width="80" alt="Pox Hound marker" /> | Pox Hound | Individual special enemy toggle. |
| <img src="doc/img/chaos_hound_mutator.png"  width="80" alt="Pox Hound mutator variant marker" /> | Pox Hound, mutator variant | Uses the same toggle and scale settings as **Pox Hound**. |
| <img src="doc/img/chaos_armored_hound.png"  width="80" alt="Armored Pox Hound marker" /> | Armored Pox Hound | Individual special enemy toggle. |
| <img src="doc/img/chaos_poxwalker_bomber.png"  width="80" alt="Poxburster marker" /> | Poxburster | Individual special enemy toggle. The default display style is **Marked icon**. |
| <img src="doc/img/renegade_sniper.png"  width="80" alt="Sniper marker" /> | Sniper | Individual special enemy toggle. |
| <img src="doc/img/renegade_netgunner.png"  width="80" alt="Trapper marker" /> | Trapper | Individual special enemy toggle. |

Poxburster style example:

<p>
  <img src="doc/img/chaos_poxwalker_bomber.png"  width="80" alt="Poxburster icon only example" />
  <img src="doc/img/chaos_poxwalker_bomber_marked.png"  width="80" alt="Poxburster marked icon example" />
</p>

Left: **Icon only**. Right: **Marked icon**.

### Misc Enemies

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/chaos_ritualist.png"  width="80" alt="Ritualist marker" /> | Ritualist | Dedicated misc enemy toggle with its own **Enemy Misc** size slider. |

### Teammates

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/player_teammate_sample.png"  width="80" alt="Teammate marker sample" /> | Teammates | Uses class icons, colored by teammate slot at runtime. Can be shown as **Icon only**, **Marked icon**, **Dot only**, or **Marked dot**. **Player marker range** can be set to **Normal** or **Infinite**, and teammate visibility can be toggled independently from the local player center dot. |

Display style example for teammate markers:

<p>
  <img src="doc/img/player_teammate_icon_only_sample.png"  width="80" alt="Teammate icon only example" />
  <img src="doc/img/player_teammate_sample.png"  width="80" alt="Teammate marked icon example" />
  <img src="doc/img/player_teammate_dot_only_sample.png"  width="80" alt="Teammate dot only example" />
  <img src="doc/img/player_teammate_marked_dot_sample.png"  width="80" alt="Teammate marked dot example" />
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

### Player Tags

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/player_tag_enemy_marked.png" width="80" alt="Enemy player tag marker" /> | Enemy | Radar support for enemy callout tags. Uses the dedicated **Player tag display style** setting and can optionally show distance text. |
| <img src="doc/img/player_tag_go_there_marked.png" width="80" alt="Go there player tag marker" /> | Go There | Radar support for movement and positioning callouts placed by players. |
| <img src="doc/img/player_tag_look_there_marked.png" width="80" alt="Look there player tag marker" /> | Look There | Radar support for attention and look-here callouts placed by players. |

Display style example for player tags:

| Tag | Icon only | Marked icon |
| --- | --- | --- |
| Enemy | <img src="doc/img/player_tag_enemy.png" width="80" alt="Enemy player tag icon only" /> | <img src="doc/img/player_tag_enemy_marked.png" width="80" alt="Enemy player tag marked icon" /> |
| Go There | <img src="doc/img/player_tag_go_there.png" width="80" alt="Go there player tag icon only" /> | <img src="doc/img/player_tag_go_there_marked.png" width="80" alt="Go there player tag marked icon" /> |
| Look There | <img src="doc/img/player_tag_look_there.png" width="80" alt="Look there player tag icon only" /> | <img src="doc/img/player_tag_look_there_marked.png" width="80" alt="Look there player tag marked icon" /> |

Player tags intentionally stay flatter and cleaner than supported item markers. They do not use the item-style elevation arrow presentation.

### Common Pickups

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/crate_unknown.png"  width="80" alt="Crate marker" /> | Crates | Supports **Artwork**, **Icon**, and **Off**. Artwork keeps the pickup art, icon mode uses a simplified loot icon. |
| <img src="doc/img/pickup_ammo_small.png"  width="80" alt="Ammo tin marker" /> | Ammo Tin | Small ammo pickup, recolored with an ammo-specific yellow. |
| <img src="doc/img/pickup_ammo_big.png"  width="80" alt="Ammo stash marker" /> | Ammo Stash | Large ammo pickup, recolored with an ammo-specific yellow. |
| <img src="doc/img/pickup_grenade.png"  width="80" alt="Grenade marker" /> | Grenade | Uses a warm grenade-specific amber tint. |
| <img src="doc/img/pocketable_ammo_crate.png"  width="80" alt="Ammo crate marker" /> | Ammo Crate | Pocketable ammo crate, recolored to match the ammo family. |
| <img src="doc/img/pocketable_medical_crate.png"  width="80" alt="Medical crate marker" /> | Medical Crate | Pocketable medical crate with a medicae green tint. |
| <img src="doc/img/pocketable_syringe_ability.png"  width="80" alt="Concentration Stimm marker" /> | Concentration Stimm | Recolored syringe template. |
| <img src="doc/img/pocketable_syringe_corruption.png"  width="80" alt="Med Stimm marker" /> | Med Stimm | Recolored syringe template. |
| <img src="doc/img/pocketable_syringe_power.png"  width="80" alt="Combat Stimm marker" /> | Combat Stimm | Recolored syringe template. |
| <img src="doc/img/pocketable_syringe_speed.png"  width="80" alt="Celerity Stimm marker" /> | Celerity Stimm | Recolored syringe template. |

### Collectable Materials

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/material_diamantine.png"  width="80" alt="Diamantine marker" /> | Diamantine | Supports **Artwork**, **Icon**, and **Off**. Icon mode uses a simplified blue material icon. |
| <img src="doc/img/material_plasteel.png"  width="80" alt="Plasteel marker" /> | Plasteel | Supports **Artwork**, **Icon**, and **Off**. Icon mode uses a simplified steel-grey material icon. |

### Primary Objective Items

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/luggable_power_cell_teal.png"  width="80" alt="Power Cell marker" /> | Power Cell | Teal luggable objective marker. |
| <img src="doc/img/luggable_cryonic_rod.png"  width="80" alt="Cryonic Rod marker" /> | Cryonic Rod | Pale ice-blue luggable marker. |
| <img src="doc/img/luggable_moebian_pox_zetaphyte_13_sample.png"  width="80" alt="Moebian Pox Zetaphyte-13 Sample marker" /> | Moebian Pox Zetaphyte-13 Sample | Sickly green luggable marker. |
| <img src="doc/img/luggable_vacuum_capsule.png"  width="80" alt="Vacuum Capsule marker" /> | Vacuum Capsule | Dark steel-grey luggable marker. |
| <img src="doc/img/luggable_special_issue_ammo.png"  width="80" alt="Special Issue Ammo marker" /> | Special Issue Ammo | Olive-green luggable marker. |
| <img src="doc/img/luggable_prismata_crystal_repository.png"  width="80" alt="Prismata Crystal Repository marker" /> | Prismata Crystal Repository | Bright red luggable marker. |
| <img src="doc/img/pickup_mortis_relic.png"  width="80" alt="Mortis Relic marker" /> | Mortis Relic | Recolored device icon. |
| <img src="doc/img/pickup_coordinates_paper.png"  width="80" alt="Coordinates marker" /> | Coordinates | Uses the paper document icon. |

### Secondary Objective Items

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/pocketable_grimoire.png"  width="80" alt="Grimoire marker" /> | Grimoire | Secondary objective pocketable. |
| <img src="doc/img/pocketable_scripture.png"  width="80" alt="Scripture marker" /> | Scripture | Secondary objective pocketable. |

### Expedition POIs

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/expedition_unmarked_xi_2_4x.png" width="48" alt="Expedition unmarked XI 2 marker" /> <img src="doc/img/expedition_unmarked_n_4_4x.png" width="48" alt="Expedition unmarked N 4 marker" /> <img src="doc/img/expedition_unmarked_m_1_4x.png" width="48" alt="Expedition unmarked M 1 marker" /> | Sites of Interest | Unmarked expedition opportunity markers, using scanner-map glyphs with location numbering. |
| <img src="doc/img/expedition_marked_yellow_n_4_4x.png" width="48" alt="Expedition marked yellow N 4 marker" /> <img src="doc/img/expedition_marked_purple_xi_2_4x.png" width="48" alt="Expedition marked purple XI 2 marker" /> <img src="doc/img/expedition_marked_blue_m_1_4x.png" width="48" alt="Expedition marked blue M 1 marker" /> | Sites of Interest, player-marked | Player-marked expedition opportunity markers, using the same glyph and number combinations with the expedition marked colors. |
| <img src="doc/img/expedition_objective_transition.png"  width="80" alt="Expedition transition marker" /> | Deadsider Sanctuaries | Transition marker for sanctuary travel and section movement. |
| <img src="doc/img/expedition_loot_converter.png"  width="80" alt="Expedition loot converter marker" /> | Data Reliquary Harvesters | Uses the expedition harvester icon and is only shown while inside the sanctuary where the converter is relevant. |
| <img src="doc/img/expedition_objective_main_objective.png"  width="80" alt="Expedition main objective marker" /> | Main Objective | Main expedition objective location marker. |
| <img src="doc/img/expedition_objective_extraction.png"  width="80" alt="Expedition extraction marker" /> | Valkyrie Extraction Zone | Extraction location marker. |
| <img src="doc/img/expedition_objective_arrival.png"  width="80" alt="Expedition arrival marker" /> | Valkyrie Arrival Zone | Arrival location marker. |

These markers are driven by expedition navigation data rather than standard pickup scanning. **Sites of Interest** can appear as unmarked opportunity markers or player-marked variants, while the remaining expedition POIs use dedicated objective-style icons. Each POI category supports **Icon only**, **Icon + Distance m**, and **Off**. Sites of Interest default to distance text, while the other POI categories default to icon-only markers. Expedition POIs can optionally ignore the normal radar range limit, are filtered to the currently active expedition section, and clear outdated location markers when the active section or Deadsider Sanctuary state changes.

### Expeditions-Specific Items

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/material_expeditions_currency.png"  width="80" alt="Salvage marker" /> | Salvage | Supports **Artwork**, **Icon**, and **Off**. Artwork uses the salvage item art, icon mode uses a simplified salvage icon. |
| <img src="doc/img/material_expeditions_loot.png"  width="80" alt="Tech-Remnants marker" /> | Tech-Remnants | Supports **Artwork**, **Icon**, and **Off**. |
| <img src="doc/img/material_expeditions_loot_player_drop.png"  width="80" alt="Dropped Tech-Remnants marker" /> | Dropped Tech-Remnants | Supports **Artwork**, **Icon**, and **Off**. Icon mode uses a red-tinted simplified icon to distinguish dropped loot. |
| <img src="doc/img/luggable_data_reliquary.png"  width="80" alt="Data Reliquary marker" /> | Data Reliquaries | Gold luggable marker. |
| <img src="doc/img/pocketable_landmine_explosive.png"  width="80" alt="Servo-Triggered Mine marker" /> | Servo-Triggered Mine | Supports **Artwork**, **Icon**, and **Off**. |
| <img src="doc/img/pocketable_landmine_fire.png"  width="80" alt="Purgation Snare marker" /> | Purgation Snare | Supports **Artwork**, **Icon**, and **Off**. |
| <img src="doc/img/pocketable_landmine_shock.png"  width="80" alt="Voltaic Snare marker" /> | Voltaic Snare | Supports **Artwork**, **Icon**, and **Off**. |
| <img src="doc/img/pocketable_void_shield.png"  width="80" alt="Void Shell marker" /> | Void Shell | Supports **Artwork**, **Icon**, and **Off**. |
| <img src="doc/img/pocketable_airstrike.png"  width="80" alt="Bombing Run Signal Marker marker" /> | Bombing Run Signal Marker | Supports **Artwork**, **Icon**, and **Off**. |
| <img src="doc/img/pocketable_artillery_strike.png"  width="80" alt="Artillery Locator Beacon marker" /> | Artillery Locator Beacon | Supports **Artwork**, **Icon**, and **Off**. |
| <img src="doc/img/pocketable_big_grenade.png"  width="80" alt="Modified Grenade marker" /> | Modified Grenade | Supports **Artwork**, **Icon**, and **Off**. |
| <img src="doc/img/pocketable_valkyrie_hover.png"  width="80" alt="Fire-Support Signal Marker marker" /> | Fire-Support Signal Marker | Supports **Artwork**, **Icon**, and **Off**. |
| <img src="doc/img/luggable_promethium_barrel.png"  width="80" alt="Promethium Barrel marker" /> | Promethium Barrel | Orange explosive barrel marker. |
| <img src="doc/img/pickup_large_ammunition_crate.png"  width="80" alt="Large Ammunition Crate marker" /> | Large Ammunition Crate | Large ammo container, recolored to match the ammo family. |
| <img src="doc/img/pocketable_anti_rad_stimm.png"  width="80" alt="Anti-Rad Stimms marker" /> | Anti-Rad Stimms | Uses the expedition time syringe icon. |

### Martyr's Skull Items

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/pickup_martyr_skull.png"  width="80" alt="Martyr's Skull marker" /> | Martyr's Skull | Gold skull marker. |
| <img src="doc/img/luggable_power_cell_orange.png"  width="80" alt="Orange Power Cell marker" /> | Power Cell | Orange luggable marker used for the Martyr's Skull group. |

### Environment Markers

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/medicae_station.png"  width="80" alt="Medicae Station marker" /> | Medicae Station | Green medical interaction marker used for medicae stations and equivalent health-station interactions. |
| <img src="doc/img/luggable_socket.png"  width="80" alt="Power Socket marker" /> | Power Socket | Yellow power socket marker for luggable socket targets. |
| <img src="doc/img/heretic_idol.png"  width="80" alt="Heretic Idol marker" /> | Heretic Idol | Sickly green idol marker shown while the idol is still active. Active idols now appear reliably on the radar. |

### Deployed Items

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/pickup_ammo_cache_deployable.png"  width="80" alt="Deployable ammo crate marker" /> | Ammo Crate | Ammo-yellow deployable ammo crate marker. |
| <img src="doc/img/pickup_medkit.png"  width="80" alt="Deployable medical crate marker" /> | Medical Crate | Green deployable medical crate marker. |

### Event-Related Items

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/pickup_tainted_skull.png"  width="80" alt="Tainted Skull marker" /> | Tainted Skulls | Green skull marker. |
| <img src="doc/img/dark_rites_totem.png"  width="80" alt="Dark Rites Totem marker" /> | Dark Rites Totems | Green heretics icon marker for destroyable Dark Rites ritual totems. |
| <img src="doc/img/dark_rites_servo_skull.png"  width="80" alt="Dark Rites Servo Skull marker" /> | Dark Rites Servo Skulls | Green ability icon marker for spawned Dark Rites servo skull objective interactables. |
| <img src="doc/img/pocketable_corrupted_auspex_scanner.png"  width="80" alt="Tainted Communications Device marker" /> | Tainted Communications Device | Orange auspex scanner marker. |
| <img src="doc/img/pickup_saints.png"  width="80" alt="Holy Relics marker" /> | Holy Relics | Gold relic marker. |
| <img src="doc/img/pickup_stolen_rations.png"  width="80" alt="Stolen Rations marker" /> | Stolen Rations | Green crate marker. |

### Debug Marker

| Preview | Marker | Notes |
| --- | --- | --- |
| <img src="doc/img/pickup_unknown.png"  width="80" alt="Unknown pickup marker" /> | Unknown pickups | Optional fallback marker used when debug discovery is enabled. |

## Display Modes and Color Rules

The readme preview icons follow the default HUD presentations used by the mod. Most fixed marker and Radar UI colors are configurable in the mod options through four ARGB sliders:

- **Opacity** controls the alpha channel.
- **Red**, **Green**, and **Blue** control the color channels.
- Plain DMF shows each channel as a normal numeric slider.
- With Alf's Mod Settings Extensions installed, compatible consecutive ARGB sliders may be shown as compact color picker widgets.

The ARGB values listed below are the default values used after a fresh install or reset to defaults. Changing the sliders changes the rendered Radar colors without editing the source.

### Configurable color groups

Color sliders are placed near the setting they affect:

| Area | Examples |
| --- | --- |
| Radar Colors | Radar background, outline, guides, Auspex layers, marker text, vertical arrows, and overview legend indicators |
| Marker icon colors | Pickup, objective, expedition, event, enemy, and other icon-mode marker colors |
| Marker background colors | Marked enemy and boss background or bracket colors where applicable |
| Nearby highlight colors | Per-marker highlight colors for marker groups that support nearby screen-space highlights |

Artwork mode uses original item artwork and is not tinted by these sliders. Player teammate markers and the local player center dot use runtime player/HUD colors instead of fixed configurable marker colors.

### Artwork mode

Artwork mode keeps the original item artwork for supported markers. This is the default mode for all markers that support the new display dropdowns.

Examples:
- Crates use the pickup artwork tile.
- Diamantine, Plasteel, Salvage, Tech-Remnants, and Dropped Tech-Remnants keep their resource artwork.
- Expeditions pocketables such as Void Shell, the landmines, and the strike markers keep their existing item artwork.

### Icon mode

Icon mode swaps supported markers to simplified HUD icon materials with configurable ARGB colors. The table lists the default ARGB values.

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
| Enemy marked backgrounds and brackets | Marked enemy presentations, including bosses and per-enemy radar markers | `(220, 255, 0, 0)` |
| `content/ui/materials/icons/item_types/devices` | Mortis Relic | `(255, 110, 95, 125)` |
| `content/ui/materials/hud/interactions/icons/barrel_explosive` | Promethium Barrel | `(255, 255, 110, 0)` |
| `content/ui/materials/icons/circumstances/live_event_01` | Holy Relics | `(255, 192, 160, 0)` |
| `content/ui/materials/hud/interactions/icons/enemy` | Martyr's Skull, Tainted Skulls | `(255, 255, 215, 0)`, `(255, 150, 190, 60)` |
| `content/ui/materials/icons/achievements/categories/category_heretics` | Dark Rites Totems | `(255, 150, 190, 60)` |
| `content/ui/materials/icons/abilities/default` | Dark Rites Servo Skulls | `(255, 150, 190, 60)` |

### Runtime-dynamic colors

Not every radar marker uses a configurable fixed ARGB color:

- **Teammates** use the class icon for the detected archetype and take their color from the active HUD slot color at runtime.
- **The radar center dot** also uses the local player's HUD color.
- **Player smart tags** use their own tag presentations: attention and location tags follow player-slot colors, while threat tags keep their built-in warning color.

## Requirements

- **[Darktide Mod Framework](https://www.nexusmods.com/warhammer40kdarktide/mods/8)**
- **[Darktide Mod Loader](https://www.nexusmods.com/warhammer40kdarktide/mods/19)**

## Notes

- The radar is intended for active gameplay and suppresses itself outside valid runtime states such as hub and menu contexts.
- The radar now remains visible while the comms wheel is open, which makes live callouts and tag placement easier to track.
- The DMF options view remembers the last scroll position inside the **Radar** category while the options view remains open.
- Centered overview mode is intended as a temporary tactical view. It has separate zoom, scale-legend, and marker-cap controls and automatically exits when the radar runtime state is no longer valid.
- Normal radar range now supports **10 m** to **200 m**, and the zoom keybinds can temporarily control that range while the radar zoom modifier is held.
- **Auspex** is a full radar style with an optional animated sweep, and the same Auspex scanner background can also be selected as a guide option for Square and Circle radar styles.
- Teammates, teammate marker range, the local player center dot, and player smart tags now have separate controls, so ally information can be tuned more precisely.
- Player smart tags support optional distance text, but no longer use player-tag elevation arrows or related elevation hiding behavior. Enemy markers can use vertical arrows separately through their own category options.
- Supported ability-marked and smart-tag outlined enemies can optionally be treated as radar-visible targets, and shared `special_target` outline handling is gated to the local owning context so unrelated outlines do not leak into radar visibility. Enemy vertical arrow toggles only affect arrow display, not whether those enemies are eligible for radar visibility.
- Nearby highlights now support thickness, per-marker ARGB highlight colors, and optional distance labels, and their placement was adjusted to stay aligned more reliably under scaled HUD layouts.
- **Tagged enemies only** and **Tagged items only** are filters, not new marker families. They reuse the game's active tag state and let tagged targets ignore the normal radar range limit while tagged.
- Expedition POIs and section-scoped expedition items are filtered to the active expedition section. POI categories can independently show icon-only markers, include meter distance text, or be hidden. Sanctuary-state transitions trigger cleanup so stale safe-zone markers do not leak into open zones, while active player-dropped Tech-Remnants can still be shown.
- Marker previews in this readme were generated from the included template assets and documentation images so the legend matches the mod's configured presentations as closely as possible.

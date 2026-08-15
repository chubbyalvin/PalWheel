# PalWheel

**PalWheel** is a customizable radial action wheel for **Palworld** built with **UE4SS**.

It gives quick access to frequently used actions through **up to three configurable wheels**, with **36 saved assignment positions total** and **4 to 12 visible slots per wheel**. PalWheel is designed primarily for controller use, while still supporting keyboard and mouse.

> **Current version:** 1.3  
> **Author:** CHUBBYALVIN  
> **Platform:** Palworld for Windows  
> **Framework:** UE4SS

---

## Features

- **1, 2, or 3 configurable radial wheels**
- **36 customizable assignment positions total** — 12 per wheel
- Independently configure **4–12 visible slots per wheel**
- Controller and keyboard/mouse support
- Hybrid input support — a wheel opened from keyboard/Steam Input can also be navigated with the controller Right Stick
- In-game **F7 assignment editor**
- Automatic saving of user settings and assignments
- Configurable wheel skins
- Configurable controls, stick deadzones, movement allowlists and slow-motion behavior
- In-game **Slow Motion toggle**
- Automatic multiplayer detection; slow motion is disabled in multiplayer
- Improved controller input handling and camera stability when slow motion is unavailable
- Weapon, Pal and sphere hover/selection previews
- Input and camera handling while the wheel is open
- **Assignable vanilla Palworld emotes**
- **Configurable custom keyboard shortcut actions** for Palworld and other mods
- Separate user-generated settings, assignment and shortcut files

### Assignable actions

#### Weapons
- Weapon 1
- Weapon 2
- Weapon 3
- Weapon 4
- Weapon 5
- Weapon 6

#### Party Pals
- Pal 1
- Pal 2
- Pal 3
- Pal 4
- Pal 5

#### Game Menus
- Character
- Inventory
- World Map
- Technology
- Party
- Build

#### Custom Shortcuts
- User-defined keyboard shortcut actions from `Saved\shortcuts.tsv`
- Supports single keys and Ctrl / Shift / Alt combinations
- Up to 36 active/selectable custom shortcut definitions at a time

#### Pal Spheres
- Pal Sphere
- Mega Sphere
- Giga Sphere
- Hyper Sphere
- Ultra Sphere
- Legendary Sphere
- Ultimate Sphere
- Exotic Sphere
- Sol Sphere
- Ancient Sphere

#### Emotes
- Beckon
- Dance
- Wave
- Sit in Chair
- Sit on Ground
- Surprised
- Hand Over
- Sleep
- Kick

#### Utility
- Mercy accessory toggle

#### General
- Empty slot

---

## Default Controls

### Controller

| Input | Action |
|---|---|
| Hold **L1 / LB** | Open PalWheel |
| **Right Stick** | Highlight a slot |
| Return Right Stick inward | Activate after the configured inward-return threshold |
| Release **L1 / LB** | Activate the highlighted slot |
| **R1 / RB** | Switch between enabled wheels |

When multiple wheels are enabled, the page button cycles through them:

- 1 wheel: Wheel I
- 2 wheels: Wheel I → Wheel II
- 3 wheels: Wheel I → Wheel II → Wheel III

### Recommended Palworld controller remap

PalWheel uses **L1 / LB** as its default controller open button. To avoid a conflict with Palworld's default summon control, the recommended Palworld controller remap is:

1. Remap **Summon Pal** from **L1 / LB** to **D-pad Left**.
2. Remap **Select Previous/Left Pal** from **D-pad Left** to **D-pad Right**, the same button used for **Select Next/Right Pal**.
3. Palworld will show a **duplicate key binding warning** for the two Pal-selection actions. This is expected.

This keeps Pal summoning available on D-pad Left while freeing L1 / LB for PalWheel.

### Keyboard / Mouse

| Input | Action |
|---|---|
| Hold **Caps Lock** | Open PalWheel |
| Mouse movement | Highlight a slot |
| Release **Caps Lock** | Activate the highlighted slot |
| **Right Mouse Button** | Switch between enabled wheels |
| **F7** | Open or close the assignment editor |

### Custom trigger keys

For personal key bindings, first launch Palworld and enter a world once after installing PalWheel. This generates:

```text
PalWheel\Saved\settings.lua
```

Close the game before editing this file.

The generated `settings.lua` contains the user-facing trigger bindings, including:

```lua
controllerOpenButton = "Gamepad_LeftShoulder",
controllerPageButton = "Gamepad_RightShoulder",

openKey = "CAPS_LOCK",
keyboardPageButton = "RIGHT_MOUSE_BUTTON",
```

Change these values in `Saved\settings.lua` if you prefer a different controller or keyboard/mouse layout.

### Custom shortcut actions

PalWheel v1.3 also generates:

```text
PalWheel\Saved\shortcuts.tsv
```

This TAB-separated file defines keyboard shortcut actions that can be assigned to wheel slots, including shortcuts used by other mods. The default Character, Inventory, Party, Technology and Build actions are also defined here.

Each row contains a stable ID, display label, key, Ctrl / Shift / Alt options, and an `active` setting. The first 36 valid active shortcuts are available in the assignment picker. Existing assignments to an inactive shortcut are preserved but do not execute until that shortcut is enabled again.

Restart Palworld after manually editing `shortcuts.tsv`. Modifier keys are injected as real keypresses, so a modifier that is also bound to a Palworld gameplay action may trigger that action as well. Windows-key shortcuts and unsafe system combinations are not supported.

---

## Assignment Editor

Press **F7** in-game to open the assignment editor.

The editor displays **Wheel I, Wheel II and Wheel III** side by side and lets you:

- Assign functions to all **36 saved assignment positions**
- Choose from grouped categories including Weapons, Party, Spheres, Emotes, PalWheel and Custom Shortcuts
- Select whether **1, 2, or 3 wheels** are active
- Independently configure **4–12 visible slots for each wheel**
- Select an installed wheel skin
- Enable or disable **Slow Motion**
- Reset custom shortcut definitions to their defaults with confirmation
- Automatically save assignments and settings

All three wheel columns remain available in the editor even when fewer than three wheels are enabled, allowing additional wheels to be configured before enabling them.

> **Multiplayer:** Slow Motion is automatically disabled when PalWheel detects multiplayer, regardless of this setting.

The editor uses direct mouse clicks for assignment changes.

---

## Wheel Behavior

While PalWheel is open:

- Mouse direction or Right Stick direction selects a slot around the wheel.
- A keyboard-opened wheel can also be navigated with the controller Right Stick; mouse movement can take selection ownership again.
- The configured page button cycles between the currently enabled wheels.
- The camera is clamped while the wheel is active.
- Slow Motion can be enabled or disabled from the assignment editor.
- When multiplayer is detected, PalWheel automatically disables slow motion regardless of the saved setting.
- Allowed movement inputs can remain active.
- On controller, most other buttons close PalWheel and continue to their normal game action.
- Weapon, Pal and sphere slots can preview their selection when highlighted.
- Pal actions select the corresponding party slot and summon the Pal near the player.
- Sphere actions check inventory and attempt to equip the selected sphere type.
- Emote actions directly trigger the assigned vanilla Palworld emote.
- The World Map uses a native UI call.
- Configurable shortcut actions use deferred keyboard input through `PalworldKeyInjector.dll`.
- Closing the wheel restores cursor, input, camera and time state.

PalWheel only opens during normal playable world state and stays closed while blocking Palworld UI is active.

---

## Installation

### Manual / GitHub Release

1. Install a working **UE4SS build for Palworld**.
2. Download the latest PalWheel release archive.
3. Extract the `PalWheel` folder into:

```text
Palworld\Pal\Binaries\Win64\ue4ss\Mods\
```

or

```text
Palworld\Mods\NativeMods\UE4SS\Mods\
```

4. Confirm the final structure includes:

```text
PalWheel\
├─ Assets\
├─ Saved\
└─ Scripts\
   └─ main.lua
```

5. Start Palworld and enter a world.

PalWheel automatically creates:

```text
PalWheel\Saved\settings.lua
PalWheel\Saved\assignments.lua
PalWheel\Saved\shortcuts.tsv
```

Close the game before manually editing generated settings files.

---

## Configuration

PalWheel uses two kinds of configuration:

### Packaged defaults

```text
Scripts\config.lua
Scripts\mappings.lua
```

These define default appearance, timing, controls, input mappings and behavior.

### Generated user files

```text
Saved\settings.lua
Saved\assignments.lua
Saved\shortcuts.tsv
```

`settings.lua` stores user-facing preferences and controls, including the number of enabled wheels and the visible slot count for each wheel.

`assignments.lua` stores the **36 assignment IDs** used by Wheel I, Wheel II and Wheel III.

`shortcuts.tsv` stores configurable keyboard shortcut actions. The first 36 valid active definitions are selectable, while inactive definitions can remain assigned without executing until re-enabled.

The generated files are written separately so updates to the mod do not need to overwrite user choices.

Existing settings and assignments are migrated when required by newer PalWheel settings formats.

---

## Wheel Skins

PalWheel scans the mod's `Assets` folder for wheel skin files using names in the form:

```text
wheel_00.png
wheel_01.png
wheel_02.png
...
wheel_99.png
```

Included skins:

- `wheel_01.png` — plain wheel skin
- `wheel_02.png` — detailed default wheel skin

Additional compatible skins can be added later without changing the core wheel logic.

---

## Repository Structure

```text
PalWheel\
├─ Assets\
│  ├─ wheel_01.png
│  └─ wheel_02.png
│
├─ Saved\
│  └─ README.txt
│
├─ Scripts\
│  ├─ PalworldKeyInjector.dll
│  ├─ config.lua
│  ├─ controller.lua
│  ├─ editor_builder.lua
│  ├─ input_runtime.lua
│  ├─ main.lua
│  ├─ mappings.lua
│  ├─ menu_actions.lua
│  ├─ pal_actions.lua
│  ├─ palworld_keyinjector.lua
│  ├─ runtime_loops.lua
│  ├─ shortcut_actions.lua
│  ├─ sphere_actions.lua
│  └─ wheel_visuals.lua
│
├─ THIRD_PARTY_LICENSES\
│  └─ PalworldKeyInjector-MIT.txt
│
├─ LICENSE.md
└─ README.md
```

### Main Files

| File | Purpose |
|---|---|
| `main.lua` | Core state, saved data, action catalogue, UMG construction, UI guards and wheel/editor lifecycle |
| `config.lua` | Packaged defaults for layout, appearance, timing and features |
| `mappings.lua` | Default keyboard, mouse and controller mappings |
| `controller.lua` | Controller session handling, radial selection, wheel switching and close-on-button behavior |
| `input_runtime.lua` | Keyboard/mouse polling, release activation and wheel-session handling |
| `editor_builder.lua` | F7 editor, assignment rows, grouped function picker and dropdowns |
| `wheel_visuals.lua` | Wheel centre details, direction visuals, selection styling and reveal behavior |
| `menu_actions.lua` | Deferred configurable shortcut actions and PalworldKeyInjector integration |
| `pal_actions.lua` | Party lookup, Pal selection and summoning |
| `sphere_actions.lua` | Sphere ownership checks, cycling and verification |
| `runtime_loops.lua` | Recurring selection, input and camera update loops |
| `shortcut_actions.lua` | Generation, loading, validation and reset handling for `Saved\shortcuts.tsv` |
| `palworld_keyinjector.lua` | Lua wrapper for the PalworldKeyInjector API |
| `PalworldKeyInjector.dll` | Windows x64 helper used by configurable deferred keyboard shortcut actions |

---

## Troubleshooting

### PalWheel does not open

- Confirm UE4SS is installed and working.
- Confirm `PalWheel\Scripts\main.lua` is in the expected location.
- Check the UE4SS log for entries beginning with:

```text
[PalWheel]
```

### Custom PalWheel trigger binding does not take effect

Personal PalWheel trigger bindings should be changed in:

```text
PalWheel\Saved\settings.lua
```

Close Palworld before editing the file.

`Scripts\mappings.lua` contains the packaged defaults. Values already saved in `Saved\settings.lua` take priority over those defaults.

### Menu actions do not match remapped Palworld controls

Character, Inventory, Party, Technology and Build use configurable keyboard shortcut definitions. Update the relevant key in:

```text
PalWheel\Saved\shortcuts.tsv
```

if those Palworld controls have been remapped, then restart Palworld.

### Custom shortcut does not appear in the assignment picker

Check `PalWheel\Saved\shortcuts.tsv` and confirm the row is valid and `active` is set to `true`. Only the first 36 valid active shortcut definitions are selectable. Invalid rows are reported in the UE4SS log.

### Remapped movement keys cause the wheel to close

Update the movement allowlist in the mappings/configuration so it matches your Palworld controls.

### Controller stick drift selects slots

Increase the configured controller stick deadzone slightly.

### Background skin does not load

Confirm the selected `wheel_XX.png` file exists inside:

```text
PalWheel\Assets\
```

and that the skin name matches the saved setting.

---

## Planned / Possible Future Updates

PalWheel v1.3 expands PalWheel with configurable shortcut actions and hybrid input while retaining the existing controller-focused design.

Ideas being explored for future versions include:

- Adding icons to wheel slots
- Supporting additional Palworld menus and actions where technically possible
- Expanding utility actions
- Additional wheel skins and visual customization
- Further controller and input refinements

These are **planned goals and experiments**, not guaranteed features or release dates.

---

## Compatibility

- Palworld for Windows
- UE4SS for Palworld
- Designed for both controller and keyboard/mouse
- PalWheel is an unofficial community mod and is not affiliated with Pocketpair.

Game updates or UE4SS changes may affect compatibility.

---

## Permissions and License

PalWheel is currently **not open source under a permissive license**.

Copyright © 2026 **CHUBBYALVIN**. All Rights Reserved.

You may download and use PalWheel for personal, non-commercial use and configure it for your own use.

Unless you have prior written permission from CHUBBYALVIN, you may not:

- Redistribute or reupload PalWheel
- Publish modified versions
- Repackage the mod for another distribution
- Incorporate PalWheel source code, scripts or assets into another project
- Sell or commercially redistribute the mod
- Claim authorship of PalWheel or substantial portions of it

See [`LICENSE.md`](LICENSE.md) for the full terms.

---

## Disclaimer

Use game modifications at your own risk.

Back up important saves and configuration files before installing or updating mods. PalWheel is provided as-is without warranty, and the author is not responsible for loss or damage resulting from its use.

---

## Support the Project

If you enjoy PalWheel and would like to support my modding work, you can leave an optional tip on Ko-fi.

[![Support me on Ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/B4G024ORB8)

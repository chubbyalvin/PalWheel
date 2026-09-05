PALWHEEL v2.0 - USER GUIDE


OVERVIEW

PalWheel adds configurable action wheels to Palworld:

  - Up to three Main Wheels with 4 to 12 slots each
  - Two AUX Wheels with four direct shortcuts each
  - A separate Sphere Wheel with 5 to 10 sphere slots
  - Pal, weapon, menu, emote, Pal command, and custom shortcut actions
  - Full in-game configuration through the PalWheel Menu
  - Controller and keyboard/mouse support


------------------------------------------------------------------------


REQUIREMENTS AND INSTALLATION

PalWheel requires UE4SS.

1. Close Palworld.
2. Install UE4SS for your copy of Palworld.
3. Extract the PalWheel folder into UE4SS's Mods folder:

     ue4ss\Mods\PalWheel

4. Launch Palworld.

When updating PalWheel, replace the existing mod files but keep the contents of
PalWheel\Saved if you want to preserve your settings and custom shortcuts.


QUICK START

1. Free L1 / LB in Palworld's controller bindings if you want to use the
   default PalWheel controller controls.
2. Hold Open Wheel to open the Main Wheel.
3. Select an action with the controller stick or mouse.
4. Press Next Wheel while the wheel is open to switch Main Wheels.
5. Open the PalWheel Menu to assign actions and change settings.

Default controls:

  Controller
    Open Wheel       L1 / LB
    Next Wheel       R1 / RB
    PalWheel Menu    R3 / RS while the Main Wheel is open

  Keyboard/mouse
    Open Wheel       Caps Lock
    Next Wheel       Middle Mouse
    PalWheel Menu    F7

The default L1 / LB control must not remain assigned to a conflicting Palworld
action. Move Palworld's Summon Pal action or any other conflicting action to a
different control before using PalWheel.


USING THE MAIN WHEEL

Controller:

1. Hold Open Wheel.
2. Move the selection stick toward a slot.
3. Release Open Wheel while the slot is selected, or return the stick to the
   center after selecting it.

Keyboard/mouse:

1. Hold Open Wheel.
2. Move the mouse over a slot.
3. Left Click the slot to activate it.

Releasing Open Wheel on keyboard/mouse closes the wheel without activating an
action. Clicking empty space does nothing.

Press Next Wheel while the Main Wheel is open to cycle through the enabled
wheels. Only the number of wheels selected in the PalWheel Menu are used.


AUX WHEELS

Whenever the Main Wheel is open, PalWheel also shows AUX I and AUX II. These are
direct shortcuts and do not use Main Wheel radial selection. They can be
activated with their D-pad or face-button controls, or clicked directly with
the mouse.

AUX I uses the D-pad:

  Slot 1   D-pad Left
  Slot 2   D-pad Up
  Slot 3   D-pad Right
  Slot 4   D-pad Down

AUX II uses the face buttons:

  Slot 1   Face Left / Square / X
  Slot 2   Face Top / Triangle / Y
  Slot 3   Face Right / Circle / B
  Slot 4   Face Bottom / Cross / A

To change an AUX assignment, open the PalWheel Menu and select the FUNCTION
cell beside the corresponding D-pad or face-button slot.

SPHERE WHEEL

The Sphere Wheel opens instead of the Main Wheel when PalWheel detects that you
are preparing to throw or launch a sphere.

Normal sphere throw:

1. Hold Palworld's sphere-throw control.
2. Press or hold Open Wheel.

Sphere Launcher:

1. Equip and aim a supported Sphere Launcher.
2. Press or hold Open Wheel while still aiming.

Use the controller stick or mouse to select a sphere. Unavailable spheres
cannot be selected.

To reorder the Sphere Wheel:

1. Open the PalWheel Menu.
2. Select a SPHERE TYPE cell in the SPHERE WHEEL column.
3. Choose a sphere. If it is already assigned elsewhere, the two positions are
   swapped.
4. Select SAVE & APPLY.


------------------------------------------------------------------------


PALWHEEL MENU

Press F7 by default to open the PalWheel Menu.

Controller navigation:

  D-pad or Left Stick   Move between controls
  Cross / A             Select
  Circle / B            Go back one level
  Triangle / Y          Save and apply when available

Available settings:

  WHEELS
    Choose 1, 2, or 3 active Main Wheels.

  WHEEL SLOT COUNTS
    Choose 4 to 12 slots independently for each Main Wheel.

  SPHERE WHEEL SLOT COUNT
    Choose 5 to 10 visible sphere slots.

  SKIN
    Choose the wheel background.

  SLOW MOTION
    Slow the game while a wheel is open. This is disabled in multiplayer.

  ZOOM
    Enable or disable controller Camera Zoom.

  HAPTICS
    Enable or disable controller vibration when changing the selected slot.

  FOLLOW TARGET
    Enable or disable target following while using the Sphere Wheel with a
    controller.

Changes remain in draft until SAVE & APPLY is selected.

RESTORE DEFAULTS resets Main Wheel, AUX Wheel, and Sphere Wheel assignments;
wheel and slot counts; Skin; Slow Motion; Zoom; Haptics; and Follow Target.
Controls and Custom Shortcuts are not changed.

If you close the menu with unsaved changes, PalWheel asks whether to discard
them.


ASSIGNING WHEEL ACTIONS

Main Wheels:

1. Open the PalWheel Menu.
2. Select the FUNCTION cell for a slot.
3. Choose an action.

Choose Empty to clear a Main Wheel or AUX Wheel slot.

Available action groups include:

  Party Pals
    Select or summon a Pal from the current party. Additional Pal slots become
    available when Palworld reports a larger party capacity.

  Weapons
    Select equipped weapon or tool slots 1 through 6.

  Palworld menus
    Inventory, Party, Technology, Mission, Palpedia, Guild, Options, Build,
    and World Map.

  Pal actions
    Feed Pal, Pet Pal, Photo Mode, and Peaceful, Defensive, or Aggressive Pal
    commands.

  Mercy Toggle
    Equip or remove the Ring of Mercy or Pal Tamer's Glasses when one is
    available in your inventory.

  Emotes
    Activate a supported Palworld emote.

  Custom Shortcuts
    Run a configured keyboard shortcut from a wheel slot, including while
    playing with a controller.


CHANGING CONTROLS

Open PalWheel Menu > CONTROLS to change:

  - Open Wheel
  - Next Wheel
  - Keyboard/mouse PalWheel Menu
  - Controller PalWheel Menu
  - Open Wheel behavior: Hold or Toggle

Select CHANGE beside a binding, choose the new control, then select CONFIRM.
Changes remain in draft until SAVE & APPLY is selected.

The keyboard Open Wheel, Next Wheel, and PalWheel Menu bindings must be
different. The three controller bindings must also be different.

PalWheel warns when some controller choices overlap with AUX, Zoom, or detected
Palworld controls. Some overlaps are warnings rather than hard conflicts when
the controls are used in different contexts.

RESTORE DEFAULT CONTROLS restores the default bindings and changes Open Wheel
behavior back to Hold.


------------------------------------------------------------------------


CUSTOM SHORTCUTS

Open PalWheel Menu > SHORTCUTS.

You can:

  - Add or duplicate a shortcut
  - Edit its label and ID
  - Choose its key and one optional Ctrl, Shift, or Alt modifier
  - Enable or disable it
  - Delete it
  - Reload shortcuts.tsv
  - Restore the packaged shortcut rows into the draft

Only active shortcuts appear in the assignment picker. The first 36 valid
active shortcuts are selectable.

Shortcut IDs must be unique. Labels can contain up to 20 characters.

Renaming a shortcut keeps wheel slots connected to it. Deleting a shortcut
changes slots using it to Empty after SAVE & APPLY.

Custom shortcuts may also trigger Palworld actions assigned to the same keys.


ADVANCED CUSTOM SHORTCUT EDITING

Most users should use the in-game shortcut editor.

PalWheel\Saved\shortcuts.tsv can be edited outside the game when you need a
non-Latin label or want to edit several shortcuts at once. Close Palworld first
and keep the file in UTF-8 tab-separated format.

After changing the file, restart Palworld or open PalWheel Menu > SHORTCUTS and
select RELOAD FILE.

Do not manually edit settings.lua. Use the PalWheel Menu for settings, controls,
and wheel assignments.


------------------------------------------------------------------------


TROUBLESHOOTING

PalWheel does not load:

  Confirm that UE4SS is working and that the PalWheel folder is inside
  ue4ss\Mods.

The default controller Open Wheel control does not work correctly:

  Remove the conflicting L1 / LB assignment from Palworld's own controller
  bindings or choose a different Open Wheel control in PalWheel Menu > CONTROLS.

A custom shortcut does not appear in the assignment picker:

  Confirm that it is valid and active, then select SAVE & APPLY. If the file was
  edited outside the game, select RELOAD FILE. Only the first 36 valid active
  shortcuts are selectable.

A shortcut will not save:

  Check that its ID is valid and unique. An unmodified shortcut cannot use a
  key currently assigned to Open Wheel, Next Wheel, or PalWheel Menu. Adding
  Ctrl, Shift, or Alt makes it a distinct shortcut where supported.

An additional party Pal slot is unavailable:

  The slot becomes available only when Palworld reports the required party
  capacity.

Mercy Toggle does not work:

  Confirm that a Ring of Mercy or Pal Tamer's Glasses is in your inventory. You
  also need inventory space when removing an equipped accessory.

Restore normal settings:

  Use RESTORE DEFAULTS in the PalWheel Menu. This does not reset Controls or
  Custom Shortcuts.

If damaged settings prevent the menu from working, close Palworld, rename
PalWheel\Saved\settings.lua as a backup, and restart the game. PalWheel will
create fresh defaults.

For further diagnosis, check UE4SS.log for lines beginning with [PalWheel].


Thanks for checking out PalWheel! Making PalWheel has been a lot of fun, and I
hope it makes your Palworld experience smoother and more enjoyable. If you’re
enjoying the mod, feel free to drop by the mod page to share your feedback or
show some support. While you’re there, check out my other mods too! Have fun!

- ChubbyAlvin

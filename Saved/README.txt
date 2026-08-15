PalWheel user-generated and user-editable settings are stored in this folder.

IMPORTANT
  Launch Palworld once to let PalWheel generate the files, then close the game
  before manually editing them.

settings.lua
  General user-facing PalWheel settings. Generated automatically after first
  run. This is the normal file to edit for custom PalWheel trigger bindings.

  Common binding fields:
    openKey
    keyboardPageButton
    settingsKey
    controllerOpenButton
    controllerPageButton

  It also stores wheel count/slot counts, wheel skin, slow-motion settings,
  deadzones, and movement allowlists.

  Scripts\mappings.lua contains packaged/default mappings. It is not the
  primary user customization file once Saved\settings.lua has been generated.

assignments.lua
  The 36 wheel slot assignment IDs. Generated and maintained automatically.

shortcuts.tsv
  Configurable keyboard shortcut actions. This is a TAB-separated text file
  that can be edited in Excel, LibreOffice Calc, Google Sheets, or a text
  editor.

shortcuts.tsv columns:
  id       Stable unique ID. Use letters, numbers, underscore, or hyphen only.
  label    Name displayed in PalWheel. Commas and quotation marks are allowed.
  key      Supported keyboard key, for example F10, T, TAB, PAGE_DOWN.
  ctrl     true or false
  shift    true or false
  alt      true or false
  active   true or false. Only active rows appear in the assignment picker.

The first 36 valid active shortcuts are selectable in PalWheel. Inactive rows
remain defined but are hidden from the assignment picker and do not consume the
36 active slots. If an inactive shortcut was already assigned to a wheel slot,
that assignment is preserved but will not execute until active is changed back
to true. Later valid active rows beyond the first 36 also remain defined but are
not selectable. PalWheel reads at most 256 valid shortcut definitions. Restart
Palworld after manually editing shortcuts.tsv so PalWheel can reload the file.

Do not place TAB characters or line breaks inside a field. Invalid rows are
ignored and reported in UE4SS.log. A malformed header causes PalWheel to use
safe defaults without overwriting the existing file.

Blocked or unsupported combinations are rejected. Windows-key shortcuts are
not supported. Examples such as Alt+F4 and Ctrl+Alt+Delete are blocked.
Modifier keys are injected as real keypresses, so a modifier that Palworld uses
for a gameplay action may also trigger that gameplay action.

Use the RESET SHORTCUTS button in the F7 editor to restore the default five
shortcut definitions. A confirmation popup is shown before resetting.

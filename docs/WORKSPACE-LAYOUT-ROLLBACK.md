# Combined workspace layout — Build 42

Build 41 is preserved before this redesign:

- Local Git tag: `build-41-before-layout` (commit `69aa5d3`).
- Saved source: `outputs/checkpoints/build-41/source.tgz`.
- Saved normal app: `outputs/checkpoints/build-41/Shelf Elf Librarian.app`.
- Saved isolated test app: `outputs/checkpoints/build-41/Shelf Elf Librarian Fresh Install Test.app`.

To compare the old layout, quit the newer matching app and open its saved Build 41 copy. The test edition continues to use its own test settings/history. No settings migration is introduced by Build 42. Do not overwrite your profiles or preferences just to change interface versions.

A code rollback can use the local Git tag or source archive after preserving any subsequent work. No automatic rollback or GitHub push has been performed. File operations made while testing are not undone by replacing the executable; use operation history and its guarded undo actions.

## Presentation changes

The main window uses a native macOS toolbar with the elf logo, visible version, profile picker/Magic indicator, Profile Settings, General Settings and History. A compact workspace row retains Open Workspace, Refresh, Include subfolders and Finder access. Selection, bulk rename, manual Magic and filename filtering remain above the file list.

The inspector is narrower and resizable. With no selected files it shows an empty state. Episode and movie fields are presented contextually, with the other fields still available in disclosure sections. Interpretation evidence and longer help text are expandable. Current filenames, bulk editing, interpretation alternatives, confirmation, batch name editing and remembered-correction controls remain available.

Every file still shows its editable proposal, including unchanged names. Per-row save/rename checkmarks, Return/Escape editing, direct rename undo, red/blue differences, source spelling marks, Show changes, suggestions and contextual spelling menus remain unchanged. Neutral proposal fields replace the previous full yellow/green field backgrounds. Name status is explicit; component confirmation is a separate Filing indicator and inspector status.

The combined filing area retains operation selection, File only, both preview actions and library Finder access. Clean Preview is labeled Preview Renames; File Preview is labeled Preview Filing. Immediate rename actions remain immediate. Status and cancellation remain outside the disabled workspace. Splash, About and blank-workspace artwork are retained.

Build 42 is also retained as local Git tag `build-42-before-window-fixes` (`f0dcc3c`), with source and both app copies under `outputs/checkpoints/build-42`. Build 43 addresses toolbar backgrounds, duplicate title, editable-field contrast, hover containment and owner-relative dialog/chooser positioning without changing the settings schema.

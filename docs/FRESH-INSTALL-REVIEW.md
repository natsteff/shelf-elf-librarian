# Fresh-install review — Build 41

The generated app **outputs/Shelf Elf Librarian Fresh Install Test.app** has a separate bundle identifier, preference suite, profile file and operation journal. Its window title includes **Fresh Install Test**. It does not restore the normal app's workspace or settings. It can run alongside the normal app. It starts with nine profiles and suggested universal exceptions; library destinations remain unconfigured until selected.

Normal data remains in `~/Library/Application Support/com.local.LibraryFiler.Alpha`. Test data goes to `~/Library/Application Support/com.local.LibraryFiler.FreshInstallTest`. Test preferences use `com.local.LibraryFiler.FreshInstallTest`. Notice acknowledgments and remembered-workspace preferences are separate too. Building the test app does not launch it or alter either set of saved settings.

1. Open the Fresh Install Test app, and confirm the title identifies the test edition.
2. Select a starter profile: Video Media Server, Music, Audiobooks, FORGE, ROMs, Photos, PDF Library, Software & Installers, or Ebooks & Comics.
3. Use a disposable workspace. Filename-only examples are provided under `outputs/fresh-install-review/Workspace`; these are not playable media, ROMs or installers.
4. Set that profile's Destination Root to a folder under `outputs/fresh-install-review/Library`, not your real library.
5. Inspect Profile Settings, including Description / Notes, patterns, classifications and route masks. Test input examples and selected files before saving.
6. Review components and proposals in the main list. Typing changes proposals only. Rename applies in place; File Preview reviews copy/move destinations before Apply.
7. Use **Tools → Export Settings…** to retain your reviewed setup. **Tools → Import Settings…** replaces profiles and General Settings after a confirmation and automatic backup. It leaves library files and undo history unchanged. A starter archive at `outputs/fresh-install-review/Starter Settings.json` can restore these test defaults through that same import flow.

Your pre-Build-40 saved settings were copied read-only into `outputs/settings-backups/20261021-162605/`. This includes raw profiles, raw preference data and an importable `Shelf Elf Settings before Build 40.json` archive. It was validated as containing nine profiles. Preferences not yet flushed by an already-running app may be newer than that snapshot; Tools → Export Settings in the running app captures its current profile/General Settings values.

When ready to try the normal Build 40 app, quit the previous normal version first. First startup backs up and migrates saved profiles, retaining compatibility parsing until you opt into the editable rules. Do not copy test preferences over normal files manually; use the reviewed export/import flow if desired. Operations performed in the test app have their own undo history.

Build 41 adds descriptions and organization suggestions to all starter profiles. Quit and reopen the existing Fresh Install Test app to load the update. Matching profiles whose Notes were never set receive the descriptions; notes you edited or intentionally cleared remain unchanged.

# Automatic configuration backups

Available in Shelf Elf Librarian 0.1.0 Beta 1.

Manual **Tools → Export Settings…** remains the primary portable backup. Its JSON archive includes all profiles, General Settings and active profile identity. It excludes library contents, operation history, remembered corrections and transient workspace/UI state.

## Safety net

Before a committed profile or General Settings change, save a full pre-change archive under the app's Application Support folder in **Settings Backups**. Keep the newest 10 snapshots. Each snapshot records the timestamp and reason for the upcoming change. UUID filenames prevent collisions during rapid saves. Write and verify the new snapshot before pruning older automatic snapshots or replacing configuration. Backups have a private directory and private file permissions.

Covered changes: create/duplicate/save/delete profile, General Settings Save, add filing type from the workspace, confirmed library identity/bookmark reconnection, imports, automatic restores, and startup profile/default migrations. Unsaved drafts, cancelled dialogs, unchanged profile/General Settings saves, file selection/filtering, workspace changes and profile selection do not consume slots. Initial creation of starter defaults has no prior configuration to preserve. Session preferences, license acknowledgments and learning/history actions are outside this settings archive, matching manual export.

A failed backup blocks configuration replacement and reports the error. A failed atomic profile write leaves the existing profile file intact and its pre-change snapshot available. If pruning itself fails, the save stops and extra snapshots may remain until the storage problem is fixed. Automatic snapshots are local, finite, and not an independent/off-device backup. Historical migration/import backups outside this folder and manually exported files are not rotated.

## Restore

**Tools → Restore Settings Backup…** lists date/time and trigger reason, newest first. Restore validates and migrates the chosen archive, confirms replacing all profiles and General Settings, and backs up the current configuration before replacement. Cancel leaves settings unchanged. The selected archive is decoded before rotation, so restoring the oldest backup remains safe even when the pre-restore snapshot rotates its file out. Destinations can require reconnecting, especially on another Mac. The Fresh Install Test edition uses its separate support folder and therefore has separate automatic snapshots.

Profile data remains in the existing atomic `profiles.json` file and General Settings in the existing UserDefaults entry; this change adds pre-change recovery, not a transactional multi-file database. A process/system interruption during import/restore can still leave profiles and General Settings from different states. The pre-change archive contains both and is available for recovery.

## Validation

Disposable checks cover 12 snapshots rotating to 10, exact retained boundaries, custom profile values and General Settings round-trip, active profile identity, restore of the oldest snapshot with a pre-restore backup, old archive compatibility, rapid same-time snapshot naming, corrupt restore refusal, outside-folder restore refusal, isolated test storage, and backup creation failure preventing profile replacement. Native restore dialog review and real crash/power-loss testing remain outstanding. No production settings are changed by fixture tests.

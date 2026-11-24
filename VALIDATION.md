# Validation scope

## 0.1.0 Beta 2

Public version: **0.1.0 Beta 2**, internal bundle version **74**. Built for Apple Silicon with the selected Xcode toolchain. The app remains ad hoc signed, not Developer ID signed or notarized.

All **99 disposable fixture scenarios** pass. Suggested-entry checks include preview non-mutation, exact agreement between preview and applied counts, duplicate/conflicting-spelling retention, preservation of custom entries and repeated-load idempotence. Existing transfer, collision/source guards, parsing, metadata, settings backup and history checks remain included.

Native visual review of the new yellow-highlight presentation was blocked by a locked desktop; compilation and fixture checks passed, but the appearance and Clear Highlights interaction remain unverified.

The main and isolated-test app signatures were verified. The mounted DMG’s application binary and metadata matched the packaged build; its stable bundle identifier, public/internal versions and Applications shortcut were checked.

The standard main-app distribution is a compressed read-only DMG containing the app, an Applications shortcut and install/upgrade instructions. The packaging script verifies the app signature, verifies the disk image and creates a SHA-256 checksum. It packages only the generated application and installation text; user settings and local work records are not included.

## Upgrade compatibility

The main app retains bundle identifier `com.local.LibraryFiler.Alpha`, the existing preferences suite and Application Support location. There is no new settings schema or migration in Beta 2. Public Beta numbering is independent of the internal bundle counter.

Install by quitting the old copy, dragging the new app into Applications and choosing Replace. Export Settings provides a portable pre-upgrade backup. Launch the installed app after ejecting the image and confirm the version and existing profiles. No automatic updater, installer script, settings reset or new background service is included.

The isolated Fresh Install Test edition uses a separate identifier, settings and history. Test-edition review does not certify preservation of a particular production configuration. Actual owner installation and confirmation of existing profiles remain a user acceptance step.

## Existing limits

- Fixture results are not a release-safety certification. Live SMB Move, hardware/network failure, full filesystem attribute fidelity and server durability are not certified by local fixture passes. Reported free space is an estimate, not a reservation.
- Automatic settings backups retain ten pre-change snapshots. Profiles and UserDefaults are separate stores; import/restore is not a crash-atomic cross-store transaction. Native restore and crash/power-loss acceptance remain unverified.
- Minimum-window-width, older-macOS toolbar fallback and comprehensive accessibility/dark-appearance review remain incomplete.
- No automatic crash rollback, unattended filing, video tag writing, transcoding or full-library inventory is provided.
- README workspace images remain the fictional Beta 1 captures; no replacement public captures were needed for this update.

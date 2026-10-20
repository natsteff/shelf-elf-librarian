# Shelf Elf Librarian

<p align="center">
  <img src="Branding/README-Logo.png" alt="Shelf Elf Librarian — the elf librarian at a laptop in front of a bookshelf" width="720">
</p>

**0.1.0 Alpha (Build 13)** · Native macOS 14+ · SwiftUI/AppKit · Apple Silicon

Your libraries, neatly shelved. Thanks to this adorable little elf!

Shelf Elf Librarian prepares filenames and files selected items into separate libraries. Profiles determine the visible file types, optional filename cleanup, destination and folder rules. Processing stays local; there are no accounts, telemetry, online identification services or embedded metadata edits.

## Build and run

Open `Package.swift` in Xcode, or run on a Mac with an Apple Swift toolchain and macOS SDK:

```sh
./scripts/build.sh
open "../Shelf Elf Librarian.app"
```

The script builds the app and standalone fixture runner, runs its checks, packages a fresh app bundle next to the checkout, and signs it locally with an ad hoc signature. The current build targets the machine's architecture; the delivered local builds are arm64. The app is not notarized. `Info.plist` supplies its version and build labels.

## Try the fictional demo

**Load Fictional Demo** creates an isolated workspace and four separate demo library roots under this app's Application Support folder. The tiny files are labeled synthetic text payloads with media extensions, not playable media or valid PDFs.

1. Choose a library profile and open a workspace. Only the profile's accepted extensions appear; unsupported files and links are excluded.
2. Select visible files and review the proposed fields. Confirm filename-based interpretations before filing.
3. Choose a destination category and explicitly confirm it. New categories/folders are created only on Apply.
4. Choose **Copy to Library** (default) or explicitly select Move. **File only** retains source basenames. **Clean Preview** renames in the workspace; **File Preview** combines cleanup and filing.
5. Review complete paths, new folders, groups and conflicts. Apply affects only included, actionable rows. Hidden main-list selections are excluded.

Use one category per operation. Music and audiobook profiles can both accept MP3: the chosen profile, rather than an extension guess, determines the library. For a chapter group, select the chapter files together, enter Author and Book title, and confirm the fields. Chapter numbering is preserved by default.

The last workspace and selected profile restore on launch and files are rescanned read-only. Unavailable or replaced workspaces show a reconnect message. Selections, previews, confirmed categories and pending operations do not resume automatically.

## Configure library profiles

In **Settings**, edit a profile's name, destination root, comma-separated extensions, cleaning rules, extraction mask and output masks. **Save** commits the draft; **Cancel** discards it. **Duplicate as New Profile** creates an independent configuration. **Delete this profile** removes settings after confirmation, leaving library files and operation history intact.

Templates provide defaults for video, music, audiobooks, PDF documents, and **Other / Custom**. Choosing a template alone retains existing rules; **Reset rules to selected template** explicitly applies defaults to the draft.

For ROMs or other file types:

- Duplicate a profile, choose **Other / Custom**, and reset its rules.
- Enter the exact extensions to display, for example `nes, sfc, smc, gba, gb, gbc, n64, nds, chd, iso, zip, 7z`.
- Set the destination root and optional folder rules, then Save.

Custom defaults disable cleanup and parsing, use no item subfolder, and retain the basename and extension, including casing, dots, underscores, repeated spaces and region/version markers. Extensions start empty. `{Title}` uses the basename after any cleanup you explicitly enable; it is also editable per file. There is no ROM-content parsing or archive extraction.

## File operations and recovery

Previews freeze source identity, size, timestamps, SHA-256, parent identity and destination checks. Apply revalidates them. Exclusive filesystem publication prevents overwriting an existing destination; conservative preview checks also detect case/Unicode collisions and duplicate batch outputs.

Copies use an exclusive temporary target, request supported filesystem metadata through `fcopyfile(COPYFILE_ALL)`, and verify the complete payload size and SHA-256 before publication. Same-volume moves use an exclusive rename. Cross-volume moves copy, verify, publish, revalidate the original, and claim the exact source through a journaled holding name before removal. Errors report the actual state and retained/temporary locations. Cancellation stops between files; completed items remain completed and groups are not atomic.

SQLite records frozen plans and per-file transitions with WAL and synchronous FULL. **History & Recovery** exposes results and interrupted operations, including temporary paths. Recovery is journal-assisted and manual: inspect source/destination paths and re-preview retained originals. Nothing is automatically resumed or deleted.

Guarded Undo verifies destination identity/content. Deleting a completed copy needs explicit confirmation. Same-volume move undo refuses occupied original locations or changed files. Cross-volume undo requires a new reviewed operation. Empty folders are left intact.

## Alpha limitations

Use disposable fixtures while evaluating this prototype. Release acceptance is incomplete:

- Some destination traversal/creation remains path based. Hostile concurrent directory replacement and network filesystem semantics need further hardening.
- Payloads are verified, but resource-fork/xattr/ACL fidelity across differing filesystems is not fully verified.
- The verified-copy move branch is exercised through injected fixtures; actual cross-device/network moves, disconnects, disk-full and read-only destinations need further integration testing.
- Case-only/Unicode-equivalent renames, automatic crash rollback/cleanup and automatic cross-volume undo are not implemented.
- Categories are direct child folders. Sorting is by filename. Extraction masks are modest; ambiguous interpretations require review. Clean-only batches spanning multiple parent directories may be refused; process one parent at a time.
- No embedded media/tag editing, sidecar handling, transcoding, collection inventory, automatic file watching or unattended filing.

See [VALIDATION.md](VALIDATION.md) for the scope of the current fixture checks. Screenshots are intentionally deferred during early development.

## Local data

The stable internal identifier is `com.local.LibraryFiler.Alpha`. Its folder under `~/Library/Application Support/` contains profile settings/bookmarks, the SQLite operation journal and explicitly generated demo folders. The original identifier is retained to preserve existing settings across app renames. Source/library discovery and previews are read-only.

## Artwork

The README and launch splash use the supplied **enhanced bookshelf logo**, saved as `Branding/README-Logo.png`, with the current name and no “the.” The welcome workspace uses `In-App-Logo.png`. The compact 48×48 header uses `Header-Portrait-White.png`; the macOS app icon uses `App-Icon-v3.png`. Supplied originals and image-edit prompts are included in `Branding/`.

The splash shows version/build metadata, dismisses after three seconds, and has a Continue button. Replay it through **Shelf Elf Librarian → Show Welcome Screen**.

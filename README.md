# Shelf Elf Librarian

<p align="center">
  <img src="Branding/README-Logo.png" alt="Shelf Elf Librarian — the elf librarian at a laptop in front of a bookshelf" width="720">
</p>

**0.1.0 Alpha (Build 33)** · Native macOS 14+ · SwiftUI/AppKit · Apple Silicon

Your libraries, neatly shelved. Thanks to this adorable little elf!

Shelf Elf Librarian prepares filenames and files selected items into separate libraries. Profiles determine the visible file types, optional filename cleanup, destination and folder rules. Processing stays local; there are no accounts, telemetry, online identification services or embedded metadata edits.

## Filenames and metadata

Shelf Elf Librarian organizes files using filenames, filename components and profile rules. It currently does not read or modify embedded metadata tags, including those in MP3 and MP4 files. Artist, Title and similar components shown in the app are inferred from filenames, not read from media tags. Magic can also use parent-folder names, patterns among selected files and remembered corrections.

Use a dedicated tagging application such as TagCraft for embedded metadata. Metadata support may be considered for a future version.

The filename mask specifies which components appear in the proposed name and their order; the folder mask builds destination subfolders. **Confirmation required** means the user has not confirmed the interpreted components. Select the file, check the components in the right panel, and click **Confirm Filename Components**. The **OK** checkmark and green input tint mean only that the proposed filename exactly matches the current one; yellow means it differs. Confirmation does not replace Preview’s validation of missing values and conflicts.

## Build and run

Open `Package.swift` in Xcode, or run on a Mac with an Apple Swift toolchain and macOS SDK:

```sh
./scripts/build.sh
open "outputs/Shelf Elf Librarian.app"
```

The script builds the app and standalone fixture runner, runs its checks, packages a fresh app bundle in the checkout’s `outputs/` folder, and signs it locally with an ad hoc signature. The current build targets the machine's architecture; the delivered local builds are arm64. The app is not notarized. `Info.plist` supplies its version and build labels.

## Using a workspace

Open your own workspace and configure a library destination in Profile Settings. Fictional demo loading has been removed; automated checks use independent disposable fixtures. Existing demo folders or saved profiles are not deleted.

1. Choose a library profile and open a workspace. Only the profile's accepted extensions appear; unsupported files and links are excluded.
2. Select visible files and review the filename components. Confirm filename-based interpretations before filing.
3. Configure the destination in Profile Settings. An optional advanced category adds one folder beneath the root; a blank category uses the root with any folder-mask subfolders. New folders are created only on Apply. Open Library in Finder is available in Settings and beside the workspace destination path.
4. Choose **Copy to Library** (default) or explicitly select Move. **File only** retains source basenames. **Clean Preview** renames in the workspace; **File Preview** combines cleanup and filing.
5. Review complete paths, new folders, groups and conflicts. Apply affects only included, actionable rows. Hidden main-list selections are excluded.

Music and audiobook profiles can both accept MP3: the chosen profile, rather than an extension guess, determines the library. For a chapter group, select the chapter files together, enter Author and Book title, and confirm the filename components. Chapter numbering is preserved by default.

The last workspace and selected profile restore on launch and files are rescanned read-only. Unavailable or replaced workspaces show a reconnect message. Selections, previews and pending operations do not resume automatically.

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
- Case-only file/folder renames now use journaled staging, guarded undo and explicit staged recovery. Automatic crash rollback/cleanup and cross-volume undo remain unimplemented.
- Categories are direct child folders. Sorting is by filename. Extraction masks are modest; ambiguous interpretations require review. Clean-only batches spanning multiple parent directories may be refused; process one parent at a time.
- Folder Clean renames explicitly selected direct child folders, validates their contents and offers guarded undo; it does not recursively reorganize nested folder names.
- No embedded media/tag editing, sidecar handling, transcoding, collection inventory, automatic file watching or unattended filing.

See [VALIDATION.md](VALIDATION.md) for the scope of the current fixture checks. Screenshots are intentionally deferred during early development.

## Local data

The stable internal identifier is `com.local.LibraryFiler.Alpha`. Its folder under `~/Library/Application Support/` contains profile settings/bookmarks, the SQLite operation journal and explicitly generated demo folders. The original identifier is retained to preserve existing settings across app renames. Source/library discovery and previews are read-only.

## Artwork

The README and launch splash use the supplied **enhanced bookshelf logo**, saved as `Branding/README-Logo.png`, with the current name and no “the.” The welcome workspace uses `In-App-Logo.png`. The compact 48×48 header uses `Header-Portrait-White.png`; the macOS app icon uses `App-Icon-v3.png`. Supplied originals and image-edit prompts are included in `Branding/`.

The splash shows version/build metadata, dismisses after three seconds, and has a Continue button. Replay it through **Shelf Elf Librarian → Show Welcome Screen**.

## New preparation tools (Build 33)

See [Profile rules, Magic, manual editing and script migration](docs/PROFILE-RULES.md) for the full code-versus-settings guide.

- Per-profile hyphen replacement, periods-to-dashes, folder-name cleanup, smart title casing and single-episode S/E formatting/casing.
- Ordered literal Find → Replace rules, scoped to Filename/Folder/Both with Anywhere/Prefix/Suffix matching.
- Configurable artist number/symbol buckets and optional leading-The handling.
- Editable proposed basenames with preserved extensions, override reset and a selected-name replacement editor.
- Optional **Use Magic** with original-name, selected-sibling and parent-folder evidence, alternatives and qualitative confidence; no full-library scans or online service. Manual edits are retained and uncertain items require confirmation.
- Profile-specific correction examples from successful approved operations; explicit Remember/Forget controls. Settings recommendations modify only the draft, and development reports are previewable, anonymized by default and copied only on user action.
- Explicit folder-clean previews with all affected contents, case-only rename staging, guarded undo and interrupted-stage recovery in History.
- Clicking the app-header icon/name/version opens the private GitHub repository.

New cleanup/Magic switches default off for existing profiles. No existing library is reorganized or profile rewritten automatically. Screenshot/visual review remains deferred to the user.

### Direct renaming and filing

Use **Rename Selected to Proposed Names** to rename selected visible changed names immediately in their current folders. The per-row boxed checkmark does the same for one file; it is hidden when no rename is needed. Edit a row's basename and press Return or click Save to rename it on disk. Escape cancels uncommitted typing. Neither typing alone nor losing focus renames a file. The original extension is kept.

Successful direct renames update the current filename, turn the proposal green and clear that row's Include selection. The row undo arrow restores the prior actual filename using journaled, guarded undo; it refuses changed files and occupied original names. Failed rows retain their names/selections and show errors. History retains recovery and undo information after a refresh or relaunch; row undo is available during the current session.

Direct renaming never confirms filename components for filing. The **Components** column refers to the right-side component review, which remains independent. Reselect a renamed file when you want to file it. **Clean Preview** remains available for a reviewed batch rename; **File Preview** prepares copy/move operations into the library. Successful direct renames retain their actual basename as an override so subsequent filing keeps a deliberate manual name; refreshing or changing profile recomputes suggestions.

Header buttons sort columns; Include toggles visible selections. General Settings and Profile Settings are both directly available on the main screen. Shared Spelling Exceptions is the first control under Filename cleaning. Hover explanations are non-interactive overlays so they do not consume button clicks.

Profiles default to **Remember confirmed corrections for Magic by default** enabled. This initializes the workspace checkbox when files load; individual selections can opt out. Only successful operations supply correction examples. Existing examples can be forgotten in Recommendations & Learning. No rules or file operations are applied automatically by learning.

## License & Usage Notice

Shelf Elf Librarian is free, open-source software under the [GNU Affero General Public License, version 3 (AGPL-3.0)](LICENSE). Its standard warranty and liability provisions apply; there is no separate restrictive EULA or custom monetary liability cap.

Read the [License & Usage Notice](USAGE-NOTICE.md) for backups, previews, file operations and recovery considerations. This notice does not restrict rights granted by AGPL. The app includes the same notice and complete license, accessible at startup and through **License & Usage Notice…** in the app menu.

The notice appears once per new app version/build or notice version. **Continue** acknowledges the notice locally; it does not accept an additional contract. **Quit** closes the app without acknowledgment, so the notice appears again next launch. AGPL section 9 does not require acceptance merely to run the software.

See [the cross-project Codex handoff](docs/SHARED-TERMS-HANDOFF.md) for reuse and platform considerations.

## Content types and shared spelling

Content type selects interpretation and the editor's filename components. Changing it keeps existing rules, extensions and masks; **Load defaults for this content type** replaces those settings while preserving profile name and destination. Other / Custom starts without media parsing or automatic cleanup.

Spelling exceptions now live in **General Settings** in the app menu and apply to every profile. Profile Settings links to this shared editor. Old per-profile exception lists are ignored, not migrated. Saving the shared list refreshes the workspace, clearing pending proposals and selections.

Video, Music and Audiobook expose **Season/episode capitalization** (Keep original, Uppercase, Lowercase), separate from separator formatting and whole-episode-filename lowercasing. Keep original protects indicator letter case from title and whole-name casing. Explicit indicator case wins over whole-name lowercasing; shared spelling exceptions apply last. Documents and Other / Custom do not apply these episode rules. Extensions are preserved. Example: `Show s01e01 Pilot` can become `Show - S01E01 - Pilot` when formatting and Uppercase are enabled.

### Seeing proposed differences

The current filename marks removed or replaced characters in red. The proposed-name input highlights replacement or added characters in blue while not focused; editing uses ordinary text. **Show changes** expands an actual-difference summary and comparison using visible space (`·`) and tab (`⇥`) markers. These markers are display-only, never inserted into filenames. Filename text is slightly larger. Comparisons are cached per displayed row and recomputed when its filename/proposal changes; long names use a bounded fallback. This changes presentation only, not cleaning or rename behavior.

Build 33 strengthens red source highlights and adds changed-character hover descriptions without inserting marker characters in filenames. The general editor tooltip is removed; focused editors show “Enter to rename · Esc to cancel” below the input. Workspace and library Reveal in Finder actions select the folder in Finder rather than opening its contents.

Build 33 uses a single fully opaque, click-through native hover panel above the list. Scrolling, clicking, typing, leaving its target, loss of window focus, and changes to its target clear it. Helpers appear on actual mouse movement rather than appearing from row relayout alone. **Show Workspace/Library in Finder** opens the folder contents.

Clear season/episode spacing such as `s01e 10` or `s 01 e 10` is repaired before ordinary cleanup for supported content types with episode handling enabled. Indicators are protected during title casing and literal replacement; episode separator formatting and the explicit capitalization choice run afterward. Split digits are not guessed. If Hyphens to spaces is enabled without episode separator formatting, those separator hyphens are intentionally removed.

Show changes includes **Rules triggered**, recorded from cleanup stages that actually changed text during basic interpretation. Enabled rules with no effect are omitted. Manual filename overrides are identified separately. Magic interpretation currently reports when per-rule attribution is unavailable rather than guessing from the final difference; output masks and component edits can also change the final name independently of cleanup.

Build 33 keeps literal filenames in rows and replaces changed whitespace only in expanded comparisons with explicit display labels such as `[[SPACE]]`, `[[SPACES × 2]]`, and `[[TAB]]`. One warning identifies any reserved labels that also occur literally in the filenames. Case-only word changes use “Corrected preferred case” hover wording. Filename component inputs retain labels above their values; the right panel has no fixed maximum width and can be widened with the divider, subject to the file list’s minimum width.

## Universal spelling, case and title-word preferences

General Settings groups **Universal Spelling & Case Preference Exceptions** into Abbreviations & acronyms; People, artists & organizations; Brands, products & platforms; Formats & technical terms; Editions, regions & identifiers; and Other preferred spellings. Commas and line breaks separate entries. Groups are organizational only: every entry applies to every profile. Display-only examples are not saved entries. The selectable gray combined list previews exactly what Save will activate. Identical entries are deduplicated, and conflicting capitalization blocks Save until resolved. Existing app-wide exceptions are retained in Other; old profile lists are not merged.

Removable labels delete matching text before exceptions apply. An exception does not preserve or restore a removed label: `1080p` can be removed by one profile but retained in its preferred case by another. Overlaps are informational. Preferred entries protect their punctuation and normalize spaces around internal hyphens before parsing and cleanup. They do not perform fuzzy spelling correction. Extensions are preserved.

**Universal lowercase title words** is a separate shared list in General Settings. Each profile still enables Title case and Smart title casing independently. When enabled, it uses the shared list; explicit exceptions win afterward. Old profile-specific title-word lists are ignored. Save refreshes the workspace, clearing pending proposals and selections.

Episode-component hover explanations distinguish preferred-case changes, spacing repairs and numeric padding, including when more than one applies to the same component.

## Advisory filename spelling checks

Unrecognized words in source basenames receive solid amber underlines on the current filename, independent of red/blue rename differences. Show changes lists the words and explains that names, invented words and foreign-language titles may be intentional. The details remain available when the filename itself needs no changes. These warnings never block renaming/filing or affect component confirmation. There are no spelling hovers, suggested replacements or automatic corrections.

Checks use macOS NSSpellChecker's background spelling service and preferred languages, checking lowercase words and caching results by word/languages. Matching universal exceptions (including complete multiword entries), recognized episode indicators and numeric identifiers are excluded. Extensions are not checked. General Settings offers **Flag unrecognized filename words**, enabled by default. The current filename carries the underlines; proposed-name inputs are reserved for rename differences. Spelling results refresh when the source basename or universal exceptions change.

## Suggested entries and protected text

**Load Suggested Entries** at the top of General Settings asks for confirmation, then appends missing suggestions to the settings draft. Matches are checked case-insensitively across all groups: existing entries remain in their current groups, identical suggestions are skipped, and conflicting suggested capitalization is skipped in favor of the user’s entry. Counts report added, existing and conflicting entries. Save commits; Cancel discards. No suggestions are added to Other. Fresh installations use alphabetized, comma-separated defaults in the other groups, with no embedded line breaks; existing installations are not automatically changed.

Preferred entries are recognized before delimiter parsing and protected through destructive cleanup. For example, `ac - dc - song name.mp3` can suggest `AC-DC - Song Name.mp3` without splitting AC and DC into separate components. Matches require complete letter/number boundaries; `BAC-DC`, `BAC-DCE` and `AC-DCE` do not match AC-DC. Ordinary cleanup can still affect those unmatched names. Removable labels take precedence, including when a removable label is also a preferred entry. Compiled matching patterns are cached.

Spelling warnings use a **solid amber underline**. Show changes lists dictionary checking separately from Rules triggered because checking is advisory and does not modify names.

## Books, comics and additional music components

Content type **Books & Comics** has Mixed, Audiobook, Ebook and Comic subtypes. Existing Audiobook profiles retain the Audiobook subtype. Choose a subtype, then use **Load defaults for this content type** if you want to replace the current extensions/masks with its defaults; changing subtype alone preserves custom rules.

Shared book components: Author, Title/BookTitle, Series, SeriesNumber, Publisher and Year. Audiobooks add Narrator, ChapterNumber and ChapterTitle. Comics add Illustrator, IssueNumber and Volume. `{Title}` aliases the book title for this content type. Examples: `{Author}/{Publisher}/{BookTitle}` as folders, or `{Series} - {IssueNumber} - {BookTitle}` as a filename. A component is required only when the chosen output mask references it.

Music adds `{Year}`, `{TrackNumber}`, `{TrackNumber:02}`, `{RecordingType}` and optional `{Live}`. Recording type is Unspecified, Live or Studio. Unspecified is never inferred to mean Studio. `{Live}` outputs `(Live)` only for Live and is otherwise blank; adjacent extra whitespace from its omission is tidied. Example: `{TrackNumber:02} - {Artist} - {Title}`. The default music filename remains `{Artist} - {Title}`.

A leading numbered section can supply TrackNumber. Explicit parenthesized years and bracketed Live/Studio labels can supply Year/RecordingType, but are retained in Title to avoid silently deleting information. Other new components are supplied by extraction masks or manual entry. These features do not read embedded tags or infer publishers, narrators or illustrators from absent evidence. All new values participate in journal serialization and correction reports; legacy records decode with empty optional components.

Build 33 moves spelling warnings to the current/source filename, leaving the proposal's red/blue difference display separate. Workspace controls show **Show Workspace in Finder** before **Currently open Workspace:** and the path. Selection/rename buttons precede the filename filter. Profile Settings keeps the profile name in its fixed heading and separates the scrolling form from fixed footer actions with a divider and padding. A single status bar prevents overlapping cancellation controls and labels discovery cancellation **Cancel Scan**. Additional General Settings proposals and the lower-right filing actions are unchanged.

Build 34 makes Magic explicit: **Run Magic on Selected Files** above the file list analyzes selected visible files only, in the background, with cancellation between files. Startup, workspace/profile switches, Refresh and settings saves discover files and run ordinary cleanup without Magic. The former profile-level Use Magic switch and lower-right Analyze Selected button are replaced by this action; remembered corrections remain a separate opt-in. Cancelling Magic retains existing proposals.

General Settings now includes **Show filename differences** (red/blue highlighting only; spelling underlines remain independent), **Hover help** (Immediate, Short delay of half a second, Off), and **Default filing action** (Copy or Move, with Copy as the initial default). Hover timing covers application help panels and character-change explanations. The filing default takes effect at app startup; the workspace Operation selector overrides it for the current session. Existing saved preferences retain the previous display defaults. Other lower-right filing controls are unchanged.

Build 35 restores **Enable Magic for this profile** in Profile Settings, preserving each profile's saved value. Enabled profiles show the wand icon and **Magic enabled** beneath the profile picker. **Run Magic on Selected Files** appears only for enabled profiles and requires a selected visible file. Magic remains manual; discovery and refresh never run it automatically.

Build 38 connects bulk filename-component edits to episode proposals. Recognized TV episodes leave Title blank and use Series, Season, Episode and Episode Title. Legacy video `{Title}` / `{TitleYear}` masks render the assembled episode name, so editing Series or Season updates each selected file's proposal while retaining its own episode number/title. Movies retain Title/Year behavior. Editing components supersedes a manual filename override; typing alone does not touch files. **Rename Selected to Proposed Names** applies reviewed proposals in the current folders without requiring component confirmation for filing.

The component editor repeats the current filename beneath its heading (identifying the example when multiple files are selected). Clicking current filenames, type/size, review status or unused row space selects that file alone; checkboxes retain bulk selection and existing editor/buttons keep their actions. The Magic indicator aligns to the dropdown's left edge. The filter includes a clear button and an eligible-result count; **Show excluded filenames** sits beside the lower-left eligibility summary. Filtering does not change eligibility or selection counts.

Build 39 adds on-demand macOS spelling suggestions through **Suggestions…** beside unknown words in Show changes and a contextual menu on amber-underlined source words. Both offer manual replacement when needed. A choice replaces complete matching words in that file's existing proposal, preserving its other edits and extension; universal case preferences apply to the replacement. No disk changes occur until Rename. Show changes provides **Undo spelling replacement** for the latest proposed correction, guarded against later edits; the source warning remains until the source is renamed. The app does not change the system's learned or ignored words.

Existing-folder cleanup is now **Tools → Clean Folder Names…**. The chooser and review identify the active profile. A separate **Smart title case (existing folder names)** preference defaults on; universal preferred spellings/punctuation and universal lowercase title words apply, along with folder replacements and the folder hyphen setting. Generated destination-folder behavior is unchanged. Preview explains applied rules or why no change is needed. Only selected direct child folder names are changed, with the existing collision, content-validation, journal and undo guards; child names and contents remain unchanged.

## Configurable interpretation and filing — Build 40

Profile Settings now includes ordered **Workspace Filename Patterns & Filing Types** with tests against example names or selected files. Patterns capture components, assign a classification from a dropdown or read it from a filename, and map Type/System/Genre to relative folder and filename layouts. Video, music genres, ROM systems, FORGE game names, book series hierarchies and additional custom captures share the same engine. Unknown captured classifications require review. Magic remains manual.

New content types are **Video Game ROMs**, **Photos**, and **Software & Installers**. Nine starter profiles are preloaded on new installations, including FORGE and separate audiobook/ebook profiles. Music buckets remain music-specific. Optional `{Series?}` folder levels and `{BookFolder}` support standalone and numbered-series books. Parent-folder interpretation is available explicitly and is disabled by default in audiobook starters. No embedded media or photo tags are read.

Existing profiles migrate after an automatic settings backup. Their enabled compatibility rule retains previous interpretation; editable suggested rules are supplied disabled for review. Category folders are folded into masks, preserving destinations and bookmarks. **Description / Notes** is optional multiline profile text and travels with settings exports. Notes do not affect interpretation or learning signatures.

**Tools → Export Settings / Import Settings** saves/restores profiles and General Settings. Import confirms replacement and saves a backup first. Library files and history remain separate. A separately signed **Fresh Install Test** app uses isolated preferences, profiles and history. See [pattern documentation](docs/FILENAME-PATTERNS.md) and the [fresh-install review guide](docs/FRESH-INSTALL-REVIEW.md). GitHub publishing remains on hold.

Build 41 gives all nine starter profiles default descriptions and organization recommendations. Each begins with the same optional-starter paragraph. FORGE includes the project link and approved explanatory text. Existing matching profiles receive descriptions only when Notes was never set; custom notes and intentionally cleared notes are preserved. Profile rules and destinations are unchanged.

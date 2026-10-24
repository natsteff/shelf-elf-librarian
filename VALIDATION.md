# Validation scope

The current app is **0.1.0 Beta 1 (internal build 72)**, compiled for arm64 and locally ad hoc signed. The latest build completed with **zero failures across 99 disposable fixture scenarios**. Both the main app and isolated Fresh Install Test edition were packaged and their signatures verified. Native GUI appearance and interactions require manual review.

Beta 1 publication validation: all 99 disposable fixture scenarios pass. Main and test app signatures verify. Native fictional-workspace and copy-preview screenshots were captured from a dedicated isolated demo edition. The settings import replacement confirmation was verified to appear after the chooser, then cancelled without importing; chooser completion is deferred until the chooser has detached. The screenshot edition has separate profiles/preferences/history and uses only opt-in bundle configuration; the normal and Fresh Install Test release bundles have no screenshot root. Public Beta numbering is separate from the monotonically increasing internal bundle build number (72). Known live SMB move/hardware and minimum-width acceptance gaps remain as documented.

Build 71 promotes the release label to Beta at Nate’s direction. Version remains 0.1.0, with the existing bundle identifier, support folders, profiles, preferences and history retained. Validation scope and known acceptance gaps are unchanged; Beta labeling is not additional safety certification.

Build 70 moves the existing elf-head link into the leading toolbar group before Profile Settings, removes the profile picker’s fixed 240-point frame and reduces group gaps to 8 points. Center title/version and trailing General Settings/History are retained. Native appearance of the content-sized picker remains for owner review.

Build 69 implements Nate’s revised header grouping: profile sliders, profile picker and full Magic status left; app name/version centered; general-settings gear and History right. The original elf head begins the workspace ribbon, retaining its website link. All 99 scenarios pass. Native isolated-test screenshot at 1320x850 confirms alignment and icon assignment. Minimum-width and older-macOS fallback review remain outstanding.

Build 68 explicitly retains Magic status text in the native toolbar, inserts flexible toolbar space before the fixed-size trailing brand, and removes the expanding workspace-path frame so its Finder button stays adjacent. macOS 26 uses native ToolbarSpacer; earlier systems use a SwiftUI spacer fallback. Native isolated-test visual review at 1320x850 with populated files confirms full Magic text, left controls, far-right branding and workspace Finder beside the path. Minimum-width and older-macOS fallback review remain outstanding.

Build 67 moves profile/Magic status, settings/history and original branding into the native unified title-bar toolbar. Workspace counts, selection status, table headings and row metadata use 13-point system text; metadata columns and footer height are expanded to accommodate it. No file-operation behavior changes. All 99 scenarios pass; native toolbar/minimum-width/populated-workspace visual acceptance remains outstanding.

Build 66 is the first grouped UI pass: regular-size workspace/header/filing controls with consistent 13-point system labels, increased gaps/padding and a wider operation picker. Existing wording/actions, split layout, logos and transfer behavior are preserved. Native layout inspection results are recorded in the work log.

Build 65 adds automatic pre-change settings snapshots (newest 10) and a restore picker. Two additional disposable scenarios exercise retention, profile/general round-trip, pre-restore backup, legacy compatibility, naming collisions, corrupt/foreign restore refusal, isolated stores and backup failure preventing profile replacement. Native restore UI and crash/power-loss acceptance remain manual.

Build 64 adds a local date/time suffix (yyyy.MM.dd-HH.mm) to the suggested settings export filename. Archive contents and import behavior are unchanged.

Build 63 replaces the Copy/Move segmented selector with horizontal native radio buttons and shortens the ordinary execution button to Copy/Move N Files. Magic retains its explicit Run Magic action label. Transfer behavior is unchanged; native visual review remains manual.

Build 62 keeps Copy/Move dialogs open for progress and completion in reviewed filing, keep-current-name filing and Magic. Completion includes copied/moved and failed counts, inline error/recovery details, cancellation status and an explicit Done button. Move completion waits for workspace refresh. Native dialog appearance and interactions require manual review. SMB batch free-space preflight is covered by an injected insufficient-space check confirming that no destination is created and the source remains intact; capacity estimates do not reserve space or guarantee server durability.

Build 61 adds forced SMB copy/move, occupied-destination refusal, failed verification with retained source and recovery path, Magic tag preparation/publication, correct final journal identity, and persisted bucket/notice values. These use disposable local fixtures to exercise the SMB algorithm. A live SMB test was attempted on /Volumes/music and its Spotify subfolder, but macOS denied creation of the disposable test directory (EPERM). Nate subsequently confirmed seven copies completed successfully on his SMB share in Build 61. Live SMB move behavior and native popup/layout review remain unverified. The standalone runner supports `--smb-smoke /path/to/share`: it creates and removes only a UUID-named test directory and also reports the share's protected-rename response.

Build 59 adds coverage for Documents custom capture editing/rendering/persistence, fixed Music/Video capture validation, removed legacy extraction and cleanup behavior, optional audiobook SeriesName, ROM extension routing and original-filename preservation, editable System destinations, ambiguous extensions and linked-disc-set guards. Builds 56–58 also cover bounded MP3/video reading, reviewed tag update/purge, verified audio preservation, optional Magic staging steps and 30-day history retention.

Build 60 adds regressions for Music/Video parsing with nil, empty, obsolete compatibility and misconfigured pattern rows; schema-2 profile repair and persistence; Music Artist/Title/track recognition and Video TV/movie classification; default-on resolution shorthand, portrait/cropped sizes, explicit labels and full-dimension opt-out.

Historical build notes below describe coverage at those points in development; the current behavior is documented in README.md.

## Reproduce

Run `./scripts/build.sh`. It builds and runs `SafetyChecks` against disposable temporary fixtures, packages the app, and verifies its local signature. The runner invokes the production planner, executor, journal and undo coordinator. It does not require XCTest.

The scenarios cover:

- Copy payload/source preservation and explicit guarded copy undo.
- Same-volume move, occupied-original refusal and guarded move undo.
- The independently forced verified-copy move branch.
- Injected verification/publication failures retaining source/recovery information.
- Journal reopening, existing/late destination conflicts, duplicate batch outputs and no-op.
- Stale sources, replaced destination roots, links/dangling links and path traversal.
- Cancellation between files and externally changed undo targets.
- Profile eligibility, missing/unconfirmed interpretation fields, chapter grouping and shared destinations.
- Unexpected new destination folders, music/video output paths and extension-case preservation.

These checks are not a release-safety certification. They do not cover actual unplugged/network volumes, disk-full/read-only hardware failures, all concurrent filesystem races, or metadata fidelity across differing filesystems. The verified-copy move branch is forced on local fixtures rather than tested on an actual second volume. See the README limitations.

## Build 14 additions

Fixtures also cover ordered/scoped/anchored replacements, extension preservation, episode separators/casing, intelligent title words, artist bucket behavior, manual overrides and journal learning, legacy profile decoding, profile/context/settings-isolated memories, conflicting Magic group alternatives, noninvented required fields, recommendations and anonymized reports, case-only file rename/undo/restart recovery, and explicit folder rename/undo/conflict/link/stale-content/cancellation/recovery paths.

No real workspace/library files or saved user profiles were modified during these checks. No UI automation, screenshot refresh or whole-library scan was performed for this release. The fixtures do not resolve the remaining concurrent path, network-volume, metadata-fidelity or hardware failure acceptance gaps.

## Build 33 additions

New fixture coverage verifies fresh suggested defaults with Other empty; append idempotence and cross-group duplicate/case-conflict handling; preferred punctuation and complete-entry boundaries; AC-DC delimiter parsing in basic and Magic modes; removal precedence; book subtype defaults and new mask/extraction fields; legacy field decoding; music track/year/recording evidence and optional Live output. Prior direct rename/undo, filesystem guards, spelling token exclusions, display comparisons and episode-order checks remain included.

UI appearance, dictionary availability in the normal app, and new settings/subtype workflows remain for owner review. No real library contents or user preference files were changed by these fixture checks. Build 59 is prepared for public source and binary publication.

Build 33 is a UI/source-spelling presentation update. All 41 disposable fixture checks remain included. New control placement, scrolling footer separation, status layout and source underline placement are awaiting owner visual review; no UI automation was performed.

## Build 34 additions

The fixture suite now includes 42 scenarios. Added coverage verifies discovery remains ordinary cleanup even for legacy profiles with Use Magic enabled, explicit Magic produces alternatives, cancellation returns no partial result, older general preferences decode with existing defaults, and new preferences round-trip through JSON. All filesystem tests use disposable fixtures. Native tooltip timing, control layout and appearance remain for owner visual review; no UI automation or real library changes were performed.

Build 35 restores the profile-level Magic preference and conditions both the header indicator and manual action on that preference. The action also guards against disabled profiles. The existing 42 fixture scenarios remain included; header placement and conditional controls await owner visual review.

Build 36 anchors the Magic indicator below the profile picker as an overlay, so the picker and adjacent header buttons share their original row alignment. No behavioral changes; owner visual review remains.

Build 37 corrects the Magic indicator overlay using a position below the picker's top edge; the prior alignment guide allowed text to overlap the picker. Header controls retain one-row alignment. Visual placement awaits owner review.

Build 38 adds a 43rd disposable fixture covering differently named episode sources, blank episode Title in ordinary and Magic interpretation, shared Series/Season corrections preserving per-file episode values, unchanged source paths before explicit rename, successful explicit batch rename, invalid numeric episode input, and movie Title/Year behavior. Row clicks, filter controls, footer placement and dropdown alignment require owner visual review; no UI automation or real library changes were performed.

Build 39 adds two fixture scenarios (45 total): spelling replacement boundaries, repeated words, Unicode offsets, preferred case and invalid/path replacements; and existing-folder title case, protected hyphens/universal exceptions, rule explanations, explicit disable behavior, and unchanged child bytes after rename. Existing folder collision, cancellation, stale-content and guarded undo checks remain included. Native dictionary suggestions and contextual/popover placement require owner review in the running app; the sandbox does not validate the macOS spelling service. No real library files or system spelling dictionaries were modified.

## Build 40

51 disposable fixture scenarios cover editable pattern precedence, captures, literal labels, classification aliases and unknown values, per-type routes and filenames, custom components, optional book hierarchy, opt-in parent-folder chapter interpretation, ROM/FORGE/software/photo/music-genre defaults, migration preserving identities/destinations/bookmarks/notes, archive validation and round-trip, protected delimiters, and explicit classified copies. All previous filesystem, undo, cancellation, spelling and manual-Magic checks remain included. Existing on-disk settings were backed up read-only and the importable archive validated as containing nine profiles; normal application settings were not modified by the build/test commands.

The Fresh Install Test app is built with a distinct bundle ID, preference suite and support/history directory. It is signed and verified but not launched automatically. Native settings layout, dropdown/pattern editing, spelling service behavior and interactive test-app isolation remain for owner review. Metadata reading and actual cross-volume/network/hardware acceptance gaps remain outside this build's validation.

Build 41 adds informational descriptions to starter profiles, backfills only unset notes on matching names/content types, and preserves explicit notes including an empty string. The existing 51 fixture scenarios remain the validation suite. The Fresh Install Test artifact and starter settings archive are refreshed with the same descriptions; neither app is launched by the build.

Build 42 changes workspace presentation only. The existing 51 fixture scenarios pass; no core parser, filing, rename, undo, settings migration or spelling logic is changed. Per-file proposal editors and checkmark/save/undo conditions are retained. Native toolbar/inspector sizing and appearance require owner visual review; no UI automation or real library operations were performed. Build 41 code and both app bundles were saved before edits. Both Build 42 app bundles are signed and verified; the Fresh Install Test edition still uses isolated settings/history.

Build 43 retains the 51 passing fixture scenarios. All file/folder/save choosers now route through the window-attached presenter; standalone modal confirmation remains only as a fallback when no app window exists. Toolbar background suppression is availability-gated to macOS 26; earlier systems retain native toolbar behavior. Hover placement is clamped to the owner window and visible screen bounds, with dismissal on owner move/resize. About/Help are nonmodal child windows centered over their owner and constrained to screen bounds. New native presentation, field contrast and window positioning require owner visual review; no UI automation or real library operations were performed.

# Validation scope

The current local app is **0.1.0 Alpha (Build 33)**, compiled for arm64 and locally ad hoc signed. The latest build completed with zero failures across 41 fixture scenarios. Screenshots are deferred during early development; the new preparation/settings interface is awaiting user review.

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

UI appearance, dictionary availability in the normal app, and new settings/subtype workflows remain for owner review. No real library contents or user preference files were changed by these fixture checks. GitHub publishing remains on hold.

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

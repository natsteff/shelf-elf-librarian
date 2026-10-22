# Shelf Elf Librarian — rules, Magic and manual editing

0.1.0 Alpha, Build 14

## What changed in code versus what you configure

All seven script behaviors now have app capabilities. You do **not** need to write Swift or shell code for them. Enable and configure the appropriate features per profile in **Settings → Filename cleaning**, then Save. Existing profiles keep the new cleaning/Magic switches off until you enable them. Artist numeric/symbol bucket behavior is now configurable, with defaults `0-9` and `#`.

| Former script | Capability added/provided by code | Profile settings and action |
|---|---|---|
| `dashestospaces` | Basename hyphen replacement; extension stays unchanged | Enable **Hyphens to spaces (filenames)**. Enable whitespace normalization if you want repeated spaces collapsed. Use **Clean Preview** to rename in place. |
| `dashestospacesdir` | Separate existing-folder planner/executor, content revalidation, journal and guarded undo | Enable **Hyphens and surrounding spaces to one space (folder names)**. Click **Folder Clean…**, choose direct child folders of the workspace, review their contents, include the folders you want, then Apply. It renames those folders only, carrying their contents without editing child names. |
| `dotstodashes` | Period replacement within the basename, retaining the original extension/case | Enable **Periods to ‘ - ’ (basename only)**. It takes precedence over separator dots to spaces. This explicit rule replaces decimal/date/initial periods too; leave it off if those periods are meaningful. |
| `episodeformat` | Recognition of single S/E identifiers and separator formatting; structured TV mask fields | Enable **Format TV identifiers with ‘ - ’ separators**. Examples: `show.S1E2.title` → `Show - S01E02 - Title` when separator-dot cleanup and Title case are also enabled. Use a video-specific extension list to scope it. |
| `lowerepisode` | Targeted identifier casing, plus a separate whole-TV-basename option | Enable **Lowercase TV identifiers (s01e01)**. If your old script lowercased the whole TV name, also enable **Lowercase the entire TV basename**. Non-TV filenames do not get lowercased by that option. Extensions retain their original case. |
| `music-sort` | Artist field hierarchy, A–Z buckets, a configurable numeric bucket and a symbol bucket | Use Music, set extensions to `mp3`, choose the mounted Synology music root, enable **Music first-letter bucket**, and use folder mask `{Bucket}/{Artist}`. Numeric bucket defaults to `0-9`; symbol bucket defaults to `#`. Optional **Ignore leading The for bucket only** retains “The” in the artist folder. |
| `titlecase` | Smart title capitalization with configurable small words and protected TV identifiers | Enable **Title case**, then **Smart title casing**. Edit **Lowercase title words** as needed. First/last words and words after title separators remain capitalized. **Spelling exceptions** have final precedence, for example `DJ, VNV Nation, BT-AI, III`. |

For pure filename cleanup, use **Other / Custom**, the desired extensions and filename mask `{Title}`. Structured profiles construct names from fields: explicit separators/literals in the output mask remain authoritative. For example, a music mask `{Artist} - {Title}` deliberately inserts that separator; use `{Artist} {Title}` if you want no hyphen between those fields. Generic cleanup acts on the source/title fields, not arbitrary executable expressions in a mask.

Folder-scoped rules also affect newly constructed destination folder components. Do not enable folder hyphen cleanup in a music profile if you want to preserve a literal `0-9` bucket or `- Singles` folder.

## Ordered literal replacement rules

Under **Ordered literal Find → Replace rules**, add replacements, choose Filename/Folder/Both, and choose Anywhere/Prefix/Suffix matching. Empty replacement text deletes a match. Up/down buttons set order. Enabled rules need nonempty Find text; separators/control characters cannot be inserted into paths.

Built-in underscore/hyphen/dot replacements run first, followed by literal replacements, whitespace normalization, casing/TV formatting and spelling exceptions. Prefix/suffix are applied to the assembled filename. Folder masks are relative to the profile root. All resulting components are validated and conflicts are previewed.

These are literal rules, not shell commands or a regex language. Masks combine supported fields. For music, generic filename edits may be clearer as changes to Artist/Title or to the output mask; use Other / Custom for one undivided basename.

For `music-sort`, allow and confirm the library root if buckets should sit directly under it; otherwise the selected category comes before `{Bucket}`. Set filename mask `{Artist} - {Title}`, or select **File only** to keep the source basename. Review Artist before filing; no embedded tags are read. The app does not scan the destination library to identify artists.

## TV masks

Supported fields now include `{Series}`, `{Season}`, `{Season:02}`, `{Episode}`, `{Episode:02}`, `{EpisodeID}`, `{EpisodeTitle}`. For example:

- Folder mask: `{Series}/Season {Season:02}`
- Filename mask: `{Series} - {EpisodeID} - {EpisodeTitle}`

Missing values block the affected row rather than creating an Unknown folder. This initial parser handles a single S/E pair, including spaced/dotted/underscored forms. Multi-episode ranges and `1x02` notation do not have dedicated parsing yet; review them manually. Date/revision document fields are also available as `{Date}` and `{Revision}`.

## Manual proposed filenames

Edit the proposed basename directly in the workspace row. The current filename stays above it and the locked original extension stays beside the editor. Your entry is an override: Magic and output masks cannot silently replace it. The reset arrow removes the override and returns to a suggestion that must be reviewed.

Select files and use **Edit Selected Names…** for a deliberate literal replacement across selected visible proposals. Hidden selections are excluded. Field edits in the selection editor apply to the selected visible files; a Magic alternative applies to the item named above the alternatives menu.

No rename occurs while typing. The preview recomputes full destinations, conflicts and no-op states. File-only deliberately keeps the original basename even if a manual proposal exists. Confirm category again after edits, then preview and Apply. Case-only file/folder renames are supported through journaled intermediate names; History offers guarded undo and recovery of interrupted staged renames.

## Magic: optional, local, reviewable

Enable **Use Magic** in a profile, Save, select files and click **Analyze Selected**. Magic uses original filenames before cleanup, the active profile, parent folder names, reviewed selected siblings, spelling rules and explicitly remembered examples. It never scans the whole destination library or calls an online AI service.

It can suggest artist/title, movie title/year, TV fields, audiobook author/book/chapter, or document date/revision markers. Evidence, qualitative strength and alternatives are shown in the selection editor. Competing selected book groups remain unresolved until you choose one; absent chapter titles, authors, years and other fields are not invented. Suggestions require confirmation and do not execute anything automatically.

Manual names/fields are retained on reanalysis. The executor independently revalidates the frozen plan. Clean-only and file-only remain available. Magic is an initial set of transparent local heuristics, not a general understanding of every naming convention.

## Learning and recommendations

Successful user-approved operations record original → automatic → final names and field corrections in the local journal. Unchanged automatic proposals do not create correction examples. Undo removes an example from active learning. Check **Remember confirmed corrections for Magic** when you want those corrections reused; otherwise they are only recommendation evidence.

Remembered exact-name suggestions are scoped to the same profile and source parent. They are not reused after profile settings change until reapproved under those settings. Reviewed field corrections can be reused within the compatible profile; every suggestion still needs review. It does not learn from unobserved Finder edits or inventory entire libraries.

**Settings → Recommendations & Learning** appears when evidence exists:

- Repeated distinct corrections can suggest a spelling exception, prefix/suffix, anchored removal, or literal replacement.
- Excluded extensions can be suggested with explicitly weak evidence. An observed extension alone does not mean it belongs in this profile.
- **Add to Profile Draft** changes only the draft; Save/Cancel still applies. Dismiss ignores a suggestion.
- Recurring name/field corrections can produce a **Profile Development Recommendation**. It is a discussion report, not proof that new code is required: first consider whether existing masks/rules express the changes.
- Reports show before/automatic/approved examples and changed fields. They default to anonymized filenames/profile names and omit filesystem paths. Preview, then Copy Report; nothing is automatically shared or uploaded.
- **Forget** removes an example from learning, preserving the operation journal for recovery.

## Remaining limits

Folder Clean operates on explicitly selected **direct child folders**, not a recursive folder reorganization. It validates all their contents, including hidden files; links/aliases and unreadable or changed contents are refused. Contents move with the directory, so all affected paths are listed even when the active profile excludes their extensions. Cancellation is between folders.

The existing alpha limitations on hostile concurrent path changes, network filesystem behavior, full metadata fidelity and cross-volume undo still apply. Tests use disposable fixtures; external/Synology volumes have not been integration-tested here. No user profile settings or real libraries were modified as part of this implementation. Visual review is left to you.

# Profile rules, Magic and manual editing

Current behavior: **0.1.0 Alpha, Build 59**. See the [README](../README.md) for setup and limitations, and the [pattern guide](FILENAME-PATTERNS.md) for mask syntax.

## What you configure

Profile Settings controls accepted extensions, library location, filename interpretation, cleanup, generated names/folders, Magic and remembered corrections. Changing the content type alone preserves rules; Load defaults replaces them explicitly. Save commits the draft and Cancel discards it.

| Task | Current control |
| --- | --- |
| Replace specific filename text | Advanced cleanup & replacements: ordered literal rules with filename/folder/both scope and anywhere/prefix/suffix position |
| Convert filename periods | Period handling: keep, separator periods to spaces, or all periods to spaced hyphens; the last two cannot be enabled together |
| Apply title casing | Title case; Smart title case uses General Settings’ editable Universal lowercase title words |
| Format episodes | Format season/episode separators and Season/episode capitalization; whole-episode lowercasing is removed |
| Convert hyphens | Use explicit filename replacement rules; broad filename hyphen conversion is removed. Destination/existing-folder cleanup has separate folder settings |
| Organize music artists | Folder masks, numeric/symbol buckets, optional bucket-only leading-The ignore, and independent leading-The-to-end formatting |
| Rename existing folders | Tools → Clean Folder Names…; preview explicitly selected direct child folders and their contents |
| Read components | Workspace Filename Patterns & Filing Types…; editable ordered patterns, with no legacy extraction-mask control |
| Route files | Folder/filename masks, Type/System/Genre layouts, and optional video Media Categories |

Extensions retain their original spelling/case. Removed labels take precedence over preferred-spelling exceptions. Explicit fixed text in output masks is retained.

## Proposed names and components

Typing a basename does not rename a file. Enter or the row checkmark applies it; Esc cancels. Rename Selected applies proposals to selected visible files in their current folders. Manual names override generated filename masks until reset or superseded by component edits.

Component edits change proposals. Normal library filing separately requires confirmation of interpreted components; renaming alone does not confirm them. Keep Current Filenames skips individual component confirmation but still computes folder destinations and validates them. A blocked file stays blocked until its missing values or conflicts are resolved.

Documents profiles can define custom captures directly in patterns, such as `{GameTitle} - {ResourceName}`. Those names appear in the component editor and output masks. Music and Video retain built-in captures and metadata mappings. Books support SeriesName as an alias of Series and optional folder levels.

## Magic

Enable Magic for the profile, select visible files, then click Run Magic. It uses local filename, parent-folder, selected-file and remembered-correction evidence. Alternatives and evidence remain available for review. It does not scan the entire destination library or contact an online AI service.

Every run opens a mandatory Copy/Move confirmation; nothing is filed before confirmation. Discovery, profile changes and Refresh never run Magic automatically. Manual edits remain protected. Cancellation stops between files, so completed files remain completed.

Music profiles can optionally update tags from nonempty components and then purge unwanted MP3 tags on a private library staging copy before publication. Both options default off. The keep list defaults to retaining every category, including artwork. Changed-tag operations have no automatic Undo or retained backup. See the README for details.

## Learning

Successful approved corrections can be remembered locally and reused for the compatible profile and source context. Remember/Forget controls remain explicit. Recommendations change a settings draft for review, not active rules or files automatically. Reports are previewed and copied only on user action; anonymization is the default.

Operation history expires after 30 days. Remembered corrections persist separately until forgotten. History is a recovery aid, not a complete file backup. The filesystem and hardware limitations in the README still apply.

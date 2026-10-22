# Workspace patterns and filing layouts — Build 40

Open **Profile Settings → Workspace Filename Patterns & Filing Types…**. Pattern changes stay in the profile draft until you click Done, then Save in Profile Settings. Cancel in the pattern window restores its starting draft.

## Interpretation

Rules run top to bottom. The first enabled rule matching the complete basename (without extension) supplies the components. Spaces and punctuation outside braces are literal, matched without case sensitivity. Extensions remain unchanged. A broad `{Title}` rule belongs last. Enabled rules are cached and evaluated during ordinary workspace discovery; this is not Magic.

| Pattern | Classification choice | Result |
|---|---|---|
| `{Title} ({Year})` | Movie | Title and four-digit Year |
| `{Series} - {EpisodeID} - {EpisodeTitle}` | TV Show | Series, Season, Episode, Episode Title; Title blank |
| `Commercial - {Title} ({Year})` | Commercial | Literal prefix supplies classification |
| `{Title} [Commercial]` | Commercial | Literal suffix supplies classification |
| `{Title} [{Type}]` | Read from filename | Bracketed value matched to a configured Type or alias |
| `{Title} [{System}]` | Read from filename | ROM system matched to a configured System or alias |
| `{Artist} - {Title} [{Genre}]` | Read from filename | Music genre matched to a configured Genre or alias |
| `{Game} - {Title}` | Unspecified | FORGE game and resource title |

`{Year}` captures a year; `(Year)` is the literal text `(Year)`. `{EpisodeID}` understands S/E identifiers and validates numeric portions. Individual Season/Episode captures and `:02` output formatting are also available. Use `{FieldName}` to capture an additional named field; it appears in the component editor and can be referenced by output masks. Names use letters and digits and start with a letter. Prefix/suffix, preferred spelling and existing cleanup settings continue to apply.

The assignment dropdown chooses a configured Type/System/Genre, reads a captured value, or leaves classification unspecified. Add Type creates an editable configuration entry. Names and aliases must be unique without regard to case. An unknown captured classification remains visible and blocks filing until selected or registered. It does not silently create an arbitrary classification folder. Classifications are also editable in bulk in the filename-component panel.

Use **Test Example** or **Test Selected Files** to see the first matching rule, extracted components and full destination. Tests process at most 25 selected files, do not read file contents or create folders, and do not apply renames. A missing component is shown in the preview rather than invented.

## Filing layouts

Each configured classification can inherit the profile's masks or override its folder and/or filename mask. A blank custom folder mask means the library root. Multiple classifications may share a folder mask. Choose Folder accepts a directory inside the profile's destination root; you can instead type a relative literal folder name or mask.

Examples:

- Movie: `Movies/{Title} ({Year?})`
- TV Show: `TV Shows/{Series}/Season {Season:02}`
- Commercial: `Commercials`
- ROMs: profile folder mask `{System}`
- Music by genre: `{Genre}/{Artist}/{AlbumOrIndividual}`
- FORGE: folder `{Game}`, filename `{Game} - {Title}`

Masks determine layout; they do not infer missing values. Output placeholders come from the matched rule or manual component edits. A manually edited proposed filename still overrides the filename mask for that item. Changing a component clears that override so proposals use the edited components.

## Books

Audiobooks and Ebooks & Comics starters use `{Author}/{Series?}/{BookFolder}`:

- Standalone: `Full Author/Book Name`
- Series: `Full Author/Series Name/02 - Book Name`

`{Series?}` omits the whole folder segment when Series is blank. BookFolder combines SeriesNumber (when present), ` - `, and BookTitle. SeriesNumber and ChapterNumber are separate.

The audiobook starter also includes disabled parent-folder patterns. Enable one and move it above filename rules to read existing author/series/book folders, matching the final folder levels before the file. For `{Author}/{Series}/{SeriesNumber} - {BookTitle}`, the path `Full Author/Series Name/02 - Book Name/03 - Chapter Name.mp3` supplies Author, Series, SeriesNumber and BookTitle from folders, plus ChapterNumber/ChapterTitle from the filename. Parent patterns are opt-in because an unrelated folder hierarchy is not reliable evidence of authorship or series.

## Existing profiles

Before migrating old saved profiles, the app saves an importable settings archive alongside the normal profiles file. Existing IDs, names, notes, extensions, masks, destinations and bookmarks remain preserved. A fixed Category is folded into the beginning of the folder mask rather than changing the library root. Undo history is unchanged.

The enabled **compatibility interpretation** row preserves the prior permissive parser and legacy extraction mask. Suggested editable rows are pre-populated but disabled below it. Enable and move the relevant rows above compatibility, test them, and then disable compatibility if you want patterns exclusively. This avoids quietly changing proposals when upgrading. Suggested classifications inherit existing masks on migrated profiles; configure route overrides explicitly. New installs use editable rules and starter route mappings immediately.

The compatibility recognizer and reusable token handlers remain code. Explicit rules, their order, assigned classification and routing masks are settings. Manual Magic still offers additional filename/folder interpretations and remembered corrections; it never runs automatically. Settings changes may make older remembered examples ineligible for automatic reuse, but their history is retained. Notes alone do not invalidate learning signatures.

## Scope

The eight content types are Video, Music, Books & Comics, Documents, Video Game ROMs, Photos, Software & Installers, and Other / Custom. FORGE and PDF Library are Documents profiles; book subtypes remain Audiobook/Ebook/Comic/Mixed. Existing profiles keep their content type and custom settings. Changing the picker alone does not reset them; Load defaults is an explicit replacement of the profile's rules.

Metadata such as Genre, DateTaken, Platform and Version comes from patterns or manual entry. MP3 tags, photo EXIF and application internals are not read. Regular installer files and archives are supported; .app bundles are not treated as ordinary files. TV/children/documentary classifications are configurable values, not inferred audience or content judgments.

### Optional video resolution

Use `{Resolution}` in an input pattern, for example `{Title} {Year} {Resolution}`. Numeric labels such as `720P` normalize to `720p`. The video component editor allows manual correction. No video dimensions or source media are inspected.

Output `{TitleYear} [{Resolution?}]` produces `Movie (2005) [720p]`, or `Movie (2005)` when Resolution is blank. `{Resolution}` without `?` requires a value. Existing profile masks are preserved.

### Movie defaults

New video profiles use explicit movie folder `{Title} ({Year?})` and filename `{Title} ({Year?}) [{Resolution?}]` masks. Year and Resolution are optional; their surrounding parentheses/brackets disappear when blank. Remove `?` to require a component instead. Missing required values are displayed below the filename editor. TV Show mappings retain Series/Season folders and episode filenames.

Default ordered input patterns recognize trailing years (1900–2100) with bare or bracketed numeric p/i resolution labels before generic Type or Title patterns. Leading title numbers are retained. Magic uses the same configured interpretation first; alternatives remain manual. No dimension inference or DVD/Blu-ray source detection is performed. Literal output characters and labels are preserved. Only unchanged shipped defaults are upgraded; custom input sequences and masks are retained.

### Episode and year positions

Video defaults include EpisodeID-first and EpisodeID-last patterns. The ordered, editable `{EpisodeIDAnywhere}` recognition rule captures one standalone S/E identifier anywhere; when remaining text has two clear ` - ` sections, they become Series and EpisodeTitle. Otherwise Series remains blank for review. Multiple episode identifiers are not guessed.

Year-first defaults accept `({Year}) - {Title}`, `({Year}) {Title}`, and `{Year} - {Title}`. `{ParenthesizedYearAnywhere}` recognizes one explicit parenthesized year (1900–2100) and removes surrounding edge separators. Multiple candidate years require review. Bare leading years without a separator remain in Title; manual Magic may offer a limited-evidence alternative. Output structure remains determined by the user's masks. Upgrades only extend unchanged shipped input sequences; custom sequences retain their order and contents.

### Profile settings flow and defaults

Every content type uses Profile & destination → Read filenames → Clean components → Build names & folders → Magic & learning. Video exposes Movie and TV Show mapping masks directly; advanced type overrides remain in Filing Types. Examples and component references follow content type/book subtype.

New video/music/book profiles enable smart title case. New video profiles also enable hyphens-to-spaces and episode formatting and start with no removable labels. Existing cleanup choices are not overwritten. ROM/photo/software/custom cleanup stays conservative. Magic remains opt-in.

Period handling has one choice: Keep periods, Separator periods → spaces, or All periods → spaced hyphens. A legacy profile with both transformations enabled must select one before saving. Existing saved files can still be opened for correction; no automatic choice is made.

The workspace column header stays fixed above scrolling rows. A flagged unrecognized word shows Spelling review when the proposed name is unchanged; applying a spelling replacement that changes the name shows Rename proposed.

### Library operations and confirmations

Workspace row checkmarks and Rename Selected rename in place. The redundant rename-preview button and File only checkbox have been removed. The bottom preview button follows the selected operation: Preview Copy to Library or Preview Move to Library. Ordinary preview uses proposed filenames and still requires confirmed components.

Run Magic analyzes selected visible files and opens one confirmation with a Copy/Move choice defaulting to the workspace operation. Proposed filenames and profile folder masks determine destinations. Cancel leaves the suggestions available but performs no filesystem operation.

The operation preview also offers Skip Individual Review & Copy All… / Move All…. This path keeps current filenames and uses folder masks for destinations. All means the complete set of files in that preview, not unrelated or hidden selections. It opens a confirmation with eligible/blocked counts and full source/destination paths.

Both explicit paths bypass only the per-item reviewed flag for this operation. Workspace flags are unchanged. Missing folder components, collisions, stale sources, linked/unavailable roots and executor checks still apply. Only actionable rows execute after confirmation. Copy leaves source filenames unchanged; Move publishes into the library under the displayed destination names.

Missing library destinations prompt Open Profile Settings or Cancel. Invalid paths and unavailable directories have distinct messages. Save validation failures scroll to the message, and period-handling examples explicitly preserve the final extension separator and extension.

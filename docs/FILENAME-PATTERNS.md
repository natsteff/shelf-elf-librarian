> Build 60: Music and Video use built-in filename parsing. Their saved input-pattern rows are ignored and removed during migration. Input-pattern editing below applies to Documents and other configurable content types; Music/Video still support filing Types and output masks.

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
- FORGE: input `{GameTitle} - {ResourceName}`, folder `{GameTitle}`, filename `{GameTitle} - {ResourceName}`

Masks determine layout; they do not infer missing values. Output placeholders come from the matched rule or manual component edits. A manually edited proposed filename still overrides the filename mask for that item. Changing a component clears that override so proposals use the edited components.

## Books

Audiobooks and Ebooks & Comics starters use `{Author}/{Series?}/{BookFolder}`:

- Standalone: `Full Author/Book Name`
- Series: `Full Author/Series Name/02 - Book Name`

`{Series?}` omits the whole folder segment when Series is blank. BookFolder combines SeriesNumber (when present), ` - `, and BookTitle. SeriesNumber and ChapterNumber are separate.

The audiobook starter also includes disabled parent-folder patterns. Enable one and move it above filename rules to read existing author/series/book folders, matching the final folder levels before the file. For `{Author}/{Series}/{SeriesNumber} - {BookTitle}`, the path `Full Author/Series Name/02 - Book Name/03 - Chapter Name.mp3` supplies Author, Series, SeriesNumber and BookTitle from folders, plus ChapterNumber/ChapterTitle from the filename. Parent patterns are opt-in because an unrelated folder hierarchy is not reliable evidence of authorship or series.

## Existing profiles

Before migrating old saved profiles, the app saves an importable settings archive alongside the normal profiles file. Existing IDs, names, notes, extensions, masks, destinations and bookmarks remain preserved. A fixed Category is folded into the beginning of the folder mask rather than changing the library root. Undo history is unchanged.

Legacy extraction masks and compatibility interpretation rows have been removed. Existing editable patterns are retained; profiles that used compatibility receive editable starter patterns. Review their order and test representative names before filing.

Documents profiles can capture their own named components, for example `{GameTitle} - {ResourceName}`. Captured names appear in Filename Components and can be used in output masks, including optional folder levels. Music and Video input patterns retain fixed built-in components and metadata mappings.

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

New video/music/book profiles enable smart title case. New video profiles also enable episode formatting and start with no removable labels. Existing cleanup choices are not overwritten. ROM/photo/software/custom cleanup stays conservative. Magic remains opt-in.

Period handling has one choice: Keep periods, Separator periods → spaces, or All periods → spaced hyphens. A legacy profile with both transformations enabled must select one before saving. Existing saved files can still be opened for correction; no automatic choice is made.

The workspace column header stays fixed above scrolling rows. A flagged unrecognized word shows Spelling review when the proposed name is unchanged; applying a spelling replacement that changes the name shows Rename proposed.

### Library operations and confirmations

Workspace row checkmarks and Rename Selected rename in place. The redundant rename-preview button and File only checkbox have been removed. The bottom preview button follows the selected operation: Preview Copy to Library or Preview Move to Library. Ordinary preview uses proposed filenames and still requires confirmed components.

Run Magic analyzes selected visible files and opens one confirmation with a Copy/Move choice defaulting to the workspace operation. Proposed filenames and profile folder masks determine destinations. Cancel leaves the suggestions available but performs no filesystem operation.

The operation preview also offers Skip Individual Review & Copy All… / Move All…. This path keeps current filenames and uses folder masks for destinations. All means the complete set of files in that preview, not unrelated or hidden selections. It opens a confirmation with eligible/blocked counts and full source/destination paths.

Both explicit paths bypass only the per-item reviewed flag for this operation. Workspace flags are unchanged. Missing folder components, collisions, stale sources, linked/unavailable roots and executor checks still apply. Only actionable rows execute after confirmation. Copy leaves source filenames unchanged; Move publishes into the library under the displayed destination names.

Missing library destinations prompt Open Profile Settings or Cancel. Invalid paths and unavailable directories have distinct messages. Save validation failures scroll to the message, and period-handling examples explicitly preserve the final extension separator and extension.

### Optional Media Categories for mixed video libraries

Type and Media Category are separate. Type describes layout; a Media Category selects a user-mapped root-level folder and may override subfolder/filename layouts. Enable routing in Profile Settings → Build names & folders → Media Categories. Existing routing remains unchanged while disabled. Six editable starter definitions are supplied: Commercials, Documentaries, Home Videos, Movies, Music Videos, TV Shows. Their destination folders are deliberately **unmapped**; folder names are never assumed.

Choose an existing direct child folder, enter its name to create on Apply, or explicitly choose Use Library Root. Multiple categories may map to the same folder. Add/remove/rename/reorder/disable categories and rules; removing a definition never deletes or moves library data. Subfolder masks are relative to the mapped folder. Category overrides take precedence over Type/profile masks; inheriting a full old Type mask also inherits any literal folder prefix. Type inheritance is labeled explicitly in the main settings form.

Routing order is explicit MediaCategory selection/capture → Type+keyword rules → keyword-only rules → Type-only rules → configured default → Needs review. Category/rule order resolves ties within each specificity group. Conditions within a rule are AND; rules within a category are OR. Keywords are case-insensitive whole words/phrases in the original basename, with separator periods/underscores/hyphens treated as spaces. Unknown/disabled explicit categories never silently fall back. Unmapped categories block filing even with Skip Individual Review. Category reasons and destination paths appear in the workspace/operation previews.

The optional `{MediaCategory}` component may be captured or included in output masks. The settings button adds explicit capture examples before broad/compatibility recognizers. For example `{Title} ({Year}) [{MediaCategory}]` can capture a user-defined category/alias; the output can omit that marker. Names and aliases resolve to the configured canonical category. Manual workspace overrides still take precedence over proposed names.

Category inference is shared by ordinary proposals, manual Magic, confirmed filing and the keep-current-names bypass. A year alone is not category evidence beyond the profile’s configured input Type rules. Documentary/music/home/commercial starter keyword rules are editable filename evidence, not content inspection. No folders are created during discovery, classification, settings edits or preview. Existing collision, link, stale-source and executor guards remain in force. Category definitions, mapping choices and rules are included in settings export/import and learning signatures. Older settings decode with routing off.

Description / Notes uses the normal system field font. Its height is measured from saved content and actual wrapping width on opening/reload, clamped to 100–300 points. Height stays stable while typing; longer text scrolls. There is no manual resize handle.

### Simple category setup

The main category list shows category names and mapped library folders, with Choose/Change, Advanced and Remove actions. Choose/Change opens a small folder form: enter a direct-child folder name or browse an existing folder, then Use Folder. Browse cannot create folders; typed new names are created only by a subsequent filing operation. Clear Mapping and explicit Use library root remain available there.

Add Category asks for a name, a starter naming layout and an optional filename keyword. It does not duplicate broad matching rules from the chosen layout. Without a keyword, use explicit category selection/capture or choose the category as the unmatched-video default. Existing matching rules, aliases, masks and ordering are preserved and edited through each row’s Advanced window. Capture-pattern setup and adding missing starters are under Advanced Setup.

### Mapping dialog, unmatched root and persistence

The category-folder browser identifies its purpose in its title, visible message and confirmation button: Select destination folder for CATEGORY / Use for CATEGORY.

Unmatched videos has a final Use Library Root option. It bypasses only category-folder selection, applying the file’s Type/fallback layout beneath the library root. It does not rescue an unknown/disabled explicit category or a matched category with no mapped folder. The fallback choice is persisted separately from a default-category identifier.

Older enabled video profiles are supplied missing built-in Type definitions required by their category rules. Existing custom Type names, layouts, patterns and category mappings are retained. Equivalent aliases are reused, and the repair is idempotent. Unknown custom layouts still require an explicit correction in Advanced.

Profile Save writes atomically before publishing model changes or dismissing settings. Validation and write failures say Profile not saved, keep the draft open and reveal the error. Existing unreadable/corrupt settings are not silently replaced with starters during startup. Fixtures exercise successful write/reload, failed writes, retained prior data and compatibility repair. Choices from a previous failed Save were never persisted and must be selected again.

## ROM organization

ROMs retain their original filenames, including punctuation, case and region/revision markers. Automatic output filename masks do not rename ROM files; a manual filename edit remains explicit. In Workspace Filename Patterns & Filing Types, extension mappings identify System for clear extensions (nes, sfc/smc, gb, gbc, gba, n64/z64/v64, nds, 3ds). System mappings choose library folder masks, or inherit `{System}`. The mappings are editable and can be removed.

Shared formats such as iso, bin, chd, zip and 7z have no default system inference. Capture `{System}` from filenames or parent folders, or choose it manually. Explicit captured Systems take priority over extension mappings; discrepancies are shown in evidence. Unknown/missing Systems require review. No archives are inspected. Folders containing cue, m3u/m3u8, gdi, ccd or mds descriptors are conservatively blocked from individual copy, move and rename operations; keep linked sets together outside this workflow.

Audiobooks accept `{SeriesName}` as an alias of `{Series}`. The starter folder mask is `{Author}/{SeriesName?}/{BookFolder}`; empty series levels are omitted. Both numbered-series and unnumbered Author - SeriesName - BookTitle patterns are provided.

## Video resolution display

Use common resolution shorthand defaults on for Video profiles. Pixel dimensions from read-only metadata map to the closest 480p, 720p, 1080p, 4K or 8K size tier; both edges are considered for cropped/portrait video. Disable the option to retain full display dimensions. Explicit filename/component labels are retained. The conventional p labels do not assert progressive scan detection, and DVD/Blu-ray origin is never inferred from size.

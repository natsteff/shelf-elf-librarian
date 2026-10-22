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

- Movie: `Movies/{TitleYear}`
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

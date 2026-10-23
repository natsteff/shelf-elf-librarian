import SwiftUI
import AppKit
import FilerCore

struct BatchNamesView: View {
    @EnvironmentObject var m: Model
    @Environment(\.dismiss) var dismiss
    @State private var find = ""
    @State private var replacement = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Selected Proposed Names").font(.title2.bold())
            Text("Literal replacement in \(m.visibleSelected.count) selected visible basenames. Extensions and hidden selections stay unchanged. This edits proposals only; preview and Apply are still required.")
            TextField("Find", text: $find); TextField("Replace with (blank deletes)", text: $replacement)
            ScrollView { VStack(alignment: .leading, spacing: 8) {
                ForEach(m.visibleSelected) { item in
                    let name = (try? proposedBasename(item, profile: m.active)) ?? "[missing required field]"
                    Text(name + " → " + (find.isEmpty ? name : name.replacingOccurrences(of: find, with: replacement))).font(.caption).textSelection(.enabled)
                }
            } }.frame(maxHeight: 260)
            HStack { Button("Cancel") { dismiss() }; Spacer(); Button("Update Proposals") { m.replaceSelected(find: find, replacement: replacement); dismiss() }.disabled(find.isEmpty) }
        }.textFieldStyle(.roundedBorder).padding(24).frame(width: 700)
    }
}
struct FolderReviewView: View {
    @EnvironmentObject var m: Model
    @Environment(\.dismiss) var dismiss
    @State private var included: Set<UUID> = []
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review Existing Folder Renames").font(.title2.bold())
            Text("Rules from profile: " + m.active.name).font(.headline)
            Text("Only the folders you chose are listed. Renaming a folder carries every item inside it, including hidden files and unsupported extensions; child filenames and bytes are not edited. Linked contents are refused.").font(.callout)
            if let plan = m.folderPlan {
                ScrollView { LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(plan.rows) { row in
                        VStack(alignment: .leading, spacing: 7) {
                            Toggle(row.status, isOn: Binding(get: { included.contains(row.id) }, set: { if $0 { included.insert(row.id) } else { included.remove(row.id) } })).disabled(!row.actionable)
                            Text(row.source + "\n→ " + row.destination).textSelection(.enabled)
                            Text(row.detail).font(.caption).foregroundStyle(.secondary)
                            if !row.members.isEmpty {
                                DisclosureGroup("All affected contents (\(row.members.count))") {
                                    ForEach(row.members, id: \.relativePath) { member in Text((member.directory == nil ? "File: " : "Folder: ") + member.relativePath).font(.caption).textSelection(.enabled) }
                                }
                            }
                        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                } }
                Text("Nothing is selected automatically. Cancel stops between folders; completed renames remain completed. History provides guarded undo and journaled recovery paths.").font(.caption)
                HStack {
                    Button("Cancel") { dismiss() }
                    Button("Select Actionable Folders") { included = Set(plan.rows.filter(\.actionable).map(\.id)) }
                    Spacer()
                    Button("Rename \(included.count) Folders") { m.applyFolders(included) }.buttonStyle(.borderedProminent).disabled(included.isEmpty)
                }
            }
        }.padding(24).frame(width: 920, height: 680)
    }
}
struct RecommendationsView: View {
    @EnvironmentObject var m: Model
    @Environment(\.dismiss) var dismiss
    @Binding var profile: Profile
    @State private var report: ProfileRecommendation?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Profile Recommendations & Learning").font(.title2.bold())
            Text("Suggestions never change rules automatically. Add a setting to the profile draft, review it, then Save in Profile Settings. Development reports are copied only when you choose; nothing is uploaded.").font(.callout)
            ScrollView { LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(m.recommendations(for: profile)) { recommendation in
                    VStack(alignment: .leading, spacing: 8) {
                        Text((recommendation.kind == .development ? "Development: " : "Setting: ") + recommendation.title).font(.headline)
                        Text(recommendation.explanation).font(.callout)
                        ForEach(recommendation.examples.prefix(3)) { example in
                            Text("Original: \(example.original)\nAutomatic: \(example.automatic)\nApproved: \(example.final)").font(.caption).textSelection(.enabled)
                        }
                        HStack {
                            if recommendation.kind == .setting { Button("Add to Profile Draft") { recommendation.apply(to: &profile) } }
                            else { Button("Preview Shareable Report…") { report = recommendation } }
                            Button("Dismiss") { m.dismissRecommendation(recommendation.id) }
                        }
                    }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
                Divider()
                Text("Confirmed examples for this profile").font(.headline)
                Text("Only examples marked Remember can be reused by Magic. Forget removes an example from learning, not the operation journal needed for recovery.").font(.caption)
                ForEach(m.observations.filter { $0.profileID == profile.id }) { example in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading) { Text(example.original + " → " + example.final).textSelection(.enabled); Text(example.remember ? (example.settingsSignature == Learning.settingsSignature(profile) ? "Remembered for Magic" : "Profile settings changed — reapprove before reuse") : "Recommendation evidence only").font(.caption).foregroundStyle(.secondary) }
                        Spacer(); Button("Forget") { m.forgetCorrection(example.id) }
                    }
                }
            } }
            HStack { Spacer(); Button("Done") { dismiss() } }
        }.padding(24).frame(width: 850, height: 660)
        .sheet(item: $report) { ReportPreviewView(recommendation: $0, profile: profile) }
    }
}
struct ReportPreviewView: View {
    @Environment(\.dismiss) var dismiss
    let recommendation: ProfileRecommendation
    let profile: Profile
    @State private var anonymize = true
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Profile Development Recommendation").font(.title2.bold())
            Toggle("Anonymize filenames and profile name", isOn: $anonymize)
            Text("Review the full report before copying or sharing it. Anonymization replaces letters/numbers with placeholders; no filesystem paths are included.").font(.caption)
            ScrollView { Text(recommendation.report(profile: profile, anonymize: anonymize)).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }
            HStack { Button("Close") { dismiss() }; Spacer(); if copied { Text("Copied") }; Button("Copy Report") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(recommendation.report(profile: profile, anonymize: anonymize), forType: .string); copied = true } }
        }.padding(24).frame(width: 800, height: 600)
    }
}

struct SettingsHint: View {
    let text: String
    var body: some View { Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
}

struct SettingsInput: View {
    let title: String
    @Binding var text: String
    let example: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
            TextField("", text: $text, prompt: Text("example- " + example).foregroundColor(.secondary))
                .textFieldStyle(.roundedBorder)
        }.padding(.vertical, 3)
    }
}

struct MaskGuideView: View {
    @Environment(\.dismiss) var dismiss
    private func entry(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Interpretation & Output Masks").font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    entry("How the pieces fit", "Original filename → interpreted filename components → cleanup → output masks → editable proposal → reviewed operation. Settings examples shown in light text with ‘example-’ are hints only; they are not saved values. Profile changes take effect when you click Save.")
                    entry("Reading filenames and configuring layouts", "Music and Video use built-in filename parsers, independent of saved input patterns. Use Filing Types & Layouts to configure their output organization. Other profiles use Workspace Filename Patterns & Filing Types: enabled rules match the full original basename in order, and the first match wins. Documents profiles can define custom components such as {GameTitle} and {ResourceName}. Assign a classification or read it from {Type}, {System} or {Genre}, and test examples before saving. Legacy extraction masks and compatibility rows have been removed. Magic remains manual.")
                    entry("Input components", "Use {Title}, {Year}, {Artist}, {Album}, {Author}, {BookTitle}, {ChapterNumber}, {ChapterTitle}, {Series}, {Season}, {Episode}, {EpisodeTitle}, {Date}, or {Revision}, {Narrator}, {Publisher}, {Illustrator}, {IssueNumber}, {Volume}, {SeriesNumber}, {TrackNumber}, {RecordingType}. Type, System, Genre, Game, Product, Version, Platform, Architecture, DateTaken, Event, Region, Edition and Resolution are also available. Resolution preserves numeric p/i labels in lowercase; it does not inspect video dimensions. Other / Custom may capture additional named fields. Video recognition rules {EpisodeIDAnywhere} and {ParenthesizedYearAnywhere} recognize one explicit marker anywhere. Episode recognition requires review of remaining Series/Episode title; multiple markers need manual review. These rules can be reordered or disabled like other patterns. Component names are case-sensitive. Use plain component names in extraction; formatting such as :02 belongs in output masks. A mask that does not match leaves the item needing review.")
                    entry("Folder masks choose the structure", "The destination is: library root / folder mask / filename. Fixed folder names belong directly in the mask, for example Rock/{Artist}/{Album}. A Type/System/Genre mapping can choose a different folder and filename mask per classification. Blank folder masks use the root directly. Old fixed categories are migrated into folder masks without changing destination roots.")
                    entry("Filename masks assemble the name", "{Artist} - {Title} produces BT-AI - No Trail Leads Home.mp3. {Title} uses only the reviewed Title. Do not add the extension to the mask: the original extension is kept automatically. Literal separators in a mask are deliberate output: ‘ - ’ remains even when hyphens-to-spaces cleaned the extracted filename components. Prefix and suffix are added once around the assembled basename.")
                    entry("TV, audiobooks and documents", "TV: {Series} - {EpisodeID} - {EpisodeTitle}; EpisodeID uses season/episode filename components, such as S01E02 (or s01e02 with lowercase identifiers enabled). Audiobooks: {Author}/{BookTitle} for folders and {ChapterNumber:02} - {ChapterTitle} for names. Documents: {Date} - {Title} - {Revision}. These examples require the corresponding reviewed values; the app does not invent missing titles, dates or numbers.")
                    entry("Output filename components and helpers", "Video example: {TitleYear} [{Resolution?}] adds a bracketed resolution only when specified. Output supports captured components, plus {BookFolder}, {TitleYear}, {ChapterOrBook}, {Bucket}, {AlbumOrIndividual}, {EpisodeID}, {Season:02}, {Episode:02}, and {ChapterNumber:02}. :02 pads a numeric value to at least two digits: 3 → 03. TitleYear combines title and year when available. {Series?} omits its entire folder level when blank. BookFolder prefixes BookTitle with SeriesNumber when present. ChapterOrBook uses the cleaned original basename when a chapter number is present, otherwise the book title. Bucket and AlbumOrIndividual use the music profile’s bucket and individual-track settings.")
                    entry("Music sorting example", "Enable Music first-letter bucket and use {Bucket}/{Artist}/{AlbumOrIndividual} as the folder mask. Artists sort into letter folders, the configured number bucket (normally 0-9), or the symbol bucket. Ignore leading The changes only the bucket choice. Set accepted extensions and destination root separately; this does not scan the library or read audio tags.")
                    entry("Missing values and manual edits", "Required empty filename components or unknown output tokens block a proposal until corrected. Bucket and AlbumOrIndividual may omit a folder level when their settings allow it. A manually edited proposed filename overrides the filename mask for that item; the folder mask still uses its reviewed filename components. File-only keeps the actual filename. Clean renames in the source folder; File uses the configured destination. Always inspect the complete destination in Preview before Apply.")
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 12)
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 760, height: 650)
    }
}


private struct InstantHelp: ViewModifier {
    let message: String
    func body(content: Content) -> some View { content.overlay { HelpRegion(message: message) } }
}
extension View {
    func instantHelp(_ message: String) -> some View { modifier(InstantHelp(message: message)) }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var m: Model
    @Environment(\.dismiss) var dismiss
    @State private var draft = UniversalPreferences()
    @State private var validation = ""
    @State private var confirmSuggestions = false
    @State private var suggestionsResult = ""
    private func groupInput(_ group: UniversalExceptionGroup) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(group.title).font(.headline)
            Text("Display-only examples: " + group.examples).font(.caption).foregroundStyle(.secondary)
            TextEditor(text: Binding(get: { draft.groups[group.id] ?? "" }, set: { draft.groups[group.id] = $0 }))
                .font(.system(.body, design: .monospaced)).frame(height: 64)
                .padding(4).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.3)))
                .accessibilityLabel(group.title)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("General Settings").font(.title2.bold())
                Spacer()
                Button("Load Suggested Entries") { confirmSuggestions = true }
            }
            if !suggestionsResult.isEmpty { Text(suggestionsResult).font(.caption).foregroundStyle(.secondary) }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Toggle("Show filename differences", isOn: Binding(get: { draft.showFilenameDifferences ?? true }, set: { draft.showFilenameDifferences = $0 }))
                    SettingsHint(text: "Show red/blue rename highlighting. Current and proposed names, change details and amber spelling underlines remain available when disabled.")
                    Picker("Hover help", selection: Binding(get: { draft.hoverTiming ?? .immediate }, set: { draft.hoverTiming = $0 })) {
                        Text("Immediate").tag(HoverTiming.immediate)
                        Text("Short delay").tag(HoverTiming.shortDelay)
                        Text("Off").tag(HoverTiming.off)
                    }
                    Picker("Default filing action", selection: Binding(get: { draft.filingAction }, set: { draft.defaultFilingAction = $0 })) {
                        Text("Copy to Library").tag(Mode.copy)
                        Text("Move to Library").tag(Mode.move)
                    }
                    SettingsHint(text: "Used when the app starts. The workspace Operation selector can override this for the current session. Copy is the initial default.")
                    Toggle("Flag unrecognized filename words", isOn: Binding(get: { draft.flagUnrecognizedWords ?? true }, set: { draft.flagUnrecognizedWords = $0 }))
                    SettingsHint(text: "Advisory solid amber underlines on the current/source filename use your macOS spelling languages. Capitalization is ignored; universal exceptions, episode indicators and numeric identifiers are excluded. No automatic spelling corrections. Open Show changes for Suggestions, or right-click an amber-underlined source word. Choosing a replacement updates the proposal only; Rename applies it. Details appear even when no rename is needed.")
                    Text("Universal Spelling & Case Preference Exceptions").font(.title3.bold())
                    SettingsHint(text: "Enter your preferred spelling/case using commas or one entry per line. Groups organize the list only; every entry applies to all profiles. Examples are display-only. Fresh installations start with the suggested list; existing installations can add it using Load Suggested Entries. Exact duplicates are combined. Conflicting capitalization must be resolved before saving.")
                    ForEach(UniversalExceptionGroup.all) { groupInput($0) }
                    Text("Combined exceptions used by the app (\(draft.combinedEntries.count))").font(.headline)
                    Text(draft.combined.isEmpty ? "No exceptions" : draft.combined)
                        .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    SettingsHint(text: "Read-only preview updates as you type. Save makes it the active universal list. Entries protect matching preferred spellings and their punctuation during cleanup and filename splitting. Case is ignored when matching; spaces around an entry’s internal hyphen are normalized. No fuzzy spelling correction is performed. Filename extensions stay unchanged.")
                    ForEach(draft.conflicts, id: \.self) { Text($0).font(.caption).foregroundStyle(.red) }
                    SettingsHint(text: "Removable labels delete matching text first. Universal exceptions only adjust what remains; they do not protect text from removal.")
                    ForEach(m.profiles) { profile in
                        if !draft.overlaps(removableLabels: profile.removeTokens).isEmpty {
                            Text("\(profile.name): removal takes precedence for " + draft.overlaps(removableLabels: profile.removeTokens).joined(separator: ", ") + ". This is informational and does not block saving.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    Text("Universal lowercase title words").font(.title3.bold())
                    TextEditor(text: $draft.lowercaseTitleWords).font(.system(.body, design: .monospaced)).frame(height: 70)
                        .padding(4).overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.3)))
                        .accessibilityLabel("Universal lowercase title words")
                    SettingsHint(text: "This editable list controls the Smart title case option in Profile Settings → Clean components. Enable both Title case and Smart title case in each profile that should use it. Commas or line breaks separate words. Beginning/end words and words after separators are capitalized; explicit preferred-case exceptions apply last. Saving refreshes the workspace and clears selections and pending proposals. Old per-profile lowercase lists are not imported.")
                    if !validation.isEmpty { Text(validation).foregroundStyle(.red) }
                }.padding(.trailing, 8)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { do { try m.saveGeneralSettings(draft); dismiss() } catch { validation = error.localizedDescription } }
                    .keyboardShortcut(.defaultAction).disabled(m.busy || !draft.conflicts.isEmpty)
            }
        }.padding(24).frame(width: 780, height: 720)
        .onAppear { draft = m.universalPreferences }
        .alert("Load suggested entries?", isPresented: $confirmSuggestions) {
            Button("Cancel", role: .cancel) {}
            Button("Add to Draft") { suggestionsResult = draft.appendSuggestions().summary }
        } message: {
            Text("Append missing suggestions to their groups? Entries already present anywhere are skipped. Your preferred spellings and Other group are kept. Review the draft and click Save to apply, or Cancel to discard.")
        }
    }
}


struct DirectFilenameEditor: View {
    @EnvironmentObject var m: Model
    let item: Item
    let nameMatches: Bool
    var highlightedProposal: AttributedString? = nil
    var changedCharacters: Set<Int> = []
    var comparison: FilenameDifference? = nil
    @State private var draft = ""
    @FocusState private var focused: Bool
    private var proposed: String { (try? proposedBasename(item, profile: m.active)) ?? "" }
    private var edited: Bool { !draft.utf8.elementsEqual(proposed.utf8) }
    private func focusRequestedFilename() {
        guard m.filenameFocusID == item.id else { return }
        draft = proposed; focused = true
        DispatchQueue.main.async { if m.filenameFocusID == item.id { m.filenameFocusID = nil } }
    }
    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
        HStack(spacing: 4) {
            TextField("Filename without extension", text: $draft)
                .textFieldStyle(.plain).font(.system(size: 13)).focused($focused).autocorrectionDisabled(true)
                .foregroundColor(!focused && !edited && highlightedProposal != nil ? .clear : .primary)
                .overlay(alignment: .leading) {
                    if !focused && !edited, let highlightedProposal {
                        Text(highlightedProposal).font(.system(size: 13)).lineLimit(1).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(focused ? Color.accentColor : Color.primary.opacity(0.4), lineWidth: focused ? 1.5 : 1))
                .onSubmit { if edited || !nameMatches { m.renameNow([item.id], manualBasename: draft); focused = false } }
                .onExitCommand { m.cancelTagEdits(item.id); draft = proposed; focused = false }
                .changedTextHover(text: draft, changes: focused || edited ? [] : changedCharacters, source: false, fontSize: 13, comparison: comparison)
            Text(item.url.pathExtension.isEmpty ? "" : "." + item.url.pathExtension)
                .font(.caption).foregroundStyle(.secondary).instantHelp("Original extension is preserved")
            if edited {
                Button { m.renameNow([item.id], manualBasename: draft); focused = false } label: { Image(systemName: "square.and.arrow.down") }
                    .instantHelp("Save edited filename to disk now. The file stays in this folder and is deselected after success.")
            } else if !nameMatches {
                Button { m.renameNow([item.id]) } label: { Image(systemName: "checkmark.square") }
                    .instantHelp("Rename this file to the proposed name now. Stays in this folder; deselected after success. Component confirmation is unchanged.")
            }
            if let event = m.directRenameUndo[item.id] {
                Button { m.undoDirectRename(event) } label: { Image(systemName: "arrow.uturn.backward") }
                    .instantHelp("Undo the last direct rename on disk, restoring the original filename if safe.")
            }
        }
        if focused { Text("Enter to rename · Esc to cancel").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing) }
        }
        .onAppear { draft = proposed; focusRequestedFilename() }
        .onChange(of: proposed) { draft = proposed }
        .onChange(of: m.filenameFocusRequest) { focusRequestedFilename() }
    }
}

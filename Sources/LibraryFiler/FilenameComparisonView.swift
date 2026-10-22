import SwiftUI
import FilerCore

private func differenceText(_ text: String, changes: Set<Int>, source: Bool, visibleWhitespace: Bool = false, comparison: FilenameDifference? = nil, unrecognized: Set<Int> = [], highlight: Bool = true) -> AttributedString {
    let parts: [FilenameDisplayPart]
    if visibleWhitespace, let comparison { parts = comparison.displayParts(sourceSide: source, markWhitespace: true) }
    else {
        // Display exactly the real characters in the row and editor.
        var result = AttributedString()
        for (index, character) in text.enumerated() {
            var part = AttributedString(String(character))
            if highlight && changes.contains(index) {
                part.foregroundColor = source ? .red : .primary
                part.backgroundColor = source ? Color.red.opacity(0.32) : Color.blue.opacity(0.22)
                part.inlinePresentationIntent = .stronglyEmphasized
            }
            if unrecognized.contains(index) { part.underlineStyle = Text.LineStyle(color: Color(red: 0.78, green: 0.48, blue: 0.02)) }
            result.append(part)
        }
        return result
    }
    var result = AttributedString()
    for display in parts {
        var part = AttributedString(display.text)
        if highlight && display.changed {
            part.foregroundColor = source ? .red : .primary
            part.backgroundColor = source ? Color.red.opacity(0.32) : Color.blue.opacity(0.22)
            part.inlinePresentationIntent = .stronglyEmphasized
        }
        result.append(part)
    }
    return result
}

struct FilenameComparisonView: View {
    @EnvironmentObject var m: Model
    let item: Item
    let nameMatches: Bool
    var spellingReviewChanged: (Bool) -> Void = { _ in }
    @State private var difference = FilenameDifference(source: "", proposed: "")
    @State private var expanded = false
    @State private var unrecognized: [FilenameSpellingWord] = []
    @State private var checkingSpelling = false
    @State private var suggestionWord = ""
    @State private var guesses: [String] = []
    @State private var showSuggestions = false
    @State private var showReplacement = false
    @State private var replacement = ""
    @State private var priorOverride: String?
    @State private var correctionProposal: String?
    @State private var correctionSummary = ""
    private func choose(_ word: String, _ suggestion: String?) {
        suggestionWord = word
        if let suggestion { applySpelling(word, replacement: suggestion) }
        else { replacement = ""; showReplacement = true }
    }
    private func applySpelling(_ word: String, replacement: String) {
        do {
            let corrected = try FilenameSpelling.replacing(word, in: basename, with: replacement, profile: m.active)
            priorOverride = item.overrideBasename
            correctionProposal = corrected
            correctionSummary = "Spelling replacement: " + word + " → " + replacement
            m.editBasename(item.id, value: corrected)
        } catch { m.error = error.localizedDescription }
    }
    private var uniqueWords: [String] {
        var seen = Set<String>()
        return unrecognized.map(\.word).filter { seen.insert($0.lowercased()).inserted }
    }
    private var highlight: Bool { m.universalPreferences.showFilenameDifferences ?? true }
    private var basename: String { (try? proposedBasename(item, profile: m.active)) ?? "" }
    private var proposalError: String? {
        do { _ = try proposedFilename(item, profile: m.active); return nil }
        catch { return error.localizedDescription }
    }
    private var filename: String { (try? proposedFilename(item, profile: m.active)) ?? item.url.lastPathComponent }
    private var sourceBasename: String { item.url.deletingPathExtension().lastPathComponent }
    private var spellingKey: String { sourceBasename + "\n" + m.sharedExceptions + "\n" + String(m.universalPreferences.flagUnrecognizedWords ?? true) }
    private var spellingIndices: Set<Int> { unrecognized.reduce(into: Set<Int>()) { $0.formUnion($1.characterIndices) } }
    private var spellingWords: String {
        var seen = Set<String>()
        return unrecognized.map(\.word).filter { seen.insert($0.lowercased()).inserted }.joined(separator: ", ")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(differenceText(item.url.lastPathComponent, changes: difference.removed, source: true, unrecognized: spellingIndices, highlight: highlight))
                    .font(.system(size: 14)).contentShape(Rectangle()).onTapGesture { m.selectRow(item.id) }
                    .changedTextHover(text: item.url.lastPathComponent, changes: highlight ? difference.removed : [], source: true, fontSize: 14, comparison: difference)
                    .overlay { SpellingContextMenu(text: item.url.lastPathComponent, words: unrecognized, bold: highlight ? difference.removed : [], choose: choose) }
                EmbeddedMetadataButton(item: item)
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, alignment: .leading)
            DirectFilenameEditor(item: item, nameMatches: nameMatches,
                highlightedProposal: differenceText(basename, changes: difference.inserted, source: false, highlight: highlight), changedCharacters: highlight ? difference.inserted : [], comparison: difference)
                .environmentObject(m)
            if let proposalError { Text(proposalError).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            if difference.changed || !unrecognized.isEmpty {
                Button { expanded.toggle() } label: {
                    Label(expanded ? "Hide changes" : "Show changes", systemImage: expanded ? "chevron.up" : "chevron.down")
                }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                if expanded {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(difference.summary).font(.caption.bold())
                        if correctionProposal == item.overrideBasename && !correctionSummary.isEmpty {
                            HStack {
                                Text(correctionSummary)
                                Button("Undo spelling replacement") {
                                    m.restoreSpellingProposal(item.id, expected: correctionProposal, previous: priorOverride)
                                    correctionProposal = nil; correctionSummary = ""
                                }
                            }.font(.caption)
                        }
                        if m.universalPreferences.flagUnrecognizedWords ?? true {
                            Text("Source spelling check: macOS dictionary + universal exceptions · " + (checkingSpelling ? "Checking…" : "\(unrecognized.count) unrecognized word\(unrecognized.count == 1 ? "" : "s")")).font(.caption).foregroundStyle(.secondary)
                        }
                        if !unrecognized.isEmpty {
                            ForEach(uniqueWords, id: \.self) { word in
                                HStack {
                                    Text(word).foregroundStyle(Color(red: 0.78, green: 0.48, blue: 0.02))
                                    Button("Suggestions…") {
                                        suggestionWord = word; guesses = FilenameSpellChecker.shared.suggestions(for: word); showSuggestions = true
                                    }
                                }.font(.caption)
                            }
                            Text("Choose Suggestions or right-click an amber-underlined source word. Corrections affect matching words in this file’s proposal only; Rename applies the result.").font(.caption2).foregroundStyle(.secondary)
                            Text("Solid amber underlines on the current filename mark source words not recognized by the macOS dictionary or your universal exceptions. Names, invented words and words in other languages may be intentional. Advisory only; files can still be renamed or filed.").font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("Current: ") + Text(differenceText(difference.source, changes: difference.removed, source: true, visibleWhitespace: true, comparison: difference, highlight: highlight))
                        Text("Proposed: ") + Text(differenceText(difference.proposed, changes: difference.inserted, source: false, visibleWhitespace: true, comparison: difference, highlight: highlight))
                        Text("Red = removed/replaced · Blue = added/replacement. [[SPACE]], [[SPACES × count]] and [[TAB]]/[[TABS × count]] are display-only labels for changed whitespace; unchanged spaces stay blank.")
                            .font(.caption2).foregroundStyle(.secondary)
                        if !difference.literalWhitespaceLabels.isEmpty {
                            Text("Review carefully: " + difference.literalWhitespaceLabels.joined(separator: ", ") + " also occurs literally in the source or proposed filename. Those literal occurrences are not generated whitespace labels.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        Text("Rules triggered: " + (item.overrideBasename != nil ? "Manual filename override (automatic cleanup bypassed for output)" : (item.rulesTriggered.isEmpty ? (!item.alternatives.isEmpty ? "Magic interpretation; per-rule attribution unavailable" : "None recorded; proposal uses filename components and output mask") : item.rulesTriggered.joined(separator: " · ")))).font(.caption)
                    }.font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .popover(isPresented: $showSuggestions) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Suggestions for “" + suggestionWord + "”").font(.headline)
                if guesses.isEmpty { Text("No suggestions found").foregroundStyle(.secondary) }
                ForEach(guesses, id: \.self) { guess in
                    Button(guess) { showSuggestions = false; choose(suggestionWord, guess) }
                }
                Divider()
                Button("Enter replacement…") { showSuggestions = false; choose(suggestionWord, nil) }
            }.padding().frame(minWidth: 240)
        }
        .alert("Replace “" + suggestionWord + "” in proposed filename", isPresented: $showReplacement) {
            TextField("Replacement", text: $replacement)
            Button("Use replacement") { applySpelling(suggestionWord, replacement: replacement) }.disabled(replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: { Text("Updates matching words in this file’s proposal only. Rename applies the change to disk.") }
        .task(id: spellingKey) {
            unrecognized = []; spellingReviewChanged(false)
            guard m.universalPreferences.flagUnrecognizedWords ?? true else { checkingSpelling = false; return }
            checkingSpelling = true
            let checked = await FilenameSpellChecker.shared.unrecognized(in: sourceBasename, exceptions: m.universalPreferences.combinedEntries)
            if !Task.isCancelled { unrecognized = checked; checkingSpelling = false; spellingReviewChanged(!checked.isEmpty) }
        }
        .onAppear { update() }
        .onChange(of: filename) { update() }
        .onChange(of: item.url.path) { correctionProposal = nil; correctionSummary = ""; showSuggestions = false; update() }
    }
    private func update() { HoverHelp.shared.hide(); difference = FilenameDifference(source: item.url.lastPathComponent, proposed: filename) }
}

import SwiftUI
import AppKit
import FilerCore

@discardableResult func showFolderInFinder(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return false }
    return NSWorkspace.shared.open(url)
}

enum AppIdentity {
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Shelf Elf Librarian"
    static var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let release = Bundle.main.object(forInfoDictionaryKey: "ShelfElfReleaseLabel") as? String ?? "Beta 1"
        return "\(version) \(release)"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "AppIcon-v3", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = icon
        }
    }
}
@main struct LibraryFilerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model = Model()
    var body: some Scene {
        WindowGroup(AppIdentity.name) { MainView().environmentObject(model).frame(minWidth: 1100, minHeight: 700) }
            .defaultSize(width: 1320, height: 850)
            .windowStyle(.titleBar)
            .windowToolbarStyle(.unified(showsTitle: false))
            .commands {
                CommandGroup(replacing: .appInfo) {
                    Button("About \(AppIdentity.name)") { WindowPresentation.about() }
                }
                CommandGroup(replacing: .help) {
                    Button("Shelf Elf Help") { WindowPresentation.help() }.keyboardShortcut("?", modifiers: .command)
                }
                CommandMenu("Tools") {
                    Button("Export Settings…") { model.exportSettings() }.disabled(model.busy)
                    Button("Import Settings…") { model.importSettings() }.disabled(model.busy)
                    Button("Restore Settings Backup…") { model.showSettingsBackups = true }.disabled(model.busy)
                    Divider()
                    Button("Update MP3 Tags from Components…") { model.prepareMP3Tags(.update) }.disabled(model.busy || model.active.kind != .music || model.visibleSelected.isEmpty)
                    Button("Purge Other MP3 Tags…") { model.prepareMP3Tags(.purge) }.disabled(model.busy || model.active.kind != .music || model.visibleSelected.isEmpty)
                    Divider()
                    Button("Clean Folder Names…") { model.prepareFolders() }.disabled(model.workspace == nil || model.busy)
                }
                CommandGroup(after: .appInfo) {
                    Button("License & Usage Notice…") { NotificationCenter.default.post(name: Notification.Name("ShowLicenseTerms"), object: nil) }
                    Button("General Settings…") { model.showGeneralSettings = true }
                    Button("Show Welcome Screen") { NotificationCenter.default.post(name: Notification.Name("ShowShelfElfWelcome"), object: nil) }
                }
            }
        Settings { SettingsView(profile: model.active, existing: model.profiles.contains { $0.id == model.activeID }, save: model.saveProfile, delete: model.deleteProfile).environmentObject(model).frame(width: 660, height: 700) }
    }
}
struct WorkspaceSession: Codable {
    let path: String
    let bookmark: Data?
    let identity: DirectoryIdentity?
}
@MainActor final class Model: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var activeID = UUID()
    @Published var items: [Item] = []
    @Published var selected: Set<String> = []
    @Published var workspace: URL?
    @Published var recursive = false
    @Published var filter = ""
    @Published var reverse = false
    @Published var sortColumn = "name"
    @Published var excluded: [String] = []
    @Published var category = ""
    @Published var availableCategories: [String] = []
    @Published var categoryConfirmed = false
    @Published var mode: Mode = .copy
    @Published var busy = false
    @Published var status = "Choose a profile and open a workspace, then review filename cleanup."
    @Published var progress = ""
    @Published var plan: Plan?
    @Published var transferPlan: Plan?
    @Published var transferSummary: String?
    @Published var transferDetails: [String] = []
    func dismissTransfer() {
        guard !busy else { return }
        showReview = false; showQuickFiling = false
        transferPlan = nil; transferSummary = nil; transferDetails = []
    }
    @Published var showReview = false
    @Published var showQuickFiling = false
    @Published var quickPlan: Plan?
    @Published var quickFailure: String?
    private var pendingSkipFiling = false
    @Published var quickMode: Mode = .copy
    @Published var quickKeepNames = false
    @Published var quickIsMagic = false
    private var quickItems: [Item] = []
    private var quickProfile: Profile?
    private var previewItems: [Item] = []
    @Published var mp3TagPlan: MP3TagPlan?
    @Published var showMP3Tags = false
    @Published var showHistory = false
    @Published var showSettings = false
    @Published var showExcluded = false
    @Published var events: [Event] = []
    @Published var folderEvents: [FolderEvent] = []
    @Published var observations: [ConfirmedCorrection] = []
    @Published var folderPlan: FolderPlan?
    @Published var showFolders = false
    @Published var showBatchNames = false
    @Published var error: String?
    let support: URL
    var cancellation = Cancellation()
    var scopeURLs: [URL] = []
    let newProfile = ProfileSetup.configured(.video, name: "New Video Profile")
    @Published var universalPreferences: UniversalPreferences = {
        if let data = AppEnvironment.defaults.data(forKey: "universalSpellingCasePreferences"), let saved = try? JSONDecoder().decode(UniversalPreferences.self, from: data) { return saved }
        // Preserve the user's existing universal list in Other; do not import profile-specific lists.
        if let old = AppEnvironment.defaults.string(forKey: "globalSpellingExceptions") { return UniversalPreferences(existingExceptions: old) }
        return UniversalPreferences.suggestedDefaults
    }()
    var sharedExceptions: String { universalPreferences.combined }
    @Published var showSettingsBackups = false
    @Published var showGeneralSettings = false
    var active: Profile {
        var p = profiles.first { $0.id == activeID } ?? newProfile
        p.exceptions = sharedExceptions
        var rules = p.rules; rules.smallWords = universalPreferences.titleWords; p.rules = rules
        return p
    }
    func saveGeneralSettings(_ preferences: UniversalPreferences) throws {
        guard !busy else { throw fail("Wait for the current operation to finish.") }
        try preferences.validate()
        guard preferences != universalPreferences else { return }
        let data = try JSONEncoder().encode(preferences)
        try backupConfiguration("Save General Settings")
        AppEnvironment.defaults.set(data, forKey: "universalSpellingCasePreferences")
        universalPreferences = preferences
        HoverHelp.shared.timing = preferences.hoverTiming ?? .immediate
        invalidate()
        if workspace != nil { refresh() }
    }
    var visible: [Item] {
        let filtered = items.filter { filter.isEmpty || $0.url.lastPathComponent.localizedCaseInsensitiveContains(filter) }
        return filtered.sorted { a, b in
            var order: ComparisonResult = .orderedSame
            switch sortColumn {
            case "ok":
                let x = nameMatches(a), y = nameMatches(b)
                if x != y { order = x ? .orderedAscending : .orderedDescending }
            case "type":
                order = a.url.pathExtension.localizedCaseInsensitiveCompare(b.url.pathExtension)
                if order == .orderedSame && a.size != b.size { order = a.size < b.size ? .orderedAscending : .orderedDescending }
            case "confirmation":
                if a.reviewed != b.reviewed { order = a.reviewed ? .orderedAscending : .orderedDescending }
            default: break
            }
            if order == .orderedSame { order = a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent) }
            if order == .orderedSame { order = a.id.compare(b.id) }
            return reverse ? order == .orderedDescending : order == .orderedAscending
        }
    }
    func nameMatches(_ item: Item) -> Bool {
        (try? proposedFilename(item, profile: active)).map { $0.utf8.elementsEqual(item.url.lastPathComponent.utf8) } ?? false
    }
    func sortBy(_ column: String) { HoverHelp.shared.hide(); if sortColumn == column { reverse.toggle() } else { sortColumn = column; reverse = false } }
    func toggleVisibleSelection() {
        let ids = Set(visible.map(\.id))
        if ids.isSubset(of: selected) { selected.subtract(ids) } else { selected.formUnion(ids) }
        invalidate()
    }
    var tagEditsBefore: [String: Item] = [:]
    @Published var filenameFocusID: String?
    @Published var filenameFocusRequest = UUID()
    @Published var directRenameUndo: [String: Event] = [:]
    private var directRenameBefore: [UUID: Item] = [:]
    func renameNow(_ ids: Set<String>, manualBasename: String? = nil) {
        guard !busy else { return }
        let originals = items.filter { ids.contains($0.id) }
        let chosen = originals.map { item in
            var copy = item
            if let manualBasename { copy.overrideBasename = manualBasename }
            return copy
        }
        guard !chosen.isEmpty else { return }
        let profile = active, db = support.appendingPathComponent("operations.sqlite")
        cancellation = Cancellation(); let token = cancellation
        invalidate(); busy = true; progress = "Renaming in workspace…"
        Task {
            do {
                let (result, completed, blocked) = try await Task.detached { () throws -> (ExecutionResult, [Event], [String]) in
                    let plan = try makeDirectRenamePlan(items: chosen, profile: profile)
                    let journal = try Journal(url: db)
                    let result = try Executor(journal: journal).execute(plan, cancel: token)
                    let completed = try journal.events().filter { $0.operation == plan.id && $0.state == "Moved" }
                    let blocked = plan.rows.filter { !$0.actionable }.map { $0.source + ": " + $0.status + " — " + $0.explanation }
                    return (result, completed, blocked)
                }.value
                for event in completed {
                    guard let index = items.firstIndex(where: { $0.id == event.row.source }), let before = originals.first(where: { $0.id == event.row.source }) else { continue }
                    directRenameUndo.removeValue(forKey: before.id)
                    directRenameBefore[event.id] = before
                    selected.remove(before.id)
                    tagEditsBefore.removeValue(forKey: before.id)
                    items[index].url = URL(fileURLWithPath: event.row.destination)
                    // Keep component values and their confirmation independent of the direct rename.
                    items[index].overrideBasename = items[index].url.deletingPathExtension().lastPathComponent
                    directRenameUndo[items[index].id] = event
                }
                status = "\(result.completed) renamed in workspace • \(result.failed + blocked.count) failed or blocked"
                let details = result.details + blocked
                if !details.isEmpty { error = details.joined(separator: "\n\n") }
            } catch { self.error = error.localizedDescription }
            busy = false; progress = ""; loadHistory()
        }
    }
    func undoDirectRename(_ event: Event) {
        guard !busy else { return }
        let db = support.appendingPathComponent("operations.sqlite")
        invalidate(); busy = true; progress = "Undoing workspace rename…"
        Task {
            do {
                try await Task.detached { try Executor(journal: Journal(url: db)).undo(event, allowDeleteCopy: false) }.value
                if let index = items.firstIndex(where: { $0.id == event.row.destination }) {
                    selected.remove(items[index].id)
                    if let before = directRenameBefore.removeValue(forKey: event.id) { items[index] = before }
                    else { items[index].url = URL(fileURLWithPath: event.row.source); items[index].overrideBasename = nil }
                }
                directRenameUndo.removeValue(forKey: event.row.destination)
                status = "Original filename restored on disk."
            } catch { self.error = error.localizedDescription }
            busy = false; progress = ""; loadHistory()
        }
    }

    var visibleSelected: [Item] { visible.filter { selected.contains($0.id) } }
    init() {
        support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(AppEnvironment.supportName)
        mode = universalPreferences.filingAction
        HoverHelp.shared.timing = universalPreferences.hoverTiming ?? .immediate
        do {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            let profilesURL = support.appendingPathComponent("profiles.json")
            if let demoRoot = AppEnvironment.screenshotRoot {
                let root = URL(fileURLWithPath: demoRoot)
                let archive = try JSONDecoder().decode(SettingsArchive.self, from: Data(contentsOf: root.appendingPathComponent("Demo Settings.json")))
                let demoProfiles = try archive.validatedProfiles()
                try ProfileSettingsStore.write(demoProfiles, to: profilesURL)
                universalPreferences = archive.general; mode = archive.general.filingAction
                AppEnvironment.defaults.set(try JSONEncoder().encode(archive.general), forKey: "universalSpellingCasePreferences")
                AppEnvironment.defaults.set(archive.activeProfileID?.uuidString, forKey: "lastProfile")
                AppEnvironment.defaults.removeObject(forKey: "workspaceSession")
                AppEnvironment.defaults.set(root.appendingPathComponent("Workspace/Music").path, forKey: "recentWorkspace")
            }
            if FileManager.default.fileExists(atPath: profilesURL.path) { profiles = try ProfileSettingsStore.read(from: profilesURL) }
            else { profiles = ProfileSetup.starterProfiles; try ProfileSettingsStore.write(profiles, to: profilesURL) }
            let migratedProfiles = try profiles.map { try ProfileSetup.migrate($0) }
            if migratedProfiles != profiles {
                let migrated = migratedProfiles
                try persistProfiles(migrated, reason: "Profile pattern migration")
                profiles = migrated
            }
            let described = profiles.map { StarterDescriptions.fillingBlankNotes(ProfileSetup.addingMissingVideoTypes(ProfileSetup.updatingVideoDefaults($0))) }
            if described != profiles {
                try persistProfiles(described, reason: "Update starter profile defaults/descriptions")
                profiles = described
            }
            activeID = UUID(uuidString: AppEnvironment.defaults.string(forKey: "lastProfile") ?? "") ?? profiles.first?.id ?? newProfile.id
            if !profiles.contains(where: { $0.id == activeID }) { activeID = profiles.first?.id ?? newProfile.id }
            for p in profiles { if let bookmark = p.bookmark { var stale = false; let u = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], bookmarkDataIsStale: &stale); if stale { status = "Reconnect a saved destination in Settings." }; if u.startAccessingSecurityScopedResource() { scopeURLs.append(u) } } }
            loadHistory()
            loadCategories()
            restoreWorkspace()
        } catch { self.error = error.localizedDescription }
    }
    func invalidate() { HoverHelp.shared.hide(); plan = nil; folderPlan = nil; categoryConfirmed = false; showReview = false; showFolders = false }
    func changeProfile() {
        tagEditsBefore.removeAll(); filenameFocusID = nil; selected = []; items = []; invalidate(); AppEnvironment.defaults.set(activeID.uuidString, forKey: "lastProfile"); loadCategories(); if profiles.isEmpty { excluded = []; status = "No library profiles. Open Settings to create one." } else if workspace != nil { refresh() } }
    func loadCategories() { availableCategories = []; category = "" }
    func saveProfile(_ input: Profile) throws {
        guard !busy else { throw fail("Wait for the running operation before changing profile settings.") }
        let p = ProfileSetup.addingMissingVideoTypes(input)
        try p.validate()
        var next = profiles
        if let i = next.firstIndex(where: { $0.id == p.id }) { next[i] = p } else { next.append(p) }
        try persistProfiles(next, reason: "Save profile: " + p.name)
        profiles = next; activeID = p.id; changeProfile(); showSettings = false
    }
    func deleteProfile(_ id: UUID) throws {
        guard !busy else { throw fail("Wait for the current operation to finish before deleting a profile.") }
        guard profiles.contains(where: { $0.id == id }) else { throw fail("This profile is no longer saved.") }
        let next = profiles.filter { $0.id != id }
        // Persist first: a failed write must leave the current profile and preview intact.
        try persistProfiles(next, reason: "Delete profile: " + (profiles.first { $0.id == id }?.name ?? "Profile"))
        profiles = next
        if activeID == id { activeID = next.first?.id ?? newProfile.id }
        showSettings = false
        changeProfile()
    }
    func rememberWorkspace(_ url: URL) throws {
        let directory = try Directory(url.path)
        let session = WorkspaceSession(path: url.path,
            bookmark: try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil),
            identity: DirectoryIdentity(device: directory.device, inode: directory.inode))
        AppEnvironment.defaults.set(try JSONEncoder().encode(session), forKey: "workspaceSession")
        AppEnvironment.defaults.set(url.path, forKey: "recentWorkspace")
        AppEnvironment.defaults.set(activeID.uuidString, forKey: "lastProfile")
    }
    func restoreWorkspace() {
        let defaults = AppEnvironment.defaults
        let session: WorkspaceSession
        do {
            if let data = defaults.data(forKey: "workspaceSession") {
                session = try JSONDecoder().decode(WorkspaceSession.self, from: data)
            } else if let path = defaults.string(forKey: "recentWorkspace") {
                session = WorkspaceSession(path: path, bookmark: nil, identity: nil)
            } else { return }
        } catch { status = "Could not restore the saved workspace. Use Open Workspace to choose it again."; return }
        busy = true; progress = "Restoring workspace…"
        Task {
            do {
                let (url, scoped) = try await Task.detached { () throws -> (URL, Bool) in
                    let url: URL
                    if let bookmark = session.bookmark {
                        var stale = false
                        url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], bookmarkDataIsStale: &stale)
                    } else { url = URL(fileURLWithPath: session.path) }
                    let scoped = url.startAccessingSecurityScopedResource()
                    do {
                        let d = try Directory(url.path)
                        if let identity = session.identity {
                            guard d.device == identity.device, d.inode == identity.inode else { throw fail("The saved folder or volume has been replaced.") }
                        }
                        return (url, scoped)
                    } catch { if scoped { url.stopAccessingSecurityScopedResource() }; throw error }
                }.value
                if scoped { scopeURLs.append(url) }
                try rememberWorkspace(url)
                workspace = url
                busy = false; progress = ""
                if profiles.isEmpty { status = "Workspace restored. Open Settings to create a library profile." }
                else { refresh() }
            } catch {
                busy = false; progress = ""
                status = "Last workspace unavailable: \(session.path). Use Open Workspace to reconnect. \(error.localizedDescription)"
            }
        }
    }
    func openWorkspace() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = "Open Workspace"
        WindowPresentation.choose(panel) { [self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try rememberWorkspace(url)
                if url.startAccessingSecurityScopedResource() { scopeURLs.append(url) }
                workspace = url; invalidate(); selected = []; refresh()
            } catch { self.error = error.localizedDescription }
        }
    }
    func refresh() {
        guard !profiles.isEmpty, let root = workspace else { return }; let p = active, recurse = recursive
        cancellation = Cancellation(); let token = cancellation
        tagEditsBefore.removeAll(); filenameFocusID = nil
        busy = true; status = "Discovering eligible files…"; progress = "Scanning"; invalidate()
        Task { do { let r = try await Task.detached { try await scanMedia(root, profile: p, recursive: recurse, cancel: token) }.value; items = r.items.map { var item = $0; item.rememberCorrection = p.rememberCorrectionsByDefault ?? true; return item }; excluded = r.excluded; selected = []; status = "\(items.count.formatted()) eligible • \(excluded.count.formatted()) excluded" } catch { self.error = error.localizedDescription }; busy = false; progress = "" }
    }
    func updateFields(_ edit: (inout Fields) -> Void) { for i in items.indices where selected.contains(items[i].id) && visible.contains(where: { $0.id == items[i].id }) { edit(&items[i].fields); items[i].fields.artist = RuleEngine.artistName(items[i].fields.artist, profile: active); items[i].overrideBasename = nil; items[i].reviewed = false }; invalidate() }
    func selectRow(_ id: String) { selected = [id]; invalidate() }
    func confirmFields() { for i in items.indices where visibleSelected.contains(where: { $0.id == items[i].id }) { items[i].reviewed = true }; invalidate() }
    func preview(_ clean: Bool) {
        // The profile now fully specifies the destination. Preview is the confirmation step.
        var p = active
        p.rootAllowed = true
        let chosen = visibleSelected, operation: Mode = clean ? .clean : mode, cat = p.fixedCategory
        guard !chosen.isEmpty else { error = "Select eligible visible files first."; return }
        if !clean && !checkLibraryDestination(p, onReconnect: { [weak self] _ in self?.preview(clean) }) { return }
        previewItems = chosen
        busy = true; progress = "Hashing preview sources…"
        Task { do { plan = try await Task.detached { try makePlan(items: chosen, profile: p, mode: operation, category: cat, fileOnly: false) }.value; showReview = true } catch { self.error = error.localizedDescription }; busy = false; progress = "" }
    }
    func checkLibraryDestination(_ profile: Profile, onReconnect: @escaping (Profile) -> Void = { _ in }) -> Bool {
        if profile.root.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let alert = NSAlert(); alert.messageText = "Library destination not configured"
            alert.informativeText = "Choose a destination folder in Profile Settings → Profile & destination → Choose Library Location before copying or moving files."
            alert.addButton(withTitle: "Open Profile Settings"); alert.addButton(withTitle: "Cancel")
            WindowPresentation.confirm(alert) { [weak self] response in if response == .alertFirstButtonReturn { self?.showSettings = true } }
            return false
        }
        do {
            guard profile.root.hasPrefix("/"), !profile.root.contains("//"), !profile.root.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { throw fail("The library destination is not a valid absolute folder path.") }
            let directory = try Directory(profile.root)
            if let identity = profile.rootIdentity, identity.device != directory.device || identity.inode != directory.inode {
                let replacement = DirectoryIdentity(device: directory.device, inode: directory.inode)
                let alert = NSAlert(); alert.messageText = "Library folder has been replaced"
                alert.informativeText = "The path is still configured, but it now refers to a different folder:\n\n" + profile.root + "\n\nUse this folder as this profile’s library? The preview will be rebuilt before any files are processed."
                alert.addButton(withTitle: "Use This Folder"); alert.addButton(withTitle: "Cancel")
                WindowPresentation.confirm(alert) { [weak self] response in
                    guard let self, response == .alertFirstButtonReturn else { return }
                    do {
                        let current = try Directory(profile.root)
                        guard current.device == replacement.device, current.inode == replacement.inode else { throw fail("The library folder changed again. Preview again to confirm the current folder.") }
                        guard let i = self.profiles.firstIndex(where: { $0.id == profile.id }), self.profiles[i].root == profile.root, self.profiles[i].rootIdentity == profile.rootIdentity else { throw fail("The profile’s library setting changed. Preview again using the current settings.") }
                        let bookmark = try URL(fileURLWithPath: profile.root).bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                        var next = self.profiles
                        next[i].rootIdentity = replacement; next[i].bookmark = bookmark
                        try self.persistProfiles(next, reason: "Reconnect library: " + profile.name)
                        self.profiles = next; self.invalidate()
                        var rebound = profile; rebound.rootIdentity = replacement; rebound.bookmark = bookmark
                        onReconnect(rebound)
                    } catch { self.error = "Library folder was not reconnected. " + error.localizedDescription }
                }
                return false
            }
            return true
        } catch { self.error = "Library destination unavailable: \(profile.root). Reconnect it in Profile Settings → Choose Library Location. \(error.localizedDescription)"; return false }
    }
    func skipReviewAndFile() {
        guard !busy, let preview = plan, preview.mode != .clean else { return }
        quickItems = previewItems; quickProfile = preview.profile; quickMode = preview.mode; quickKeepNames = true; quickIsMagic = false
        pendingSkipFiling = true; showReview = false
    }
    func reviewDismissed() {
        guard pendingSkipFiling else { return }
        pendingSkipFiling = false; rebuildQuickFiling(quickMode)
    }
    func beginQuickFiling(_ chosen: [Item], profile: Profile, mode: Mode, keepNames: Bool, magic: Bool = false) {
        guard !chosen.isEmpty, checkLibraryDestination(profile, onReconnect: { [weak self] rebound in self?.beginQuickFiling(chosen, profile: rebound, mode: mode, keepNames: keepNames, magic: magic) }) else { return }
        quickItems = chosen; quickProfile = profile; quickMode = mode; quickKeepNames = keepNames; quickIsMagic = magic
        rebuildQuickFiling(mode)
    }
    func rebuildQuickFiling(_ mode: Mode) {
        guard !busy, let profile = quickProfile else { return }
        let chosen = quickItems, keepNames = quickKeepNames, magic = quickIsMagic
        quickPlan = nil; quickFailure = "Confirm the replacement library folder to rebuild this preview."
        guard checkLibraryDestination(profile, onReconnect: { [weak self] rebound in self?.quickProfile = rebound; self?.rebuildQuickFiling(mode) }) else { return }
        quickPlan = nil; quickFailure = nil; busy = true; progress = "Checking library destinations…"
        cancellation = Cancellation(); let token = cancellation
        Task {
            do {
                let result = try await Task.detached { try magic ? makeMagicFilingPlan(items: chosen, profile: profile, mode: mode, cancel: token) : makeConfirmedFilingPlan(items: chosen, profile: profile, mode: mode, keepCurrentNames: keepNames) }.value
                guard !token.cancelled else { busy = false; progress = ""; status = "Preview cancelled; no files changed."; return }
                quickPlan = result; showQuickFiling = true
            } catch { if token.cancelled { status = "Preview cancelled; no files changed." } else { quickFailure = error.localizedDescription; showQuickFiling = true } }
            busy = false; progress = ""
        }
    }
    func cancelQuickFiling() {
        if busy { cancellation.cancel() }
        showQuickFiling = false; quickPlan = nil; quickFailure = nil
    }
    func applyQuickFiling() {
        guard !busy, var confirmed = quickPlan else { return }
        confirmed.rows = confirmed.rows.filter(\.actionable)
        guard !confirmed.rows.isEmpty else { return }
        plan = confirmed; quickPlan = nil; apply()
    }
    func apply() {
        guard let p = plan, !busy else { return }
        let reviewWasVisible = showReview
        if p.mode != .clean && !checkLibraryDestination(p.profile, onReconnect: { [weak self] rebound in
            guard let self else { return }
            let sources = Set(p.rows.map(\.source))
            self.quickItems = self.items.filter { sources.contains($0.id) }
            self.quickProfile = rebound; self.quickMode = p.mode; self.quickKeepNames = p.fileOnly; self.quickIsMagic = p.magicRun == true
            if reviewWasVisible { self.pendingSkipFiling = true; self.showReview = false }
            else { self.rebuildQuickFiling(p.mode) }
        }) { return }
        if p.mode != .clean {
            transferPlan = p; transferSummary = nil; transferDetails = []
            if !showReview && !showQuickFiling { showReview = true }
        } else { showReview = false; showQuickFiling = false }
        busy = true; progress = "Preparing transfer…"
        cancellation = Cancellation(); let token = cancellation
        let db = support.appendingPathComponent("operations.sqlite")
        Task {
            var summary = "Operation stopped. Review History for details."
            do {
                let r = try await Task.detached {
                    let j = try Journal(url: db)
                    return try Executor(journal: j).execute(p, cancel: token) { done, total in Task { @MainActor in self.progress = "\(done.formatted()) / \(total.formatted()) files" } }
                }.value
                summary = "\(r.completed) completed • \(r.failed) failed. \(token.cancelled ? "Cancelled; completed items remain completed." : "")"
                if transferPlan != nil {
                    let action = p.mode == .copy ? "Copy" : "Move"
                    let verb = p.mode == .copy ? "copied" : "moved"
                    let outcome = token.cancelled ? "cancelled" : r.failed > 0 ? "finished with errors" : "complete"
                    transferSummary = "\(action) \(outcome) — \(r.completed) \(verb), \(r.failed) failed"
                    transferDetails = r.details
                } else if !r.details.isEmpty { error = r.details.joined(separator: "\n\n") }
            } catch {
                if transferPlan != nil { transferSummary = "\(p.mode == .copy ? "Copy" : "Move") stopped"; transferDetails.append(error.localizedDescription) }
                else { self.error = error.localizedDescription }
            }
            let completed: Set<String>
            do { completed = OperationPresentation.completedSources(plan: p, events: try Journal(url: db).events()) }
            catch {
                completed = []
                let detail = "Could not read operation completion details. Review History. " + error.localizedDescription
                if transferPlan != nil { transferDetails.append(detail) } else { self.error = detail }
            }
            selected.subtract(completed)
            for id in completed { tagEditsBefore.removeValue(forKey: id) }
            if p.mode == .move {
                let existing = items, remainingSelection = selected
                items.removeAll { completed.contains($0.id) }
                if let root = workspace {
                    let profile = active, recurse = recursive
                    let refreshToken = Cancellation(); cancellation = refreshToken
                    progress = "Refreshing workspace…"
                    do {
                        let fresh = try await Task.detached { try await scanMedia(root, profile: profile, recursive: recurse, cancel: refreshToken) }.value
                        let updated = OperationPresentation.reconcile(existing: existing, scanned: fresh.items, selected: remainingSelection, completed: completed, rememberNew: profile.rememberCorrectionsByDefault ?? true)
                        items = updated.items; selected = updated.selected; excluded = fresh.excluded
                        let ids = Set(items.map(\.id)); directRenameUndo = directRenameUndo.filter { ids.contains($0.key) }
                    } catch {
                        let detail = "Workspace refresh was incomplete. Click Refresh to reload it. " + error.localizedDescription
                        if transferPlan != nil { transferDetails.append(detail) } else { self.error = detail }
                    }
                }
            }
            status = summary; busy = false; progress = ""; plan = nil; quickPlan = nil; categoryConfirmed = false; loadHistory()
        }
    }
    func loadHistory() {
        do {
            let journal = try Journal(url: support.appendingPathComponent("operations.sqlite"))
            try journal.pruneHistory()
            events = try journal.events(); folderEvents = try journal.folderEvents()
            let forgotten = Set(AppEnvironment.defaults.stringArray(forKey: "forgottenCorrections") ?? [])
            let current = Learning.observations(events: events, forgotten: forgotten)
            let currentIDs = Set(current.map(\.id))
            observations = current + (try journal.rememberedCorrections()).filter { !forgotten.contains($0.id.uuidString) && !currentIDs.contains($0.id) }
            directRenameUndo = directRenameUndo.filter { $0.value.date >= Date().addingTimeInterval(-30 * 24 * 60 * 60) }
            let undoIDs = Set(directRenameUndo.values.map(\.id)); directRenameBefore = directRenameBefore.filter { undoIDs.contains($0.key) }
        } catch { self.error = error.localizedDescription }
    }
    func recommendations(for profile: Profile) -> [ProfileRecommendation] {
        let dismissed = Set(AppEnvironment.defaults.stringArray(forKey: "dismissedRecommendations") ?? [])
        return Learning.recommendations(profile: profile, observations: observations, excluded: profile.id == activeID ? excluded : []).filter { !dismissed.contains($0.id) }
    }
    func dismissRecommendation(_ id: String) {
        var ids = AppEnvironment.defaults.stringArray(forKey: "dismissedRecommendations") ?? []; ids.append(id)
        AppEnvironment.defaults.set(ids, forKey: "dismissedRecommendations"); objectWillChange.send()
    }
    func forgetCorrection(_ id: UUID) {
        var ids = AppEnvironment.defaults.stringArray(forKey: "forgottenCorrections") ?? []; ids.append(id.uuidString)
        AppEnvironment.defaults.set(ids, forKey: "forgottenCorrections"); invalidate(); loadHistory()
    }
    func editBasename(_ id: String, value: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if items[index].initialBasename == nil { items[index].initialBasename = try? proposedBasename(items[index], profile: active) }
        if items[index].initialFields == nil { items[index].initialFields = items[index].fields }
        items[index].overrideBasename = value; invalidate()
    }
    func restoreSpellingProposal(_ id: String, expected: String?, previous: String?) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].overrideBasename == expected else { return }
        items[index].overrideBasename = previous; invalidate()
    }
    func resetName(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].overrideBasename = nil; items[index].reviewed = false; invalidate()
    }
    func replaceSelected(find: String, replacement: String) {
        guard !find.isEmpty else { return }
        let edits = visibleSelected.compactMap { item -> (String, String)? in
            guard let stem = try? proposedBasename(item, profile: active) else { return nil }
            return (item.id, stem.replacingOccurrences(of: find, with: replacement))
        }
        for (id, name) in edits { editBasename(id, value: name) }
    }
    func analyzeMagic() {
        guard !busy, active.rules.useMagic, !visibleSelected.isEmpty else { return }
        let chosen = visibleSelected, profile = active, memory = observations, operation = mode
        guard checkLibraryDestination(profile, onReconnect: { [weak self] _ in self?.analyzeMagic() }) else { return }
        cancellation = Cancellation(); let token = cancellation
        busy = true; progress = "Analyzing with Magic…"; invalidate()
        Task {
            do {
                let results = try await Task.detached { try Magic.prepare(chosen, profile: profile, memories: memory, cancel: token) }.value
                if token.cancelled { throw fail("Magic analysis cancelled; existing proposals unchanged.") }
                for result in results { if let index = items.firstIndex(where: { $0.id == result.id }) { items[index] = result } }
                status = "Magic analysis complete. Confirm Copy or Move to apply proposed names in the library."
                busy = false; progress = ""
                beginQuickFiling(results, profile: profile, mode: operation, keepNames: false, magic: true)
                return
            } catch { status = error.localizedDescription }
            busy = false; progress = ""
        }
    }
    func chooseAlternative(_ id: String, choice: Interpretation) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].fields = choice.fields; items[index].evidence = choice.evidence; items[index].confidence = choice.confidence
        if items[index].overrideBasename == nil { items[index].overrideBasename = choice.overrideBasename }
        items[index].reviewed = false; invalidate()
    }
    func rememberSelected(_ remember: Bool) {
        for i in items.indices where visibleSelected.contains(where: { $0.id == items[i].id }) { items[i].rememberCorrection = remember }
        invalidate()
    }
    func prepareFolders() {
        guard let root = workspace else { error = "Open a workspace first."; return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true; panel.directoryURL = root
        panel.prompt = "Preview Folder Renames"; panel.message = "Using profile: \(active.name). Choose direct child folders of this workspace. All contents, including hidden files, move with a folder rename. Names inside it remain unchanged."
        WindowPresentation.choose(panel) { [self] response in
            guard response == .OK else { return }
            guard panel.urls.allSatisfy({ $0.deletingLastPathComponent().path == root.path }) else { error = "Choose only direct child folders of the current workspace."; return }
            let chosen = Set(panel.urls.map(\.path)), p = active
            busy = true; cancellation = Cancellation(); let token = cancellation; progress = "Validating selected folder contents…"; invalidate()
            Task {
                do { folderPlan = try await Task.detached { try planFolders(workspace: root, profile: p, selectedPaths: chosen, cancel: token) }.value; showFolders = true }
                catch { self.error = error.localizedDescription }
                busy = false; progress = ""
            }
        }
    }
    func applyFolders(_ included: Set<UUID>) {
        guard let plan = folderPlan else { return }
        busy = true; showFolders = false; cancellation = Cancellation(); let token = cancellation
        let db = support.appendingPathComponent("operations.sqlite"); progress = "Renaming selected folders…"
        Task {
            do {
                let result = try await Task.detached { try FolderExecutor(journal: Journal(url: db)).execute(plan, included: included, cancel: token) }.value
                status = "\(result.completed) folders renamed • \(result.failed) failed. Refresh the workspace to update paths."
                if !result.details.isEmpty { error = result.details.joined(separator: "\n\n") }
            } catch { self.error = error.localizedDescription }
            busy = false; progress = ""; folderPlan = nil; items = []; selected = []; loadHistory()
        }
    }
    func undoFolder(_ event: FolderEvent) {
        busy = true; let db = support.appendingPathComponent("operations.sqlite")
        Task {
            do { try await Task.detached { try FolderExecutor(journal: Journal(url: db)).undo(event) }.value; status = "Folder rename undone. Refresh the workspace." }
            catch { self.error = error.localizedDescription }
            busy = false; loadHistory()
        }
    }
    func canRecover(_ event: Event) -> Bool {
        event.state == "Case rename staged" && !events.contains { $0.operation == event.operation && $0.row.id == event.row.id && (["Moved", "Undone", "Recovered original location"].contains($0.state) || ($0.state.hasPrefix("Failed") && $0.detail.contains("restored"))) }
    }
    func canRecover(_ event: FolderEvent) -> Bool {
        event.state == "Case rename staged" && !folderEvents.contains { $0.operation == event.operation && $0.row.id == event.row.id && (["Renamed folder", "Undone folder", "Recovered original folder"].contains($0.state) || ($0.state.hasPrefix("Failed") && $0.detail.contains("restored"))) }
    }
    func recoverStagedFile(_ event: Event) {
        busy = true; let db = support.appendingPathComponent("operations.sqlite")
        Task {
            do { try await Task.detached { try Executor(journal: Journal(url: db)).recoverCaseStage(event) }.value; status = "Original file location recovered. Refresh the workspace." }
            catch { self.error = error.localizedDescription }
            busy = false; loadHistory()
        }
    }
    func recoverStagedFolder(_ event: FolderEvent) {
        busy = true; let db = support.appendingPathComponent("operations.sqlite")
        Task {
            do { try await Task.detached { try FolderExecutor(journal: Journal(url: db)).recoverCaseStage(event) }.value; status = "Original folder location recovered. Refresh the workspace." }
            catch { self.error = error.localizedDescription }
            busy = false; loadHistory()
        }
    }
    func undo(_ e: Event, delete: Bool) {
        busy = true; let db = support.appendingPathComponent("operations.sqlite")
        Task { do { try await Task.detached { try Executor(journal: Journal(url: db)).undo(e, allowDeleteCopy: delete) }.value; status = "Undo completed." } catch { self.error = error.localizedDescription }; busy = false; loadHistory() }
    }
    func openLibraryInFinder() {
        let url = URL(fileURLWithPath: active.root)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if !showFolderInFinder(url) { error = "Could not open the library folder. Reconnect the destination in Profile Settings." }
    }

}
struct BrandImage: View {
    let name: String
    var body: some View {
        if let url = Bundle.main.url(forResource: name, withExtension: "png"), let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit().accessibilityLabel("Shelf Elf Librarian")
        } else { Image(systemName: "folder.badge.gearshape").resizable().scaledToFit() }
    }
}
struct SplashView: View {
    let dismiss: () -> Void
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            VStack(spacing: 16) {
                BrandImage(name: "README-Logo")
                    .frame(width: 570, height: 380)
                    .padding(20).background(Color.white, in: RoundedRectangle(cornerRadius: 24))
                Text(AppIdentity.name + (AppEnvironment.isFreshInstallTest ? " — Fresh Install Test" : "")).font(.title2.bold())
                Text(AppIdentity.version).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                Text("Your libraries, neatly shelved.").foregroundStyle(.secondary)
                Button("Continue", action: dismiss).keyboardShortcut(.defaultAction)
            }.padding(30)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
struct MainView: View {
    @EnvironmentObject var m: Model
    @State private var showSplash = true
    @State private var spellingReview: Set<String> = []
    @State private var hoveredFilenameRow: String?
    @AppStorage("acknowledgedUsageNoticeVersion", store: AppEnvironment.defaults) private var acceptedTermsVersion = ""
    @AppStorage("acknowledgedUsageNoticeAppRelease", store: AppEnvironment.defaults) private var acceptedTermsRelease = ""
    private var currentTermsRelease: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return version + ":" + build
    }
    private var termsAcceptanceRequired: Bool {
        acceptedTermsVersion != LicenseTerms.version || acceptedTermsRelease != currentTermsRelease
    }
    @FocusState private var filterFocused: Bool
    @State private var showTerms = false
    @State private var quitAfterTermsDismissal = false
    private func sortHeader(_ title: String, column: String) -> some View {
        Button { m.sortBy(column) } label: {
            HStack(spacing: 3) {
                Text(title)
                if m.sortColumn == column { Image(systemName: m.reverse ? "arrow.down" : "arrow.up").font(.system(size: 8)) }
            }
        }
    }
    var version: String { AppIdentity.version }
    var body: some View {
        VStack(spacing: 0) {
            WorkspaceLocationBar().environmentObject(m)
            Divider()
            WorkspaceActionBar().environmentObject(m)
            Divider()
            HSplitView {
                VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            Toggle("Include all visible files", isOn: Binding(get: { !m.visible.isEmpty && m.visible.allSatisfy { m.selected.contains($0.id) } }, set: { _ in m.toggleVisibleSelection() }))
                                .labelsHidden().frame(width: 28).instantHelp("Select all visible files, or clear them when all are selected.")
                            sortHeader("Current / proposed filename", column: "name").frame(maxWidth: .infinity, alignment: .leading)
                            sortHeader("Type / size", column: "type").frame(width: 80)
                            sortHeader("Name status", column: "ok").frame(width: 128, alignment: .leading)
                            sortHeader("Filing", column: "confirmation").frame(width: 52)
                        }.buttonStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        Divider()
                ScrollViewReader { filenameScroll in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(m.visible) { item in
                            let proposal = try? proposedFilename(item, profile: m.active)
                            let nameMatches = proposal.map { $0.utf8.elementsEqual(item.url.lastPathComponent.utf8) } ?? false
                            HStack(alignment: .top, spacing: 10) {
                                Toggle("Include", isOn: Binding(get: { m.selected.contains(item.id) }, set: { if $0 { m.selected.insert(item.id) } else { m.selected.remove(item.id) }; m.invalidate() })).labelsHidden().frame(width: 28)
                                FilenameComparisonView(item: item, nameMatches: nameMatches, spellingReviewChanged: { review in if review { spellingReview.insert(item.id) } else { spellingReview.remove(item.id) } }).environmentObject(m)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                VStack(alignment: .center) { Text(item.url.pathExtension.uppercased()); Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)) }.font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 80, alignment: .center).contentShape(Rectangle()).onTapGesture { m.selectRow(item.id) }
                                Text(nameMatches ? (spellingReview.contains(item.id) ? "Spelling review" : "Unchanged") : proposal == nil ? "Needs attention" : "Rename proposed")
                                    .font(.system(size: 13)).foregroundStyle(nameMatches ? (spellingReview.contains(item.id) ? Color.orange : Color.secondary) : proposal == nil ? Color.orange : Color.accentColor)
                                    .frame(width: 128, alignment: .leading).contentShape(Rectangle()).onTapGesture { m.selectRow(item.id) }
                                    .instantHelp(nameMatches ? (spellingReview.contains(item.id) ? "Unrecognized source words need review. Choose a replacement to create a rename proposal." : "Filename already matches—no rename needed.") : "Proposed filename differs from the current filename.")
                                Image(systemName: item.reviewed ? "checkmark.circle.fill" : "circle.dashed")
                                    .foregroundStyle(.secondary).frame(width: 52)
                                    .accessibilityLabel(item.reviewed ? "Components confirmed for filing" : "Components unconfirmed for filing")
                                    .contentShape(Rectangle()).onTapGesture { m.selectRow(item.id) }
                                    .instantHelp(item.reviewed ? "Filename components confirmed for filing. Direct renames are separate. Preview still checks required values and destination conflicts." : "For filing, select this file and confirm its filename components in the right panel. Direct renaming does not confirm components.")
                            }.padding(.horizontal, 14).padding(.vertical, 12).background { (m.selected.contains(item.id) ? Color.accentColor.opacity(0.08) : Color.clear).contentShape(Rectangle()).onTapGesture { m.selectRow(item.id) } }
                                .onHover { inside in if inside { hoveredFilenameRow = item.id } else if hoveredFilenameRow == item.id { hoveredFilenameRow = nil } }
                                .zIndex(hoveredFilenameRow == item.id ? 100 : 0).id(item.id)
                            Divider()
                        }
                    }
                }.overlay {
                    if m.items.isEmpty {
                        VStack(spacing: 14) {
                            BrandImage(name: "In-App-Logo").frame(width: 250, height: 250)
                                .padding(20).background(Color.white, in: RoundedRectangle(cornerRadius: 20))
                            Text(m.workspace == nil ? "Your libraries, neatly shelved. Thanks to this adorable little elf!" : "No eligible files in this workspace.").font(.headline).multilineTextAlignment(.center)
                            Text(m.workspace == nil ? "Choose a library profile, then open a workspace to begin." : "Check this profile’s extensions in Settings, or choose another workspace.")
                                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.padding(24).allowsHitTesting(false)
                    }
                }
                .onChange(of: m.filenameFocusRequest) {
                    if let id = m.filenameFocusID { filenameScroll.scrollTo(id, anchor: .center) }
                }
                }
                }.frame(minWidth: 660, maxWidth: .infinity)
                FieldEditor().frame(minWidth: 280, idealWidth: 340, maxWidth: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
            }
            Divider()
            WorkspaceFilingBar().environmentObject(m)
            Divider()
            Color.clear.frame(height: 52) // Status controls are rendered once, outside the disabled workspace.

        }
        .toolbar {
            UnsharedToolbarItem(placement: .navigation) {
                HStack(spacing: 8) {
                    Link(destination: URL(string: "https://github.com/natsteff/shelf-elf-librarian")!) {
                        BrandImage(name: "Header-Icon").frame(width: 28, height: 28)
                    }.buttonStyle(.plain).accessibilityLabel("Shelf Elf Librarian website")
                        .instantHelp("Open Shelf Elf Librarian on GitHub")
                    Button { m.showSettings = true } label: { Label("Profile Settings", systemImage: "slider.horizontal.3") }
                        .labelStyle(.iconOnly).instantHelp("Profile Settings")
                    WorkspaceProfilePicker().environmentObject(m)
                }.controlSize(.regular).font(.system(size: 13)).disabled(m.busy || showSplash)
            }
            UnsharedToolbarItem(placement: .principal) {
                WorkspaceTitle()
            }
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.flexible, placement: .automatic)
            } else {
                ToolbarItem(placement: .automatic) { Spacer() }
            }
            UnsharedToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    Button { m.showGeneralSettings = true } label: { Label("General Settings", systemImage: "gearshape") }
                        .labelStyle(.iconOnly).instantHelp("General Settings")
                    Button { m.loadHistory(); m.showHistory = true } label: { Label("History", systemImage: "clock") }
                        .labelStyle(.iconOnly).instantHelp("History & Undo")
                }.controlSize(.regular).font(.system(size: 13)).disabled(m.busy || showSplash)
            }
        }
        .background(MainWindowAppearance())
        .disabled(m.busy || showSplash)
        .overlay {
            if showSplash {
                SplashView { withAnimation(.easeOut(duration: 0.2)) { showSplash = false } }
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showTerms, onDismiss: {
            if quitAfterTermsDismissal {
                DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
            }
        }) {
            LicenseTermsView(requiresAcceptance: termsAcceptanceRequired, accept: {
                acceptedTermsVersion = LicenseTerms.version
                acceptedTermsRelease = currentTermsRelease
                AppEnvironment.defaults.set(Date(), forKey: "usageNoticeAcknowledgedAt")
                showTerms = false
            }, close: { showTerms = false }, decline: {
                // AppKit refuses termination while this mandatory sheet is attached.
                // Quit after dismissal, without recording acknowledgment.
                quitAfterTermsDismissal = true
                showTerms = false
            })
        }
        .onReceive(Timer.publish(every: 3600, on: .main, in: .common).autoconnect()) { _ in if !m.busy { m.loadHistory() } }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowLicenseTerms"))) { _ in showTerms = true }
        .onAppear {
            if termsAcceptanceRequired { showTerms = true }
            if let url = Bundle.main.url(forResource: "AppIcon-v3", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
                NSApplication.shared.applicationIconImage = icon
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowShelfElfWelcome"))) { _ in
            guard !m.busy else { return }; showSplash = true
        }
        .task(id: showSplash) {
            guard showSplash else { return }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            withAnimation(.easeOut(duration: 0.2)) { showSplash = false }
        }
        .overlay(alignment: .bottom) { if !showSplash { OperationStatusBar().environmentObject(m) } }
        .sheet(isPresented: $m.showGeneralSettings) { GeneralSettingsView().environmentObject(m) }
        .sheet(isPresented: $m.showSettings) { SettingsView(profile: m.active, existing: m.profiles.contains { $0.id == m.activeID }, save: m.saveProfile, delete: m.deleteProfile).frame(width: 690, height: 740) }
        .sheet(isPresented: $m.showReview, onDismiss: { m.reviewDismissed() }) { ReviewView().environmentObject(m) }
        .sheet(isPresented: $m.showSettingsBackups) { SettingsBackupsView().environmentObject(m) }
        .sheet(isPresented: $m.showQuickFiling) { QuickFilingView().environmentObject(m) }
        .sheet(isPresented: $m.showMP3Tags) { MP3TagReviewView().environmentObject(m) }
        .sheet(isPresented: $m.showHistory) { HistoryView().environmentObject(m) }
        .sheet(isPresented: $m.showFolders) { FolderReviewView().environmentObject(m) }
        .sheet(isPresented: $m.showBatchNames) { BatchNamesView().environmentObject(m) }
        .sheet(isPresented: $m.showExcluded) { VStack(alignment: .leading) { Text("Excluded files").font(.title2); Text("Unsupported extensions and links cannot be applied under this profile."); List(m.excluded, id: \.self) { Text($0).textSelection(.enabled) }; Button("Done") { m.showExcluded = false } }.padding().frame(width: 650, height: 450) }
        .alert(AppIdentity.name, isPresented: Binding(get: { m.error != nil }, set: { if !$0 { m.error = nil } })) { Button("OK") { m.error = nil } } message: { Text(m.error ?? "") }
    }
}
struct OperationStatusBar: View {
    @EnvironmentObject var m: Model
    private var scanning: Bool { m.progress == "Scanning" || m.progress == "Restoring workspace…" || m.progress == "Refreshing workspace…" }
    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                if !m.busy && m.workspace != nil {
                    Text("\(m.items.count.formatted()) eligible • \(m.excluded.count.formatted()) excluded")
                    if m.status != "\(m.items.count.formatted()) eligible • \(m.excluded.count.formatted()) excluded" { Text(m.status).lineLimit(2).foregroundStyle(.secondary) }
                } else { Text(m.status).lineLimit(2) }
            }
            if !m.busy && m.workspace != nil {
                Button("Show excluded filenames") { m.showExcluded = true }.controlSize(.regular).font(.system(size: 13)).fixedSize().disabled(m.excluded.isEmpty)
            }
            Spacer()
            if !m.busy {
                Text(m.visibleSelected.isEmpty && m.selected.isEmpty ? "No selection" : "\(m.visibleSelected.count) selected visible" + (m.selected.count > m.visibleSelected.count ? " · \(m.selected.count - m.visibleSelected.count) hidden, excluded from actions" : ""))
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            if m.busy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(m.progress).lineLimit(1)
                }.frame(maxWidth: 300, alignment: .trailing)
                Button(scanning ? "Cancel Scan" : "Cancel after current file") { m.cancellation.cancel() }
                    .controlSize(.regular).font(.system(size: 13)).fixedSize()
            }
        }.font(.system(size: 13)).padding(.horizontal, 16).frame(height: 52)
            .background(Color(nsColor: .windowBackgroundColor))
            .onChange(of: m.busy) { if m.busy { HoverHelp.shared.hide() } }
    }
}
struct FieldEditor: View {
    @EnvironmentObject var m: Model
    func value(_ key: KeyPath<Fields, String>) -> String { let values = Set(m.visibleSelected.map { $0.fields[keyPath: key] }); return values.count == 1 ? values.first! : "" }
    func field(_ label: String, _ key: WritableKeyPath<Fields, String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            TextField(label, text: Binding(get: { value(key) }, set: { v in m.updateFields { $0[keyPath: key] = key == \Fields.resolution ? FieldCatalog.normalizedResolution(v) : v } }), prompt: Text(Set(m.visibleSelected.map { $0.fields[keyPath: key] }).count > 1 ? "Mixed values — type to replace" : label))
                .accessibilityLabel(label)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var includesEpisodes: Bool { m.visibleSelected.contains { !$0.fields.season.isEmpty || !$0.fields.episode.isEmpty || $0.fields.type.localizedCaseInsensitiveContains("TV") } }
    private var includesMovies: Bool { m.visibleSelected.contains { $0.fields.season.isEmpty && $0.fields.episode.isEmpty && !$0.fields.type.localizedCaseInsensitiveContains("TV") } }
    private var episodeFields: some View {
        Group {
            field(m.active.kind == .audiobook ? "Series name (optional)" : "Series", \.series)
            HStack(alignment: .top, spacing: 10) { field("Season", \.season); field("Episode", \.episode) }
            field("Episode title", \.episodeTitle)
        }
    }
    var body: some View {
        Group {
            if m.visibleSelected.isEmpty {
                ContentUnavailableView("Select a file to review", systemImage: "cursorarrow.click", description: Text("Click a filename to view its components. Use checkboxes to edit several files together."))
                    .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { editor }
        }
    }
    private var editor: some View {
        ScrollView { VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Filename Components").font(.headline)
                Spacer()
                if m.visibleSelected.count > 1 { Text("\(m.visibleSelected.count) selected").font(.system(size: 12)).foregroundStyle(.secondary) }
            }
            if let item = m.visibleSelected.first {
                Text((m.visibleSelected.count > 1 ? "Interpretation shown for: " : "Current filename: ") + item.url.lastPathComponent)
                    .font(.system(size: 12, weight: .medium)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            if let item = m.visibleSelected.first { EmbeddedMetadataButton(item: item, showLabel: true) }
            Text("Edits update proposed names. Rename Selected or the row checkmark applies them in the current folders.").font(.caption).foregroundStyle(.secondary)
            ClassificationField().environmentObject(m)
            MediaCategoryField().environmentObject(m)
            if let item = m.visibleSelected.first {
                DisclosureGroup("Interpretation & evidence") { Text(item.evidence).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled) }.font(.system(size: 12))
                if !item.alternatives.isEmpty {
                    Text(item.confidence).font(.caption.bold())
                    Menu("Choose interpretation") { ForEach(item.alternatives) { choice in Button(choice.label + " — " + choice.confidence) { m.chooseAlternative(item.id, choice: choice) } } }
                }
            }
            if m.active.kind == .video {
                if includesMovies { field("Title", \.title); field("Year", \.year) }
                if includesEpisodes { episodeFields }
                if !includesEpisodes { DisclosureGroup("TV episode components") { episodeFields }.font(.system(size: 12)) }
                if !includesMovies { DisclosureGroup("Movie components") { field("Title", \.title); field("Year", \.year) }.font(.system(size: 12)) }
            } else if m.active.kind == .documents || m.active.kind == .roms || m.active.kind == .photos || m.active.kind == .software || m.active.kind == .other {
                field(m.active.kind == .other ? "Filename (without extension)" : "Title", \.title)
            }
            ForEach(Array(Set(PatternEngine.customComponents(m.active) + m.visibleSelected.flatMap { $0.fields.custom?.keys.map { $0 } ?? [] })).sorted(), id: \.self) { key in
                VStack(alignment: .leading, spacing: 4) {
                    Text(key).font(.caption.bold()).foregroundStyle(.secondary)
                    TextField(key, text: Binding(get: {
                        let values = Set(m.visibleSelected.map { FieldCatalog.get(key, $0.fields) }); return values.count == 1 ? values.first! : ""
                    }, set: { value in m.updateFields { FieldCatalog.set(key, value, &$0) } }))
                }
            }
            if m.active.kind == .video { field("Resolution (optional)", \.resolution) }
            if m.active.kind == .documents { field("Date", \.date); field("Revision", \.revision) }
            if m.active.kind == .documents && ((m.active.workspacePatterns ?? []).contains { $0.pattern.contains("{Game}") } || m.visibleSelected.contains { !$0.fields.game.isEmpty }) { field("Game", \.game) }
            if m.active.kind == .roms { field("Region", \.region); field("Edition", \.edition); field("Revision", \.revision) }
            if m.active.kind == .photos { field("Date taken", \.dateTaken); field("Event", \.event) }
            if m.active.kind == .software { field("Product", \.product); field("Version", \.version); field("Platform", \.platform); field("Architecture", \.architecture) }
            if m.active.kind == .music {
                field("Artist", \.artist); field("Title", \.title); field("Album (optional)", \.album)
                field("Release year (optional)", \.year); field("Track number (optional)", \.trackNumber)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recording type (optional)").font(.caption.bold()).foregroundStyle(.secondary)
                    Picker("Recording type", selection: Binding(get: { value(\.recordingType) }, set: { recording in m.updateFields { $0.recordingType = recording } })) {
                        ForEach(RecordingKind.allCases) { Text($0.label).tag($0.rawValue) }
                    }.labelsHidden()
                }
                Text("Unspecified does not imply Studio. {Live} adds (Live) only for Live; {RecordingType} outputs Live or Studio when specified. No embedded tags are read.").font(.caption).foregroundStyle(.secondary)
            }
            if m.active.kind == .audiobook {
                field("Author — shared group", \.author); field("Title — shared group", \.bookTitle)
                field("Series name (optional)", \.series); field("Series number (optional)", \.seriesNumber)
                field("Publisher (optional)", \.publisher); field("Published year (optional)", \.year)
                if m.active.effectiveBookSubtype == .audiobook || m.active.effectiveBookSubtype == .general {
                    field("Narrator (optional)", \.narrator)
                    if m.visibleSelected.count == 1 { field("Chapter number (optional)", \.chapterNumber); field("Chapter title (optional)", \.chapterTitle) }
                }
                if m.active.effectiveBookSubtype == .comic || m.active.effectiveBookSubtype == .general {
                    field("Artist / illustrator (optional)", \.illustrator); field("Issue number (optional)", \.issueNumber); field("Volume (optional)", \.volume)
                }
                Text("Only components referenced in output masks are required. {Title} and {BookTitle} both use the book title. Extra details come from extraction masks or your edits, not embedded metadata.").font(.caption).foregroundStyle(.secondary)
            }
            Divider().padding(.vertical, 4)
            Label(m.visibleSelected.allSatisfy(\.reviewed) ? "Components confirmed for filing" : "Components unconfirmed for filing", systemImage: m.visibleSelected.allSatisfy(\.reviewed) ? "checkmark.circle" : "circle.dashed")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Button("Confirm Filename Components", systemImage: "checkmark.circle") { m.confirmFields() }.disabled(m.visibleSelected.isEmpty)
            Button("Edit Selected Names…") { m.showBatchNames = true }.disabled(m.visibleSelected.isEmpty)
            Toggle("Remember confirmed corrections for Magic", isOn: Binding(get: { !m.visibleSelected.isEmpty && m.visibleSelected.allSatisfy(\.rememberCorrection) }, set: { m.rememberSelected($0) })).disabled(m.visibleSelected.isEmpty)
            DisclosureGroup("How edits and filing work") {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Row rename buttons and Return in the name editor rename files immediately in the workspace. Component confirmation here is separate and is used for filing. Successful direct renames are deselected.")
                    Text("Filename components come from filenames; Magic may also use folder names and remembered corrections. MP3 tags are read-only reference information. Video metadata can fill missing components used by masks. Tags change only through explicit MP3 Tools actions or enabled, confirmed Magic steps.")
                    Text("Only successful, user-approved operations supply learning examples. Remembering allows Magic to reuse them in this profile; it never changes rules automatically.")
                    Text("Edits apply to selected visible files. Mixed filename components stay unchanged unless you type a replacement. Shared author/book filename components define an audiobook group.")
                }.font(.system(size: 12)).foregroundStyle(.secondary)
            }.font(.system(size: 12))
        }.textFieldStyle(.roundedBorder).controlSize(.regular).padding(16) }
    }
}
struct SettingsView: View {
    @EnvironmentObject var m: Model
    @State private var showGeneral = false
    @State private var showRecommendations = false
    @State private var showMaskGuide = false
    @State private var showPatterns = false
    @Environment(\.dismiss) var dismiss
    @State var draft: Profile
    let save: (Profile) throws -> Void
    let delete: (UUID) throws -> Void
    let savedProfileID: UUID?
    let savedProfileName: String
    @State var confirmDelete = false
    @State var validation = ""
    @State private var validationScrollRequest = 0
    init(profile: Profile, existing: Bool, save: @escaping (Profile) throws -> Void, delete: @escaping (UUID) throws -> Void) {
        _draft = State(initialValue: profile); self.save = save; self.delete = delete
        savedProfileID = existing ? profile.id : nil; savedProfileName = profile.name
    }
    var body: some View {
        ScrollViewReader { scroll in
        VStack(alignment: .leading) {
            Text("Profile Settings: " + (draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Profile" : draft.name)).font(.title2.bold()).lineLimit(2)
            Form {
                ProfileSettingsContent(profile: $draft, validation: $validation,
                    patterns: { showPatterns = true }, guide: { showMaskGuide = true },
                    general: { showGeneral = true }, recommendations: { showRecommendations = true })
                if !validation.isEmpty { Text(validation).foregroundStyle(.red).id("profileValidation")
                    .background(ValidationScrollAnchor(request: validationScrollRequest)) }
            }.formStyle(.grouped).textFieldStyle(.roundedBorder)
            Divider().padding(.top, 8).padding(.bottom, 10)
            VStack(alignment: .leading, spacing: 12) {
            if let id = savedProfileID, draft.id == id {
                HStack {
                    Button("Delete this profile", role: .destructive) { confirmDelete = true }
                    Text("Removes settings only. Library files stay untouched.").font(.caption).foregroundStyle(.secondary)
                }.padding(.bottom, 6)
            }
            HStack { Button("Duplicate as New Profile") { draft.id = UUID(); draft.name += " Copy" }; Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Save") { do { draft.rootAllowed = true; draft.exceptions = ""; draft = ProfileSetup.addingMissingVideoTypes(draft); try draft.validate(); try save(draft); dismiss() } catch { validation = "Profile not saved. " + error.localizedDescription; validationScrollRequest += 1; DispatchQueue.main.async { withAnimation { scroll.scrollTo("profileValidation", anchor: .bottom) } } } }.keyboardShortcut(.defaultAction) }
            }.padding(.top, 2).padding(.bottom, 4)
        }.padding()
        }
        .sheet(isPresented: $showGeneral) { GeneralSettingsView().environmentObject(m) }
        .sheet(isPresented: $showRecommendations) { RecommendationsView(profile: $draft).environmentObject(m) }
        .sheet(isPresented: $showMaskGuide) { MaskGuideView() }
        .sheet(isPresented: $showPatterns) { PatternSettingsView(profile: $draft).environmentObject(m) }
        .alert("Delete “\(savedProfileName)” profile?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Profile", role: .destructive) {
                guard let id = savedProfileID else { return }
                do { try delete(id); dismiss() } catch { validation = error.localizedDescription }
            }
        } message: {
            Text("This removes the saved profile and its rules. Workspace files, library folders, and operation history remain untouched. Unsaved edits will be discarded.")
        }
    }
}
struct ReviewView: View {
    @EnvironmentObject var m: Model
    @State var included: Set<UUID> = []
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let transfer = m.transferPlan {
                TransferProgressView(plan: transfer)
            } else if let plan = m.plan {
                Text("Review \(plan.mode == .clean ? "Rename" : plan.mode.rawValue.capitalized) Operation").font(.title2.bold())
                Text("\(plan.profile.name) • \(plan.mode == .clean ? "Workspace folders" : plan.profile.root) • file contents remain unchanged").foregroundStyle(.secondary).textSelection(.enabled)
                GroupedPlanRows(plan: plan, included: $included)
                Text("Cancellation stops between files. Completed files remain completed. A group may be partially completed; inspect History for recovery.").font(.caption)
                HStack { Button("Back") { m.showReview = false }; if plan.mode != .clean { Button("Skip Individual Review & \(plan.mode == .copy ? "Copy" : "Move") All…") { m.skipReviewAndFile() } }; Spacer(); Button("\(plan.mode == .clean ? "Rename" : plan.mode.rawValue.capitalized) \(included.count) files") { var p = plan; p.rows = plan.rows.filter { included.contains($0.id) }; m.plan = p; m.apply() }.buttonStyle(.borderedProminent).disabled(included.isEmpty) }
            }
        }.padding(20).frame(width: 930, height: 700)
        .interactiveDismissDisabled(m.transferPlan != nil)
        .onAppear { included = Set(m.plan?.rows.filter(\.actionable).map(\.id) ?? []) }
    }
}
struct HistoryView: View {
    @EnvironmentObject var m: Model
    @State var confirm: Event?
    var body: some View {
        VStack(alignment: .leading) {
            Text("Operation History & Recovery").font(.title2.bold())
            Text("History and its Undo actions expire after 30 days. Remembered Magic corrections are retained separately. Source, destination and temporary files are never deleted by history cleanup. Interrupted operations are never resumed or deleted automatically. Inspect the recorded source, destination, and temporary paths. Re-preview retained source files. Cross-volume move undo requires a new reviewed operation.").font(.callout)
            if !m.folderEvents.isEmpty {
                DisclosureGroup("Folder rename history (\(m.folderEvents.count) transitions)") {
                    ScrollView { VStack(alignment: .leading) { ForEach(m.folderEvents) { e in
                        VStack(alignment: .leading) {
                            HStack { Text(e.state).bold(); Spacer(); if e.state == "Renamed folder" { Button("Guarded Undo Folder") { m.undoFolder(e) }.disabled(m.busy) }; if m.canRecover(e) { Button("Recover Original Folder") { m.recoverStagedFolder(e) }.disabled(m.busy) } }
                            Text(e.row.source + "\n→ " + e.row.destination).font(.caption).textSelection(.enabled)
                            if let path = e.temporary { Text("Recovery path: " + path).font(.caption).textSelection(.enabled) }
                            if !e.detail.isEmpty { Text(e.detail).font(.caption) }
                        }; Divider()
                    } } }.frame(maxHeight: 180)
                }
            }
            List(m.events) { e in VStack(alignment: .leading, spacing: 5) {
                HStack { Text(e.state).bold(); Text(e.date.formatted()).foregroundStyle(.secondary); Spacer(); if ["Copied", "Moved"].contains(e.state) && !e.hasMagicTagChanges { Button("Guarded Undo…") { confirm = e }.disabled(m.busy) }; if m.canRecover(e) { Button("Recover Original File") { m.recoverStagedFile(e) }.disabled(m.busy) } }
                Text(e.row.source + "\n→ " + e.row.destination).font(.caption).textSelection(.enabled)
                if !e.detail.isEmpty { Text(e.detail).font(.caption) }
                if let t = e.temporary { Text("Recovery path: " + t).font(.caption).textSelection(.enabled) }
            }.padding(.vertical, 6) }
            HStack { Button("Reveal Journal") { NSWorkspace.shared.activateFileViewerSelecting([m.support.appendingPathComponent("operations.sqlite")]) }; Spacer(); Button("Done") { m.showHistory = false } }
        }.padding().frame(width: 950, height: 650)
        .alert("Confirm guarded undo", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) { Button("Cancel", role: .cancel) { confirm = nil }; Button(confirm?.state == "Copied" ? "Delete Verified Copy" : "Restore Original Location", role: .destructive) { if let e = confirm { m.undo(e, delete: e.state == "Copied") }; confirm = nil } } message: { Text("Undo verifies the recorded destination identity and content. Changed files or occupied original locations are refused. Deleting a copied file is permanent.") }
    }
}

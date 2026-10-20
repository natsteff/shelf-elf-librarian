import SwiftUI
import AppKit
import FilerCore

enum AppIdentity {
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Shelf Elf Librarian"
    static var version: String { "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0") Alpha (Build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))" }
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
            .commands {
                CommandGroup(replacing: .appInfo) {
                    Button("About \(AppIdentity.name)") {
                        var options: [NSApplication.AboutPanelOptionKey: Any] = [:]
                        if let url = Bundle.main.url(forResource: "AppIcon-v3", withExtension: "icns"), let icon = NSImage(contentsOf: url) { options[.applicationIcon] = icon }
                        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
                    }
                }
                CommandGroup(after: .appInfo) {
                    Button("Show Welcome Screen") { NotificationCenter.default.post(name: Notification.Name("ShowShelfElfWelcome"), object: nil) }
                }
            }
        Settings { SettingsView(profile: model.active, existing: model.profiles.contains { $0.id == model.activeID }, save: model.saveProfile, delete: model.deleteProfile).frame(width: 660, height: 700) }
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
    @Published var excluded: [String] = []
    @Published var category = ""
    @Published var availableCategories: [String] = []
    @Published var categoryConfirmed = false
    @Published var mode: Mode = .copy
    @Published var fileOnly = false
    @Published var busy = false
    @Published var status = "Choose a profile and open a workspace, or load the fictional demo."
    @Published var progress = ""
    @Published var plan: Plan?
    @Published var showReview = false
    @Published var showHistory = false
    @Published var showSettings = false
    @Published var showExcluded = false
    @Published var events: [Event] = []
    @Published var error: String?
    let support: URL
    var cancellation = Cancellation()
    var scopeURLs: [URL] = []
    let newProfile = Profile(.video)
    var active: Profile { profiles.first { $0.id == activeID } ?? newProfile }
    var visible: [Item] { let a = items.filter { filter.isEmpty || $0.url.lastPathComponent.localizedCaseInsensitiveContains(filter) }; return reverse ? Array(a.reversed()) : a }
    var visibleSelected: [Item] { visible.filter { selected.contains($0.id) } }
    init() {
        support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("com.local.LibraryFiler.Alpha")
        do {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            if let data = try? Data(contentsOf: support.appendingPathComponent("profiles.json")) { profiles = try JSONDecoder().decode([Profile].self, from: data) }
            else { profiles = Kind.allCases.map(Profile.init) }
            activeID = UUID(uuidString: UserDefaults.standard.string(forKey: "lastProfile") ?? "") ?? profiles.first?.id ?? newProfile.id
            if !profiles.contains(where: { $0.id == activeID }) { activeID = profiles.first?.id ?? newProfile.id }
            for p in profiles { if let bookmark = p.bookmark { var stale = false; let u = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], bookmarkDataIsStale: &stale); if stale { status = "Reconnect a saved destination in Settings." }; if u.startAccessingSecurityScopedResource() { scopeURLs.append(u) } } }
            loadHistory()
            loadCategories()
            restoreWorkspace()
        } catch { self.error = error.localizedDescription }
    }
    func invalidate() { plan = nil; categoryConfirmed = false }
    func changeProfile() { selected = []; items = []; invalidate(); UserDefaults.standard.set(activeID.uuidString, forKey: "lastProfile"); loadCategories(); if profiles.isEmpty { excluded = []; status = "No library profiles. Open Settings to create one." } else if workspace != nil { refresh() } }
    func loadCategories() { availableCategories = (try? categories(active.root)) ?? []; category = active.fixedCategory }
    func saveProfile(_ p: Profile) {
        do { try p.validate(); var next = profiles; if let i = next.firstIndex(where: { $0.id == p.id }) { next[i] = p } else { next.append(p) }; try JSONEncoder().encode(next).write(to: support.appendingPathComponent("profiles.json"), options: .atomic); profiles = next; activeID = p.id; changeProfile(); showSettings = false }
        catch { self.error = error.localizedDescription }
    }
    func deleteProfile(_ id: UUID) throws {
        guard !busy else { throw fail("Wait for the current operation to finish before deleting a profile.") }
        guard profiles.contains(where: { $0.id == id }) else { throw fail("This profile is no longer saved.") }
        let next = profiles.filter { $0.id != id }
        // Persist first: a failed write must leave the current profile and preview intact.
        try JSONEncoder().encode(next).write(to: support.appendingPathComponent("profiles.json"), options: .atomic)
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
        UserDefaults.standard.set(try JSONEncoder().encode(session), forKey: "workspaceSession")
        UserDefaults.standard.set(url.path, forKey: "recentWorkspace")
        UserDefaults.standard.set(activeID.uuidString, forKey: "lastProfile")
    }
    func restoreWorkspace() {
        let defaults = UserDefaults.standard
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
        if panel.runModal() == .OK, let url = panel.url {
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
        busy = true; status = "Discovering eligible files…"; progress = "Scanning"; invalidate()
        Task { do { let r = try await Task.detached { try scan(root, profile: p, recursive: recurse, cancel: token) }.value; items = r.items; excluded = r.excluded; selected = []; status = "\(items.count.formatted()) eligible • \(excluded.count.formatted()) excluded" } catch { self.error = error.localizedDescription }; busy = false; progress = "" }
    }
    func updateFields(_ edit: (inout Fields) -> Void) { for i in items.indices where selected.contains(items[i].id) && visible.contains(where: { $0.id == items[i].id }) { edit(&items[i].fields); items[i].reviewed = false }; invalidate() }
    func confirmFields() { for i in items.indices where visibleSelected.contains(where: { $0.id == items[i].id }) { items[i].reviewed = true }; invalidate() }
    func preview(_ clean: Bool) {
        let p = active, chosen = visibleSelected, operation: Mode = clean ? .clean : mode, cat = category, only = fileOnly
        guard clean || categoryConfirmed else { error = "Confirm the destination category for this operation."; return }
        guard !chosen.isEmpty else { error = "Select eligible visible files first."; return }
        busy = true; progress = "Hashing preview sources…"
        Task { do { plan = try await Task.detached { try makePlan(items: chosen, profile: p, mode: operation, category: cat, fileOnly: clean ? false : only) }.value; showReview = true } catch { self.error = error.localizedDescription }; busy = false; progress = "" }
    }
    func apply() {
        guard let p = plan else { return }; busy = true; showReview = false; cancellation = Cancellation(); let token = cancellation; let db = support.appendingPathComponent("operations.sqlite")
        Task { do {
            let r = try await Task.detached { let j = try Journal(url: db); return try Executor(journal: j).execute(p, cancel: token) { done, total in Task { @MainActor in self.progress = "\(done.formatted()) / \(total.formatted()) files" } } }.value
            status = "\(r.completed) completed • \(r.failed) failed. \(token.cancelled ? "Cancelled; completed items remain completed." : "")"
            if !r.details.isEmpty { error = r.details.joined(separator: "\n\n") }
        } catch { self.error = error.localizedDescription }; busy = false; progress = ""; plan = nil; categoryConfirmed = false; loadHistory() }
    }
    func loadHistory() { do { events = try Journal(url: support.appendingPathComponent("operations.sqlite")).events() } catch { self.error = error.localizedDescription } }
    func undo(_ e: Event, delete: Bool) {
        busy = true; let db = support.appendingPathComponent("operations.sqlite")
        Task { do { try await Task.detached { try Executor(journal: Journal(url: db)).undo(e, allowDeleteCopy: delete) }.value; status = "Undo completed." } catch { self.error = error.localizedDescription }; busy = false; loadHistory() }
    }
    func demo() {
        do {
            let demo = support.appendingPathComponent("Demo-\(UUID().uuidString.prefix(8))")
            let src = demo.appendingPathComponent("Workspace"); try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
            let files = ["The.Example.Film.2024.1080p.WEB-DL.mkv", "Another_Film.mp4", "northbound_-_midnight_lines.mp3", "Mira Vale - The Glass Harbor.m4b", "01 - Arrival.mp3", "02 - The Letter.mp3", "03 - Harbor Lights.mp3", "project_report__2025_FINAL.pdf", "unrelated.txt"]
            for name in files { try Data("FICTIONAL FILING FIXTURE — NOT PLAYABLE MEDIA\n\(name)\n".utf8).write(to: src.appendingPathComponent(name), options: .withoutOverwriting) }
            var next: [Profile] = []
            for kind in Kind.allCases.filter({ $0 != .other }) { var p = Profile(kind); let root = demo.appendingPathComponent("\(kind.rawValue)-Library"); let category = root.appendingPathComponent(kind == .video ? "Drama" : kind == .audiobook ? "Fiction" : kind == .documents ? "Reports" : "Music"); try FileManager.default.createDirectory(at: category, withIntermediateDirectories: true); p.root = root.path; let d = try Directory(root.path); p.rootIdentity = DirectoryIdentity(device: d.device, inode: d.inode); next.append(p) }
            profiles += next; try JSONEncoder().encode(profiles).write(to: support.appendingPathComponent("profiles.json"), options: .atomic)
            activeID = next[0].id; try rememberWorkspace(src); workspace = src; changeProfile()
        } catch { self.error = error.localizedDescription }
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
                Text(AppIdentity.name).font(.title2.bold())
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
    var version: String { AppIdentity.version }
    var body: some View {
        VStack(spacing: 0) {
            HStack { BrandImage(name: "Header-Icon").frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 10)); VStack(alignment: .leading) { Text(AppIdentity.name).font(.title2.bold()); Text(version).font(.caption).foregroundStyle(.secondary) }; Spacer(); Picker("Library profile", selection: $m.activeID) { if m.profiles.isEmpty { Text("No profiles — open Settings").tag(m.activeID) }; ForEach(m.profiles) { Text($0.name).tag($0.id) } }.frame(width: 300).onChange(of: m.activeID) { m.changeProfile() }; Button("Settings", systemImage: "gearshape") { m.showSettings = true }; Button("History", systemImage: "clock") { m.loadHistory(); m.showHistory = true } }.padding()
            Divider()
            HStack { Button("Open Workspace…", systemImage: "folder") { m.openWorkspace() }; Button("Refresh", systemImage: "arrow.clockwise") { m.refresh() }.disabled(m.workspace == nil); Toggle("Include subfolders", isOn: $m.recursive).onChange(of: m.recursive) { m.refresh() }; Spacer(); Button("Load Fictional Demo") { m.demo() } }.padding(.horizontal).padding(.vertical, 10)
            VStack(alignment: .leading, spacing: 8) {
                Text(m.workspace?.path ?? "No workspace open").font(.callout).textSelection(.enabled).lineLimit(2)
                HStack { TextField("Filter filenames", text: $m.filter).textFieldStyle(.roundedBorder).frame(maxWidth: 350).onChange(of: m.filter) { m.invalidate() }; Button("Select All Visible") { m.selected = Set(m.visible.map(\.id)); m.invalidate() }; Button("Select None") { m.selected = []; m.invalidate() }; Button(m.reverse ? "Name ↓" : "Name ↑") { m.reverse.toggle() }; Spacer(); Button("\(m.excluded.count) excluded") { m.showExcluded = true } }
            }.padding(.horizontal).padding(.bottom, 10)
            HSplitView {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        HStack { Text("Include").frame(width: 55); Text("Current filename / proposed filename").frame(maxWidth: .infinity, alignment: .leading); Text("Type / Size").frame(width: 100); Text("Status").frame(width: 130, alignment: .leading) }.font(.caption.bold()).foregroundStyle(.secondary).padding(10)
                        Divider()
                        ForEach(m.visible) { item in
                            HStack(alignment: .top) {
                                Toggle("Include", isOn: Binding(get: { m.selected.contains(item.id) }, set: { if $0 { m.selected.insert(item.id) } else { m.selected.remove(item.id) }; m.invalidate() })).labelsHidden().frame(width: 55)
                                VStack(alignment: .leading, spacing: 4) { Text(item.url.lastPathComponent).textSelection(.enabled); Text((try? Names.render(m.active.filenameMask, fields: item.fields, profile: m.active, source: item.url, folder: false)).map { $0 + "." + item.url.pathExtension } ?? "Missing required value").foregroundStyle(.secondary).font(.caption) }.frame(maxWidth: .infinity, alignment: .leading)
                                VStack(alignment: .leading) { Text(item.url.pathExtension.uppercased()); Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)) }.font(.caption).frame(width: 100, alignment: .leading)
                                Label(item.reviewed ? "Reviewed" : "Needs review", systemImage: item.reviewed ? "checkmark.circle" : "pencil.circle").font(.caption).foregroundStyle(item.reviewed ? .green : .orange).frame(width: 130, alignment: .leading)
                            }.padding(10).background(m.selected.contains(item.id) ? Color.accentColor.opacity(0.08) : Color.clear)
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
                }.frame(minWidth: 600)
                FieldEditor().frame(minWidth: 300, idealWidth: 330, maxWidth: 400)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Destination library: \(m.active.root.isEmpty ? "Choose a root in Settings" : m.active.root)").font(.caption).textSelection(.enabled).lineLimit(2)
                HStack {
                    Picker("Category", selection: $m.category) { Text("Choose category…").tag(""); ForEach(m.availableCategories, id: \.self) { Text($0).tag($0) } }.frame(width: 230).onChange(of: m.category) { m.invalidate() }
                    TextField("Or new category", text: $m.category).frame(width: 160).onChange(of: m.category) { m.invalidate() }
                    Toggle(m.category.isEmpty ? "Confirm library root" : "Confirm category", isOn: $m.categoryConfirmed)
                    Spacer()
                    Picker("Operation", selection: $m.mode) { Text("Copy to Library").tag(Mode.copy); Text("Move to Library").tag(Mode.move) }.frame(width: 225).onChange(of: m.mode) { m.invalidate() }
                    Toggle("File only", isOn: $m.fileOnly).onChange(of: m.fileOnly) { m.invalidate() }
                }
                HStack { Text("One category per operation • \(m.visibleSelected.count) selected visible • \(m.selected.count - m.visibleSelected.count) hidden selections excluded").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Clean Preview") { m.preview(true) }; Button("File Preview…") { m.preview(false) }.buttonStyle(.borderedProminent) }
            }.padding()
            Divider()
            HStack { Text(m.status).lineLimit(2); Spacer(); if m.busy { ProgressView().controlSize(.small); Text(m.progress); Button("Cancel after current file") { m.cancellation.cancel() } } }.font(.caption).padding(.horizontal).frame(height: 48)
        }
        .disabled(m.busy || showSplash)
        .overlay {
            if showSplash {
                SplashView { withAnimation(.easeOut(duration: 0.2)) { showSplash = false } }
                    .transition(.opacity)
            }
        }
        .onAppear {
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
        .overlay(alignment: .bottomTrailing) { if m.busy { Button("Cancel after current file") { m.cancellation.cancel() }.padding(10) } }
        .sheet(isPresented: $m.showSettings) { SettingsView(profile: m.active, existing: m.profiles.contains { $0.id == m.activeID }, save: m.saveProfile, delete: m.deleteProfile).frame(width: 690, height: 740) }
        .sheet(isPresented: $m.showReview) { ReviewView().environmentObject(m) }
        .sheet(isPresented: $m.showHistory) { HistoryView().environmentObject(m) }
        .sheet(isPresented: $m.showExcluded) { VStack(alignment: .leading) { Text("Excluded files").font(.title2); Text("Unsupported extensions and links cannot be applied under this profile."); List(m.excluded, id: \.self) { Text($0).textSelection(.enabled) }; Button("Done") { m.showExcluded = false } }.padding().frame(width: 650, height: 450) }
        .alert(AppIdentity.name, isPresented: Binding(get: { m.error != nil }, set: { if !$0 { m.error = nil } })) { Button("OK") { m.error = nil } } message: { Text(m.error ?? "") }
    }
}
struct FieldEditor: View {
    @EnvironmentObject var m: Model
    func value(_ key: KeyPath<Fields, String>) -> String { let values = Set(m.visibleSelected.map { $0.fields[keyPath: key] }); return values.count == 1 ? values.first! : "" }
    func field(_ label: String, _ key: WritableKeyPath<Fields, String>) -> some View {
        TextField(label, text: Binding(get: { value(key) }, set: { v in m.updateFields { $0[keyPath: key] = v } }), prompt: Text(Set(m.visibleSelected.map { $0.fields[keyPath: key] }).count > 1 ? "Mixed values — type to replace" : label))
    }
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 12) {
            Text("Selection & Group").font(.headline)
            Text("\(m.visibleSelected.count) visible files selected").foregroundStyle(.secondary)
            if let item = m.visibleSelected.first { Text(item.evidence).font(.caption).foregroundStyle(.secondary) }
            if m.active.kind == .video || m.active.kind == .documents || m.active.kind == .other { field(m.active.kind == .other ? "Filename (without extension)" : "Title", \.title); if m.active.kind == .video { field("Year", \.year) } }
            if m.active.kind == .music { field("Artist", \.artist); field("Title", \.title); field("Album (optional)", \.album) }
            if m.active.kind == .audiobook { field("Author — shared group", \.author); field("Book title — shared group", \.bookTitle); if m.visibleSelected.count == 1 { field("Chapter number", \.chapterNumber); field("Chapter title", \.chapterTitle) }; Text("Select chapters together and enter Author and Book title once. Original chapter names and numbering are retained.").font(.caption) }
            Button("Confirm Reviewed Fields", systemImage: "checkmark.circle") { m.confirmFields() }.disabled(m.visibleSelected.isEmpty)
            Text("Edits apply to selected visible files. Mixed fields stay unchanged unless you type a replacement. Shared author/book fields define an audiobook group.").font(.caption).foregroundStyle(.secondary)
        }.textFieldStyle(.roundedBorder).padding() }
    }
}
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @State var draft: Profile
    let save: (Profile) -> Void
    let delete: (UUID) throws -> Void
    let savedProfileID: UUID?
    let savedProfileName: String
    @State var confirmDelete = false
    @State var validation = ""
    init(profile: Profile, existing: Bool, save: @escaping (Profile) -> Void, delete: @escaping (UUID) throws -> Void) {
        _draft = State(initialValue: profile); self.save = save; self.delete = delete
        savedProfileID = existing ? profile.id : nil; savedProfileName = profile.name
    }
    var body: some View {
        VStack(alignment: .leading) {
            Text("Profile Settings").font(.title2.bold())
            ScrollView { Form {
                TextField("Profile name", text: $draft.name)
                Picker("Template", selection: $draft.kind) { ForEach(Kind.allCases) { Text($0 == .other ? "Other / Custom" : $0.rawValue.capitalized).tag($0) } }
                Button("Reset rules to selected template") { var p = Profile(draft.kind); p.id = draft.id; p.name = draft.name; p.root = draft.root; p.rootIdentity = draft.rootIdentity; p.bookmark = draft.bookmark; draft = p }
                if draft.kind == .other {
                    Text("For ROMs or other files: click Reset rules to selected template to start with unchanged filenames and no parsing. Then enter your extensions and filing rules. Changing the picker alone keeps existing rules.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                TextField("Extensions (comma separated)", text: $draft.extensions)
                if draft.kind == .other { Text("Examples: nes, sfc, smc, gba, gb, gbc, n64, nds, chd, iso, zip, 7z. Only the extensions you enter will appear in the workspace.").font(.caption).foregroundStyle(.secondary) }
                LabeledContent("Destination root") { Text(draft.root.isEmpty ? "Not configured" : draft.root).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                Button("Choose Destination Root…") { let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; if panel.runModal() == .OK, let u = panel.url { do { let d = try Directory(u.path); draft.rootIdentity = DirectoryIdentity(device: d.device, inode: d.inode); draft.root = u.path; draft.bookmark = try u.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) } catch { validation = error.localizedDescription } } }
                Toggle("Allow filing directly in root (still requires confirmation)", isOn: $draft.rootAllowed)
                TextField("Fixed category (blank = ask each time)", text: $draft.fixedCategory)
                Section("Filename cleaning") {
                    Toggle("Replace underscores", isOn: $draft.replaceUnderscores)
                    Toggle("Treat separator dots as spaces", isOn: $draft.replaceDots)
                    Toggle("Title case", isOn: $draft.titleCase)
                    Toggle("Normalize repeated spaces and trim whitespace", isOn: Binding(get: { draft.normalizeSpaces ?? true }, set: { draft.normalizeSpaces = $0 }))
                    TextField("Removable labels (comma separated)", text: $draft.removeTokens)
                    TextField("Spelling exceptions (comma separated)", text: $draft.exceptions)
                    TextField("Prefix", text: $draft.prefix); TextField("Suffix", text: $draft.suffix)
                }
                Section("Interpretation & output masks") {
                    TextField("Extraction mask (optional)", text: $draft.extractionMask)
                    Text(draft.kind == .other ? "Leave extraction blank for no parsing. {Title} uses the filename without its extension, after any enabled cleanup." : "Example: {Artist} - {Title}. Filename evidence only; confirm matches in the editor.").font(.caption)
                    TextField("Folder mask", text: $draft.folderMask)
                    TextField("Filename mask (without extension)", text: $draft.filenameMask)
                    Text("Fields: Title, Year, TitleYear, Artist, Album, Author, BookTitle, ChapterNumber, ChapterNumber:02, ChapterTitle, ChapterOrBook, Bucket, AlbumOrIndividual. Folder masks use / between components.").font(.caption)
                    if draft.kind == .music {
                        Toggle("Music first-letter bucket", isOn: $draft.bucket)
                        TextField("Custom individual tracks folder (optional)", text: $draft.individualTracks)
                    }
                }
                if !validation.isEmpty { Text(validation).foregroundStyle(.red) }
            }.formStyle(.grouped) }
            if let id = savedProfileID, draft.id == id {
                HStack {
                    Button("Delete this profile", role: .destructive) { confirmDelete = true }
                    Text("Removes settings only. Library files stay untouched.").font(.caption).foregroundStyle(.secondary)
                }.padding(.bottom, 6)
            }
            HStack { Button("Duplicate as New Profile") { draft.id = UUID(); draft.name += " Copy" }; Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Save") { do { try draft.validate(); save(draft); dismiss() } catch { validation = error.localizedDescription } }.keyboardShortcut(.defaultAction) }
        }.padding()
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
            if let plan = m.plan {
                Text("Review \(plan.mode == .clean ? "Rename" : plan.mode.rawValue.capitalized) Operation").font(.title2.bold())
                Text("\(plan.profile.name) • \(plan.category.isEmpty ? "Library root / source folder" : plan.category) • file contents remain unchanged").foregroundStyle(.secondary)
                ScrollView { LazyVStack(alignment: .leading, spacing: 12) { ForEach(plan.rows) { r in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Toggle(r.status, isOn: Binding(get: { included.contains(r.id) }, set: { if $0 { included.insert(r.id) } else { included.remove(r.id) } })).disabled(!r.actionable); Spacer(); if !r.group.isEmpty { Text("Group: \(r.group)").font(.caption) } }
                        Text("Source: \(r.source)")
                        Text("Destination: \(r.destination)").fontWeight(.medium)
                        if !r.newFolders.isEmpty { Text("New folders (created only on Apply):\n" + r.newFolders.joined(separator: "\n")).foregroundStyle(.blue) }
                        Text(r.explanation).font(.caption).foregroundStyle(.secondary)
                    }.textSelection(.enabled).padding().frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                } } }
                Text("Cancellation stops between files. Completed files remain completed. A group may be partially completed; inspect History for recovery.").font(.caption)
                HStack { Button("Back") { m.showReview = false }; Spacer(); Button("\(plan.mode == .clean ? "Rename" : plan.mode.rawValue.capitalized) \(included.count) files") { var p = plan; p.rows = plan.rows.filter { included.contains($0.id) }; m.plan = p; m.apply() }.buttonStyle(.borderedProminent).disabled(included.isEmpty) }
            }
        }.padding(20).frame(width: 930, height: 700).onAppear { included = Set(m.plan?.rows.filter(\.actionable).map(\.id) ?? []) }
    }
}
struct HistoryView: View {
    @EnvironmentObject var m: Model
    @State var confirm: Event?
    var body: some View {
        VStack(alignment: .leading) {
            Text("Operation History & Recovery").font(.title2.bold())
            Text("Interrupted operations are never resumed or deleted automatically. Inspect the recorded source, destination, and temporary paths. Re-preview retained source files. Cross-volume move undo requires a new reviewed operation.").font(.callout)
            List(m.events) { e in VStack(alignment: .leading, spacing: 5) {
                HStack { Text(e.state).bold(); Text(e.date.formatted()).foregroundStyle(.secondary); Spacer(); if ["Copied", "Moved"].contains(e.state) { Button("Guarded Undo…") { confirm = e }.disabled(m.busy) } }
                Text(e.row.source + "\n→ " + e.row.destination).font(.caption).textSelection(.enabled)
                if !e.detail.isEmpty { Text(e.detail).font(.caption) }
                if let t = e.temporary { Text("Recovery path: " + t).font(.caption).textSelection(.enabled) }
            }.padding(.vertical, 6) }
            HStack { Button("Reveal Journal") { NSWorkspace.shared.activateFileViewerSelecting([m.support.appendingPathComponent("operations.sqlite")]) }; Spacer(); Button("Done") { m.showHistory = false } }
        }.padding().frame(width: 950, height: 650)
        .alert("Confirm guarded undo", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) { Button("Cancel", role: .cancel) { confirm = nil }; Button(confirm?.state == "Copied" ? "Delete Verified Copy" : "Restore Original Location", role: .destructive) { if let e = confirm { m.undo(e, delete: e.state == "Copied") }; confirm = nil } } message: { Text("Undo verifies the recorded destination identity and content. Changed files or occupied original locations are refused. Deleting a copied file is permanent.") }
    }
}

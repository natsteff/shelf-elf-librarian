import SwiftUI
import AppKit
import FilerCore

struct WorkspaceBrand: View {
    var body: some View {
        Link(destination: URL(string: "https://github.com/natsteff/shelf-elf-librarian")!) {
            HStack(spacing: 9) {
                BrandImage(name: "Header-Icon").frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 1) {
                    Text(AppEnvironment.isFreshInstallTest ? "Shelf Elf · Fresh Install Test" : AppIdentity.name).font(.system(size: 13, weight: .semibold))
                    Text(AppIdentity.version).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }.buttonStyle(.plain).instantHelp("Open Shelf Elf Librarian on GitHub")
    }
}
struct WorkspaceProfilePicker: View {
    @EnvironmentObject var m: Model
    var body: some View {
        HStack(spacing: 8) {
            if m.active.rules.useMagic {
                Label("Magic enabled", systemImage: "wand.and.stars").fixedSize().foregroundStyle(.secondary)
                    .accessibilityLabel("Magic enabled")
                    .instantHelp("Magic is enabled for this profile. Run Magic starts manual analysis of selected visible files.")
            }
            Picker("Library profile", selection: $m.activeID) {
                if m.profiles.isEmpty { Text("No profiles — open Settings").tag(m.activeID) }
                ForEach(m.profiles) { Text($0.name).tag($0.id) }
            }.labelsHidden().pickerStyle(.menu).controlSize(.regular)
                .frame(width: 220).onChange(of: m.activeID) { m.changeProfile() }
        }
    }
}
struct WorkspaceLocationBar: View {
    @EnvironmentObject var m: Model
    var body: some View {
        HStack(spacing: 10) {
            Button("Open Workspace…", systemImage: "folder.badge.plus") { m.openWorkspace() }
            Button { m.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .disabled(m.workspace == nil).accessibilityLabel("Refresh workspace").instantHelp("Reload files and ordinary cleanup proposals. Does not run Magic.")
            Toggle("Include subfolders", isOn: $m.recursive).onChange(of: m.recursive) { m.refresh() }
            Divider().frame(height: 18)
            HStack(spacing: 5) {
                Text("Workspace:").foregroundStyle(.secondary)
                if let url = m.workspace {
                    Text(url.path).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        .instantHelp(url.path)
                        .contextMenu {
                            Button("Copy Full Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.path, forType: .string) }
                        }
                    Button("Show Workspace in Finder", systemImage: "folder") {
                        if !showFolderInFinder(url) { m.error = "Workspace folder is unavailable. Use Open Workspace to reconnect." }
                    }.fixedSize()
                } else { Text("None open").foregroundStyle(.secondary) }
            }.font(.callout)
            Spacer(minLength: 8)
        }.controlSize(.small).padding(.horizontal, 14).padding(.vertical, 9)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }
}
struct WorkspaceActionBar: View {
    @EnvironmentObject var m: Model
    @FocusState private var filterFocused: Bool
    var body: some View {
        HStack(spacing: 8) {
            Button("Select All Visible") { m.selected = Set(m.visible.map(\.id)); m.invalidate() }
            Button("Select None") { m.selected = []; m.invalidate() }
            Divider().frame(height: 18)
            Button("Rename Selected", systemImage: "pencil") { m.renameNow(Set(m.visibleSelected.map(\.id))) }
                .disabled(!m.visibleSelected.contains { !m.nameMatches($0) })
                .instantHelp("Immediately rename selected visible files to their proposed names in their current folders. Successful rows are deselected; files are not filed into the library.")
            if m.active.rules.useMagic {
                Button("Run Magic", systemImage: "wand.and.stars") { m.analyzeMagic() }.disabled(m.visibleSelected.isEmpty)
                    .instantHelp("Run Magic on selected visible files. Proposes components using filename evidence, folders and remembered corrections; never runs automatically.")
            }
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter filenames", text: $m.filter).focused($filterFocused).textFieldStyle(.plain)
                if !m.filter.isEmpty {
                    Button { m.filter = ""; filterFocused = true } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Clear filename filter").instantHelp("Clear filename filter")
                }
            }.padding(6).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
                .frame(minWidth: 140, idealWidth: 240, maxWidth: 300).onChange(of: m.filter) { m.invalidate() }
            Text(m.filter.isEmpty ? "\(m.items.count) eligible files" : "Showing \(m.visible.count) of \(m.items.count)")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize()
        }.controlSize(.small).padding(.horizontal, 14).padding(.vertical, 10)
    }
}
struct WorkspaceFilingBar: View {
    @EnvironmentObject var m: Model
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "folder").font(.title3).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("Library destination").font(.system(size: 12, weight: .medium))
                Text(m.active.root.isEmpty ? "Choose a destination in Profile Settings" : m.active.root)
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    .instantHelp(m.active.root.isEmpty ? "Choose a destination root in Profile Settings." : m.active.root)
            }
            Button("Show Library in Finder", systemImage: "folder") { m.openLibraryInFinder() }
                .fixedSize()
                .disabled(m.active.root.isEmpty).accessibilityLabel("Show Library in Finder").instantHelp("Show Library in Finder")
            Spacer(minLength: 8)
            Divider().frame(height: 34)
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 12) {
                    Picker("Operation", selection: $m.mode) { Text("Copy to Library").tag(Mode.copy); Text("Move to Library").tag(Mode.move) }
                        .labelsHidden().frame(width: 165).onChange(of: m.mode) { m.invalidate() }
                    Toggle("File only", isOn: $m.fileOnly).onChange(of: m.fileOnly) { m.invalidate() }
                        .instantHelp("Copy or move using current filenames, without applying proposed names again. Folder masks still determine destination subfolders.")
                }
                HStack(spacing: 8) {
                    Button("Preview Renames…") { m.preview(true) }.disabled(m.visibleSelected.isEmpty)
                        .instantHelp("Clean Preview: review renames in the existing folders before Apply. Row checkmarks and Rename Selected remain immediate actions.")
                    Button("Preview Filing…") { m.preview(false) }.disabled(m.visibleSelected.isEmpty)
                        .buttonStyle(.borderedProminent).instantHelp("File Preview: review copying or moving selected visible files into the library before Apply.")
                }
            }
        }.controlSize(.small).padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }
}

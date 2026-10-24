import SwiftUI
import AppKit
import FilerCore

struct WorkspaceTitle: View {
    var body: some View {
        VStack(spacing: 1) {
            Text(AppEnvironment.isFreshInstallTest && AppEnvironment.screenshotRoot == nil ? "Shelf Elf · Fresh Install Test" : AppIdentity.name)
                .font(.system(size: 13, weight: .semibold))
            Text(AppIdentity.version).font(.system(size: 11)).foregroundStyle(.secondary)
        }.multilineTextAlignment(.center).fixedSize()
    }
}
struct WorkspaceProfilePicker: View {
    @EnvironmentObject var m: Model
    var body: some View {
        HStack(spacing: 8) {
            Picker("Library profile", selection: $m.activeID) {
                if m.profiles.isEmpty { Text("No profiles — open Settings").tag(m.activeID) }
                ForEach(m.profiles) { Text($0.name).tag($0.id) }
            }.labelsHidden().pickerStyle(.menu).controlSize(.regular)
                .fixedSize(horizontal: true, vertical: false).onChange(of: m.activeID) { m.changeProfile() }
            Label(m.active.rules.useMagic ? "Magic available" : "Magic off", systemImage: "wand.and.stars")
                .labelStyle(.titleAndIcon).fixedSize().foregroundStyle(.secondary)
                .accessibilityLabel(m.active.rules.useMagic ? "Magic available" : "Magic off")
                .instantHelp(m.active.rules.useMagic ? "Magic is available for this profile. Click Run Magic to analyze selected visible files, then confirm Copy or Move. It does not run in the background." : "Magic is off for this profile. Turn it on in Profile Settings to make Run Magic available.")
        }
    }
}
struct WorkspaceLocationBar: View {
    @EnvironmentObject var m: Model
    var body: some View {
        HStack(spacing: 12) {
            Button("Open Workspace…", systemImage: "folder.badge.plus") { m.openWorkspace() }
            Button { m.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .disabled(m.workspace == nil).accessibilityLabel("Refresh workspace").instantHelp("Reload files and ordinary cleanup proposals. Does not run Magic.")
            Toggle("Include subfolders", isOn: $m.recursive).onChange(of: m.recursive) { m.refresh() }
            Divider().frame(height: 18)
            HStack(spacing: 5) {
                Text("Workspace:").foregroundStyle(.secondary)
                if let url = m.workspace {
                    Text(url.path).frame(minWidth: 80).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        .layoutPriority(-1).instantHelp(url.path)
                        .contextMenu {
                            Button("Copy Full Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.path, forType: .string) }
                        }
                    Button("Show Workspace in Finder", systemImage: "folder") {
                        if !showFolderInFinder(url) { m.error = "Workspace folder is unavailable. Use Open Workspace to reconnect." }
                    }.fixedSize()
                } else { Text("None open").foregroundStyle(.secondary) }
            }.font(.system(size: 13))
            Spacer(minLength: 8)
        }.controlSize(.regular).font(.system(size: 13)).padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }
}
struct WorkspaceActionBar: View {
    @EnvironmentObject var m: Model
    @FocusState private var filterFocused: Bool
    var body: some View {
        HStack(spacing: 12) {
            Button("Select All Visible") { m.selected = Set(m.visible.map(\.id)); m.invalidate() }
            Button("Select None") { m.selected = []; m.invalidate() }
            Divider().frame(height: 18)
            Button("Rename Selected", systemImage: "pencil") { m.renameNow(Set(m.visibleSelected.map(\.id))) }
                .disabled(!m.visibleSelected.contains { !m.nameMatches($0) })
                .instantHelp("Immediately rename selected visible files to their proposed names in their current folders. Successful rows are deselected; files are not filed into the library.")
            if m.active.rules.useMagic {
                Button("Run Magic", systemImage: "wand.and.stars") { m.analyzeMagic() }.disabled(m.visibleSelected.isEmpty)
                    .instantHelp("Analyze selected visible files, then confirm Copy or Move to Library using proposed filenames. Nothing is copied or moved until confirmation.")
            }
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter filenames", text: $m.filter).focused($filterFocused).textFieldStyle(.plain)
                if !m.filter.isEmpty {
                    Button { m.filter = ""; filterFocused = true } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Clear filename filter").instantHelp("Clear filename filter")
                }
            }.padding(8).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
                .frame(minWidth: 140, idealWidth: 240, maxWidth: 300).onChange(of: m.filter) { m.invalidate() }
            Text(m.filter.isEmpty ? "\(m.items.count) eligible files" : "Showing \(m.visible.count) of \(m.items.count)")
                .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize()
        }.controlSize(.regular).font(.system(size: 13)).padding(.horizontal, 16).padding(.vertical, 12)
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
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    .instantHelp(m.active.root.isEmpty ? "Choose a destination root in Profile Settings." : m.active.root)
            }
            Button("Show Library in Finder", systemImage: "folder") { m.openLibraryInFinder() }
                .fixedSize()
                .disabled(m.active.root.isEmpty).accessibilityLabel("Show Library in Finder").instantHelp("Show Library in Finder")
            Spacer(minLength: 8)
            Divider().frame(height: 34)
            VStack(alignment: .trailing, spacing: 12) {
                HStack(spacing: 12) {
                    Picker("Operation", selection: $m.mode) { Text("Copy to Library").tag(Mode.copy); Text("Move to Library").tag(Mode.move) }
                        .labelsHidden().frame(width: 220).onChange(of: m.mode) { m.invalidate() }

                }
                HStack(spacing: 12) {
                    Button(m.mode == .copy ? "Preview Copy to Library…" : "Preview Move to Library…") { m.preview(false) }.disabled(m.visibleSelected.isEmpty)
                        .buttonStyle(.borderedProminent).fixedSize().instantHelp("Review proposed names and destinations for the selected operation. The preview also offers copying or moving with current names without individual component review.")
                }
            }
        }.controlSize(.regular).font(.system(size: 13)).padding(.horizontal, 16).padding(.vertical, 14)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }
}

import SwiftUI
import FilerCore

struct ROMSettings: View {
    @Binding var profile: Profile
    private var mappings: Binding<[ROMExtensionMapping]> {
        Binding(get: { ROMRouting.entries(profile) }, set: { profile.romExtensionMappings = $0 })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ROM extensions → System").font(.headline)
            SettingsHint(text: "Map clear extensions to a System. System’s folder mapping below chooses the library folder; otherwise Folder mask applies. Shared extensions such as iso, bin, chd, zip and 7z need {System} in a filename or parent-folder pattern, or a manual System selection. Explicit filename values take priority; differences are flagged for review.")
            ForEach(mappings) { $entry in
                HStack {
                    TextField("Extensions (comma separated)", text: $entry.extensions)
                    Picker("System", selection: $entry.system) {
                        ForEach(profile.classifications ?? []) { system in Text(system.name).tag(system.name) }
                    }
                    Button("Remove") { mappings.wrappedValue.removeAll { $0.id == entry.id } }
                }
            }
            Button("Add Extension Mapping") { mappings.wrappedValue.append(ROMExtensionMapping("", system: profile.classifications?.first?.name ?? "")) }
            SettingsHint(text: "ROM filenames are preserved automatically. Rename only with an explicit manual filename edit. Folders containing disc descriptors or playlists are blocked from individual filing because linked files must stay together. No archives are opened or ROM contents inspected.")
        }
    }
}

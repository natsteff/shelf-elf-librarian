import AppKit
import FilerCore

extension Model {
    func settingsArchive() -> SettingsArchive { SettingsArchive(profiles: profiles, general: universalPreferences, activeProfileID: activeID) }
    func exportSettings() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Shelf Elf Settings.json"; panel.title = "Export Profiles & General Settings"
        WindowPresentation.choose(panel) { [self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(settingsArchive()).write(to: url, options: .atomic)
                status = "Settings exported: " + url.path
            } catch { self.error = error.localizedDescription }
        }
    }
    func importSettings() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false; panel.title = "Import Profiles & General Settings"
        WindowPresentation.choose(panel) { [self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try Data(contentsOf: url)
                guard data.count <= 20_000_000 else { throw fail("Settings archive is too large.") }
                let archive = try JSONDecoder().decode(SettingsArchive.self, from: data)
                let imported = try archive.validatedProfiles()
                let alert = NSAlert(); alert.messageText = "Replace current profiles and General Settings?"
                alert.informativeText = "Import \(imported.count) profiles from \(url.lastPathComponent). A backup of your current settings will be saved first. Library files and operation history are unchanged. Destinations may need reconnecting on another Mac."
                alert.addButton(withTitle: "Import Settings"); alert.addButton(withTitle: "Cancel")
                WindowPresentation.confirm(alert) { [self] response in
                    guard response == .alertFirstButtonReturn else { return }
                    do {
                        let backup = support.appendingPathComponent("Settings before import-\(UUID().uuidString).json")
                        try JSONEncoder().encode(settingsArchive()).write(to: backup, options: .atomic)
                        try JSONEncoder().encode(imported).write(to: support.appendingPathComponent("profiles.json"), options: .atomic)
                        AppEnvironment.defaults.set(try JSONEncoder().encode(archive.general), forKey: "universalSpellingCasePreferences")
                        profiles = imported; universalPreferences = archive.general
                        HoverHelp.shared.timing = archive.general.hoverTiming ?? .immediate
                        activeID = imported.contains(where: { $0.id == archive.activeProfileID }) ? archive.activeProfileID! : imported.first?.id ?? newProfile.id
                        items = []; selected = []; invalidate(); changeProfile()
                        status = "Settings imported. Prior settings backup: " + backup.path
                    } catch { self.error = error.localizedDescription }
                }
            } catch { self.error = error.localizedDescription }
        }
    }
}

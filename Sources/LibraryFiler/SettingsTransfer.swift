import AppKit
import FilerCore

extension Model {
    func settingsArchive() -> SettingsArchive { SettingsArchive(profiles: profiles, general: universalPreferences, activeProfileID: activeID) }
    @discardableResult
    func backupConfiguration(_ reason: String) throws -> URL {
        do { return try SettingsBackupStore(support: support).save(settingsArchive(), reason: reason) }
        catch { throw fail("Settings were not changed because their automatic backup failed. " + error.localizedDescription) }
    }
    func persistProfiles(_ next: [Profile], reason: String) throws {
        guard next != profiles else { return }
        do { try SettingsBackupStore(support: support).writeProfiles(next, current: settingsArchive(), to: support.appendingPathComponent("profiles.json"), reason: reason) }
        catch { throw fail("Settings could not be saved. " + error.localizedDescription) }
    }
    func replaceSettings(_ archive: SettingsArchive, reason: String, statusText: String) throws {
        guard !busy else { throw fail("Wait for the current operation to finish.") }
        let imported = try archive.validatedProfiles()
        let generalData = try JSONEncoder().encode(archive.general)
        let backup = try SettingsBackupStore(support: support).writeProfiles(imported, current: settingsArchive(), to: support.appendingPathComponent("profiles.json"), reason: reason)
        AppEnvironment.defaults.set(generalData, forKey: "universalSpellingCasePreferences")
        profiles = imported; universalPreferences = archive.general
        HoverHelp.shared.timing = archive.general.hoverTiming ?? .immediate
        mode = archive.general.filingAction
        activeID = imported.contains(where: { $0.id == archive.activeProfileID }) ? archive.activeProfileID! : imported.first?.id ?? newProfile.id
        items = []; selected = []; invalidate(); changeProfile()
        status = statusText + ". Previous settings backed up: " + backup.path
    }
    func exportSettings() {
        let timestamp = DateFormatter()
        timestamp.locale = Locale(identifier: "en_US_POSIX")
        timestamp.calendar = Calendar(identifier: .gregorian)
        timestamp.timeZone = .current
        timestamp.dateFormat = "yyyy.MM.dd-HH.mm"
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Shelf Elf Settings-\(timestamp.string(from: Date())).json"
        panel.title = "Export Profiles & General Settings"
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
                        try replaceSettings(archive, reason: "Import settings", statusText: "Settings imported")
                    } catch { self.error = error.localizedDescription }
                }
            } catch { self.error = error.localizedDescription }
        }
    }
}

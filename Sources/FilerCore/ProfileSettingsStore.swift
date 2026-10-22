import Foundation

/// Persist before publishing model changes or dismissing the settings draft.
public enum ProfileSettingsStore {
    public static func write(_ profiles: [Profile], to url: URL) throws {
        try JSONEncoder().encode(profiles).write(to: url, options: .atomic)
    }
    public static func read(from url: URL) throws -> [Profile] {
        try JSONDecoder().decode([Profile].self, from: Data(contentsOf: url))
    }
}

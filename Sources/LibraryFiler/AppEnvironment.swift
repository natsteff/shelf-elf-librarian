import Foundation

enum AppEnvironment {
    static var isFreshInstallTest: Bool {
        Bundle.main.bundleIdentifier?.hasSuffix(".fresh-test") == true || ProcessInfo.processInfo.arguments.contains("--fresh-install-test")
    }
    // Only a separately packaged test bundle can opt into deterministic screenshot fixtures.
    static var screenshotRoot: String? {
        guard isFreshInstallTest else { return nil }
        return Bundle.main.object(forInfoDictionaryKey: "ShelfElfScreenshotRoot") as? String
    }
    static let defaults: UserDefaults = screenshotRoot != nil ? UserDefaults(suiteName: "com.local.LibraryFiler.ScreenshotDemo")! : isFreshInstallTest ? UserDefaults(suiteName: "com.local.LibraryFiler.FreshInstallTest")! : .standard
    static var supportName: String { screenshotRoot != nil ? "com.local.LibraryFiler.ScreenshotDemo" : isFreshInstallTest ? "com.local.LibraryFiler.FreshInstallTest" : "com.local.LibraryFiler.Alpha" }
}

import Foundation

enum AppEnvironment {
    static var isFreshInstallTest: Bool {
        Bundle.main.bundleIdentifier?.hasSuffix(".fresh-test") == true || ProcessInfo.processInfo.arguments.contains("--fresh-install-test")
    }
    static let defaults: UserDefaults = isFreshInstallTest ? UserDefaults(suiteName: "com.local.LibraryFiler.FreshInstallTest")! : .standard
    static var supportName: String { isFreshInstallTest ? "com.local.LibraryFiler.FreshInstallTest" : "com.local.LibraryFiler.Alpha" }
}

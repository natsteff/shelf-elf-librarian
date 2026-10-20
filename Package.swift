// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "LibraryFiler", platforms: [.macOS(.v14)], products: [.executable(name: "LibraryFiler", targets: ["LibraryFiler"])], targets: [.target(name: "FilerCore", linkerSettings: [.linkedLibrary("sqlite3")]), .executableTarget(name: "LibraryFiler", dependencies: ["FilerCore"]), .executableTarget(name: "SafetyChecks", dependencies: ["FilerCore"])])

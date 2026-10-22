import Foundation
import AVFoundation

public enum VideoMetadata {
    /// AVFoundation exposes supported containers locally. No exports, tag writes or online lookups.
    public static func read(_ url: URL, cancel: Cancellation? = nil) async -> EmbeddedMetadata {
        var result = EmbeddedMetadata(video: true)
        guard ["mp4", "m4v", "mov"].contains(url.pathExtension.lowercased()) else {
            result.notes = ["Video metadata reading currently supports MP4, M4V and MOV. Filename interpretation remains available for this format."]; return result
        }
        let asset = AVURLAsset(url: url)
        let monitor: Task<Void, Never>? = cancel.map { token in
            Task {
                while !Task.isCancelled {
                    if token.cancelled { asset.cancelLoading(); return }
                    do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
                }
            }
        }
        defer { monitor?.cancel() }
        do {
            let formats = try await asset.load(.availableMetadataFormats)
            for format in formats {
                if Task.isCancelled { asset.cancelLoading(); return result }
                let values = try await asset.loadMetadata(for: format)
                for item in values.prefix(2048) {
                    let identifier = item.identifier?.rawValue ?? String(describing: item.key ?? "Unknown" as NSString)
                    let rawKey = identifier.components(separatedBy: "/").last ?? identifier
                    var value = "", binary = false
                    if let string = try? await item.load(.stringValue) { value = string }
                    else if let number = try? await item.load(.numberValue) { value = number.stringValue }
                    else if let data = try? await item.load(.dataValue) { value = "\(data.count) bytes of binary data"; binary = true }
                    guard !value.isEmpty else { continue }
                    let key = component(for: rawKey)
                    result.tags.append(.init(key: identifier, label: key ?? rawKey, value: value, component: binary ? nil : key, source: format.rawValue, binary: binary))
                }
                if values.count > 2048 { result.notes.append("Only the first 2,048 metadata items in \(format.rawValue) are displayed.") }
            }
            let tracks = try await asset.loadTracks(withMediaType: .video)
            if let track = tracks.first {
                let size = try await track.load(.naturalSize), transform = try await track.load(.preferredTransform)
                let display = size.applying(transform)
                let w = abs(display.width).rounded(), h = abs(display.height).rounded()
                if w.isFinite, h.isFinite, (1...100_000).contains(w), (1...100_000).contains(h) {
                    let width = Int(w), height = Int(h)
                    // Pixel dimensions do not imply progressive/interlaced scanning or a marketing resolution.
                    result.tags.append(.init(key: "dimensions", label: "Resolution (display dimensions)", value: "\(width)x\(height)", component: "Resolution", source: "Video track"))
                }
            }
        } catch { result.notes.append("Video metadata could not be fully read. Filename interpretation is still available. " + error.localizedDescription) }
        return result
    }
    public static func component(for key: String) -> String? {
        // AVFoundation escapes legacy Latin-1 atom names (for example itsk/%A9day).
        let legacy = key.replacingOccurrences(of: "%C2%A9", with: "©", options: .caseInsensitive).replacingOccurrences(of: "%A9", with: "©", options: .caseInsensitive)
        let decoded = legacy.removingPercentEncoding ?? legacy
        switch decoded {
        case "©nam", "title", "com.apple.quicktime.title", "com.apple.quicktime.displayname": return "Title"
        case "©day", "year", "date", "releaseDate": return "Year"
        case "tvsh", "show", "series", "TVSHOW": return "Series"
        case "tvsn", "season", "SEASON": return "Season"
        case "tves", "episode", "EPISODE": return "Episode"
        case "©gen", "genre", "com.apple.quicktime.genre": return "Genre"
        default: return nil
        }
    }
}
/// Metadata enrichment runs with discovery, off the main actor. A failed metadata read never excludes a file.
public func scanMedia(_ root: URL, profile: Profile, recursive: Bool, cancel: Cancellation? = nil) async throws -> ScanResult {
    var result = try scan(root, profile: profile, recursive: recursive, cancel: cancel)
    guard profile.kind == .video else { return result }
    for i in result.items.indices {
        if cancel?.cancelled == true || Task.isCancelled { throw fail("Discovery cancelled; source files unchanged.") }
        let metadata = await VideoMetadata.read(result.items[i].url, cancel: cancel)
        if cancel?.cancelled == true || Task.isCancelled { throw fail("Discovery cancelled; source files unchanged.") }
        result.items[i].metadata = metadata
        let enriched = metadata.fillingVideoFields(result.items[i].fields, profile: profile, source: result.items[i].url)
        result.items[i].fields = enriched.0; result.items[i].initialFields = enriched.0
        if !enriched.1.isEmpty {
            result.items[i].evidence += "\n" + enriched.1.joined(separator: "\n")
            result.items[i].reviewed = false
        }
        result.items[i].initialBasename = try? proposedBasename(result.items[i], profile: profile)
    }
    return result
}

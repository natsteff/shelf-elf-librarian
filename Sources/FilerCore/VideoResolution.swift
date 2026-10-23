import Foundation

public enum VideoResolution {
    /// Resolution tiers describe approximate picture size, not DVD/Blu-ray provenance or scan detection.
    public static func display(_ value: String, profile: Profile) -> String {
        guard profile.kind == .video, profile.useCommonResolutionShorthand ?? true else { return value }
        let pattern = #"^\s*(\d{1,6})\s*[x×]\s*(\d{1,6})\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let width = Double((value as NSString).substring(with: match.range(at: 1))),
              let height = Double((value as NSString).substring(with: match.range(at: 2))), width > 0, height > 0 else { return value }
        // Use the long edge as well as the short edge so cropped widescreen and portrait video
        // retain their familiar tier (1920x800 -> 1080p, 1080x1920 -> 1080p).
        let equivalentHeight = max(min(width, height), max(width, height) * 9 / 16)
        let tiers: [(Double, String)] = [(480, "480p"), (720, "720p"), (1080, "1080p"), (2160, "4K"), (4320, "8K")]
        return tiers.min { abs($0.0 - equivalentHeight) < abs($1.0 - equivalentHeight) }!.1
    }
}

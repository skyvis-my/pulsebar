import Foundation

/// Every string here has a fixed character count, so with a monospaced font the menu bar never reflows.
/// Values are whole numbers: the unit steps up at 1000, so three digits always suffice.
enum Format {
    /// " 98 MB/s", "  1 KB/s", "512  B/s" — 3-digit value, space, 4-char unit.
    static func rate(_ bytesPerSec: Double) -> String {
        let units = [" B/s", "KB/s", "MB/s", "GB/s", "TB/s"]
        let (v, i) = scaled(max(0, bytesPerSec), unitCount: units.count)
        return pad(String(format: "%.0f", v), 3) + " " + units[i]
    }

    /// " 98M", "  1M", "  0K" — 4 chars, kilobytes minimum.
    static func compactRate(_ bytesPerSec: Double) -> String {
        let units = ["K", "M", "G", "T"]
        let (v, i) = scaled(max(0, bytesPerSec) / 1024, unitCount: units.count)
        return pad(String(format: "%.0f", v), 3) + units[i]
    }

    /// Exactly 3 chars of milliseconds: "  4", " 14", "214", or "  –" on timeout.
    /// The pinger times out below 1 s, so three digits always suffice.
    static func ping(_ ms: Double?) -> String {
        guard let ms else { return "  –" }
        return pad(String(format: "%.0f", min(ms, 999)), 3)
    }

    /// Short axis/stat label: "980K", "12M", "1G" (bytes/second).
    static func axisRate(_ bytesPerSec: Double) -> String {
        compactRate(bytesPerSec).trimmingCharacters(in: .whitespaces)
    }

    static func pingLong(_ ms: Double?) -> String {
        guard let ms else { return "–" }
        return String(format: "%.0f", ms)
    }

    /// Divides by 1024 until the value rounds to at most 999, capped at the largest unit.
    private static func scaled(_ value: Double, unitCount: Int) -> (Double, Int) {
        var v = value, i = 0
        while v >= 999.5 && i < unitCount - 1 { v /= 1024; i += 1 }
        return (min(v, 999), i)
    }

    private static func pad(_ s: String, _ width: Int) -> String {
        s.count >= width ? s : String(repeating: " ", count: width - s.count) + s
    }
}

import Foundation

/// Every string here has a fixed character count, so with a monospaced font the menu bar never reflows.
enum Format {
    /// "98.0 MB/s", "0.98 KB/s", " 512  B/s" — 4-char value, space, 4-char unit.
    static func rate(_ bytesPerSec: Double) -> String {
        let units = [" B/s", "KB/s", "MB/s", "GB/s", "TB/s"]
        var v = max(0, bytesPerSec), i = 0
        while v >= 999.5 && i < units.count - 1 { v /= 1024; i += 1 }
        return pad(number(v, integer: i == 0), 4) + " " + units[i]
    }

    /// "98M", "1.2M", "  0K" — 4 chars, kilobytes minimum.
    static func compactRate(_ bytesPerSec: Double) -> String {
        let units = ["K", "M", "G", "T"]
        var v = max(0, bytesPerSec) / 1024, i = 0
        while v >= 999.5 && i < units.count - 1 { v /= 1024; i += 1 }
        v = min(v, 999)
        let s = v < 9.95 && v >= 0.05 ? String(format: "%.1f", v) : String(format: "%.0f", v)
        return pad(s, 3) + units[i]
    }

    /// Exactly 3 chars of milliseconds: "  4", " 14", "214", or "  –" on timeout.
    /// The pinger times out below 1 s, so three digits always suffice.
    static func ping(_ ms: Double?) -> String {
        guard let ms else { return "  –" }
        return pad(String(format: "%.0f", min(ms, 999)), 3)
    }

    /// Short axis/stat label: "980K", "12M", "1.2G" (bytes/second).
    static func axisRate(_ bytesPerSec: Double) -> String {
        compactRate(bytesPerSec).trimmingCharacters(in: .whitespaces)
    }

    static func pingLong(_ ms: Double?) -> String {
        guard let ms else { return "–" }
        return ms < 10 ? String(format: "%.1f", ms) : String(format: "%.0f", ms)
    }

    private static func number(_ v: Double, integer: Bool) -> String {
        if integer || v >= 99.95 { return String(format: "%.0f", v) }
        if v >= 9.995 { return String(format: "%.1f", v) }
        return String(format: "%.2f", v)
    }

    private static func pad(_ s: String, _ width: Int) -> String {
        s.count >= width ? s : String(repeating: " ", count: width - s.count) + s
    }
}

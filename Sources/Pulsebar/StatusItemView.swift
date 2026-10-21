import AppKit

/// Draws the menu bar item. Its width is computed once per style from worst-case strings,
/// so the item never changes size no matter what the numbers do.
final class StatusItemView: NSView {
    var style: MenuStyle = .spark
    var up = 0.0
    var down = 0.0
    var ping: Double?
    var recent: [Double?] = []
    var recentRates: [(up: Double, down: Double)] = []

    private static let small = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)
    private static let big = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
    private static let line = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
    private static let pad: CGFloat = 3
    private static let gap: CGFloat = 4
    /// Widest possible speed line; the twin column is always exactly this wide.
    private static let twinSample = "↑999M"
    private static let barCount = 6
    private static let barStep: CGFloat = 3 // 2 pt bar + 1 pt gap

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil } // let the status button take clicks

    static func width(for style: MenuStyle) -> CGFloat {
        let twin = measure(twinSample, small).width
        let pingW = measure("999", big).width
        switch style {
        case .twin: return ceil(pad + twin + gap + pingW + pad)
        case .spark: return ceil(pad + twin + gap + pingW + pad)
        case .line: return ceil(pad + measure(lineText(up: 0, down: 0, ping: nil), line).width + pad)
        case .pingOnly: return ceil(pad + CGFloat(barCount) * barStep - 1 + gap + pingW + pad)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let h = bounds.height
        var x = Self.pad
        let label = NSColor.labelColor
        let pingColor = ping == nil ? Quality.poor.color : label

        switch style {
        case .twin, .spark:
            if style == .spark {
                let twinW = Self.measure(Self.twinSample, Self.small).width
                drawRateHistory(in: NSRect(x: x - 2, y: 2, width: twinW + 4, height: h - 4))
            }
            x = drawTwin(at: x, height: h, color: label) + Self.gap
            if style == .spark {
                let pingW = Self.measure("999", Self.big).width
                drawPingHistory(in: NSRect(x: x - 1, y: 2, width: pingW + 2, height: h - 4))
            }
            drawCentered(Format.ping(ping), Self.big, pingColor, x: x, height: h)
        case .line:
            drawCentered(Self.lineText(up: up, down: down, ping: ping), Self.line, label, x: x, height: h)
        case .pingOnly:
            drawBars(at: x, height: h)
            x += CGFloat(Self.barCount) * Self.barStep - 1 + Self.gap
            drawCentered(Format.ping(ping), Self.big, pingColor, x: x, height: h)
        }
    }

    // MARK: - Pieces

    private func drawTwin(at x: CGFloat, height h: CGFloat, color: NSColor) -> CGFloat {
        let top = "↑" + Format.compactRate(up)
        let bottom = "↓" + Format.compactRate(down)
        let lineH = Self.small.ascender - Self.small.descender
        let y0 = (h - lineH * 2) / 2
        let attrs: [NSAttributedString.Key: Any] = [.font: Self.small, .foregroundColor: color]
        top.draw(at: NSPoint(x: x, y: y0), withAttributes: attrs)
        bottom.draw(at: NSPoint(x: x, y: y0 + lineH), withAttributes: attrs)
        return x + Self.measure(Self.twinSample, Self.small).width
    }

    /// Faint download (filled) and upload (line) history behind the speed numbers — costs no width.
    private func drawRateHistory(in rect: NSRect) {
        let pts = Array(recentRates.suffix(30))
        guard pts.count > 1 else { return }
        let ceiling = max(pts.map { max($0.up, $0.down) }.max() ?? 0, 64 * 1024)
        let step = rect.width / 29
        let x0 = rect.maxX - step * CGFloat(pts.count - 1)
        // Top out at 80% so the upper speed line always stays legible.
        func y(_ v: Double) -> CGFloat { rect.maxY - CGFloat(v / ceiling) * rect.height * 0.8 }

        let area = NSBezierPath()
        area.move(to: NSPoint(x: x0, y: rect.maxY))
        for (i, p) in pts.enumerated() { area.line(to: NSPoint(x: x0 + step * CGFloat(i), y: y(p.down))) }
        area.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        area.close()
        Self.downTint.withAlphaComponent(0.2).setFill()
        area.fill()

        let up = NSBezierPath()
        for (i, p) in pts.enumerated() {
            let pt = NSPoint(x: x0 + step * CGFloat(i), y: y(p.up))
            if i == 0 { up.move(to: pt) } else { up.line(to: pt) }
        }
        up.lineWidth = 1
        Self.upTint.withAlphaComponent(0.55).setStroke()
        up.stroke()
    }

    private static let downTint = NSColor(red: 0.36, green: 0.79, blue: 0.65, alpha: 1)
    private static let upTint = NSColor(red: 0.62, green: 0.55, blue: 0.95, alpha: 1)

    /// Faint ping history behind the ping number, tinted by current quality — costs no width.
    private func drawPingHistory(in rect: NSRect) {
        let pts = Array(recent.suffix(15))
        guard pts.count > 1 else { return }
        let ceiling = max(pts.compactMap { $0 }.max() ?? 0, 40)
        let step = rect.width / 14
        let x0 = rect.maxX - step * CGFloat(pts.count - 1)
        // Top out at 80%, like the bandwidth history, so the digits stay legible.
        func y(_ v: Double) -> CGFloat { rect.maxY - CGFloat(v / ceiling) * rect.height * 0.8 }
        let tint = Quality(ping).color

        var run: [NSPoint] = []
        func flush() {
            defer { run.removeAll() }
            guard run.count > 1 else { return }
            let area = NSBezierPath()
            area.move(to: NSPoint(x: run[0].x, y: rect.maxY))
            run.forEach { area.line(to: $0) }
            area.line(to: NSPoint(x: run[run.count - 1].x, y: rect.maxY))
            area.close()
            tint.withAlphaComponent(0.2).setFill()
            area.fill()
            let line = NSBezierPath()
            line.move(to: run[0])
            run.dropFirst().forEach { line.line(to: $0) }
            line.lineWidth = 1
            tint.withAlphaComponent(0.6).setStroke()
            line.stroke()
        }
        for (i, v) in pts.enumerated() {
            let x = x0 + step * CGFloat(i)
            guard let v else {
                // Timeout: a red tick at the top, and break the line.
                flush()
                Quality.poor.color.setFill()
                NSRect(x: x - 0.75, y: rect.minY, width: 1.5, height: 3).fill()
                continue
            }
            run.append(NSPoint(x: x, y: y(v)))
        }
        flush()
    }

    private func drawBars(at x: CGFloat, height h: CGFloat) {
        let pts = Array(recent.suffix(Self.barCount))
        let maxH: CGFloat = 13
        let base = (h + maxH) / 2
        let lead = Self.barCount - pts.count
        for (i, v) in pts.enumerated() {
            // Log scale: 5 ms is a stub, 500 ms+ is full height.
            let frac = v.map { min(1, max(0.15, log10(max($0, 5) / 5) / 2)) } ?? 1
            let bh = maxH * CGFloat(frac)
            Quality(v).color.setFill()
            NSRect(x: x + CGFloat(lead + i) * Self.barStep, y: base - bh, width: Self.barStep - 1, height: bh).fill()
        }
    }

    private func drawCentered(_ s: String, _ font: NSFont, _ color: NSColor, x: CGFloat, height h: CGFloat) {
        let size = Self.measure(s, font)
        s.draw(at: NSPoint(x: x, y: (h - size.height) / 2),
               withAttributes: [.font: font, .foregroundColor: color])
    }

    private static func lineText(up: Double, down: Double, ping: Double?) -> String {
        "↓" + Format.compactRate(down) + " ↑" + Format.compactRate(up) + " " + Format.ping(ping)
    }

    private static func measure(_ s: String, _ font: NSFont) -> NSSize {
        (s as NSString).size(withAttributes: [.font: font])
    }
}

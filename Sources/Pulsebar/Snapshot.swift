import AppKit
import SwiftUI

/// `Pulsebar --snapshot <dir>` renders every menu bar style (idle and busy, light and dark) and the
/// popover to PNGs after collecting some live samples, then quits. Used to check layout without screen access.
@MainActor
enum Snapshot {
    static var directory: URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    static func render(monitor: Monitor, to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let busyPings: [Double?] = [18, 22, 40, 35, nil, 90, 140, 120, 214, 180, 60, 44, 210, 230, 190, 214, 170, 214, 205, 214]
        let busyRates: [(up: Double, down: Double)] = (0..<30).map { (i: Int) -> (up: Double, down: Double) in
            let up: Double = Double(i % 7) * 200_000
            let down: Double = Double(30 + i * 3) * 1_048_576
            return (up, down)
        }
        for dark in [false, true] {
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            for style in MenuStyle.allCases {
                for busy in [false, true] {
                    let w = StatusItemView.width(for: style)
                    let v = StatusItemView(frame: NSRect(x: 0, y: 0, width: w, height: 24))
                    v.style = style
                    v.up = busy ? 1.2 * 1_048_576 : monitor.up
                    v.down = busy ? 98 * 1_048_576 : monitor.down
                    v.ping = busy ? 214 : monitor.ping
                    v.recent = busy ? busyPings : monitor.recentPings(20)
                    v.recentRates = busy ? busyRates : monitor.recentRates(30)
                    let bar = Backdrop(frame: v.frame, color: dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.93, alpha: 1))
                    bar.appearance = appearance
                    bar.addSubview(v)
                    save(bar, dir.appendingPathComponent("bar-\(style.rawValue)-\(busy ? "busy" : "idle")-\(dark ? "dark" : "light").png"))
                }
            }
        }

        // ImageRenderer draws text and charts faithfully; AppKit-backed controls (text field, picker) show as placeholders.
        for dark in [false, true] {
            let content = PopoverView(monitor: monitor)
                .background(dark ? Color(white: 0.16) : Color.white)
                .environment(\.colorScheme, dark ? .dark : .light)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            if let cg = renderer.cgImage {
                let rep = NSBitmapImageRep(cgImage: cg)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: dir.appendingPathComponent("popover-\(dark ? "dark" : "light").png"))
            }
        }
    }

    private static func save(_ view: NSView, _ url: URL) {
        let scale: CGFloat = 2
        let size = view.bounds.size
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

private final class Backdrop: NSView {
    let color: NSColor
    init(frame: NSRect, color: NSColor) { self.color = color; super.init(frame: frame) }
    required init?(coder: NSCoder) { nil }
    override func draw(_ dirtyRect: NSRect) { color.setFill(); bounds.fill() }
}

import XCTest
@testable import Pulsebar

/// The menu bar stays still only if every formatted string keeps the same character count.
final class FormatTests: XCTestCase {
    private let rates: [Double] = [0, 1, 999, 999.4, 999.6, 1023, 1024, 10_240, 102_400, 1_000_000,
                                   12_345_678, 98_000_000, 999_999_999, 5e12, 9e15]

    func testRateWidthIsFixed() {
        for r in rates { XCTAssertEqual(Format.rate(r).count, 9, "\(r) → '\(Format.rate(r))'") }
        XCTAssertEqual(Format.rate(98.0 * 1024 * 1024), "98.0 MB/s")
        XCTAssertEqual(Format.rate(0), "   0  B/s")
    }

    func testCompactRateWidthIsFixed() {
        for r in rates { XCTAssertEqual(Format.compactRate(r).count, 4, "\(r) → '\(Format.compactRate(r))'") }
    }

    func testPingWidthIsFixedAndUnitless() {
        for ms in [nil, 0.4, 4, 14, 99.6, 214, 999, 1500] as [Double?] {
            let s = Format.ping(ms)
            XCTAssertEqual(s.count, 3, "\(String(describing: ms)) → '\(s)'")
            XCTAssertFalse(s.contains("ms"))
        }
        XCTAssertEqual(Format.ping(14.2), " 14")
    }
}

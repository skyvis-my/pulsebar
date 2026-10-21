import XCTest
@testable import Pulsebar

/// The menu bar ping only moves when a reading is at least 5 ms and more than 10% away from what's shown.
@MainActor
final class SteadyPingTests: XCTestCase {
    func testSmallChangesHold() {
        XCTAssertEqual(Monitor.steadied(shown: 20, latest: 24), 20)   // 4 ms
        XCTAssertEqual(Monitor.steadied(shown: 12, latest: 16), 12)   // 33% but only 4 ms
        XCTAssertEqual(Monitor.steadied(shown: 5, latest: 6), 5)      // 20% but only 1 ms
        XCTAssertEqual(Monitor.steadied(shown: 100, latest: 109), 100) // 9 ms but only 9%
        XCTAssertEqual(Monitor.steadied(shown: 50, latest: 55), 50)   // 5 ms but exactly 10%
    }

    func testLargerChangesUpdate() {
        XCTAssertEqual(Monitor.steadied(shown: 20, latest: 25), 25)   // 5 ms, 25%
        XCTAssertEqual(Monitor.steadied(shown: 12, latest: 17), 17)
        XCTAssertEqual(Monitor.steadied(shown: 20, latest: 15), 15)
        XCTAssertEqual(Monitor.steadied(shown: 100, latest: 111), 111)
    }

    func testDriftEventuallyUpdates() {
        // Each step is small, but it updates once it's far enough from the shown value.
        var shown: Double? = 20
        for v in [21.0, 22.0, 23.0, 24.0, 25.0] { shown = Monitor.steadied(shown: shown, latest: v) }
        XCTAssertEqual(shown, 25)
    }

    func testTimeoutsAndRecoveryShowImmediately() {
        XCTAssertNil(Monitor.steadied(shown: 20, latest: nil))
        XCTAssertEqual(Monitor.steadied(shown: nil, latest: 20), 20)
    }
}

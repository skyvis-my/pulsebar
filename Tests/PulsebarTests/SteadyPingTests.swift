import XCTest
@testable import Pulsebar

/// The shown ping only moves when a reading is more than 10% away from what's on screen.
@MainActor
final class SteadyPingTests: XCTestCase {
    func testSmallChangesHold() {
        XCTAssertEqual(Monitor.steadied(shown: 20, latest: 21), 20)
        XCTAssertEqual(Monitor.steadied(shown: 20, latest: 18), 20)
        XCTAssertEqual(Monitor.steadied(shown: 20, latest: 22), 20) // exactly 10% holds
    }

    func testLargerChangesUpdate() {
        XCTAssertEqual(Monitor.steadied(shown: 20, latest: 23), 23)
        XCTAssertEqual(Monitor.steadied(shown: 20, latest: 17), 17)
        XCTAssertEqual(Monitor.steadied(shown: 5, latest: 6), 6) // 20% at low values
    }

    func testDriftEventuallyUpdates() {
        // Slow drift: each step is under 10%, but it updates once it's 10% past the shown value.
        var shown: Double? = 20
        for v in [21.0, 21.5, 22.0, 22.5] { shown = Monitor.steadied(shown: shown, latest: v) }
        XCTAssertEqual(shown, 22.5)
    }

    func testTimeoutsAndRecoveryShowImmediately() {
        XCTAssertNil(Monitor.steadied(shown: 20, latest: nil))
        XCTAssertEqual(Monitor.steadied(shown: nil, latest: 20), 20)
    }
}

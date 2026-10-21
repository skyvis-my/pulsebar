import XCTest
@testable import Pulsebar

/// The guards decide when "keep running with lid closed" must hand control back to normal sleep.
final class KeepAwakeTests: XCTestCase {
    func testLowBatteryStopsOnlyOnBattery() {
        XCTAssertEqual(KeepAwake.stopReason(onBattery: true, batteryPercent: 20, thermal: .nominal), .lowBattery(20))
        XCTAssertEqual(KeepAwake.stopReason(onBattery: true, batteryPercent: 5, thermal: .nominal), .lowBattery(5))
        XCTAssertNil(KeepAwake.stopReason(onBattery: true, batteryPercent: 21, thermal: .nominal))
        // Charging at 10% is fine: the battery is going up.
        XCTAssertNil(KeepAwake.stopReason(onBattery: false, batteryPercent: 10, thermal: .nominal))
        // Desktop Macs report no battery.
        XCTAssertNil(KeepAwake.stopReason(onBattery: false, batteryPercent: nil, thermal: .nominal))
    }

    func testHeatStopsAtSeriousOrWorse() {
        XCTAssertNil(KeepAwake.stopReason(onBattery: false, batteryPercent: 80, thermal: .fair))
        XCTAssertEqual(KeepAwake.stopReason(onBattery: false, batteryPercent: 80, thermal: .serious), .hot)
        XCTAssertEqual(KeepAwake.stopReason(onBattery: true, batteryPercent: 80, thermal: .critical), .hot)
    }

    func testNotes() {
        XCTAssertEqual(KeepAwake.StopReason.lowBattery(18).offNote, "Turned off at 18% battery.")
        XCTAssertEqual(KeepAwake.StopReason.lowBattery(18).blockedNote, "Battery is at 18%. Charge above 20% first.")
    }
}

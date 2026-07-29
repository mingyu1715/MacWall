import CoreGraphics
import SwiftUI
import XCTest
@testable import MacWallApp

final class MenuBarBrandIconTests: XCTestCase {
    func testMarkUsesOneTransparentTrackpadOpening() {
        let path = MacWallMenuBarMark().path(
            in: CGRect(x: 0, y: 0, width: 656, height: 458)
        )

        XCTAssertTrue(path.contains(CGPoint(x: 328, y: 427), eoFill: true))
        XCTAssertFalse(path.contains(CGPoint(x: 328, y: 441), eoFill: true))
    }
}

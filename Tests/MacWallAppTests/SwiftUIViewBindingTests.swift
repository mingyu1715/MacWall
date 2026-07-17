import XCTest

final class SwiftUIViewBindingTests: XCTestCase {
    func testSwiftUIControlsDeferModelWritesOutsideViewUpdates() throws {
        // Given
        let helperSource = try SourceFixture.contents(of: "Sources/MacWallApp/UI/ViewDeferredBinding.swift")
        let contentViewSource = try SourceFixture.contents(of: "Sources/MacWallApp/UI/ContentView.swift")
        let statusMenuSource = try SourceFixture.contents(of: "Sources/MacWallApp/UI/StatusMenu.swift")

        // Then
        XCTAssertTrue(helperSource.contains("func viewDeferredBinding"))
        XCTAssertTrue(helperSource.contains("Task { @MainActor"))
        XCTAssertTrue(contentViewSource.contains("selection: viewDeferredBinding"))
        XCTAssertTrue(contentViewSource.contains("isOn: viewDeferredBinding"))
        XCTAssertTrue(contentViewSource.contains("selection: viewDeferredBinding"))
        XCTAssertTrue(statusMenuSource.contains("isOn: viewDeferredBinding"))
        XCTAssertFalse(contentViewSource.contains("isOn: $model."))
        XCTAssertFalse(contentViewSource.contains("selection: $model."))
        XCTAssertFalse(contentViewSource.contains("selection: Binding("))
        XCTAssertFalse(statusMenuSource.contains("isOn: $model."))
    }
}

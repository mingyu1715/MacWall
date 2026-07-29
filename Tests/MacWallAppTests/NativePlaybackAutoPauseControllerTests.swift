import XCTest
@testable import MacWallApp

@MainActor
final class NativePlaybackAutoPauseControllerTests: XCTestCase {
    func testCoveredDesktopSuspendsAfter200Milliseconds() {
        let harness = makeHarness(desktopVisible: false)
        harness.controller.setNativePlaybackActive(true)

        harness.scheduler.advance(by: .milliseconds(199))
        XCTAssertTrue(harness.publishedStates.values.isEmpty)

        harness.scheduler.advance(by: .milliseconds(1))
        XCTAssertEqual(harness.publishedStates.values, [true])
    }

    func testRapidVisibilityChangeCancelsStaleCoveredState() {
        let harness = makeHarness(desktopVisible: false)
        harness.controller.setNativePlaybackActive(true)
        harness.scheduler.advance(by: .milliseconds(100))

        harness.visibility.value = true
        harness.controller.pollVisibility()
        harness.scheduler.advance(by: .milliseconds(200))

        XCTAssertTrue(harness.publishedStates.values.isEmpty)
    }

    func testSleepSuspendsImmediatelyAndWakeReevaluatesAfter500Milliseconds() {
        let harness = makeHarness(desktopVisible: true)
        harness.controller.setNativePlaybackActive(true)
        harness.scheduler.advance(by: .milliseconds(200))

        harness.controller.handleWillSleep()
        XCTAssertEqual(harness.publishedStates.values, [true])

        harness.controller.handleDidWake()
        harness.scheduler.advance(by: .milliseconds(499))
        XCTAssertEqual(harness.publishedStates.values, [true])

        harness.scheduler.advance(by: .milliseconds(1))
        XCTAssertEqual(harness.publishedStates.values, [true, false])
    }

    func testDisablingOptionImmediatelyResumesAndIgnoresCoverage() {
        let harness = makeHarness(desktopVisible: false)
        harness.controller.setNativePlaybackActive(true)
        harness.scheduler.advance(by: .milliseconds(200))
        XCTAssertEqual(harness.publishedStates.values, [true])

        harness.controller.setEnabled(false)
        XCTAssertEqual(harness.publishedStates.values, [true, false])

        harness.controller.pollVisibility()
        harness.scheduler.advance(by: .milliseconds(200))
        XCTAssertEqual(harness.publishedStates.values, [true, false])
    }

    func testInactiveNativePlaybackDoesNotPublishControl() {
        let harness = makeHarness(desktopVisible: false)

        harness.controller.pollVisibility()
        harness.controller.handleWillSleep()
        harness.scheduler.advance(by: .milliseconds(500))

        XCTAssertTrue(harness.publishedStates.values.isEmpty)
    }

    private func makeHarness(desktopVisible: Bool) -> Harness {
        let scheduler = TestNativeAutoPauseScheduler()
        let visibility = MutableDesktopVisibility(value: desktopVisible)
        let publishedStates = PublishedStates()
        let controller = NativePlaybackAutoPauseController(
            enabled: true,
            scheduler: scheduler,
            isDesktopVisible: { visibility.value },
            automaticallyMonitorsLifecycle: false,
            publishSuspended: { publishedStates.values.append($0) }
        )
        return Harness(
            controller: controller,
            scheduler: scheduler,
            visibility: visibility,
            publishedStates: publishedStates
        )
    }
}

@MainActor
private struct Harness {
    let controller: NativePlaybackAutoPauseController
    let scheduler: TestNativeAutoPauseScheduler
    let visibility: MutableDesktopVisibility
    let publishedStates: PublishedStates
}

@MainActor
private final class MutableDesktopVisibility {
    var value: Bool

    init(value: Bool) {
        self.value = value
    }
}

@MainActor
private final class PublishedStates {
    var values: [Bool] = []
}

@MainActor
private final class TestNativeAutoPauseScheduler: PlaybackScheduling {
    private struct Entry {
        let id: Int
        let deadline: TimeInterval
        let operation: @MainActor () -> Void
    }

    private var now: TimeInterval = 0
    private var nextID = 0
    private var entries: [Entry] = []
    private var cancelled: Set<Int> = []

    @discardableResult
    func schedule(
        after delay: PlaybackDelay,
        _ operation: @escaping @MainActor () -> Void
    ) -> PlaybackScheduledTask {
        nextID += 1
        let id = nextID
        entries.append(
            Entry(
                id: id,
                deadline: now + delay.seconds,
                operation: operation
            )
        )
        return PlaybackScheduledTask { [weak self] in
            self?.cancelled.insert(id)
        }
    }

    func advance(by delay: PlaybackDelay) {
        now += delay.seconds
        let ready = entries
            .filter { $0.deadline <= now }
            .sorted { $0.deadline < $1.deadline }
        entries.removeAll { $0.deadline <= now }
        ready
            .filter { !cancelled.contains($0.id) }
            .forEach { $0.operation() }
    }
}

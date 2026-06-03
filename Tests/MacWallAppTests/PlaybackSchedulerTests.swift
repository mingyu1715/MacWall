import XCTest
@testable import MacWallApp

@MainActor
final class PlaybackSchedulerTests: XCTestCase {
    func testScreenChangeDebounceFiresAfter300Milliseconds() {
        let scheduler = TestPlaybackScheduler()
        var fired = 0

        scheduler.schedule(after: .milliseconds(300)) {
            fired += 1
        }

        scheduler.advance(by: .milliseconds(299))
        XCTAssertEqual(fired, 0)

        scheduler.advance(by: .milliseconds(1))
        XCTAssertEqual(fired, 1)
    }

    func testWakeDebounceFiresAfter500Milliseconds() {
        let scheduler = TestPlaybackScheduler()
        var fired = 0

        scheduler.schedule(after: .milliseconds(500)) {
            fired += 1
        }

        scheduler.advance(by: .milliseconds(499))
        XCTAssertEqual(fired, 0)

        scheduler.advance(by: .milliseconds(1))
        XCTAssertEqual(fired, 1)
    }

    func testVisibilityDebounceFiresAfter200Milliseconds() {
        let scheduler = TestPlaybackScheduler()
        var fired = 0

        scheduler.schedule(after: .milliseconds(200)) {
            fired += 1
        }

        scheduler.advance(by: .milliseconds(199))
        XCTAssertEqual(fired, 0)

        scheduler.advance(by: .milliseconds(1))
        XCTAssertEqual(fired, 1)
    }

    func testCancelPreventsStaleScheduledTask() {
        let scheduler = TestPlaybackScheduler()
        var fired = 0

        let task = scheduler.schedule(after: .milliseconds(300)) {
            fired += 1
        }
        task.cancel()
        scheduler.advance(by: .milliseconds(300))

        XCTAssertEqual(fired, 0)
    }
}

@MainActor
private final class TestPlaybackScheduler: PlaybackScheduling {
    private struct Entry {
        let id: Int
        let deadline: TimeInterval
        let operation: @MainActor () -> Void
    }

    private var now: TimeInterval = 0
    private var nextId = 0
    private var entries: [Entry] = []
    private var cancelled: Set<Int> = []

    @discardableResult
    func schedule(
        after delay: PlaybackDelay,
        _ operation: @escaping @MainActor () -> Void
    ) -> PlaybackScheduledTask {
        nextId += 1
        let id = nextId
        entries.append(Entry(id: id, deadline: now + delay.seconds, operation: operation))
        return PlaybackScheduledTask { [weak self] in
            self?.cancelled.insert(id)
        }
    }

    func advance(by delay: PlaybackDelay) {
        now += delay.seconds
        let ready = entries.filter { $0.deadline <= now }
        entries.removeAll { $0.deadline <= now }
        ready.filter { !cancelled.contains($0.id) }.forEach { $0.operation() }
    }
}

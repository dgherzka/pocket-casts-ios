import XCTest

@testable import podcasts

final class PlaybackPositionHistoryTests: XCTestCase {
    private typealias Sample = PlaybackPositionHistory.Sample

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// One sample a second from `from` for `count` seconds, advancing `perSecond` seconds of the episode each second
    private func samples(count: Int, from position: TimeInterval, perSecond: TimeInterval, rate: Double, startingAt date: Date) -> [Sample] {
        (0..<count).map { index in
            Sample(date: date.addingTimeInterval(TimeInterval(index)), position: position + perSecond * TimeInterval(index), rate: rate)
        }
    }

    private func startPosition(_ listening: TimeInterval, history: [Sample], now: Sample) -> TimeInterval {
        PlaybackPositionHistory.startPosition(forLast: listening, endingAt: now, history: history)
    }

    // MARK: - Calculation

    func testNormalSpeedGoesBackTheSameAmountOfTheEpisode() {
        let history = samples(count: 30, from: 100, perSecond: 1, rate: 1, startingAt: start)
        let now = Sample(date: start.addingTimeInterval(30), position: 130, rate: 1)

        XCTAssertEqual(startPosition(10, history: history, now: now), 120, accuracy: 0.001)
    }

    func testDoubleSpeedCoversTwiceAsMuchOfTheEpisode() {
        let history = samples(count: 30, from: 100, perSecond: 2, rate: 2, startingAt: start)
        let now = Sample(date: start.addingTimeInterval(30), position: 160, rate: 2)

        XCTAssertEqual(startPosition(10, history: history, now: now), 140, accuracy: 0.001)
    }

    func testTrimSilenceUsesTheRecordedPositionsRatherThanTheSpeed() {
        // At 1x with silences trimmed, the episode moves 1.5 s for every second of listening
        let history = samples(count: 30, from: 100, perSecond: 1.5, rate: 1, startingAt: start)
        let now = Sample(date: start.addingTimeInterval(30), position: 145, rate: 1)

        XCTAssertEqual(startPosition(10, history: history, now: now), 130, accuracy: 0.001)
    }

    func testPausesDontCountAsListening() {
        // 20 seconds of listening, a 5 minute pause, then 4 more seconds of listening
        let beforePause = samples(count: 20, from: 100, perSecond: 1, rate: 1, startingAt: start)
        let resumed = start.addingTimeInterval(19 + 300)
        let afterPause = samples(count: 4, from: 120, perSecond: 1, rate: 1, startingAt: resumed)
        let now = Sample(date: resumed.addingTimeInterval(4), position: 124, rate: 1)

        XCTAssertEqual(startPosition(10, history: beforePause + afterPause, now: now), 114, accuracy: 0.001)
    }

    func testPressingWhilePausedKeepsWhatWasHeardBeforeThePause() {
        let history = samples(count: 30, from: 100, perSecond: 1, rate: 1, startingAt: start)
        let now = Sample(date: start.addingTimeInterval(29 + 600), position: 129, rate: 1)

        XCTAssertEqual(startPosition(10, history: history, now: now), 119, accuracy: 0.001)
    }

    func testStopsAtASkipBack() {
        // Listened from 100 to 130, skipped back to 115, then listened for 3 seconds
        let beforeSkip = samples(count: 31, from: 100, perSecond: 1, rate: 1, startingAt: start)
        let afterSkip = samples(count: 3, from: 115, perSecond: 1, rate: 1, startingAt: start.addingTimeInterval(31))
        let now = Sample(date: start.addingTimeInterval(34), position: 118, rate: 1)

        XCTAssertEqual(startPosition(10, history: beforeSkip + afterSkip, now: now), 115, accuracy: 0.001)
    }

    func testStopsAtASkipForward() {
        // Listened from 100 to 120, skipped forward 30 seconds, then listened for 4 seconds
        let beforeSkip = samples(count: 21, from: 100, perSecond: 1, rate: 1, startingAt: start)
        let afterSkip = samples(count: 4, from: 151, perSecond: 1, rate: 1, startingAt: start.addingTimeInterval(21))
        let now = Sample(date: start.addingTimeInterval(25), position: 155, rate: 1)

        XCTAssertEqual(startPosition(10, history: beforeSkip + afterSkip, now: now), 151, accuracy: 0.001)
    }

    func testFallsBackToTheSpeedWhenTheHistoryIsTooShort() {
        // Only 3 seconds of history at 1.5x: the other 7 seconds are approximated with the speed
        let history = samples(count: 3, from: 200, perSecond: 1.5, rate: 1.5, startingAt: start)
        let now = Sample(date: start.addingTimeInterval(3), position: 204.5, rate: 1.5)

        XCTAssertEqual(startPosition(10, history: history, now: now), 204.5 - 15, accuracy: 0.001)
    }

    func testWithoutHistoryUsesTheSpeed() {
        let now = Sample(date: start, position: 300, rate: 2)

        XCTAssertEqual(startPosition(10, history: [], now: now), 280, accuracy: 0.001)
    }

    func testNeverGoesBeforeTheStartOfTheEpisode() {
        let now = Sample(date: start, position: 4, rate: 1)

        XCTAssertEqual(startPosition(10, history: [], now: now), 0)
    }

    func testInterpolatesBetweenSamples() {
        let history = [
            Sample(date: start, position: 100, rate: 1),
            Sample(date: start.addingTimeInterval(4), position: 104, rate: 1)
        ]
        let now = Sample(date: start.addingTimeInterval(8), position: 108, rate: 1)

        XCTAssertEqual(startPosition(5.5, history: history, now: now), 102.5, accuracy: 0.001)
    }

    // MARK: - History

    func testRecordingAnotherEpisodeStartsANewHistory() {
        let history = PlaybackPositionHistory()
        history.record(episodeUuid: "first", position: 10, rate: 1, at: start)
        history.record(episodeUuid: "first", position: 11, rate: 1, at: start.addingTimeInterval(1))
        history.record(episodeUuid: "second", position: 50, rate: 1, at: start.addingTimeInterval(2))

        XCTAssertEqual(history.samples(forEpisode: "first"), [])
        XCTAssertEqual(history.samples(forEpisode: "second"), [Sample(date: start.addingTimeInterval(2), position: 50, rate: 1)])
    }

    func testHistoryKeepsOnlyTheMostRecentSamples() {
        let history = PlaybackPositionHistory()
        let count = PlaybackPositionHistory.maximumSampleCount + 20
        for index in 0..<count {
            history.record(episodeUuid: "episode", position: TimeInterval(index), rate: 1, at: start.addingTimeInterval(TimeInterval(index)))
        }

        let samples = history.samples(forEpisode: "episode")
        XCTAssertEqual(samples.count, PlaybackPositionHistory.maximumSampleCount)
        XCTAssertEqual(samples.first?.position, 20)
        XCTAssertEqual(samples.last?.position, TimeInterval(count - 1))
    }

    func testResetClearsTheHistory() {
        let history = PlaybackPositionHistory()
        history.record(episodeUuid: "episode", position: 10, rate: 1, at: start)
        history.reset()

        XCTAssertEqual(history.samples(forEpisode: "episode"), [])
    }
}

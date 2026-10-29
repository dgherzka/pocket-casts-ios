import Foundation

/// A short in-memory history of where in the episode the listener was, sampled by
/// `PlaybackManager` about once a second while audio is actually playing.
///
/// Highlights keep "the last N seconds of listening". Because of the playback speed and Trim
/// Silence, N seconds of listening covers more than N seconds of the episode, by an amount that
/// changes as silences are trimmed. Rather than approximating it with the playback speed, the
/// history records pairs of (clock time, episode position) and walks back through them, so the
/// start of a highlight is where the listener really was N seconds of listening ago. The speed is
/// only used for the part of the window that's older than the history, such as right after
/// playback starts.
///
/// Thread safe: samples are recorded from the playback timer and read when a highlight is made.
final class PlaybackPositionHistory {
    struct Sample: Equatable {
        /// The clock time of the sample
        let date: Date
        /// The playback position, in the episode's own time
        let position: TimeInterval
        /// The playback speed
        let rate: Double
    }

    /// Enough for the longest highlight (60 seconds of listening) with room for buffering and pauses
    static let maximumSampleCount = 180

    private let lock = NSLock()
    private var episodeUuid: String?
    private var samples: [Sample] = []

    /// Adds a sample. Switching to another episode starts a new history.
    func record(episodeUuid: String, position: TimeInterval, rate: Double, at date: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }

        if self.episodeUuid != episodeUuid {
            self.episodeUuid = episodeUuid
            samples.removeAll()
        }

        samples.append(Sample(date: date, position: position, rate: rate))

        if samples.count > Self.maximumSampleCount {
            samples.removeFirst(samples.count - Self.maximumSampleCount)
        }
    }

    /// The samples for the given episode, oldest first, or none if another episode was sampled last
    func samples(forEpisode episodeUuid: String) -> [Sample] {
        lock.lock()
        defer { lock.unlock() }

        return self.episodeUuid == episodeUuid ? samples : []
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }

        episodeUuid = nil
        samples.removeAll()
    }

    // MARK: - Last N seconds of listening

    /// Positions can wobble slightly between samples; anything further back than this is a seek
    private static let backwardSeekTolerance: TimeInterval = 0.5

    /// Returns where in the episode the last `listening` seconds of listening began.
    ///
    /// Walks back from `now` through `history` (oldest first), adding up the time the listener
    /// actually spent listening between each pair of samples. Time spent paused or buffering
    /// doesn't count: between two samples the listening time is the clock time, but never more
    /// than the episode time that passed divided by the speed.
    ///
    /// The result is a single passage of the episode, so it stops at a seek: if the listener
    /// skipped since then, the highlight starts where they skipped to. A seek forward made while
    /// paused can't be told apart from the pause and isn't detected.
    ///
    /// - Parameters:
    ///   - listening: The seconds of listening to go back
    ///   - now: The current position, clock time and speed
    ///   - history: Earlier samples, oldest first
    /// - Returns: The start position, between 0 and `now.position`
    static func startPosition(forLast listening: TimeInterval, endingAt now: Sample, history: [Sample]) -> TimeInterval {
        var remaining = listening
        var newer = now

        func clamped(_ position: TimeInterval) -> TimeInterval {
            min(max(position, 0), max(now.position, 0))
        }

        guard remaining > 0 else { return clamped(now.position) }

        for older in history.reversed() {
            let clockTime = max(newer.date.timeIntervalSince(older.date), 0)
            let episodeTime = newer.position - older.position
            let rate = max(newer.rate, 0.1)

            // A skip back, or a jump forward that's far more than playback could cover
            let isBackwardSeek = episodeTime < -backwardSeekTolerance
            let isForwardSeek = episodeTime > clockTime * max(rate, 1) * 3 + 2
            if isBackwardSeek || isForwardSeek {
                return clamped(newer.position)
            }

            let episodeTimeCovered = max(episodeTime, 0)
            let listened = min(clockTime, episodeTimeCovered / rate)

            if listened > 0, listened >= remaining {
                // The window began between these two samples
                return clamped(newer.position - episodeTimeCovered * (remaining / listened))
            }

            remaining -= listened
            newer = older
        }

        // The history doesn't go back far enough, so approximate the rest with the speed
        return clamped(newer.position - remaining * max(newer.rate, 0.1))
    }
}

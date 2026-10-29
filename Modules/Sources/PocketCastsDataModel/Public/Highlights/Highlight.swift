import Foundation

/// A passage of an episode the listener marked while listening.
///
/// All times are positions in the episode's own audio file, the same timeline as the
/// playback position, so they don't depend on the playback speed or Trim Silence.
/// Highlights are stored on this device only and are never synced.
public struct Highlight: Identifiable, Equatable {
    public let uuid: String

    public var id: String { uuid }

    public let episodeUuid: String
    /// `nil` for the listener's own files
    public let podcastUuid: String?

    /// The titles when the highlight was made, so it can be shown and exported even if the
    /// episode is later removed from the database
    public let podcastTitle: String?
    public let episodeTitle: String?

    /// Where the highlight begins in the episode
    public let startTime: TimeInterval
    /// The playback position when the control was pressed
    public let pressTime: TimeInterval
    /// Where the highlight ends in the episode: the position when the control was let go
    public let endTime: TimeInterval

    /// The clock time the control was pressed
    public let created: Date
    /// The identifier of the time zone the listener was in when it was made
    public let timeZoneIdentifier: String

    /// The playback speed and whether Trim Silence was on when it was made
    public let playbackSpeed: Double
    public let trimSilence: Bool

    /// How many seconds of listening before the press the highlight keeps
    public let lookBack: TimeInterval
    /// How long the control was held, in seconds. 0 when it was only pressed.
    public let heldDuration: TimeInterval

    public var note: String?

    public init(
        uuid: String = UUID().uuidString.lowercased(),
        episodeUuid: String,
        podcastUuid: String?,
        podcastTitle: String?,
        episodeTitle: String?,
        startTime: TimeInterval,
        pressTime: TimeInterval,
        endTime: TimeInterval,
        created: Date,
        timeZoneIdentifier: String,
        playbackSpeed: Double,
        trimSilence: Bool,
        lookBack: TimeInterval,
        heldDuration: TimeInterval,
        note: String? = nil
    ) {
        self.uuid = uuid
        self.episodeUuid = episodeUuid
        self.podcastUuid = podcastUuid
        self.podcastTitle = podcastTitle
        self.episodeTitle = episodeTitle
        self.startTime = startTime
        self.pressTime = pressTime
        self.endTime = endTime
        self.created = created
        self.timeZoneIdentifier = timeZoneIdentifier
        self.playbackSpeed = playbackSpeed
        self.trimSilence = trimSilence
        self.lookBack = lookBack
        self.heldDuration = heldDuration
        self.note = note
    }

    /// The time zone the highlight was made in, falling back to the current one
    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }
}

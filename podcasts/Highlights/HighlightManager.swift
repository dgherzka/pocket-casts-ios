import AVFoundation
import Foundation
import PocketCastsDataModel
import PocketCastsUtils
import UIKit

/// Makes, edits and plays highlights: passages of an episode the listener marked while listening.
///
/// A press keeps the last `Settings.highlightLookBackSeconds` seconds of listening, ending at the
/// press. Where the control can be held, as in the full screen player, the highlight keeps going
/// until it's let go: call `beginHighlight` when it's pressed and `endHighlight` when it's let go.
///
/// Highlights aren't a paid feature and are stored on this device only.
final class HighlightManager {
    static let shared = HighlightManager()

    /// Posted on the main thread when highlights are added, edited or deleted
    static let highlightsChangedNotification = Notification.Name("PCHighlightsChanged")

    enum Source: String, AnalyticsDescribable {
        case player
        case overflowMenu = "overflow_menu"
        case headphones

        var analyticsDescription: String { rawValue }
    }

    private let dataManager: DataManager
    private let playbackManager: PlaybackManager

    private let lock = NSLock()
    private var pendingHighlight: PendingHighlight?

    init(dataManager: DataManager = .shared, playbackManager: PlaybackManager = .shared) {
        self.dataManager = dataManager
        self.playbackManager = playbackManager
    }

    // MARK: - Making highlights

    /// Makes a highlight of the last few seconds of listening, ending now
    @discardableResult
    func addHighlight(source: Source) -> Highlight? {
        guard let pending = capturePress(source: source) else { return nil }

        return finish(pending, releasedAt: pending.pressDate, endPosition: pending.pressPosition)
    }

    /// Starts a highlight when the control is pressed. It's saved by `endHighlight`.
    func beginHighlight(source: Source) {
        let pending = capturePress(source: source)

        lock.lock()
        pendingHighlight = pending
        lock.unlock()
    }

    /// Whether `beginHighlight` started a highlight that hasn't been saved yet
    var hasPendingHighlight: Bool {
        lock.lock()
        defer { lock.unlock() }

        return pendingHighlight != nil
    }

    /// Saves the highlight started by `beginHighlight`, ending at the current position
    @discardableResult
    func endHighlight() -> Highlight? {
        lock.lock()
        let pending = pendingHighlight
        pendingHighlight = nil
        lock.unlock()

        guard let pending else { return nil }

        // If the episode changed while the control was held, end the highlight at the press
        let isSameEpisode = playbackManager.isCurrentEpisode(uuid: pending.episode.uuid)
        let endPosition = isSameEpisode ? playbackManager.currentTime : pending.pressPosition

        return finish(pending, releasedAt: Date(), endPosition: endPosition)
    }

    /// Everything about the moment the control was pressed
    private struct PendingHighlight {
        let source: Source
        let episode: BaseEpisode
        let pressDate: Date
        let pressPosition: TimeInterval
        let startPosition: TimeInterval
        let playbackSpeed: Double
        let trimSilence: Bool
        let lookBack: TimeInterval
    }

    private func capturePress(source: Source) -> PendingHighlight? {
        guard let episode = playbackManager.currentEpisode else { return nil }

        let position = playbackManager.currentTime
        guard position >= 0 else { return nil }

        let pressDate = Date()
        let effects = playbackManager.effects
        let lookBack = TimeInterval(Settings.highlightLookBackSeconds)

        let now = PlaybackPositionHistory.Sample(date: pressDate, position: position, rate: effects.playbackSpeed)
        let history = playbackManager.listeningHistory.samples(forEpisode: episode.uuid)
        let start = PlaybackPositionHistory.startPosition(forLast: lookBack, endingAt: now, history: history)

        return PendingHighlight(
            source: source,
            episode: episode,
            pressDate: pressDate,
            pressPosition: position,
            startPosition: start,
            playbackSpeed: effects.playbackSpeed,
            trimSilence: effects.trimSilence != .off,
            lookBack: lookBack
        )
    }

    private func finish(_ pending: PendingHighlight, releasedAt releaseDate: Date, endPosition: TimeInterval) -> Highlight? {
        let episode = pending.episode
        let podcastEpisode = episode as? Episode

        let highlight = Highlight(
            episodeUuid: episode.uuid,
            podcastUuid: podcastEpisode?.podcastUuid,
            podcastTitle: podcastEpisode?.parentPodcast(dataManager: dataManager)?.title,
            episodeTitle: episode.title,
            startTime: min(pending.startPosition, endPosition),
            pressTime: pending.pressPosition,
            endTime: max(endPosition, pending.startPosition),
            created: pending.pressDate,
            timeZoneIdentifier: TimeZone.current.identifier,
            playbackSpeed: pending.playbackSpeed,
            trimSilence: pending.trimSilence,
            lookBack: pending.lookBack,
            heldDuration: max(releaseDate.timeIntervalSince(pending.pressDate), 0)
        )

        guard dataManager.highlights.add(highlight) else {
            FileLog.shared.addMessage("[Highlights] Failed to save a highlight for \(episode.uuid)")
            return nil
        }

        FileLog.shared.addMessage("[Highlights] Saved \(highlight.startTime)-\(highlight.endTime) for \(episode.uuid) from \(pending.source.rawValue)")
        Analytics.track(.highlightCreated, properties: [
            "source": pending.source.analyticsDescription,
            "held": highlight.heldDuration > 0.5
        ])

        if pending.source == .headphones {
            playTone()
        }

        let message = L10n.highlightSaved(HighlightFormatter.range(start: highlight.startTime, end: highlight.endTime))
        Task { @MainActor in
            NotificationCenter.default.post(name: HighlightManager.highlightsChangedNotification, object: nil)

            guard UIApplication.shared.applicationState == .active else { return }
            Toast.show(message, theme: .playerTheme)
        }

        return highlight
    }

    // MARK: - Editing

    func highlights(forEpisode episodeUuid: String? = nil) -> [Highlight] {
        if let episodeUuid {
            return dataManager.highlights.highlights(forEpisode: episodeUuid)
        }

        return dataManager.highlights.allHighlights()
    }

    func highlightCount(forEpisode episodeUuid: String) -> Int {
        dataManager.highlights.highlightCount(forEpisode: episodeUuid)
    }

    func update(note: String?, for highlight: Highlight) {
        guard dataManager.highlights.update(note: note, forHighlight: highlight.uuid) else { return }

        Analytics.track(.highlightNoteUpdated)
        postChanged()
    }

    func delete(_ highlights: [Highlight]) {
        guard dataManager.highlights.delete(highlights: highlights) else { return }

        Analytics.track(.highlightDeleted, properties: ["count": highlights.count])
        postChanged()
    }

    private func postChanged() {
        Task { @MainActor in
            NotificationCenter.default.post(name: HighlightManager.highlightsChangedNotification, object: nil)
        }
    }

    // MARK: - Playing

    enum PlayError: Error {
        case episodeNotFound
    }

    /// Plays the highlight's episode from the highlight's start
    @MainActor
    func play(_ highlight: Highlight) throws {
        guard let episode = dataManager.findBaseEpisode(uuid: highlight.episodeUuid) else {
            throw PlayError.episodeNotFound
        }

        Analytics.track(.highlightPlayTapped)

        if playbackManager.isCurrentEpisode(uuid: highlight.episodeUuid) {
            playbackManager.seekTo(time: highlight.startTime, startPlaybackAfterSeek: true)
            return
        }

        // Save the position before playing so the player starts there when it loads, as bookmarks do
        dataManager.saveEpisode(playedUpTo: highlight.startTime, episode: episode, updateSyncFlag: false)
        dataManager.saveEpisode(playingStatus: .inProgress, episode: episode, updateSyncFlag: false)
        PlaybackActionHelper.play(episode: episode, podcastUuid: highlight.podcastUuid)
    }

    // MARK: - Confirmation tone

    /// Lets the listener know a highlight made with the headphones was saved, as bookmarks do
    private lazy var tonePlayer: AVAudioPlayer? = {
        guard let url = Bundle.main.url(forResource: "bookmark-creation-sound", withExtension: "wav") else {
            return nil
        }

        let player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = 0.5
        player?.prepareToPlay()
        return player
    }()

    private func playTone() {
        guard let tonePlayer else { return }

        tonePlayer.pause()
        tonePlayer.currentTime = 0
        tonePlayer.play()
    }
}

// MARK: - Settings

extension Settings {
    private static let highlightLookBackKey = "highlights.lookBackSeconds"

    static let highlightLookBackDefault = 10
    static let highlightLookBackRange = 5...60

    /// How many seconds of listening before the press a highlight keeps
    static var highlightLookBackSeconds: Int {
        get {
            let value = UserDefaults.standard.object(forKey: highlightLookBackKey) as? Int ?? highlightLookBackDefault
            return value.clamped(to: highlightLookBackRange)
        }
        set {
            UserDefaults.standard.set(newValue.clamped(to: highlightLookBackRange), forKey: highlightLookBackKey)
        }
    }
}

import Foundation
import PocketCastsDataModel

/// Formats positions in an episode as h:mm:ss
enum HighlightFormatter {
    /// Formats a position as h:mm:ss, rounding down to the second
    static func time(_ seconds: TimeInterval) -> String {
        clock(Int(max(seconds, 0).rounded(.down)))
    }

    /// Formats a position as h:mm:ss, rounding up to the second
    static func timeRoundedUp(_ seconds: TimeInterval) -> String {
        clock(Int(max(seconds, 0).rounded(.up)))
    }

    /// The range of a highlight, rounded outward to whole seconds so it always contains the passage
    static func range(start: TimeInterval, end: TimeInterval) -> String {
        "\(time(start))–\(timeRoundedUp(end))"
    }

    private static func clock(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%ld:%02ld:%02ld", hours, minutes, seconds)
    }
}

/// Builds a Markdown document of highlights that a listener can give to an LLM, together with the
/// episode's audio or a timestamped transcript, so it can find each passage.
///
/// The document is meant for a machine as much as a person, so it isn't localized: its wording
/// and structure stay the same whatever the app's language, and the data is repeated as JSON.
struct HighlightExporter {
    /// The highlights of one episode, with what's known about the episode
    struct EpisodeGroup {
        let episodeUuid: String
        let podcastUuid: String?
        let podcastTitle: String?
        let episodeTitle: String?
        let audioURL: String?
        let published: Date?
        let duration: TimeInterval?
        let highlights: [Highlight]
    }

    let exportDate: Date
    let timeZone: TimeZone

    init(exportDate: Date = Date(), timeZone: TimeZone = .current) {
        self.exportDate = exportDate
        self.timeZone = timeZone
    }

    // MARK: - Grouping

    /// Groups highlights by episode, with the most recently highlighted episode first, and looks up
    /// each episode for its audio URL, publish date and duration.
    static func groups(for highlights: [Highlight], dataManager: DataManager = .shared) -> [EpisodeGroup] {
        groups(for: highlights) { dataManager.findBaseEpisode(uuid: $0) }
    }

    static func groups(for highlights: [Highlight], episodeLookup: (String) -> BaseEpisode?) -> [EpisodeGroup] {
        var order: [String] = []
        var byEpisode: [String: [Highlight]] = [:]

        for highlight in highlights.sorted(by: { $0.created > $1.created }) {
            if byEpisode[highlight.episodeUuid] == nil {
                order.append(highlight.episodeUuid)
            }
            byEpisode[highlight.episodeUuid, default: []].append(highlight)
        }

        return order.compactMap { episodeUuid in
            guard let highlights = byEpisode[episodeUuid], let first = highlights.first else { return nil }

            let episode = episodeLookup(episodeUuid)
            let duration = episode?.duration ?? 0

            return EpisodeGroup(
                episodeUuid: episodeUuid,
                podcastUuid: first.podcastUuid,
                podcastTitle: first.podcastTitle,
                episodeTitle: first.episodeTitle ?? episode?.title,
                audioURL: episode?.downloadUrl,
                published: episode?.publishedDate,
                duration: duration > 0 ? duration : nil,
                highlights: highlights
            )
        }
    }

    // MARK: - File

    /// A file name for the export, such as "Highlights 2026-10-29.md"
    func fileName(for groups: [EpisodeGroup]) -> String {
        let title = groups.count == 1 ? (groups.first?.episodeTitle ?? "Episode") : "Highlights"
        let date = dateOnlyString(exportDate, timeZone: timeZone)
        let unsafeCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:\n\r\t")
        let safeTitle = title.components(separatedBy: unsafeCharacters).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return "\(String(safeTitle.prefix(80))) \(date).md"
    }

    // MARK: - Markdown

    func markdown(for groups: [EpisodeGroup]) -> String {
        var lines: [String] = []

        lines.append("# Pocket Casts highlights")
        lines.append("")
        lines.append("Exported \(isoString(exportDate, timeZone: timeZone)) from Pocket Casts for iOS: \(highlightCount(groups)) from \(episodeCount(groups)).")
        lines.append("")
        lines.append("## How to read this document")
        lines.append("")
        lines.append("Each highlight marks a passage of an episode that the listener wanted to find again. They're listed by episode, the most recently highlighted episode first, and within an episode in the order they occur in it.")
        lines.append("")
        lines.append("- **Times are positions in the episode's own audio file**, the file at the episode's audio URL, counted from the start of the file and written as h:mm:ss. They're exact: the playback speed and Trim Silence (which skips silences) don't change them.")
        lines.append("- A highlight starts where the listener was a set number of seconds of listening before pressing the highlight button, and ends where they let go of it (or at the press if they didn't hold it). At a faster speed or with Trim Silence on, those seconds of listening cover more of the episode's audio: 10 seconds of listening at 1.5× speed is 15 seconds of the episode. Each highlight gives both.")
        lines.append("- Listeners usually press just after hearing what they want to keep, so the important part tends to be near the end of the passage. Start and end are rounded outward to whole seconds; the JSON has them to the millisecond.")
        lines.append("- To find a passage in the audio, seek to its start and listen through to its end. In a timestamped transcript of the same file, take the lines whose timestamps fall between the start and the end, plus a few seconds either side.")
        lines.append("- If the publisher inserts ads dynamically, another download of the same episode can be offset from the file the listener heard by the length of the ads. Then use the note and the surrounding words to line the passage up.")
        lines.append("- \"Made at\" is the clock time of the press, in ISO 8601 with the listener's UTC offset. Notes are the listener's own words.")
        lines.append("- The same data is repeated as JSON at the end.")

        for group in groups {
            lines.append("")
            lines.append(contentsOf: markdown(for: group))
        }

        lines.append("")
        lines.append("## Data")
        lines.append("")
        lines.append("```json")
        lines.append(json(for: groups))
        lines.append("```")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    private func markdown(for group: EpisodeGroup) -> [String] {
        var lines: [String] = []

        let episodeTitle = group.episodeTitle ?? "Untitled episode"
        if let podcastTitle = group.podcastTitle {
            lines.append("## \(podcastTitle): \(episodeTitle)")
        } else {
            lines.append("## \(episodeTitle)")
        }
        lines.append("")
        lines.append("- Podcast: \(group.podcastTitle ?? "None (the listener's own file)")")
        lines.append("- Episode: \(episodeTitle)")
        lines.append("- Audio URL: \(group.audioURL ?? "Unknown")")
        let published = group.published.map { dateOnlyString($0, timeZone: utc) } ?? "Unknown"
        let duration = group.duration.map { HighlightFormatter.time($0) } ?? "Unknown"
        lines.append("- Published: \(published)")
        lines.append("- Duration: \(duration)")
        lines.append("- Pocket Casts episode ID: \(group.episodeUuid)")

        for (index, highlight) in sortedByPosition(group.highlights).enumerated() {
            lines.append("")
            lines.append("### Highlight \(index + 1): \(HighlightFormatter.range(start: highlight.startTime, end: highlight.endTime))")
            lines.append("")
            lines.append("- Passage: \(HighlightFormatter.time(highlight.startTime)) to \(HighlightFormatter.timeRoundedUp(highlight.endTime)) (\(seconds(highlight.endTime - highlight.startTime)) of the episode)")
            lines.append("- Made at: \(isoString(highlight.created, timeZone: highlight.timeZone))")
            lines.append("- Playback: \(speed(highlight.playbackSpeed))× speed, Trim Silence \(highlight.trimSilence ? "on" : "off")")
            lines.append("- Kept before the press: the last \(seconds(highlight.lookBack)) of listening, \(seconds(highlight.pressTime - highlight.startTime)) of the episode")
            if highlight.heldDuration >= 0.5 {
                lines.append("- Held: \(seconds(highlight.heldDuration)), adding \(seconds(highlight.endTime - highlight.pressTime)) of the episode after the press")
            } else {
                lines.append("- Held: no, it was a single press")
            }
            if let note = highlight.note, !note.isEmpty {
                lines.append("- Note: \(note.replacingOccurrences(of: "\n", with: " "))")
            } else {
                lines.append("- Note: none")
            }
        }

        return lines
    }

    // MARK: - JSON

    func json(for groups: [EpisodeGroup]) -> String {
        let document = JSONDocument(
            format: "pocket-casts-highlights",
            version: 1,
            exportedAt: isoString(exportDate, timeZone: timeZone),
            times: "Seconds from the start of the episode's audio file. Not affected by playback speed or Trim Silence.",
            episodes: groups.map { group in
                JSONEpisode(
                    episodeUuid: group.episodeUuid,
                    podcastUuid: group.podcastUuid,
                    podcastTitle: group.podcastTitle,
                    episodeTitle: group.episodeTitle,
                    audioUrl: group.audioURL,
                    published: group.published.map { isoString($0, timeZone: utc) },
                    durationSeconds: group.duration.map { milliseconds($0) },
                    highlights: sortedByPosition(group.highlights).map { highlight in
                        JSONHighlight(
                            uuid: highlight.uuid,
                            startSeconds: milliseconds(highlight.startTime),
                            endSeconds: milliseconds(highlight.endTime),
                            pressSeconds: milliseconds(highlight.pressTime),
                            start: HighlightFormatter.time(highlight.startTime),
                            end: HighlightFormatter.timeRoundedUp(highlight.endTime),
                            madeAt: isoString(highlight.created, timeZone: highlight.timeZone),
                            timeZone: highlight.timeZoneIdentifier,
                            playbackSpeed: highlight.playbackSpeed,
                            trimSilence: highlight.trimSilence,
                            listeningSecondsBeforePress: milliseconds(highlight.lookBack),
                            heldSeconds: milliseconds(highlight.heldDuration),
                            note: highlight.note
                        )
                    }
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        guard let data = try? encoder.encode(document), let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }

        return string
    }

    struct JSONDocument: Codable, Equatable {
        let format: String
        let version: Int
        let exportedAt: String
        let times: String
        let episodes: [JSONEpisode]
    }

    struct JSONEpisode: Codable, Equatable {
        let episodeUuid: String
        let podcastUuid: String?
        let podcastTitle: String?
        let episodeTitle: String?
        let audioUrl: String?
        let published: String?
        let durationSeconds: Double?
        let highlights: [JSONHighlight]
    }

    struct JSONHighlight: Codable, Equatable {
        let uuid: String
        let startSeconds: Double
        let endSeconds: Double
        let pressSeconds: Double
        let start: String
        let end: String
        let madeAt: String
        let timeZone: String
        let playbackSpeed: Double
        let trimSilence: Bool
        let listeningSecondsBeforePress: Double
        let heldSeconds: Double
        let note: String?
    }

    // MARK: - Helpers

    /// Publish dates are given in UTC, as they're the same everywhere
    private var utc: TimeZone {
        TimeZone(identifier: "UTC") ?? timeZone
    }

    private func sortedByPosition(_ highlights: [Highlight]) -> [Highlight] {
        highlights.sorted { ($0.startTime, $0.created) < ($1.startTime, $1.created) }
    }

    private func milliseconds(_ value: TimeInterval) -> Double {
        (value * 1000).rounded() / 1000
    }

    private func seconds(_ value: TimeInterval) -> String {
        let rounded = (max(value, 0) * 10).rounded() / 10
        let text = rounded == rounded.rounded() ? String(format: "%.0f", rounded) : String(format: "%.1f", rounded)
        return "\(text) s"
    }

    private func speed(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return rounded == rounded.rounded() ? String(format: "%.1f", rounded) : String(format: "%g", rounded)
    }

    private func highlightCount(_ groups: [EpisodeGroup]) -> String {
        let count = groups.reduce(0) { $0 + $1.highlights.count }
        return count == 1 ? "1 highlight" : "\(count) highlights"
    }

    private func episodeCount(_ groups: [EpisodeGroup]) -> String {
        groups.count == 1 ? "1 episode" : "\(groups.count) episodes"
    }

    private func isoString(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    private func dateOnlyString(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}

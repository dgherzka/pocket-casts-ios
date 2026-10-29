import XCTest

@testable import podcasts
@testable import PocketCastsDataModel

final class HighlightExporterTests: XCTestCase {
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

    /// 2023-11-14T22:13:20Z, which is 14:13:20 in Los Angeles
    private let pressDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeHighlight(
        uuid: String = UUID().uuidString,
        episodeUuid: String = "episode-1",
        start: TimeInterval = 723.4,
        press: TimeInterval = 738.4,
        end: TimeInterval = 738.4,
        created: Date? = nil,
        speed: Double = 1.5,
        trimSilence: Bool = true,
        held: TimeInterval = 0,
        note: String? = nil
    ) -> Highlight {
        Highlight(
            uuid: uuid,
            episodeUuid: episodeUuid,
            podcastUuid: "podcast-1",
            podcastTitle: "The Podcast",
            episodeTitle: "Episode \(episodeUuid)",
            startTime: start,
            pressTime: press,
            endTime: end,
            created: created ?? pressDate,
            timeZoneIdentifier: "America/Los_Angeles",
            playbackSpeed: speed,
            trimSilence: trimSilence,
            lookBack: 10,
            heldDuration: held,
            note: note
        )
    }

    private func makeEpisode(uuid: String) -> Episode {
        let episode = Episode()
        episode.uuid = uuid
        episode.title = "Episode \(uuid)"
        episode.downloadUrl = "https://example.com/\(uuid).mp3"
        episode.publishedDate = Date(timeIntervalSince1970: 1_699_000_000)
        episode.duration = 3723
        return episode
    }

    private var exporter: HighlightExporter {
        HighlightExporter(exportDate: pressDate.addingTimeInterval(3600), timeZone: losAngeles)
    }

    private func groups(_ highlights: [Highlight]) -> [HighlightExporter.EpisodeGroup] {
        HighlightExporter.groups(for: highlights) { [self] uuid in makeEpisode(uuid: uuid) }
    }

    private func jsonDocument(in markdown: String) throws -> HighlightExporter.JSONDocument {
        let start = try XCTUnwrap(markdown.range(of: "```json\n"), "the document should end with a JSON block")
        let end = try XCTUnwrap(markdown.range(of: "\n```", range: start.upperBound..<markdown.endIndex))
        let json = String(markdown[start.upperBound..<end.lowerBound])

        return try JSONDecoder().decode(HighlightExporter.JSONDocument.self, from: Data(json.utf8))
    }

    // MARK: - Formatting

    func testTimesAreFormattedAsHoursMinutesAndSeconds() {
        XCTAssertEqual(HighlightFormatter.time(0), "0:00:00")
        XCTAssertEqual(HighlightFormatter.time(59.9), "0:00:59")
        XCTAssertEqual(HighlightFormatter.time(3723.9), "1:02:03")
        XCTAssertEqual(HighlightFormatter.timeRoundedUp(3723.1), "1:02:04")
        XCTAssertEqual(HighlightFormatter.time(-5), "0:00:00")
    }

    func testRangeIsRoundedOutward() {
        XCTAssertEqual(HighlightFormatter.range(start: 723.4, end: 738.4), "0:12:03–0:12:19")
    }

    // MARK: - Grouping

    func testGroupsAreOrderedByTheMostRecentHighlight() {
        let older = makeHighlight(episodeUuid: "older", created: pressDate)
        let newer = makeHighlight(episodeUuid: "newer", created: pressDate.addingTimeInterval(60))
        let newest = makeHighlight(episodeUuid: "older", created: pressDate.addingTimeInterval(120))

        let result = groups([older, newer, newest])

        XCTAssertEqual(result.map(\.episodeUuid), ["older", "newer"])
        XCTAssertEqual(result.first?.highlights.map(\.uuid), [newest.uuid, older.uuid], "highlights should be newest first")
    }

    func testGroupsIncludeTheEpisodeDetails() throws {
        let group = try XCTUnwrap(groups([makeHighlight()]).first)

        XCTAssertEqual(group.audioURL, "https://example.com/episode-1.mp3")
        XCTAssertEqual(group.duration, 3723)
        XCTAssertEqual(group.podcastTitle, "The Podcast")
    }

    func testGroupsStillWorkWhenTheEpisodeIsGone() throws {
        let group = try XCTUnwrap(HighlightExporter.groups(for: [makeHighlight()]) { _ in nil }.first)

        XCTAssertNil(group.audioURL)
        XCTAssertNil(group.duration)
        XCTAssertEqual(group.episodeTitle, "Episode episode-1", "the title saved with the highlight should be used")
    }

    // MARK: - Markdown

    func testMarkdownExplainsTheTimesAndListsTheEpisode() {
        let markdown = exporter.markdown(for: groups([makeHighlight(note: "The key idea")]))

        XCTAssertTrue(markdown.contains("positions in the episode's own audio file"))
        XCTAssertTrue(markdown.contains("## The Podcast: Episode episode-1"))
        XCTAssertTrue(markdown.contains("- Audio URL: https://example.com/episode-1.mp3"))
        XCTAssertTrue(markdown.contains("- Published: 2023-11-03"))
        XCTAssertTrue(markdown.contains("- Duration: 1:02:03"))
    }

    func testMarkdownDescribesEachHighlight() {
        let markdown = exporter.markdown(for: groups([makeHighlight(end: 742.4, held: 4, note: "The key idea")]))

        XCTAssertTrue(markdown.contains("### Highlight 1: 0:12:03–0:12:23"))
        XCTAssertTrue(markdown.contains("- Made at: 2023-11-14T14:13:20-08:00"))
        XCTAssertTrue(markdown.contains("- Playback: 1.5× speed, Trim Silence on"))
        XCTAssertTrue(markdown.contains("- Kept before the press: the last 10 s of listening, 15 s of the episode"))
        XCTAssertTrue(markdown.contains("- Held: 4 s, adding 4 s of the episode after the press"))
        XCTAssertTrue(markdown.contains("- Note: The key idea"))
    }

    func testMarkdownSaysWhenAHighlightWasOnlyPressed() {
        let markdown = exporter.markdown(for: groups([makeHighlight(speed: 1, trimSilence: false)]))

        XCTAssertTrue(markdown.contains("- Held: no, it was a single press"))
        XCTAssertTrue(markdown.contains("- Playback: 1.0× speed, Trim Silence off"))
        XCTAssertTrue(markdown.contains("- Note: none"))
    }

    func testHighlightsAreListedInTheOrderTheyOccurInTheEpisode() throws {
        let later = makeHighlight(uuid: "later", start: 600, press: 610, end: 610, created: pressDate)
        let earlier = makeHighlight(uuid: "earlier", start: 100, press: 110, end: 110, created: pressDate.addingTimeInterval(60))

        let markdown = exporter.markdown(for: groups([later, earlier]))

        let earlierRange = try XCTUnwrap(markdown.range(of: "### Highlight 1: 0:01:40"))
        let laterRange = try XCTUnwrap(markdown.range(of: "### Highlight 2: 0:10:00"))
        XCTAssertLessThan(earlierRange.lowerBound, laterRange.lowerBound)
    }

    // MARK: - JSON

    func testMarkdownEndsWithTheSameDataAsJSON() throws {
        let highlight = makeHighlight(uuid: "highlight-1", end: 742.4, held: 4, note: "The key idea")
        let document = try jsonDocument(in: exporter.markdown(for: groups([highlight])))

        XCTAssertEqual(document.format, "pocket-casts-highlights")
        XCTAssertEqual(document.version, 1)
        XCTAssertEqual(document.exportedAt, "2023-11-14T15:13:20-08:00")

        let episode = try XCTUnwrap(document.episodes.first)
        XCTAssertEqual(episode.episodeUuid, "episode-1")
        XCTAssertEqual(episode.audioUrl, "https://example.com/episode-1.mp3")
        XCTAssertEqual(episode.durationSeconds, 3723)

        let exported = try XCTUnwrap(episode.highlights.first)
        XCTAssertEqual(exported.uuid, "highlight-1")
        XCTAssertEqual(exported.startSeconds, 723.4, accuracy: 0.0001)
        XCTAssertEqual(exported.endSeconds, 742.4, accuracy: 0.0001)
        XCTAssertEqual(exported.pressSeconds, 738.4, accuracy: 0.0001)
        XCTAssertEqual(exported.start, "0:12:03")
        XCTAssertEqual(exported.end, "0:12:23")
        XCTAssertEqual(exported.madeAt, "2023-11-14T14:13:20-08:00")
        XCTAssertEqual(exported.timeZone, "America/Los_Angeles")
        XCTAssertEqual(exported.playbackSpeed, 1.5)
        XCTAssertTrue(exported.trimSilence)
        XCTAssertEqual(exported.listeningSecondsBeforePress, 10)
        XCTAssertEqual(exported.heldSeconds, 4)
        XCTAssertEqual(exported.note, "The key idea")
    }

    func testJSONDoesNotEscapeTheAudioURL() {
        let json = exporter.json(for: groups([makeHighlight()]))

        XCTAssertTrue(json.contains("https://example.com/episode-1.mp3"))
    }

    // MARK: - File name

    func testFileNameUsesTheEpisodeTitleForASingleEpisode() {
        let highlight = makeHighlight(episodeUuid: "a/b:c")

        XCTAssertEqual(exporter.fileName(for: groups([highlight])), "Episode a b c 2023-11-14.md")
    }

    func testFileNameForSeveralEpisodes() {
        let highlights = [makeHighlight(episodeUuid: "one"), makeHighlight(episodeUuid: "two")]

        XCTAssertEqual(exporter.fileName(for: groups(highlights)), "Highlights 2023-11-14.md")
    }
}

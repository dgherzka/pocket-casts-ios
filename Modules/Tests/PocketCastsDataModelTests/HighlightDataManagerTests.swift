import GRDB
@testable import PocketCastsDataModel
@testable import PocketCastsUtils
import XCTest

/// Coverage for HighlightDataManager.
final class HighlightDataManagerTests: DataManagerTestCase {

    @discardableResult
    private func addHighlight(
        uuid: String = UUID().uuidString.lowercased(),
        episodeUuid: String = "episode-uuid",
        podcastUuid: String? = "podcast-uuid",
        start: TimeInterval = 100,
        end: TimeInterval = 110,
        created: Date = Date(),
        note: String? = nil,
        dataManager: DataManager
    ) -> Highlight {
        let highlight = Highlight(
            uuid: uuid,
            episodeUuid: episodeUuid,
            podcastUuid: podcastUuid,
            podcastTitle: "Podcast",
            episodeTitle: "Episode",
            startTime: start,
            pressTime: end,
            endTime: end,
            created: created,
            timeZoneIdentifier: "Europe/Paris",
            playbackSpeed: 1.5,
            trimSilence: true,
            lookBack: 10,
            heldDuration: 0,
            note: note
        )

        XCTAssertTrue(dataManager.highlights.add(highlight), "highlight should be saved")
        return highlight
    }

    // MARK: - Adding

    func testAddedHighlightIsReadBackUnchanged() throws {
        try runWithDataManager { dataManager in
            // Fractions of a second survive, as times and dates are stored as reals
            let created = Date(timeIntervalSince1970: 1_700_000_000.5)
            let highlight = addHighlight(start: 723.25, end: 738.5, created: created, note: "A note", dataManager: dataManager)

            let saved = try XCTUnwrap(dataManager.highlights.highlight(for: highlight.uuid))
            XCTAssertEqual(saved, highlight)
        }
    }

    func testHighlightOfAUserFileHasNoPodcast() throws {
        try runWithDataManager { dataManager in
            let highlight = addHighlight(podcastUuid: nil, dataManager: dataManager)

            XCTAssertNil(dataManager.highlights.highlight(for: highlight.uuid)?.podcastUuid)
        }
    }

    // MARK: - Retrieving

    func testHighlightsForAnEpisodeAreNewestFirst() throws {
        try runWithDataManager { dataManager in
            let ordered = [0, 10, 20].map {
                addHighlight(episodeUuid: "episode", created: Date(timeIntervalSince1970: TimeInterval($0)), dataManager: dataManager)
            }
            addHighlight(episodeUuid: "other", dataManager: dataManager)

            let highlights = dataManager.highlights.highlights(forEpisode: "episode")
            XCTAssertEqual(highlights.map(\.uuid), ordered.reversed().map(\.uuid))
        }
    }

    func testAllHighlightsAndCount() throws {
        try runWithDataManager { dataManager in
            addHighlight(episodeUuid: "one", dataManager: dataManager)
            addHighlight(episodeUuid: "one", dataManager: dataManager)
            addHighlight(episodeUuid: "two", dataManager: dataManager)

            XCTAssertEqual(dataManager.highlights.allHighlights().count, 3)
            XCTAssertEqual(dataManager.highlights.highlightCount(forEpisode: "one"), 2)
            XCTAssertEqual(dataManager.highlights.highlightCount(forEpisode: "none"), 0)
        }
    }

    // MARK: - Updating

    func testUpdatingTheNote() throws {
        try runWithDataManager { dataManager in
            let highlight = addHighlight(dataManager: dataManager)

            XCTAssertTrue(dataManager.highlights.update(note: "  The key idea \n", forHighlight: highlight.uuid))
            XCTAssertEqual(dataManager.highlights.highlight(for: highlight.uuid)?.note, "The key idea", "the note should be trimmed")

            XCTAssertTrue(dataManager.highlights.update(note: " ", forHighlight: highlight.uuid))
            XCTAssertNil(dataManager.highlights.highlight(for: highlight.uuid)?.note, "an empty note should be removed")
        }
    }

    // MARK: - Deleting

    func testDeletingRemovesOnlyThoseHighlights() throws {
        try runWithDataManager { dataManager in
            let deleted = addHighlight(dataManager: dataManager)
            let kept = addHighlight(dataManager: dataManager)

            XCTAssertTrue(dataManager.highlights.delete(highlights: [deleted]))

            XCTAssertNil(dataManager.highlights.highlight(for: deleted.uuid))
            XCTAssertEqual(dataManager.highlights.allHighlights().map(\.uuid), [kept.uuid])
        }
    }

    // MARK: - Schema

    func testSettingUpAnExistingDatabaseAgainKeepsTheHighlights() throws {
        let dbPool = try XCTUnwrap(DatabasePool.newTestDatabase())
        let firstLaunch = DataManager(dbQueue: GRDBQueue(dbPool: dbPool))
        let highlight = addHighlight(dataManager: firstLaunch)

        // The table is created on every launch if it's missing, which must not touch an existing one
        let secondLaunch = DataManager(dbQueue: GRDBQueue(dbPool: dbPool))
        XCTAssertNotNil(secondLaunch.highlights.highlight(for: highlight.uuid))
    }
}

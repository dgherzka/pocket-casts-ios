import PocketCastsUtils
import Foundation

/// Stores the listener's highlights in the local database. Highlights are local to this
/// device: they have no sync status and are deleted for good.
public struct HighlightDataManager {
    static let tableName = "Highlight"
    private let dbQueue: GRDBQueue

    init(dbQueue: GRDBQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Adding

    /// Adds a highlight to the database
    /// - Returns: `true` if it was saved
    @discardableResult
    public func add(_ highlight: Highlight) -> Bool {
        var success = false

        dbQueue.write { db in
            do {
                let columns: [Column] = [
                    .uuid, .episode, .podcast, .podcastTitle, .episodeTitle,
                    .startTime, .pressTime, .endTime,
                    .createdDate, .timeZone, .playbackSpeed, .trimSilence,
                    .lookBack, .heldDuration, .note
                ]

                let values: [Any?] = [
                    highlight.uuid, highlight.episodeUuid, highlight.podcastUuid, highlight.podcastTitle, highlight.episodeTitle,
                    highlight.startTime, highlight.pressTime, highlight.endTime,
                    highlight.created.timeIntervalSince1970, highlight.timeZoneIdentifier, highlight.playbackSpeed, highlight.trimSilence ? 1 : 0,
                    highlight.lookBack, highlight.heldDuration, highlight.note
                ]

                try db.insert(into: Self.tableName, columns: columns.map { $0.rawValue }, values: values)

                success = true
            } catch {
                FileLog.shared.addMessage("HighlightDataManager.add failed: \(error)")
            }
        }

        return success
    }

    // MARK: - Updating

    /// Replaces the note of a highlight. An empty or nil note removes it.
    @discardableResult
    public func update(note: String?, forHighlight uuid: String) -> Bool {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newNote: String? = (trimmed?.isEmpty ?? true) ? nil : trimmed

        let query = """
                UPDATE \(Self.tableName)
                SET \(Column.note) = ?
                WHERE \(Column.uuid) = ?
                """

        let values: [Any?] = [newNote as Any?, uuid]
        return executeUpdate(query, values: values.databaseValues, context: "update(note:)")
    }

    // MARK: - Retrieving

    /// Retrieves a single highlight for the given UUID
    public func highlight(for uuid: String) -> Highlight? {
        selectHighlights(where: .uuid, value: uuid, limit: 1).first
    }

    /// Retrieves the highlights of an episode, newest first
    public func highlights(forEpisode episodeUuid: String) -> [Highlight] {
        selectHighlights(where: .episode, value: episodeUuid)
    }

    /// Retrieves every highlight, newest first
    public func allHighlights() -> [Highlight] {
        selectHighlights()
    }

    /// Returns the number of highlights of the given episode
    public func highlightCount(forEpisode episodeUuid: String) -> Int {
        let query = "SELECT COUNT(*) FROM \(Self.tableName) WHERE \(Column.episode) = ?"

        var count = 0
        dbQueue.read { db in
            do {
                let resultSet = try db.executeQuery(query, values: [episodeUuid])
                if resultSet.next() {
                    count = resultSet.long(forColumnIndex: 0)
                }
            } catch {
                FileLog.shared.addMessage("HighlightDataManager.highlightCount failed: \(error)")
            }
        }

        return count
    }

    // MARK: - Deleting

    /// Permanently removes the highlights from the database
    @discardableResult
    public func delete(highlights: [Highlight]) -> Bool {
        guard !highlights.isEmpty else { return true }

        let placeholders = highlights.map { _ in "?" }.columnString
        let query = """
        DELETE FROM \(Self.tableName)
        WHERE \(Column.uuid) IN (\(placeholders))
        """

        return executeUpdate(query, values: highlights.map(\.uuid), context: "delete")
    }

    private func executeUpdate(_ query: String, values: [Any]?, context: String) -> Bool {
        var success = false
        dbQueue.write { db in
            do {
                try db.executeUpdate(query, values: values)
                success = true
            } catch {
                FileLog.shared.addMessage("HighlightDataManager.\(context) failed: \(error)")
            }
        }
        return success
    }

    // MARK: - Columns

    enum Column: String, CaseIterable, CustomStringConvertible {
        case uuid
        case episode = "episode_uuid"
        case podcast = "podcast_uuid"
        case podcastTitle = "podcast_title"
        case episodeTitle = "episode_title"
        case startTime = "start_time"
        case pressTime = "press_time"
        case endTime = "end_time"
        case createdDate = "date_added"
        case timeZone = "time_zone"
        case playbackSpeed = "playback_speed"
        case trimSilence = "trim_silence"
        case lookBack = "look_back"
        case heldDuration = "held_duration"
        case note

        var description: String { rawValue }
    }
}

// MARK: - Private

private extension HighlightDataManager {
    func selectHighlights(where whereColumn: Column? = nil, value: Any? = nil, limit: Int = 0) -> [Highlight] {
        let limitQuery = limit != 0 ? "LIMIT \(limit)" : ""
        let selectColumns = Column.allCases.map { $0.rawValue }

        var whereString = ""
        var values: [Any] = []
        if let whereColumn, let value {
            whereString = "WHERE \(whereColumn.rawValue) = ?"
            values = [value]
        }

        var results: [Highlight] = []

        dbQueue.read { db in
            do {
                let query = """
                    SELECT \(selectColumns.columnString)
                    FROM \(Self.tableName)
                    \(whereString)
                    ORDER BY \(Column.createdDate) DESC
                    \(limitQuery)
                """

                let resultSet = try db.executeQuery(query, values: values)

                while resultSet.next() {
                    if let highlight = Highlight(from: resultSet) {
                        results.append(highlight)
                    }
                }
            } catch {
                FileLog.shared.addMessage("HighlightDataManager.selectHighlights \(whereString) failed: \(error)")
            }
        }

        return results
    }
}

// MARK: - Schema Creation

extension HighlightDataManager {
    /// Creates the table if it doesn't exist yet. This is safe to run on every launch.
    static func createTable(in db: PCDatabase) throws {
        try db.executeUpdate("""
            CREATE TABLE IF NOT EXISTS \(Self.tableName) (
                \(Column.uuid) varchar(40) NOT NULL,
                \(Column.episode) varchar(40) NOT NULL,
                \(Column.podcast) varchar(40),
                \(Column.podcastTitle) TEXT,
                \(Column.episodeTitle) TEXT,
                \(Column.startTime) real NOT NULL,
                \(Column.pressTime) real NOT NULL,
                \(Column.endTime) real NOT NULL,
                \(Column.createdDate) real NOT NULL,
                \(Column.timeZone) TEXT NOT NULL,
                \(Column.playbackSpeed) real NOT NULL DEFAULT 1,
                \(Column.trimSilence) int NOT NULL DEFAULT 0,
                \(Column.lookBack) real NOT NULL DEFAULT 0,
                \(Column.heldDuration) real NOT NULL DEFAULT 0,
                \(Column.note) TEXT,
                PRIMARY KEY (\(Column.uuid))
            );
        """, values: nil)

        try db.executeUpdate("CREATE INDEX IF NOT EXISTS highlight_episode ON \(Self.tableName) (\(Column.episode));", values: nil)
    }
}

// MARK: - Highlight from PCDBResultSet

private extension Highlight {
    init?(from resultSet: PCDBResultSet) {
        guard
            let uuid = resultSet.string(for: .uuid),
            let episode = resultSet.string(for: .episode)
        else {
            return nil
        }

        self.init(
            uuid: uuid,
            episodeUuid: episode,
            podcastUuid: resultSet.string(for: .podcast),
            podcastTitle: resultSet.string(for: .podcastTitle),
            episodeTitle: resultSet.string(for: .episodeTitle),
            startTime: resultSet.double(for: .startTime),
            pressTime: resultSet.double(for: .pressTime),
            endTime: resultSet.double(for: .endTime),
            created: Date(timeIntervalSince1970: resultSet.double(for: .createdDate)),
            timeZoneIdentifier: resultSet.string(for: .timeZone) ?? TimeZone.current.identifier,
            playbackSpeed: resultSet.double(for: .playbackSpeed),
            trimSilence: resultSet.long(for: .trimSilence) != 0,
            lookBack: resultSet.double(for: .lookBack),
            heldDuration: resultSet.double(for: .heldDuration),
            note: resultSet.string(for: .note)
        )
    }
}

// MARK: - HighlightDataManager.Column: PCDBResultSet Extension

private extension PCDBResultSet {
    func string(for column: HighlightDataManager.Column) -> String? {
        string(forColumn: column.rawValue)
    }

    func double(for column: HighlightDataManager.Column) -> Double {
        double(forColumn: column.rawValue)
    }

    func long(for column: HighlightDataManager.Column) -> Int {
        long(forColumn: column.rawValue)
    }
}

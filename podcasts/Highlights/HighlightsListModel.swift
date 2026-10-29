import Combine
import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// The highlights of one episode, or of every episode, grouped by episode with the most recent first
@MainActor
final class HighlightsListModel: ObservableObject {
    @Published private(set) var groups: [HighlightExporter.EpisodeGroup] = []

    @Published var lookBackSeconds: Int {
        didSet {
            Settings.highlightLookBackSeconds = lookBackSeconds
        }
    }

    /// When set, only this episode's highlights are listed
    let episodeUuid: String?

    var isEmpty: Bool { groups.isEmpty }

    /// Set by the hosting controller, which presents the share sheet and the error alerts
    weak var router: HighlightsListRouter?

    private let manager: HighlightManager
    private var cancellables = Set<AnyCancellable>()

    init(episodeUuid: String? = nil, manager: HighlightManager = .shared) {
        self.episodeUuid = episodeUuid
        self.manager = manager
        self.lookBackSeconds = Settings.highlightLookBackSeconds

        reload()

        NotificationCenter.default.publisher(for: HighlightManager.highlightsChangedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reload()
            }
            .store(in: &cancellables)
    }

    func reload() {
        let highlights = manager.highlights(forEpisode: episodeUuid)
        groups = HighlightExporter.groups(for: highlights)
    }

    // MARK: - Actions

    func play(_ highlight: Highlight) {
        do {
            try manager.play(highlight)
        } catch {
            router?.showEpisodeUnavailable()
        }
    }

    func update(note: String, for highlight: Highlight) {
        manager.update(note: note, for: highlight)
    }

    func delete(_ highlight: Highlight) {
        manager.delete([highlight])
    }

    func shareAll() {
        share(groups)
    }

    func share(_ group: HighlightExporter.EpisodeGroup) {
        share([group])
    }

    private func share(_ groups: [HighlightExporter.EpisodeGroup]) {
        guard !groups.isEmpty else { return }

        Analytics.track(.highlightsShared, properties: [
            "episodes": groups.count,
            "highlights": groups.reduce(0) { $0 + $1.highlights.count }
        ])
        router?.shareHighlights(groups)
    }

    func close() {
        router?.closeHighlights()
    }
}

@MainActor
protocol HighlightsListRouter: AnyObject {
    func shareHighlights(_ groups: [HighlightExporter.EpisodeGroup])
    func showEpisodeUnavailable()
    func closeHighlights()
}

import PocketCastsUtils
import UIKit

/// Lists highlights, either every episode's from the Profile tab, or a single episode's
class HighlightsViewController: ThemedHostingController<HighlightsListView> {
    private let model: HighlightsListModel

    /// - Parameters:
    ///   - episodeUuid: Only list this episode's highlights, or every highlight when nil
    ///   - showsDoneButton: Whether to show a Done button, for when the list is presented on its own
    init(episodeUuid: String? = nil, showsDoneButton: Bool = false) {
        let model = HighlightsListModel(episodeUuid: episodeUuid)
        self.model = model

        super.init(rootView: HighlightsListView(model: model, showsDoneButton: showsDoneButton))

        model.router = self
    }

    @MainActor dynamic required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        Analytics.track(.highlightsListShown, properties: ["episode": model.episodeUuid != nil])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Pick up titles and highlights that changed while the list was hidden
        model.reload()
    }
}

// MARK: - HighlightsListRouter

extension HighlightsViewController: HighlightsListRouter {
    func shareHighlights(_ groups: [HighlightExporter.EpisodeGroup]) {
        let exporter = HighlightExporter()
        let markdown = exporter.markdown(for: groups)

        // Share a Markdown file so it can be attached to a chat with an LLM, or the text if the file can't be written
        let item: Any
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(exporter.fileName(for: groups))
        do {
            try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
            item = fileURL
        } catch {
            FileLog.shared.addMessage("[Highlights] Couldn't write the export to a file, sharing the text instead: \(error)")
            item = markdown
        }

        let activityController = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        if let popover = activityController.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        present(activityController, animated: true)
    }

    func showEpisodeUnavailable() {
        let alert = UIAlertController(title: L10n.highlightEpisodeUnavailableTitle, message: L10n.highlightEpisodeUnavailableMessage, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.ok, style: .default))
        present(alert, animated: true)
    }

    func closeHighlights() {
        dismiss(animated: true)
    }
}

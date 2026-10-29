import PocketCastsDataModel
import SwiftUI

struct HighlightsListView: View {
    @EnvironmentObject var theme: Theme
    @ObservedObject var model: HighlightsListModel

    /// Whether to show a Done button, when the list is presented on its own
    let showsDoneButton: Bool

    @State private var highlightToDelete: Highlight?
    @State private var highlightToEdit: Highlight?
    @State private var noteDraft = ""

    var body: some View {
        List {
            settingsSection

            if model.isEmpty {
                Section {
                    Text(L10n.highlightsEmpty)
                        .foregroundStyle(theme.primaryText02)
                        .listRowBackground(theme.primaryUi02)
                }
            }

            ForEach(model.groups, id: \.episodeUuid) { group in
                Section {
                    ForEach(group.highlights) { highlight in
                        row(for: highlight)
                    }
                } header: {
                    header(for: group)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.primaryUi04)
        .navigationTitle(L10n.highlights)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if showsDoneButton {
                    Button(L10n.done) {
                        model.close()
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                if !model.isEmpty {
                    Button {
                        model.shareAll()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(model.episodeUuid == nil ? L10n.highlightsShareAll : L10n.highlightsShareEpisode)
                }
            }
        }
        .alert(L10n.highlightDeleteTitle, isPresented: isPresented($highlightToDelete), presenting: highlightToDelete) { highlight in
            Button(L10n.delete, role: .destructive) {
                model.delete(highlight)
            }
            Button(L10n.cancel, role: .cancel) { }
        } message: { _ in
            Text(L10n.highlightDeleteMessage)
        }
        .alert(L10n.highlightEditNote, isPresented: isPresented($highlightToEdit), presenting: highlightToEdit) { highlight in
            TextField(L10n.highlightNotePlaceholder, text: $noteDraft)
            Button(L10n.highlightNoteSave) {
                model.update(note: noteDraft, for: highlight)
            }
            Button(L10n.cancel, role: .cancel) { }
        }
        .applyDefaultThemeOptions()
    }

    // MARK: - Settings

    private var settingsSection: some View {
        Section {
            Stepper(value: $model.lookBackSeconds, in: Settings.highlightLookBackRange, step: 5) {
                Text(L10n.highlightLength(model.lookBackSeconds))
                    .foregroundStyle(theme.primaryText01)
            }
            .accessibilityValue(L10n.highlightLengthAccessibilityValue(model.lookBackSeconds))
            .listRowBackground(theme.primaryUi02)
        } footer: {
            Text(L10n.highlightLengthFooter)
                .foregroundStyle(theme.primaryText02)
        }
    }

    // MARK: - Episodes

    private func header(for group: HighlightExporter.EpisodeGroup) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.episodeTitle ?? L10n.highlightsUnknownEpisode)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.primaryText01)
                    .textCase(nil)
                if let podcastTitle = group.podcastTitle {
                    Text(podcastTitle)
                        .font(.footnote)
                        .foregroundStyle(theme.primaryText02)
                        .textCase(nil)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer()

            Button {
                model.share(group)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(theme.primaryIcon01)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L10n.highlightsShareEpisodeNamed(group.episodeTitle ?? L10n.highlightsUnknownEpisode))
        }
    }

    // MARK: - Highlights

    private func row(for highlight: Highlight) -> some View {
        Button {
            model.play(highlight)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(HighlightFormatter.range(start: highlight.startTime, end: highlight.endTime))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(theme.primaryText01)
                Text(highlight.created.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(theme.primaryText02)
                if let note = highlight.note, !note.isEmpty {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(theme.primaryText01)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.highlightPlayHint)
        .listRowBackground(theme.primaryUi02)
        .listRowSeparatorTint(theme.primaryUi05)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                highlightToDelete = highlight
            } label: {
                Label(L10n.delete, systemImage: "trash")
            }
            .tint(.red)

            Button {
                editNote(of: highlight)
            } label: {
                Label(L10n.highlightEditNote, systemImage: "square.and.pencil")
            }
            .tint(theme.primaryInteractive01)
        }
        .contextMenu {
            Button {
                model.play(highlight)
            } label: {
                Label(L10n.play, systemImage: "play")
            }
            Button {
                editNote(of: highlight)
            } label: {
                Label(L10n.highlightEditNote, systemImage: "square.and.pencil")
            }
            Button(role: .destructive) {
                highlightToDelete = highlight
            } label: {
                Label(L10n.delete, systemImage: "trash")
            }
        }
        .accessibilityAction(named: L10n.highlightEditNote) {
            editNote(of: highlight)
        }
        .accessibilityAction(named: L10n.delete) {
            highlightToDelete = highlight
        }
    }

    private func editNote(of highlight: Highlight) {
        noteDraft = highlight.note ?? ""
        highlightToEdit = highlight
    }

    /// A binding that's true while the optional has a value, and clears it when set to false
    private func isPresented<Value>(_ value: Binding<Value?>) -> Binding<Bool> {
        Binding(
            get: { value.wrappedValue != nil },
            set: { isPresented in
                if !isPresented {
                    value.wrappedValue = nil
                }
            }
        )
    }
}

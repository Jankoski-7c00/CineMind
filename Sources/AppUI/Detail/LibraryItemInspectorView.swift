import Application
import Domain
import SwiftUI

struct LibraryItemInspectorSnapshot {
    let detail: LibraryItemDetailShell?
    let detailState: DetailState
    let playbackStatus: PlaybackApplicationStatus
    let metadataActionStatus: MetadataActionStatus
    let metadataCandidates: [LibraryMetadataCandidate]
    let isSearchingMetadataCandidates: Bool
    let curationActionStatus: CurationActionStatus
    let subtitleActionStatus: SubtitleActionStatus
    let subtitleCandidates: [LibrarySubtitleCandidate]
    let isSearchingSubtitleCandidates: Bool
    let downloadingSubtitleResultID: String?
    let installedSubtitleResultIDs: Set<String>
    let metadataActionsUnavailableMessage: String?
    let subtitleActionsUnavailableMessage: String?
    let metadataActionsAvailable: Bool
    let curationActionsAvailable: Bool
    let subtitleActionsAvailable: Bool
    let subtitleTargetAvailable: Bool

    @MainActor
    init(viewModel: LibraryItemDetailViewModel) {
        detail = viewModel.detail
        detailState = viewModel.detailState
        playbackStatus = viewModel.playbackStatus
        metadataActionStatus = viewModel.metadataActionStatus
        metadataCandidates = viewModel.metadataCandidates
        isSearchingMetadataCandidates = viewModel.isSearchingMetadataCandidates
        curationActionStatus = viewModel.curationActionStatus
        subtitleActionStatus = viewModel.subtitleActionStatus
        subtitleCandidates = viewModel.subtitleCandidates
        isSearchingSubtitleCandidates = viewModel.isSearchingSubtitleCandidates
        downloadingSubtitleResultID = viewModel.downloadingSubtitleResultID
        installedSubtitleResultIDs = viewModel.installedSubtitleResultIDs
        metadataActionsUnavailableMessage = viewModel.metadataActionsUnavailableMessage
        subtitleActionsUnavailableMessage = viewModel.subtitleActionsUnavailableMessage
        metadataActionsAvailable = viewModel.metadataActionsAvailable
        curationActionsAvailable = viewModel.curationActionsAvailable
        subtitleActionsAvailable = viewModel.subtitleActionsAvailable
        subtitleTargetAvailable = viewModel.subtitleTargetAvailable
    }
}

struct LibraryItemInspectorActions {
    let viewModel: LibraryItemDetailViewModel
}

struct LibraryItemInspectorView: View {
    let snapshot: LibraryItemInspectorSnapshot
    let actions: LibraryItemInspectorActions
    let curationSnapshot: LibraryCurationSnapshot
    @Binding var selectedSection: LibraryInspectorSection

    @State private var isRematchSheetPresented = false
    @State private var isSubtitleSearchSheetPresented = false
    @State private var newTagName = ""
    @State private var newCollectionName = ""
    @State private var editingTagID: TagID?
    @State private var editingTagName = ""
    @State private var editingCollectionID: CollectionID?
    @State private var editingCollectionName = ""
    @State private var titleOverrideText = ""
    @State private var summaryOverrideText = ""
    @State private var languageOverrideText = ""

    var body: some View {
        VStack(spacing: 0) {
            sectionPicker
                .padding(10)

            Divider()

            if let detail = snapshot.detail, snapshot.detailState == .loaded {
                inspectorContent(detail)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "sidebar.right")
                        .font(.title2)
                    Text("No Selection")
                        .font(.headline)
                    Text("Select a media item to inspect its details.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var sectionPicker: some View {
        Menu {
            ForEach(LibraryInspectorSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    Label(section.title, systemImage: section.systemImage)
                }
            }
        } label: {
            Label(selectedSection.title, systemImage: selectedSection.systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .help("Choose Inspector Section")
    }

    @ViewBuilder
    private func inspectorContent(_ detail: LibraryItemDetailShell) -> some View {
        switch selectedSection {
        case .info:
            infoList(detail)
        case .organize:
            organizeList(detail.curation)
        case .files:
            filesList(detail.files)
        case .subtitles:
            subtitlesList
                .sheet(isPresented: $isSubtitleSearchSheetPresented) {
                    subtitleCandidateSheet
                }
        case .advancedMetadata:
            advancedMetadataList(detail)
                .sheet(isPresented: $isRematchSheetPresented) {
                    metadataCandidateSheet
                }
        }
    }

    private func infoList(_ detail: LibraryItemDetailShell) -> some View {
        List {
            Section("Overview") {
                LabeledContent("Title", value: detail.displayTitle)
                LabeledContent("Type", value: detail.mediaTypeLabel)
                LabeledContent(
                    "Year / Episode",
                    value: displayValue(detail.yearOrEpisodeLabel)
                )
                LabeledContent("Availability", value: detail.availabilityLabel)
                LabeledContent("Metadata", value: detail.metadataLabel)
                LabeledContent("Last Played", value: displayValue(detail.lastPlayedLabel))
            }

            Section("Summary") {
                Text(CineMindDisplayText.summary(detail.summary))
                    .foregroundStyle(detail.summary == nil ? .secondary : .primary)
            }

            Section("Metadata") {
                let metadata = detail.metadataDetail
                LabeledContent("Local Title", value: metadata.localTitle)
                LabeledContent("Matched Title", value: displayValue(metadata.metadataTitle))
                LabeledContent("Original Title", value: displayValue(metadata.originalTitle))
                LabeledContent("Language", value: displayValue(metadata.languageLabel))
                LabeledContent("Release Date", value: displayValue(metadata.releaseOrAirDateLabel))
            }
        }
        .listStyle(.inset)
    }

    private func organizeList(_ curation: LibraryItemCurationDetail) -> some View {
        List {
            Section {
                Toggle(
                    "Favorite",
                    isOn: Binding(
                        get: { curation.isFavorite },
                        set: { actions.viewModel.setFavorite($0) }
                    )
                )
                .disabled(!snapshot.curationActionsAvailable)

                curationActionStatusView
            }

            Section("Tags") {
                tagAssignmentMenu(curation.tags)

                ForEach(curation.tags) { tag in
                    tagRow(tag)
                }

                createRow(placeholder: "New Tag", text: $newTagName) {
                    let name = newTagName
                    newTagName = ""
                    actions.viewModel.createAndAssignTag(name: name)
                }

                if let editingTagID {
                    editRow(
                        title: "Rename Tag",
                        text: $editingTagName,
                        cancel: {
                            self.editingTagID = nil
                            editingTagName = ""
                        },
                        save: {
                            let name = editingTagName
                            self.editingTagID = nil
                            editingTagName = ""
                            actions.viewModel.renameTag(tagID: editingTagID, name: name)
                        }
                    )
                }
            }

            Section("Collections") {
                collectionAssignmentMenu(curation.collections)

                ForEach(curation.collections) { collection in
                    collectionRow(collection)
                }

                createRow(placeholder: "New Collection", text: $newCollectionName) {
                    let name = newCollectionName
                    newCollectionName = ""
                    actions.viewModel.createAndAddCollection(name: name)
                }

                if let editingCollectionID {
                    editRow(
                        title: "Rename Collection",
                        text: $editingCollectionName,
                        cancel: {
                            self.editingCollectionID = nil
                            editingCollectionName = ""
                        },
                        save: {
                            let name = editingCollectionName
                            self.editingCollectionID = nil
                            editingCollectionName = ""
                            actions.viewModel.renameCollection(
                                collectionID: editingCollectionID,
                                name: name
                            )
                        }
                    )
                }
            }
        }
        .listStyle(.inset)
    }

    private func filesList(_ files: [LibraryFileSummary]) -> some View {
        List {
            if files.isEmpty {
                Section {
                    Text("No files")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(files, id: \.mediaFileID) { file in
                    Section(file.fileName) {
                        LabeledContent("Size", value: file.fileSizeLabel)
                        LabeledContent("Availability", value: file.availabilityLabel)
                        if let resumePositionLabel = file.resumePositionLabel {
                            LabeledContent("Resume", value: resumePositionLabel)
                        }
                        if let playabilityReason = file.playabilityReason {
                            Text(playabilityReason)
                                .foregroundStyle(.secondary)
                        }
                        if file.isPlayable {
                            filePlaybackButton(file)
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private var subtitlesList: some View {
        List {
            Section("Online Search") {
                if snapshot.subtitleActionsAvailable {
                    Button("Search Online", systemImage: "magnifyingglass") {
                        isSubtitleSearchSheetPresented = true
                        actions.viewModel.searchSubtitleCandidates()
                    }
                    .disabled(!snapshot.subtitleTargetAvailable)

                    if !snapshot.subtitleTargetAvailable {
                        Text("A playable local file is required.")
                            .foregroundStyle(.secondary)
                    }

                    subtitleActionStatusView
                } else {
                    Label(
                        snapshot.subtitleActionsUnavailableMessage
                            ?? "Subtitle search is not configured. Local and embedded subtitles remain available.",
                        systemImage: "exclamationmark.circle"
                    )
                    .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.inset)
    }

    private func advancedMetadataList(_ detail: LibraryItemDetailShell) -> some View {
        List {
            Section("Actions") {
                if snapshot.metadataActionsAvailable {
                    Button("Refresh Metadata", systemImage: "arrow.clockwise") {
                        actions.viewModel.refreshMetadata()
                    }
                    Button("Search Matches", systemImage: "magnifyingglass") {
                        isRematchSheetPresented = true
                        actions.viewModel.searchMetadataCandidates()
                    }
                    metadataActionStatusView
                } else {
                    Label(
                        snapshot.metadataActionsUnavailableMessage
                            ?? "Open CineMind Settings to configure online metadata matching.",
                        systemImage: "exclamationmark.circle"
                    )
                    .foregroundStyle(.secondary)
                }
            }

            Section("Overrides") {
                overrideRow(
                    label: "Title",
                    text: $titleOverrideText,
                    field: .title,
                    isLocked: detail.metadataDetail.titleOverrideLocked
                )
                overrideRow(
                    label: "Summary",
                    text: $summaryOverrideText,
                    field: .summary,
                    isLocked: detail.metadataDetail.summaryOverrideLocked
                )
                overrideRow(
                    label: "Language",
                    text: $languageOverrideText,
                    field: .language,
                    isLocked: detail.metadataDetail.languageOverrideLocked
                )
            }

            metadataSourceSection(detail.metadataDetail.source)
            posterAssetsSection(detail.posterAssets)
        }
        .listStyle(.inset)
        .onAppear {
            syncOverrideDrafts(from: detail.metadataDetail)
        }
        .onChange(of: detail.metadataDetail) { _, metadata in
            syncOverrideDrafts(from: metadata)
        }
    }

    private func tagAssignmentMenu(_ assignedTags: [LibraryTagSummary]) -> some View {
        let assignedIDs = Set(assignedTags.map(\.id))
        let availableTags = curationSnapshot.tags.filter { !assignedIDs.contains($0.id) }
        return Menu("Add Existing Tag", systemImage: "plus.circle") {
            if availableTags.isEmpty {
                Text("No Tags")
            } else {
                ForEach(availableTags) { tag in
                    Button(tag.name) {
                        actions.viewModel.assignTag(tagID: tag.id)
                    }
                }
            }
        }
        .disabled(!snapshot.curationActionsAvailable || availableTags.isEmpty)
    }

    private func tagRow(_ tag: LibraryTagSummary) -> some View {
        HStack {
            Label(tag.name, systemImage: "tag")
            Spacer()
            Button("Remove", systemImage: "xmark.circle") {
                actions.viewModel.removeTag(tagID: tag.id)
            }
            .labelStyle(.iconOnly)
            .help("Remove Tag")

            Menu("Tag Actions", systemImage: "ellipsis.circle") {
                Button("Rename") {
                    editingTagID = tag.id
                    editingTagName = tag.name
                }
                Button("Delete", role: .destructive) {
                    actions.viewModel.deleteTag(tagID: tag.id)
                }
            }
            .labelStyle(.iconOnly)
            .help("Tag Actions")
        }
    }

    private func collectionAssignmentMenu(
        _ itemCollections: [LibraryCollectionSummary]
    ) -> some View {
        let memberIDs = Set(itemCollections.map(\.id))
        let availableCollections = curationSnapshot.collections.filter {
            !memberIDs.contains($0.id)
        }
        return Menu("Add Existing Collection", systemImage: "plus.circle") {
            if availableCollections.isEmpty {
                Text("No Collections")
            } else {
                ForEach(availableCollections) { collection in
                    Button(collection.name) {
                        actions.viewModel.addToCollection(collectionID: collection.id)
                    }
                }
            }
        }
        .disabled(!snapshot.curationActionsAvailable || availableCollections.isEmpty)
    }

    private func collectionRow(_ collection: LibraryCollectionSummary) -> some View {
        HStack {
            Label(collection.name, systemImage: "rectangle.stack")
            Spacer()
            Button("Remove", systemImage: "xmark.circle") {
                actions.viewModel.removeFromCollection(collectionID: collection.id)
            }
            .labelStyle(.iconOnly)
            .help("Remove from Collection")

            Menu("Collection Actions", systemImage: "ellipsis.circle") {
                Button("Rename") {
                    editingCollectionID = collection.id
                    editingCollectionName = collection.name
                }
                Button("Delete", role: .destructive) {
                    actions.viewModel.deleteCollection(collectionID: collection.id)
                }
            }
            .labelStyle(.iconOnly)
            .help("Collection Actions")
        }
    }

    private func createRow(
        placeholder: String,
        text: Binding<String>,
        submit: @escaping () -> Void
    ) -> some View {
        HStack {
            TextField(placeholder, text: text)
            Button("Add", systemImage: "plus", action: submit)
                .labelStyle(.iconOnly)
                .help("Add")
                .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .disabled(!snapshot.curationActionsAvailable)
    }

    private func editRow(
        title: String,
        text: Binding<String>,
        cancel: @escaping () -> Void,
        save: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField(title, text: text)
                Button("Save", systemImage: "checkmark", action: save)
                    .labelStyle(.iconOnly)
                    .help("Save")
                    .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", systemImage: "xmark", action: cancel)
                    .labelStyle(.iconOnly)
                    .help("Cancel")
            }
        }
    }

    private func filePlaybackButton(_ file: LibraryFileSummary) -> some View {
        let state = LibraryFilePlaybackPresentation.buttonState(
            for: file,
            playbackStatus: snapshot.playbackStatus
        )
        return Button(state.title, systemImage: state.systemImage) {
            switch state {
            case .play:
                actions.viewModel.playFile(mediaFileID: file.mediaFileID)
            case .resume:
                actions.viewModel.resumePlayback()
            case .disabled:
                break
            }
        }
        .disabled(state.isDisabled)
    }

    private func overrideRow(
        label: String,
        text: Binding<String>,
        field: MetadataOverrideField,
        isLocked: Bool
    ) -> some View {
        VStack(alignment: .leading) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(label, text: text)
            HStack {
                Button("Save", systemImage: "checkmark") {
                    actions.viewModel.setMetadataOverride(field: field, value: text.wrappedValue)
                }
                Button("Clear", systemImage: "xmark.circle") {
                    actions.viewModel.clearMetadataOverride(field: field)
                }
                .disabled(!isLocked)
            }
            .disabled(!snapshot.metadataActionsAvailable)
        }
    }

    @ViewBuilder
    private func metadataSourceSection(_ source: LibraryMetadataSourceDetail?) -> some View {
        Section("Source") {
            if let source {
                LabeledContent("Provider", value: source.providerLabel)
                LabeledContent("Provider ID", value: source.providerID)
                LabeledContent("Media Type", value: source.providerMediaTypeLabel)
                LabeledContent("Confidence", value: source.confidenceLabel)
                LabeledContent("Match Source", value: source.matchSourceLabel)
                LabeledContent("Manual Lock", value: source.manualMatchLockLabel)
                LabeledContent("Matched", value: source.matchedAtLabel)
                LabeledContent("Refreshed", value: displayValue(source.refreshedAtLabel))
            } else {
                Text(CineMindDisplayText.emptyValue)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func posterAssetsSection(_ assets: [LibraryPosterAssetDetail]) -> some View {
        Section("Poster Assets") {
            if assets.isEmpty {
                Text(CineMindDisplayText.emptyValue)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(assets) { asset in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(asset.isSelected ? "Selected" : "Available")
                            Spacer()
                            if !asset.isSelected {
                                Button("Select") {
                                    actions.viewModel.selectPoster(posterAssetID: asset.id)
                                }
                                .disabled(!snapshot.metadataActionsAvailable)
                            }
                        }
                        Text(asset.remotePath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        LabeledContent("Source", value: asset.sourceLabel)
                        LabeledContent("Dimensions", value: displayValue(asset.dimensionsLabel))
                        LabeledContent("Cached", value: displayValue(asset.cachedAtLabel))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var curationActionStatusView: some View {
        switch snapshot.curationActionStatus {
        case .idle:
            EmptyView()
        case .loading(let message):
            statusProgress(message)
        case .success(let message):
            Label(message, systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var subtitleActionStatusView: some View {
        switch snapshot.subtitleActionStatus {
        case .idle:
            EmptyView()
        case .loading(let message):
            statusProgress(message)
        case .success(let message):
            Label(message, systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var metadataActionStatusView: some View {
        switch snapshot.metadataActionStatus {
        case .idle:
            EmptyView()
        case .loading(let message):
            statusProgress(message)
        case .success(let message):
            Label(message, systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }

    private func statusProgress(_ message: String) -> some View {
        HStack {
            ProgressView()
                .controlSize(.small)
            Text(message)
        }
    }

    private var metadataCandidateSheet: some View {
        NavigationStack {
            Group {
                if snapshot.isSearchingMetadataCandidates {
                    ProgressView("Searching...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if snapshot.metadataCandidates.isEmpty {
                    ContentUnavailableView(
                        "No Matches",
                        systemImage: "magnifyingglass",
                        description: Text("No metadata matches were found.")
                    )
                } else {
                    List(snapshot.metadataCandidates) { candidate in
                        Button {
                            isRematchSheetPresented = false
                            actions.viewModel.rematchMetadata(providerID: candidate.providerID)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.title)
                                if let subtitle = candidate.subtitle {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(candidate.confidenceLabel)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Metadata Matches")
            .toolbar {
                Button("Done") {
                    isRematchSheetPresented = false
                }
            }
        }
        .frame(minWidth: 460, minHeight: 320)
    }

    private var subtitleCandidateSheet: some View {
        NavigationStack {
            Group {
                if snapshot.isSearchingSubtitleCandidates {
                    ProgressView("Searching...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if snapshot.subtitleCandidates.isEmpty {
                    ContentUnavailableView(
                        "No Subtitles",
                        systemImage: "captions.bubble",
                        description: Text("No subtitle candidates were found.")
                    )
                } else {
                    List(snapshot.subtitleCandidates) { candidate in
                        subtitleCandidateRow(candidate)
                    }
                }
            }
            .navigationTitle("Subtitle Results")
            .toolbar {
                Button("Done") {
                    isSubtitleSearchSheetPresented = false
                }
            }
        }
        .frame(minWidth: 520, minHeight: 340)
    }

    private func subtitleCandidateRow(_ candidate: LibrarySubtitleCandidate) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.title)
                Text("\(candidate.languageLabel) · \(candidate.formatLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let reason = candidate.unavailableReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            let isInstalled = snapshot.installedSubtitleResultIDs.contains(candidate.resultID)
            Button(isInstalled ? "Installed" : "Download") {
                actions.viewModel.downloadSubtitle(resultID: candidate.resultID)
            }
            .disabled(
                !candidate.isDownloadable
                    || isInstalled
                    || snapshot.downloadingSubtitleResultID != nil
            )
        }
    }

    private func syncOverrideDrafts(from metadata: LibraryMetadataDetail) {
        titleOverrideText = metadata.metadataTitle ?? ""
        summaryOverrideText = metadata.summary ?? ""
        languageOverrideText = metadata.languageLabel ?? ""
    }

    private func displayValue(_ value: String?) -> String {
        CineMindDisplayText.value(value)
    }
}

import SwiftData
import SwiftUI

struct ClipsScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \ClipboardItem.copiedAt, order: .reverse) private var allItems: [ClipboardItem]
    @Query(sort: \Pinboard.displayOrder) private var pinboards: [Pinboard]

    @State private var ui = ClipsUIState()
    @State private var searchText = ""
    @State private var tokens: [FilterToken] = []
    @State private var availableTokens: [FilterToken] = []
    @State private var showPinboards = false
    @State private var showSettings = false
    @State private var confirmDeleteSelection = false
    @State private var hasNewClipboard = false

    @AppStorage("autoSaveOnOpen", store: ClipStore.defaults) private var autoSaveOnOpen = false

    private var library: ClipLibrary { ClipLibrary(context: context) }

    private let columns = [
        GridItem(.flexible(), spacing: ClipStyle.gridSpacing),
        GridItem(.flexible(), spacing: ClipStyle.gridSpacing),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: ClipStyle.gridSpacing) {
                    FilterChipsRow(available: availableTokens, tokens: $tokens)
                    LazyVGrid(columns: columns, spacing: ClipStyle.gridSpacing) {
                        ForEach(visibleItems) { item in
                            ClipGridCell(
                                item: item,
                                pinboards: pinboards,
                                currentPinboard: currentPinboard,
                                ui: ui
                            )
                        }
                    }
                }
                .padding(.horizontal, ClipStyle.gridPadding)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .animation(.snappy, value: visibleItems.map(\.id))
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Color(.systemGroupedBackground))
            .overlay { emptyState }
            .overlay(alignment: .top) { toastView }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .searchable(
                text: $searchText,
                tokens: $tokens,
                prompt: Text("Search")
            ) { token in
                Label(token.title, systemImage: token.systemImage)
            }
            .onChange(of: allItems.count) { refreshAvailableTokens() }
            .onAppear {
                refreshAvailableTokens()
                checkPasteboard()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { checkPasteboard() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
                // Only update the dot here. Reading now would prompt while Clipbara is in
                // use, and the notice arrives before a copy from Clipbara itself is marked
                // as its own, so wait a turn.
                DispatchQueue.main.async { checkPasteboard(saving: false) }
            }
            .sheet(isPresented: $showPinboards) {
                PinboardsSheet(pinboards: pinboards, ui: ui)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(item: $ui.previewItem) { item in
                ClipPreviewSheet(item: item, ui: ui)
            }
            .alert("Rename", isPresented: renameBinding) {
                TextField("Title", text: $ui.renameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    if let item = ui.renameItem {
                        library.rename(item, to: ui.renameText)
                    }
                }
            }
            .alert("New Pinboard", isPresented: $ui.isNamingNewPinboard) {
                TextField("Name", text: $ui.newPinboardName)
                Button("Cancel", role: .cancel) {}
                Button("Create") { createPinboardFromAlert() }
            }
            .confirmationDialog(
                deleteSelectionTitle,
                isPresented: $confirmDeleteSelection,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    library.delete(selectedItems)
                    ui.endSelecting()
                }
            }
            .sensoryFeedback(.success, trigger: ui.toast?.id)
        }
    }

    // MARK: - Data

    private var currentPinboard: Pinboard? {
        guard case .pinboard(let id) = ui.collection else { return nil }
        return pinboards.first { $0.id == id }
    }

    private var collectionItems: [ClipboardItem] {
        if let pinboard = currentPinboard {
            return pinboard.entries
                .sorted { $0.displayOrder < $1.displayOrder }
                .compactMap(\.clipboardItem)
        }
        return allItems
    }

    private var visibleItems: [ClipboardItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return collectionItems.filter { item in
            guard tokens.allSatisfy({ $0.matches(item) }) else { return false }
            guard !query.isEmpty else { return true }
            return item.displayText.localizedCaseInsensitiveContains(query)
                || (item.userTitle?.localizedCaseInsensitiveContains(query) ?? false)
                || (item.sourceAppName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var selectedItems: [ClipboardItem] {
        collectionItems.filter { ui.selectedIDs.contains($0.id) }
    }

    private var collectionTitle: String {
        currentPinboard?.name ?? String(localized: "Clipboard")
    }

    private func refreshAvailableTokens() {
        let kinds = ClipKind.allCases
            .filter { kind in allItems.contains { kind.matches($0) } }
            .map(FilterToken.kind)
        let sources = Array(Set(allItems.compactMap(\.sourceAppName))).sorted().prefix(8).map(FilterToken.source)
        availableTokens = kinds + sources
    }

    // MARK: - Pasteboard

    /// `saving` is true when Clipbara is opened: the only time "Save Clipboard When
    /// Opening" reads the clipboard.
    private func checkPasteboard(saving: Bool = true) {
        guard PasteboardWatcher.hasUnseenContent else {
            withAnimation(.snappy) { hasNewClipboard = false }
            return
        }
        if saving, autoSaveOnOpen, let clip = ClipLibrary.readGeneralPasteboard() {
            PasteboardWatcher.markSeen()
            save([clip])
            return
        }
        withAnimation(.snappy) { hasNewClipboard = true }
    }

    private func save(_ clips: [CapturedClip]) {
        var saved = 0
        for clip in clips where library.save(clip) != nil {
            saved += 1
        }
        PasteboardWatcher.markSeen()
        withAnimation(.snappy) { hasNewClipboard = false }
        if saved > 0 {
            ui.show(String(localized: "Saved to Clipboard"), systemImage: "tray.and.arrow.down.fill")
        }
    }

    private func createPinboardFromAlert() {
        let pinboard = library.createPinboard(named: ui.newPinboardName, existing: pinboards)
        if !ui.newPinboardItems.isEmpty {
            library.add(ui.newPinboardItems, to: pinboard)
            ui.show(String(localized: "Added to \(pinboard.name)"), systemImage: "pin.fill")
            ui.newPinboardItems = []
            if ui.isSelecting { ui.endSelecting() }
        } else {
            ui.collection = .pinboard(pinboard.id)
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { ui.renameItem != nil },
            set: { if !$0 { ui.renameItem = nil } }
        )
    }

    private var deleteSelectionTitle: String {
        let count = ui.selectedIDs.count
        return String(localized: "Delete \(count) clips?")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showPinboards = true
            } label: {
                HStack(spacing: 6) {
                    collectionGlyph
                    Text(collectionTitle)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 150, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel(Text("Choose Pinboard, current: \(collectionTitle)"))
            .accessibilityIdentifier("collectionButton")
        }
        .sharedBackgroundVisibility(.hidden)

        if ui.isSelecting {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { ui.endSelecting() }
                    .fontWeight(.semibold)
            }
            ToolbarItem(placement: .bottomBar) {
                pinSelectionMenu
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Text("\(ui.selectedIDs.count) selected")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarSpacer(.flexible, placement: .bottomBar)
            if let pinboard = currentPinboard {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        library.remove(selectedItems, from: pinboard)
                        ui.endSelecting()
                    } label: {
                        Label("Remove from Pinboard", systemImage: "pin.slash")
                    }
                    .disabled(ui.selectedIDs.isEmpty)
                }
            }
            ToolbarItem(placement: .bottomBar) {
                Button(role: .destructive) {
                    confirmDeleteSelection = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
                .disabled(ui.selectedIDs.isEmpty)
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Select") { ui.beginSelecting() }
                    .disabled(visibleItems.isEmpty)
                    .accessibilityIdentifier("selectButton")
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                moreMenu
            }
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
            ToolbarSpacer(.fixed, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                PasteButton(payloadType: PastedClip.self) { pasted in
                    let clips = pasted.map(\.clip)
                    Task { @MainActor in save(clips) }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.circle)
                .overlay(alignment: .topTrailing) {
                    // Something new is on the clipboard (detected without reading it).
                    if hasNewClipboard {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 9, height: 9)
                            .offset(x: 2, y: -2)
                            .allowsHitTesting(false)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .accessibilityLabel(Text("Save Clipboard"))
                .accessibilityValue(hasNewClipboard ? Text("New clipboard content") : Text(""))
                .accessibilityIdentifier("pasteButton")
            }
        }
    }

    private var collectionGlyph: some View {
        Group {
            if let pinboard = currentPinboard {
                Circle()
                    .fill(PinboardPalette.color(for: pinboard, among: pinboards))
                    .frame(width: 10, height: 10)
            } else {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pinSelectionMenu: some View {
        Menu {
            ForEach(pinboards) { pinboard in
                Button {
                    library.add(selectedItems, to: pinboard)
                    ui.show(String(localized: "Added to \(pinboard.name)"), systemImage: "pin.fill")
                    ui.endSelecting()
                } label: {
                    Label {
                        Text(pinboard.name)
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(PinboardPalette.color(for: pinboard, among: pinboards))
                    }
                }
            }
            Divider()
            Button {
                ui.beginNewPinboard(for: selectedItems)
            } label: {
                Label("New Pinboard…", systemImage: "plus")
            }
        } label: {
            Label("Pin", systemImage: "pin")
        }
        .disabled(ui.selectedIDs.isEmpty)
    }

    private var moreMenu: some View {
        Menu {
            Button {
                showPinboards = true
            } label: {
                Label("Pinboards", systemImage: "square.stack")
            }
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
    }

    // MARK: - Overlays

    @ViewBuilder
    private var emptyState: some View {
        if visibleItems.isEmpty {
            if !searchText.isEmpty || !tokens.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if currentPinboard != nil {
                ContentUnavailableView(
                    "No Pinned Clips",
                    systemImage: "pin",
                    description: Text("Long-press a clip and choose Pin to add it here.")
                )
            } else {
                ContentUnavailableView {
                    Label("No Clips Yet", systemImage: "clipboard")
                } description: {
                    Text("Copy something, then tap the paste button to save it here.")
                }
            }
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast = ui.toast {
            Label(toast.message, systemImage: toast.systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(toast.id)
        }
    }
}

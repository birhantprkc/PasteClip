import SwiftData
import SwiftUI

struct PinboardsSheet: View {
    let pinboards: [Pinboard]
    let ui: ClipsUIState

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allItems: [ClipboardItem]

    @State private var renaming: Pinboard?
    @State private var renameText = ""
    @State private var deleting: Pinboard?
    @State private var isCreating = false
    @State private var newName = ""

    private var library: ClipLibrary { ClipLibrary(context: context) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(
                        title: String(localized: "Clipboard"),
                        count: allItems.count,
                        isSelected: ui.collection == .history
                    ) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .onTapGesture { select(.history) }
                    .accessibilityIdentifier("pinboardRow-history")
                }

                Section {
                    ForEach(pinboards) { pinboard in
                        row(
                            title: pinboard.name,
                            count: pinboard.entries.count,
                            isSelected: ui.collection == .pinboard(pinboard.id)
                        ) {
                            Circle()
                                .fill(PinboardPalette.color(for: pinboard, among: pinboards))
                                .frame(width: 12, height: 12)
                        } trailing: {
                            Menu {
                                Button {
                                    renameText = pinboard.name
                                    renaming = pinboard
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    deleting = pinboard
                                } label: {
                                    Label("Delete Pinboard", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel(Text("More for \(pinboard.name)"))
                        }
                        .onTapGesture { select(.pinboard(pinboard.id)) }
                        .accessibilityIdentifier("pinboardRow-\(pinboard.name)")
                    }
                    .onMove(perform: move)
                } header: {
                    if !pinboards.isEmpty {
                        Text("Pinboards")
                    }
                } footer: {
                    if pinboards.isEmpty {
                        Text("Pinboards keep clips you use often. They are never trimmed by the history limit.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Pinboards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newName = ""
                        isCreating = true
                    } label: {
                        Label("New Pinboard", systemImage: "plus")
                    }
                }
            }
            .alert("New Pinboard", isPresented: $isCreating) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    library.createPinboard(named: newName, existing: pinboards)
                }
            }
            .alert("Rename Pinboard", isPresented: renamingBinding) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    if let renaming { library.rename(renaming, to: renameText) }
                }
            }
            .confirmationDialog(
                deleting.map { String(localized: "Delete \"\($0.name)\"?") } ?? "",
                isPresented: deletingBinding,
                titleVisibility: .visible
            ) {
                Button("Delete Pinboard", role: .destructive) {
                    if let deleting {
                        if ui.collection == .pinboard(deleting.id) { ui.collection = .history }
                        library.delete(deleting)
                    }
                }
            } message: {
                Text("Clips stay in your history.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row<Leading: View>(
        title: String,
        count: Int,
        isSelected: Bool,
        @ViewBuilder leading: () -> Leading
    ) -> some View {
        row(title: title, count: count, isSelected: isSelected, leading: leading) { EmptyView() }
    }

    private func row<Leading: View, Trailing: View>(
        title: String,
        count: Int,
        isSelected: Bool,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            leading()
                .frame(width: 24)
            Text(title)
                .font(.body.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
            Spacer()
            Text(count, format: .number)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.accentColor)
            }
            trailing()
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private func select(_ collection: ClipCollection) {
        ui.collection = collection
        dismiss()
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = pinboards
        ordered.move(fromOffsets: source, toOffset: destination)
        library.reorder(ordered)
    }

    private var renamingBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var deletingBinding: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }
}

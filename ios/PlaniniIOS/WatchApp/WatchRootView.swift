import PlaniniCore
import SwiftUI

private struct WatchErrorAlert: Identifiable {
    let id = UUID()
    let message: String
}

struct WatchRootView: View {
    @StateObject private var viewModel = WatchAppViewModel()
    @State private var presentedError: WatchErrorAlert?

    var body: some View {
        NavigationStack {
            List {
                if viewModel.needsPhoneSetup {
                    setupSection
                } else {
                    listsSection
                }
                versionSection
            }
            .navigationTitle("Lists")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isWorking)
                }
            }
        }
        .task {
            await viewModel.performInitialLoad()
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            if let newValue, newValue.isEmpty == false {
                presentedError = WatchErrorAlert(message: newValue)
            }
        }
        .alert(item: $presentedError) { error in
            Alert(
                title: Text("Error"),
                message: Text(error.message),
                dismissButton: .cancel(Text("OK")) {
                    viewModel.errorMessage = nil
                }
            )
        }
    }

    private var setupSection: some View {
        Section {
            Text("The watch needs the iPhone app to be open, unlocked, and signed in before it can sync.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            LabeledContent("iPhone app installed", value: viewModel.isCompanionAppInstalled ? "Yes" : "No")
            LabeledContent("iPhone reachable", value: viewModel.isPhoneReachable ? "Yes" : "No")

            Button(viewModel.setupButtonTitle) {
                Task { await viewModel.refresh() }
            }
            .disabled(viewModel.isWorking)
        } header: {
            Text("Watch setup")
        }
    }

    private var listsSection: some View {
        Section {
            ForEach(viewModel.displayedLists) { list in
                NavigationLink {
                    WatchListDetailView(list: list)
                        .environmentObject(viewModel)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(list.name)
                            if viewModel.isFavorite(list) {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                            }
                        }
                        Text(list.householdName)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var versionSection: some View {
        Section {
            Text(viewModel.versionBuildText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityIdentifier("watch-version-build-label")
        }
    }
}

private struct WatchListDetailView: View {
    @EnvironmentObject private var viewModel: WatchAppViewModel
    let list: GroceryListSummary
    @State private var editingItem: GroceryItemRecord?

    var body: some View {
        List {
            addItemSection
            itemsSection
        }
        .navigationTitle(list.name)
        .task(id: list.id) {
            await viewModel.showList(list)
            viewModel.startLiveUpdates(for: list)
        }
        .onDisappear {
            viewModel.stopLiveUpdates(for: list)
        }
        .sheet(item: $editingItem) { item in
            WatchEditItemSheet(list: list, item: item)
                .environmentObject(viewModel)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if viewModel.canRedoListAction(for: list) {
                    Button {
                        Task { await viewModel.redoLastListAction(in: list) }
                    } label: {
                        Label(viewModel.redoListActionTitle(for: list), systemImage: "arrow.uturn.forward")
                    }
                    .accessibilityIdentifier("watch-list-redo-button")
                    .disabled(viewModel.isWorking)
                }
                Button {
                    Task { await viewModel.undoLastListAction(in: list) }
                } label: {
                    Label(viewModel.undoListActionTitle(for: list), systemImage: "arrow.uturn.backward")
                }
                .accessibilityIdentifier("watch-list-undo-button")
                .disabled(viewModel.canUndoListAction(for: list) == false)
            }
        }
    }

    private var addItemSection: some View {
        Section {
            TextField("What?", text: $viewModel.draftItemName)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .onSubmit {
                    Task { await viewModel.addDraftItem(to: list) }
                }
        } header: {
            Text("Add item")
        }
    }

    private var itemsSection: some View {
        Group {
            if viewModel.sections(for: list).isEmpty {
                Text("Nothing on this list right now.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.sections(for: list)) { section in
                    Section {
                        ForEach(section.items) { item in
                            Button {
                                Task { await viewModel.toggle(item, in: list) }
                            } label: {
                                HStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(
                                            Color(hex: viewModel.categoryColorHex(for: item))
                                                ?? Color.secondary.opacity(0.25)
                                        )
                                        .frame(width: 4)
                                        .frame(maxHeight: .infinity)
                                    Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(item.checked ? .green : .secondary)
                                    Text(item.name)
                                        .strikethrough(item.checked)
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isWorking)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    editingItem = item
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    } header: {
                        WatchSectionHeader(section: section)
                    }
                }
            }
        }
    }
}

private struct WatchSectionHeader: View {
    let section: GroceryItemSection

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(hex: section.colorHex) ?? Color.secondary.opacity(0.4))
                .frame(width: 6, height: 6)
            Text(section.title)
            Text("\(section.itemCount)")
                .foregroundStyle(.secondary)
        }
    }
}

private struct WatchEditItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: WatchAppViewModel

    let list: GroceryListSummary
    let item: GroceryItemRecord

    @State private var note: String
    @State private var categoryID: UUID?

    init(list: GroceryListSummary, item: GroceryItemRecord) {
        self.list = list
        self.item = item
        _note = State(initialValue: item.note ?? "")
        _categoryID = State(initialValue: item.categoryID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    Picker("Category", selection: $categoryID) {
                        Text("Uncategorized").tag(Optional<UUID>.none)
                        ForEach(viewModel.availableCategories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                }

                Section("Notes") {
                    TextField("Note", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            let saved = await viewModel.saveEdit(
                                item: item,
                                note: note,
                                categoryID: categoryID,
                                in: list
                            )
                            if saved {
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.isWorking)
                }
            }
        }
    }
}

private extension Color {
    init?(hex: String?) {
        guard let hex else { return nil }
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }

        let red = Double((value & 0xFF0000) >> 16) / 255
        let green = Double((value & 0x00FF00) >> 8) / 255
        let blue = Double(value & 0x0000FF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

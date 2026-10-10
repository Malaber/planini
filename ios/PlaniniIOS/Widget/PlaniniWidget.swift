import ActivityKit
import AppIntents
import PlaniniCore
import SwiftUI
import UIKit
import WidgetKit

struct PlaniniListEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Planini List")
    static let defaultQuery = PlaniniListQuery()

    let id: UUID
    let name: String
    let householdName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(householdName)")
    }
}

struct PlaniniListQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [PlaniniListEntity] {
        availableListEntities().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [PlaniniListEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return availableListEntities() }
        return availableListEntities().filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.householdName.localizedCaseInsensitiveContains(query)
        }
    }

    func suggestedEntities() async throws -> [PlaniniListEntity] {
        availableListEntities()
    }

    private func availableListEntities() -> [PlaniniListEntity] {
        WatchSharedContainer.stateStore.load().lists
            .sorted { left, right in
                if left.householdName != right.householdName {
                    return left.householdName.localizedCaseInsensitiveCompare(right.householdName) == .orderedAscending
                }
                return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }
            .map {
                PlaniniListEntity(
                    id: $0.id,
                    name: $0.name,
                    householdName: $0.householdName
                )
            }
    }
}

struct SelectPlaniniListIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Planini List"
    static let description = IntentDescription("Choose the list shown on the widget.")

    @Parameter(title: "List")
    var list: PlaniniListEntity?

    init() {}

    init(list: PlaniniListEntity?) {
        self.list = list
    }
}

struct TogglePlaniniWidgetItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Planini Item"
    static let openAppWhenRun = false

    @Parameter(title: "Item ID")
    var itemID: String

    @Parameter(title: "List ID")
    var listID: String

    init() {}

    init(itemID: UUID, listID: UUID) {
        self.itemID = itemID.uuidString
        self.listID = listID.uuidString
    }

    func perform() async throws -> some IntentResult {
        let itemID = try uuid(from: itemID)
        let listID = try uuid(from: listID)
        let store = WatchSharedContainer.stateStore
        var state = store.load()
        if state.syncedListID != listID {
            state = try await WatchBackendClient().refreshItems(for: listID, using: state)
        }
        guard let item = state.items.first(where: { $0.id == itemID }) else {
            throw PlaniniWidgetIntentError.missingItem
        }
        let updatedState = try await WatchBackendClient().toggle(item, in: listID, using: state)
        store.save(updatedState)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct AddPlaniniWidgetItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Planini Item"
    static let openAppWhenRun = false

    @Parameter(title: "List ID")
    var listID: String

    init() {}

    init(listID: UUID) {
        self.listID = listID.uuidString
    }

    func perform() async throws -> some IntentResult {
        let listID = try uuid(from: listID)
        let store = WatchSharedContainer.stateStore
        let state = store.load()
        let updatedState = try await WatchBackendClient().addItem(
            named: state.quickAddItemName,
            to: listID,
            using: state
        )
        store.save(updatedState)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

private enum PlaniniWidgetIntentError: LocalizedError {
    case invalidID
    case missingItem

    var errorDescription: String? {
        switch self {
        case .invalidID:
            return "The widget action has an invalid identifier."
        case .missingItem:
            return "The widget could not find that item."
        }
    }
}

private func uuid(from value: String) throws -> UUID {
    guard let uuid = UUID(uuidString: value) else {
        throw PlaniniWidgetIntentError.invalidID
    }
    return uuid
}

struct PlaniniListWidgetEntry: TimelineEntry {
    let date: Date
    let configuration: SelectPlaniniListIntent
    let state: SharedAppState
    let selectedList: GroceryListSummary?
    let items: [GroceryItemRecord]
    let errorMessage: String?
}

struct PlaniniListWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PlaniniListWidgetEntry {
        let listID = UUID()
        let state = SharedAppState(
            backendURL: URL(string: "https://planini.top"),
            authToken: "token",
            syncedListID: listID,
            quickAddItemName: "Milk",
            lists: [
                GroceryListSummary(
                    id: listID,
                    householdID: UUID(),
                    householdName: "Home",
                    name: "Groceries",
                    archived: false
                )
            ],
            items: [
                GroceryItemRecord(
                    id: UUID(),
                    listID: listID,
                    name: "Bread",
                    quantityText: "1",
                    note: nil,
                    categoryID: nil,
                    checked: false,
                    checkedAt: nil,
                    sortOrder: 0
                ),
                GroceryItemRecord(
                    id: UUID(),
                    listID: listID,
                    name: "Apples",
                    quantityText: nil,
                    note: nil,
                    categoryID: nil,
                    checked: true,
                    checkedAt: nil,
                    sortOrder: 1
                ),
            ]
        )
        return PlaniniListWidgetEntry(
            date: .now,
            configuration: SelectPlaniniListIntent(list: nil),
            state: state,
            selectedList: state.lists.first,
            items: state.items(for: listID),
            errorMessage: nil
        )
    }

    func snapshot(
        for configuration: SelectPlaniniListIntent,
        in context: Context
    ) async -> PlaniniListWidgetEntry {
        await entry(for: configuration)
    }

    func timeline(
        for configuration: SelectPlaniniListIntent,
        in context: Context
    ) async -> Timeline<PlaniniListWidgetEntry> {
        let entry = await entry(for: configuration)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    private func entry(for configuration: SelectPlaniniListIntent) async -> PlaniniListWidgetEntry {
        let store = WatchSharedContainer.stateStore
        let storedState = store.load()
        let selectedListID = configuration.list?.id
            ?? storedState.favoriteListID
            ?? storedState.lists.first?.id
        guard let selectedListID else {
            return PlaniniListWidgetEntry(
                date: .now,
                configuration: configuration,
                state: storedState,
                selectedList: nil,
                items: [],
                errorMessage: "Open Planini"
            )
        }

        var state = storedState
        var errorMessage: String?
        if state.hasAuthenticatedSession {
            do {
                let snapshot = try await WatchBackendClient().refreshList(for: selectedListID, using: state)
                state = snapshot.state
                store.save(state)
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            errorMessage = "Sign in on iPhone"
        }

        return PlaniniListWidgetEntry(
            date: .now,
            configuration: configuration,
            state: state,
            selectedList: state.list(id: selectedListID),
            items: state.items(for: selectedListID),
            errorMessage: errorMessage
        )
    }
}

struct PlaniniListWidgetEntryView: View {
    let entry: PlaniniListWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var itemLimit: Int {
        switch family {
        case .systemSmall:
            return 3
        case .systemMedium:
            return 5
        default:
            return 8
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if let errorMessage = entry.errorMessage, entry.items.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if entry.items.isEmpty {
                Text("All done")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entry.items.prefix(itemLimit)) { item in
                    itemRow(item)
                }
            }

            Spacer(minLength: 0)

            if let listID = entry.selectedList?.id, entry.state.hasAuthenticatedSession {
                Button(intent: AddPlaniniWidgetItemIntent(listID: listID)) {
                    Label(entry.state.quickAddItemName, systemImage: "plus.circle.fill")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
        }
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "cart")
                .foregroundStyle(.tint)
            Text(entry.selectedList?.name ?? "Planini")
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 0)
            if entry.items.isEmpty == false {
                Text("\(entry.items.filter { $0.checked == false }.count)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func itemRow(_ item: GroceryItemRecord) -> some View {
        let selectedListID = entry.selectedList?.id ?? item.listID
        return Button(intent: TogglePlaniniWidgetItemIntent(itemID: item.id, listID: selectedListID)) {
            HStack(spacing: 6) {
                Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.checked ? .green : .secondary)
                Text(item.name)
                    .font(.caption)
                    .strikethrough(item.checked)
                    .foregroundStyle(item.checked ? .secondary : .primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }
}

struct PlaniniListWidget: Widget {
    let kind = "PlaniniListWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectPlaniniListIntent.self, provider: PlaniniListWidgetProvider()) { entry in
            PlaniniListWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Planini List")
        .description("Show a Planini list on your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct PlaniniShoppingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PlaniniShoppingActivityAttributes.self) { context in
            ShoppingActivityLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color(.systemBackground))
                .activitySystemActionForegroundColor(.accentColor)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.listName, systemImage: "cart.fill")
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.remainingText)
                        .font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.nextItemsText)
                        .font(.caption)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "cart.fill")
            } compactTrailing: {
                Text("\(context.state.remainingItemCount)")
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "cart.fill")
            }
            .keylineTint(.accentColor)
        }
    }
}

private struct ShoppingActivityLockScreenView: View {
    let attributes: PlaniniShoppingActivityAttributes
    let state: PlaniniShoppingActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "cart.fill")
                    .foregroundStyle(.tint)
                Text(attributes.listName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(state.remainingText)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(state.nextItemsText)
                .font(.subheadline)
                .lineLimit(2)

            HStack {
                Text(timerInterval: Date()...state.expiresAt, countsDown: true)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Add \(state.quickAddItemName)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .lineLimit(1)
            }
        }
        .padding()
    }
}

private extension PlaniniShoppingActivityAttributes.ContentState {
    var remainingText: String {
        "\(remainingItemCount)/\(totalItemCount)"
    }

    var nextItemsText: String {
        if uncheckedItemNames.isEmpty {
            return "All done"
        }
        return uncheckedItemNames.prefix(3).joined(separator: ", ")
    }
}

@main
struct PlaniniWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlaniniListWidget()
        PlaniniShoppingLiveActivity()
    }
}

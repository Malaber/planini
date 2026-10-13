#if os(iOS)
import ActivityKit
import AppIntents
import Foundation
import PlaniniCore
import WidgetKit

struct CheckShoppingActivityItemIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Check shopping item"
    static let openAppWhenRun = false

    @Parameter(title: "List ID") var listID: String
    @Parameter(title: "Item ID") var itemID: String
    @Parameter(title: "Checked") var checked: Bool

    init() {}

    init(listID: UUID, item: ShoppingChecklistItem) {
        self.listID = listID.uuidString
        self.itemID = item.id.uuidString
        self.checked = !item.checked
    }

    func perform() async throws -> some IntentResult {
        guard let listID = UUID(uuidString: listID), let itemID = UUID(uuidString: itemID) else {
            throw WatchBackendClientError.invalidResponse
        }
        let store = WatchSharedContainer.stateStore
        let client = WatchBackendClient()
        let state = try await client.refreshItems(for: listID, using: store.load())
        guard let item = state.items.first(where: { $0.id == itemID }) else {
            throw WatchBackendClientError.invalidResponse
        }
        let result = try await client.setChecked(checked, for: item, in: listID, using: state)
        let updated = result.snapshot.state
        store.save(updated)
        for activity in Activity<PlaniniShoppingActivityAttributes>.activities
        where activity.attributes.listID == listID {
            guard let snapshot = updated.shoppingSnapshot(for: listID, startedAt: activity.attributes.startedAt) else {
                continue
            }
            await activity.update(ActivityContent(state: .init(snapshot: snapshot), staleDate: snapshot.expiresAt))
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
#endif

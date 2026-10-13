import Foundation
import PlaniniCore

#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.2, *)
@MainActor
final class ShoppingActivityController {
    private var expirationTasks: [String: Task<Void, Never>] = [:]
    var onActivityExpired: ((UUID) -> Void)?

    var activitiesAreEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    var activeListID: UUID? {
        Activity<PlaniniShoppingActivityAttributes>.activities.first {
            $0.activityState == .active && $0.content.state.expiresAt > Date()
        }?.attributes.listID
    }

    func stop() async {
        for activity in Activity<PlaniniShoppingActivityAttributes>.activities {
            expirationTasks[activity.id]?.cancel()
            expirationTasks[activity.id] = nil
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    func start(listID: UUID, using state: SharedAppState) async throws -> ShoppingListSnapshot {
        guard let snapshot = state.shoppingSnapshot(for: listID) else {
            throw ShoppingActivityError.missingList
        }
        guard activitiesAreEnabled else {
            throw ShoppingActivityError.disabled
        }

        await stop()

        let attributes = PlaniniShoppingActivityAttributes(
            listID: snapshot.listID,
            listName: String(snapshot.listName.prefix(64)),
            startedAt: snapshot.startedAt
        )
        let content = ActivityContent(
            state: PlaniniShoppingActivityAttributes.ContentState(snapshot: snapshot),
            staleDate: snapshot.expiresAt
        )
        let activity = try Activity.request(
            attributes: attributes,
            content: content,
            pushType: nil
        )
        scheduleExpiration(for: activity, snapshot: snapshot)
        return snapshot
    }

    func update(listID: UUID, using state: SharedAppState) async {
        for activity in Activity<PlaniniShoppingActivityAttributes>.activities where activity.attributes.listID == listID {
            guard let snapshot = state.shoppingSnapshot(
                for: listID,
                startedAt: activity.attributes.startedAt
            ) else {
                return
            }
            let content = ActivityContent(
                state: PlaniniShoppingActivityAttributes.ContentState(snapshot: snapshot),
                staleDate: snapshot.expiresAt
            )
            await activity.update(content)
            scheduleExpiration(for: activity, snapshot: snapshot)
        }
    }

    func endActivities(for listID: UUID) async {
        for activity in Activity<PlaniniShoppingActivityAttributes>.activities where activity.attributes.listID == listID {
            expirationTasks[activity.id]?.cancel()
            expirationTasks[activity.id] = nil
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func scheduleExpiration(
        for activity: Activity<PlaniniShoppingActivityAttributes>,
        snapshot: ShoppingListSnapshot
    ) {
        expirationTasks[activity.id]?.cancel()
        let delay = max(snapshot.expiresAt.timeIntervalSinceNow, 0)
        let listID = activity.attributes.listID
        expirationTasks[activity.id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard Task.isCancelled == false else { return }
            let content = ActivityContent(
                state: PlaniniShoppingActivityAttributes.ContentState(snapshot: snapshot),
                staleDate: snapshot.expiresAt
            )
            await activity.end(content, dismissalPolicy: .immediate)
            await MainActor.run {
                self?.expirationTasks[activity.id] = nil
                self?.onActivityExpired?(listID)
            }
        }
    }
}

enum ShoppingActivityError: LocalizedError {
    case disabled
    case missingList

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "Live Activities are disabled for Planini."
        case .missingList:
            return "Open a list before starting shopping mode."
        }
    }
}
#endif

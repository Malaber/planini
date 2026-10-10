import Foundation
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

public struct ShoppingListSnapshot: Codable, Equatable, Sendable {
    public static let liveActivityDuration: TimeInterval = 3 * 60 * 60

    public let listID: UUID
    public let listName: String
    public let totalItemCount: Int
    public let checkedItemCount: Int
    public let uncheckedItemNames: [String]
    public let quickAddItemName: String
    public let startedAt: Date
    public let expiresAt: Date

    public init(
        listID: UUID,
        listName: String,
        totalItemCount: Int,
        checkedItemCount: Int,
        uncheckedItemNames: [String],
        quickAddItemName: String,
        startedAt: Date,
        expiresAt: Date
    ) {
        self.listID = listID
        self.listName = listName
        self.totalItemCount = totalItemCount
        self.checkedItemCount = checkedItemCount
        self.uncheckedItemNames = uncheckedItemNames
        self.quickAddItemName = quickAddItemName
        self.startedAt = startedAt
        self.expiresAt = expiresAt
    }

    public var remainingItemCount: Int {
        max(totalItemCount - checkedItemCount, 0)
    }

    public func isExpired(at date: Date = Date()) -> Bool {
        date >= expiresAt
    }
}

public struct SharedAppState: Codable, Equatable, Sendable {
    public static let defaultQuickAddItemName = "Milk"

    public var backendURL: URL?
    public var authToken: String?
    public var displayName: String?
    public var favoriteListID: UUID?
    public var syncedListID: UUID?
    public var quickAddItemName: String
    public var lists: [GroceryListSummary]
    public var items: [GroceryItemRecord]
    public var categories: [GroceryCategorySummary]
    public var categoryOrder: [ListCategoryOrderEntry]

    public init(
        backendURL: URL? = nil,
        authToken: String? = nil,
        displayName: String? = nil,
        favoriteListID: UUID? = nil,
        syncedListID: UUID? = nil,
        quickAddItemName: String = SharedAppState.defaultQuickAddItemName,
        lists: [GroceryListSummary] = [],
        items: [GroceryItemRecord] = [],
        categories: [GroceryCategorySummary] = [],
        categoryOrder: [ListCategoryOrderEntry] = []
    ) {
        self.backendURL = backendURL
        self.authToken = authToken
        self.displayName = displayName
        self.favoriteListID = favoriteListID
        self.syncedListID = syncedListID
        self.quickAddItemName = quickAddItemName
        self.lists = lists
        self.items = items
        self.categories = categories
        self.categoryOrder = categoryOrder
    }

    private enum CodingKeys: String, CodingKey {
        case backendURL
        case authToken
        case displayName
        case favoriteListID
        case syncedListID
        case quickAddItemName
        case lists
        case items
        case categories
        case categoryOrder
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        backendURL = try container.decodeIfPresent(URL.self, forKey: .backendURL)
        authToken = try container.decodeIfPresent(String.self, forKey: .authToken)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        favoriteListID = try container.decodeIfPresent(UUID.self, forKey: .favoriteListID)
        syncedListID = try container.decodeIfPresent(UUID.self, forKey: .syncedListID)
        quickAddItemName = try container.decodeIfPresent(String.self, forKey: .quickAddItemName)
            ?? SharedAppState.defaultQuickAddItemName
        lists = try container.decodeIfPresent([GroceryListSummary].self, forKey: .lists) ?? []
        items = try container.decodeIfPresent([GroceryItemRecord].self, forKey: .items) ?? []
        categories = try container.decodeIfPresent([GroceryCategorySummary].self, forKey: .categories) ?? []
        categoryOrder = try container.decodeIfPresent([ListCategoryOrderEntry].self, forKey: .categoryOrder) ?? []
    }

    public var favoriteList: GroceryListSummary? {
        guard let favoriteListID else { return nil }
        return lists.first { $0.id == favoriteListID }
    }

    public var favoriteListName: String? {
        favoriteList?.name
    }

    public var hasAuthenticatedSession: Bool {
        backendURL != nil && !(authToken?.isEmpty ?? true)
    }

    public var canQuickAdd: Bool {
        hasAuthenticatedSession
            && favoriteListID != nil
            && quickAddItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    public var syncedListName: String? {
        guard let syncedListID else { return nil }
        return list(id: syncedListID)?.name
    }

    public func list(id listID: UUID) -> GroceryListSummary? {
        lists.first { $0.id == listID }
    }

    public func items(for listID: UUID) -> [GroceryItemRecord] {
        guard (syncedListID ?? favoriteListID) == listID else { return [] }
        return items
            .filter { $0.listID == listID }
            .sorted { left, right in
                if left.checked != right.checked {
                    return left.checked == false
                }
                return left.sortOrder < right.sortOrder
            }
    }

    public func shoppingSnapshot(
        for listID: UUID,
        startedAt: Date = Date(),
        duration: TimeInterval = ShoppingListSnapshot.liveActivityDuration
    ) -> ShoppingListSnapshot? {
        guard let list = list(id: listID) else { return nil }
        let listItems = items(for: listID)
        let uncheckedNames = listItems
            .filter { $0.checked == false }
            .map(\.name)
        return ShoppingListSnapshot(
            listID: listID,
            listName: list.name,
            totalItemCount: listItems.count,
            checkedItemCount: listItems.filter(\.checked).count,
            uncheckedItemNames: uncheckedNames,
            quickAddItemName: quickAddItemName,
            startedAt: startedAt,
            expiresAt: startedAt.addingTimeInterval(duration)
        )
    }
}

#if canImport(ActivityKit) && os(iOS)
@available(iOS 16.2, *)
public struct PlaniniShoppingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public let checkedItemCount: Int
        public let totalItemCount: Int
        public let uncheckedItemNames: [String]
        public let quickAddItemName: String
        public let expiresAt: Date

        public init(
            checkedItemCount: Int,
            totalItemCount: Int,
            uncheckedItemNames: [String],
            quickAddItemName: String,
            expiresAt: Date
        ) {
            self.checkedItemCount = checkedItemCount
            self.totalItemCount = totalItemCount
            self.uncheckedItemNames = uncheckedItemNames
            self.quickAddItemName = quickAddItemName
            self.expiresAt = expiresAt
        }

        public init(snapshot: ShoppingListSnapshot) {
            self.init(
                checkedItemCount: snapshot.checkedItemCount,
                totalItemCount: snapshot.totalItemCount,
                uncheckedItemNames: snapshot.uncheckedItemNames,
                quickAddItemName: snapshot.quickAddItemName,
                expiresAt: snapshot.expiresAt
            )
        }

        public var remainingItemCount: Int {
            max(totalItemCount - checkedItemCount, 0)
        }
    }

    public let listID: UUID
    public let listName: String
    public let startedAt: Date

    public init(listID: UUID, listName: String, startedAt: Date) {
        self.listID = listID
        self.listName = listName
        self.startedAt = startedAt
    }
}
#endif

public enum PlaniniSharedConstants {
    public static let watchAppGroupID = "group.de.malaber.planini.watch"
    public static let sharedAppStateKey = "planini.shared-app-state"
    public static let watchContextPayloadKey = "state"
}

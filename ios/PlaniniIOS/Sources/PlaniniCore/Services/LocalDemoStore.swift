import Foundation

public struct LocalDemoListData: Codable, Equatable, Sendable {
    public let items: [GroceryItemRecord]
    public let categories: [GroceryCategorySummary]
    public let categoryOrder: [ListCategoryOrderEntry]
    public let disabledCategoryIDs: [UUID]

    public init(
        items: [GroceryItemRecord],
        categories: [GroceryCategorySummary],
        categoryOrder: [ListCategoryOrderEntry],
        disabledCategoryIDs: [UUID] = []
    ) {
        self.items = items
        self.categories = categories
        self.categoryOrder = categoryOrder
        self.disabledCategoryIDs = disabledCategoryIDs
    }

    private enum CodingKeys: String, CodingKey {
        case items
        case categories
        case categoryOrder
        case disabledCategoryIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([GroceryItemRecord].self, forKey: .items)
        categories = try container.decode([GroceryCategorySummary].self, forKey: .categories)
        categoryOrder = try container.decode([ListCategoryOrderEntry].self, forKey: .categoryOrder)
        disabledCategoryIDs = try container.decodeIfPresent([UUID].self, forKey: .disabledCategoryIDs) ?? []
    }
}

public struct LocalDemoSnapshot: Codable, Equatable, Sendable {
    public var households: [HouseholdSummary]
    public var lists: [GroceryListSummary]
    public var listData: [UUID: LocalDemoListData]
    public var favoriteListID: UUID?
    public var selectedListID: UUID?

    public init(
        households: [HouseholdSummary],
        lists: [GroceryListSummary],
        listData: [UUID: LocalDemoListData],
        favoriteListID: UUID?,
        selectedListID: UUID?
    ) {
        self.households = households
        self.lists = lists
        self.listData = listData
        self.favoriteListID = favoriteListID
        self.selectedListID = selectedListID
    }

    public static func seeded() -> LocalDemoSnapshot {
        let householdID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
        let listID = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
        let categoryIDs = [
            UUID(uuidString: "30000000-0000-4000-8000-000000000001")!,
            UUID(uuidString: "30000000-0000-4000-8000-000000000002")!,
            UUID(uuidString: "30000000-0000-4000-8000-000000000003")!,
            UUID(uuidString: "30000000-0000-4000-8000-000000000004")!,
        ]
        let categories = [
            GroceryCategorySummary(
                id: categoryIDs[0],
                name: "Gemuese",
                colorHex: "#7ed957",
                aliases: ["Gruenzeug"]
            ),
            GroceryCategorySummary(
                id: categoryIDs[1],
                name: "Milch & Eier",
                colorHex: "#d8b4e2",
                aliases: ["Molkerei"]
            ),
            GroceryCategorySummary(
                id: categoryIDs[2],
                name: "Nudeln",
                colorHex: "#d6b08b",
                aliases: ["Pasta"]
            ),
            GroceryCategorySummary(
                id: categoryIDs[3],
                name: "Haushalt",
                colorHex: "#64748b",
                aliases: ["Home"]
            ),
        ]
        let household = HouseholdSummary(id: householdID, name: "Demo household")
        let list = GroceryListSummary(
            id: listID,
            householdID: householdID,
            householdName: household.name,
            name: "Weekly groceries",
            archived: false,
            accentColorHex: "#3b82f6"
        )
        let items = [
            GroceryItemRecord(
                id: UUID(uuidString: "40000000-0000-4000-8000-000000000001")!,
                listID: listID,
                name: "Apples",
                quantityText: "6",
                note: nil,
                categoryID: categoryIDs[0],
                checked: false,
                checkedAt: nil,
                sortOrder: 0
            ),
            GroceryItemRecord(
                id: UUID(uuidString: "40000000-0000-4000-8000-000000000002")!,
                listID: listID,
                name: "Milk",
                quantityText: "2 cartons",
                note: nil,
                categoryID: categoryIDs[1],
                checked: false,
                checkedAt: nil,
                sortOrder: 1
            ),
            GroceryItemRecord(
                id: UUID(uuidString: "40000000-0000-4000-8000-000000000003")!,
                listID: listID,
                name: "Pasta",
                quantityText: nil,
                note: "For dinner",
                categoryID: categoryIDs[2],
                checked: true,
                checkedAt: Date(timeIntervalSince1970: 1_700_000_000),
                sortOrder: 2
            ),
        ]
        let data = LocalDemoListData(
            items: items,
            categories: categories,
            categoryOrder: categoryIDs.enumerated().map {
                ListCategoryOrderEntry(categoryID: $0.element, sortOrder: $0.offset)
            }
        )
        return LocalDemoSnapshot(
            households: [household],
            lists: [list],
            listData: [listID: data],
            favoriteListID: listID,
            selectedListID: listID
        )
    }
}

public final class LocalDemoStore: @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "planini.localDemoSnapshot"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    public func load() -> LocalDemoSnapshot? {
        guard let data = userDefaults.data(forKey: storageKey) else { return nil }
        return try? decoder.decode(LocalDemoSnapshot.self, from: data)
    }

    public func loadOrSeed() -> LocalDemoSnapshot {
        if let snapshot = load() {
            return snapshot
        }
        let snapshot = LocalDemoSnapshot.seeded()
        save(snapshot)
        return snapshot
    }

    public func save(_ snapshot: LocalDemoSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        userDefaults.set(data, forKey: storageKey)
    }

    public func clear() {
        userDefaults.removeObject(forKey: storageKey)
    }
}

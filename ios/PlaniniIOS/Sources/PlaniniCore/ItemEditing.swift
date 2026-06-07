import Foundation

public struct GroceryItemEditPayload: Codable, Equatable, Sendable {
    public var name: String
    public var quantityText: String?
    public var note: String?
    public var categoryID: UUID?

    public init(name: String, quantityText: String?, note: String?, categoryID: UUID?) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.quantityText = Self.normalizedOptionalText(quantityText)
        self.note = Self.normalizedOptionalText(note)
        self.categoryID = categoryID
    }

    public init(item: GroceryItemRecord) {
        self.init(
            name: item.name,
            quantityText: item.quantityText,
            note: item.note,
            categoryID: item.categoryID
        )
    }

    public var isValid: Bool {
        name.isEmpty == false
    }

    public var jsonBody: [String: Any] {
        [
            "name": name,
            "quantity_text": quantityText ?? NSNull(),
            "note": note ?? NSNull(),
            "category_id": categoryID?.uuidString ?? NSNull(),
        ]
    }

    private static func normalizedOptionalText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct GroceryItemEditHistory: Codable, Equatable, Sendable {
    public private(set) var undoStack: [GroceryItemEditPayload]
    public private(set) var redoStack: [GroceryItemEditPayload]
    public let limit: Int

    public init(
        undoStack: [GroceryItemEditPayload] = [],
        redoStack: [GroceryItemEditPayload] = [],
        limit: Int = 25
    ) {
        self.undoStack = Array(undoStack.suffix(limit))
        self.redoStack = Array(redoStack.suffix(limit))
        self.limit = limit
    }

    public var canUndo: Bool {
        undoStack.isEmpty == false
    }

    public var canRedo: Bool {
        redoStack.isEmpty == false
    }

    public mutating func record(previous payload: GroceryItemEditPayload, current: GroceryItemEditPayload) {
        guard payload != current else { return }
        undoStack.append(payload)
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
        redoStack.removeAll()
    }

    public mutating func undo(current: GroceryItemEditPayload) -> GroceryItemEditPayload? {
        guard let payload = undoStack.popLast() else { return nil }
        redoStack.append(current)
        if redoStack.count > limit {
            redoStack.removeFirst(redoStack.count - limit)
        }
        return payload
    }

    public mutating func redo(current: GroceryItemEditPayload) -> GroceryItemEditPayload? {
        guard let payload = redoStack.popLast() else { return nil }
        undoStack.append(current)
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
        return payload
    }
}

public enum GroceryCategorySelectionSort: String, CaseIterable, Hashable, Sendable {
    case listOrder
    case nameAscending
    case nameDescending
    case mostUsed
}

public struct GroceryCategorySelectionOption: Identifiable, Equatable, Sendable {
    public let category: GroceryCategorySummary
    public let itemCount: Int

    public init(category: GroceryCategorySummary, itemCount: Int) {
        self.category = category
        self.itemCount = itemCount
    }

    public var id: UUID {
        category.id
    }
}

public enum GroceryCategorySelectionBuilder {
    public static func options(
        categories: [GroceryCategorySummary],
        items: [GroceryItemRecord],
        categoryOrder: [ListCategoryOrderEntry],
        query: String,
        sort: GroceryCategorySelectionSort
    ) -> [GroceryCategorySelectionOption] {
        let normalizedQuery = normalizedSearchText(query)
        let itemCounts = items.reduce(into: [UUID: Int]()) { counts, item in
            guard let categoryID = item.categoryID else { return }
            counts[categoryID, default: 0] += 1
        }
        let explicitOrder = Dictionary(uniqueKeysWithValues: categoryOrder.map { ($0.categoryID, $0.sortOrder) })

        return categories
            .filter { category in
                normalizedQuery.isEmpty || matchesSearch(category, query: normalizedQuery)
            }
            .map { category in
                GroceryCategorySelectionOption(
                    category: category,
                    itemCount: itemCounts[category.id, default: 0]
                )
            }
            .sorted { left, right in
                compare(left, right, sort: sort, explicitOrder: explicitOrder)
            }
    }

    public static func uncategorizedItemCount(items: [GroceryItemRecord]) -> Int {
        items.filter { $0.categoryID == nil }.count
    }

    private static func compare(
        _ left: GroceryCategorySelectionOption,
        _ right: GroceryCategorySelectionOption,
        sort: GroceryCategorySelectionSort,
        explicitOrder: [UUID: Int]
    ) -> Bool {
        switch sort {
        case .listOrder:
            return compareByListOrder(left, right, explicitOrder: explicitOrder)
        case .nameAscending:
            return compareNames(left.category.name, right.category.name, ascending: true)
        case .nameDescending:
            return compareNames(left.category.name, right.category.name, ascending: false)
        case .mostUsed:
            if left.itemCount != right.itemCount {
                return left.itemCount > right.itemCount
            }
            return compareNames(left.category.name, right.category.name, ascending: true)
        }
    }

    private static func compareByListOrder(
        _ left: GroceryCategorySelectionOption,
        _ right: GroceryCategorySelectionOption,
        explicitOrder: [UUID: Int]
    ) -> Bool {
        let leftOrder = explicitOrder[left.category.id]
        let rightOrder = explicitOrder[right.category.id]
        if let leftOrder, let rightOrder, leftOrder != rightOrder {
            return leftOrder < rightOrder
        }
        if (leftOrder != nil) != (rightOrder != nil) {
            return leftOrder != nil
        }
        return compareNames(left.category.name, right.category.name, ascending: true)
    }

    private static func compareNames(_ left: String, _ right: String, ascending: Bool) -> Bool {
        let ordering = left.localizedCaseInsensitiveCompare(right)
        if ordering == .orderedSame {
            return left < right
        }
        return ascending ? ordering == .orderedAscending : ordering == .orderedDescending
    }

    private static func normalizedSearchText(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matchesSearch(_ category: GroceryCategorySummary, query: String) -> Bool {
        ([category.name] + category.aliases).contains { searchText in
            GroceryItemSuggestionMatcher.itemSuggestionMatch(itemName: searchText, query: query) != nil
        }
    }
}

public extension GroceryItemRecord {
    func applyingEditPayload(_ payload: GroceryItemEditPayload) -> GroceryItemRecord {
        GroceryItemRecord(
            id: id,
            listID: listID,
            name: payload.name,
            quantityText: payload.quantityText,
            note: payload.note,
            categoryID: payload.categoryID,
            checked: checked,
            checkedAt: checkedAt,
            sortOrder: sortOrder
        )
    }

    func applyingCheckedState(_ checked: Bool, recordedAt: Date) -> GroceryItemRecord {
        GroceryItemRecord(
            id: id,
            listID: listID,
            name: name,
            quantityText: quantityText,
            note: note,
            categoryID: categoryID,
            checked: checked,
            checkedAt: checked ? recordedAt : nil,
            sortOrder: sortOrder
        )
    }
}

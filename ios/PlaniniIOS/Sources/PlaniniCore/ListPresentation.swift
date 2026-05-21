import Foundation

public struct HouseholdSummary: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    public init?(json: [String: Any]) {
        guard
            let idText = json["id"] as? String,
            let id = UUID(uuidString: idText),
            let name = json["name"] as? String
        else {
            return nil
        }

        self.init(id: id, name: name)
    }
}

public struct HouseholdInviteLink: Equatable, Sendable {
    public let inviteURL: String
    public let expiresAt: Date?

    public init(inviteURL: String, expiresAt: Date?) {
        self.inviteURL = inviteURL
        self.expiresAt = expiresAt
    }

    public init?(json: [String: Any]) {
        guard let inviteURL = json["invite_url"] as? String else {
            return nil
        }

        let expiresAt = (json["expires_at"] as? String).flatMap(Self.parseDate)
        self.init(inviteURL: inviteURL, expiresAt: expiresAt)
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatterWithFractions = ISO8601DateFormatter()
        formatterWithFractions.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = formatterWithFractions.date(from: value) {
            return parsed
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

public struct GroceryListSummary: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let householdID: UUID
    public let householdName: String
    public let name: String
    public let archived: Bool

    public init(id: UUID, householdID: UUID, householdName: String, name: String, archived: Bool) {
        self.id = id
        self.householdID = householdID
        self.householdName = householdName
        self.name = name
        self.archived = archived
    }
}

public struct GroceryCategorySummary: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let colorHex: String?
    public let aliases: [String]

    public init(id: UUID, name: String, colorHex: String?, aliases: [String] = []) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.aliases = aliases
    }

    public init?(json: [String: Any]) {
        guard
            let idText = json["id"] as? String,
            let id = UUID(uuidString: idText),
            let name = json["name"] as? String
        else {
            return nil
        }

        self.init(
            id: id,
            name: name,
            colorHex: json["color"] as? String,
            aliases: json["aliases"] as? [String] ?? []
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case colorHex
        case aliases
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
    }
}

public struct ListCategoryOrderEntry: Equatable, Codable, Sendable {
    public let categoryID: UUID
    public let sortOrder: Int

    public init(categoryID: UUID, sortOrder: Int) {
        self.categoryID = categoryID
        self.sortOrder = sortOrder
    }

    public init?(json: [String: Any]) {
        guard
            let categoryIDText = json["category_id"] as? String,
            let categoryID = UUID(uuidString: categoryIDText),
            let sortOrder = json["sort_order"] as? Int
        else {
            return nil
        }

        self.init(categoryID: categoryID, sortOrder: sortOrder)
    }
}

public enum ListCategoryMoveDirection: Sendable {
    case up
    case down
}

public enum ListCategoryPresentation {
    public static func orderedCategories(
        categories: [GroceryCategorySummary],
        categoryOrder: [ListCategoryOrderEntry]
    ) -> [GroceryCategorySummary] {
        let categoryLookup = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let explicitCategoryIDs = categoryOrder
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.categoryID.uuidString < $1.categoryID.uuidString
            }
            .map(\.categoryID)

        var seenCategoryIDs = Set<UUID>()
        var ordered = explicitCategoryIDs.compactMap { categoryID -> GroceryCategorySummary? in
            guard seenCategoryIDs.insert(categoryID).inserted else { return nil }
            return categoryLookup[categoryID]
        }

        ordered.append(
            contentsOf: categories
                .filter { seenCategoryIDs.contains($0.id) == false }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        )
        return ordered
    }

    public static func availableCategories(
        categories: [GroceryCategorySummary],
        disabledCategoryIDs: Set<UUID>
    ) -> [GroceryCategorySummary] {
        categories
            .filter { disabledCategoryIDs.contains($0.id) == false }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func movedCategoryIDs(
        categories: [GroceryCategorySummary],
        categoryOrder: [ListCategoryOrderEntry],
        moving categoryID: UUID,
        direction: ListCategoryMoveDirection
    ) -> [UUID]? {
        var categoryIDs = orderedCategories(categories: categories, categoryOrder: categoryOrder).map(\.id)
        guard let currentIndex = categoryIDs.firstIndex(of: categoryID) else { return nil }

        let nextIndex: Int
        switch direction {
        case .up:
            guard currentIndex > categoryIDs.startIndex else { return nil }
            nextIndex = categoryIDs.index(before: currentIndex)
        case .down:
            guard currentIndex < categoryIDs.index(before: categoryIDs.endIndex) else { return nil }
            nextIndex = categoryIDs.index(after: currentIndex)
        }

        let movedCategoryID = categoryIDs.remove(at: currentIndex)
        categoryIDs.insert(movedCategoryID, at: nextIndex)
        return categoryIDs
    }
}

public struct GroceryItemRecord: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let listID: UUID
    public let name: String
    public let quantityText: String?
    public let note: String?
    public let categoryID: UUID?
    public let checked: Bool
    public let checkedAt: Date?
    public let sortOrder: Int

    public init(
        id: UUID,
        listID: UUID,
        name: String,
        quantityText: String?,
        note: String?,
        categoryID: UUID?,
        checked: Bool,
        checkedAt: Date?,
        sortOrder: Int
    ) {
        self.id = id
        self.listID = listID
        self.name = name
        self.quantityText = quantityText
        self.note = note
        self.categoryID = categoryID
        self.checked = checked
        self.checkedAt = checkedAt
        self.sortOrder = sortOrder
    }

    public init?(json: [String: Any]) {
        guard
            let idText = json["id"] as? String,
            let id = UUID(uuidString: idText),
            let listIDText = json["list_id"] as? String,
            let listID = UUID(uuidString: listIDText),
            let name = json["name"] as? String
        else {
            return nil
        }

        let checkedAt: Date?
        if let checkedAtText = json["checked_at"] as? String {
            checkedAt = Self.parseCheckedAt(checkedAtText)
        } else {
            checkedAt = nil
        }

        self.init(
            id: id,
            listID: listID,
            name: name,
            quantityText: json["quantity_text"] as? String,
            note: json["note"] as? String,
            categoryID: (json["category_id"] as? String).flatMap(UUID.init(uuidString:)),
            checked: (json["checked"] as? Bool) ?? false,
            checkedAt: checkedAt,
            sortOrder: (json["sort_order"] as? Int) ?? 0
        )
    }

    private static func parseCheckedAt(_ value: String) -> Date? {
        let formatterWithFractions = ISO8601DateFormatter()
        formatterWithFractions.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = formatterWithFractions.date(from: value) {
            return parsed
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

public struct GroceryItemSuggestion: Identifiable, Equatable, Sendable {
    public let item: GroceryItemRecord
    public let category: GroceryCategorySummary?
    public let matchDistance: Int
    public let matchRank: Int

    public var id: UUID { item.id }

    public init(item: GroceryItemRecord, category: GroceryCategorySummary?, matchDistance: Int, matchRank: Int) {
        self.item = item
        self.category = category
        self.matchDistance = matchDistance
        self.matchRank = matchRank
    }
}

public enum GroceryItemSuggestionMatcher {
    public static func suggestions(
        for query: String,
        items: [GroceryItemRecord],
        categories: [GroceryCategorySummary],
        limit: Int = 4
    ) -> [GroceryItemSuggestion] {
        let normalizedQuery = normalizeSearchText(query)
        guard normalizedQuery.isEmpty == false else { return [] }

        let categoryLookup = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        return items
            .compactMap { item -> GroceryItemSuggestion? in
                guard let match = itemSuggestionMatch(itemName: item.name, query: normalizedQuery) else { return nil }
                return GroceryItemSuggestion(
                    item: item,
                    category: item.categoryID.flatMap { categoryLookup[$0] },
                    matchDistance: match.distance,
                    matchRank: match.rank
                )
            }
            .sorted { left, right in
                if left.matchRank != right.matchRank {
                    return left.matchRank < right.matchRank
                }
                if left.matchDistance != right.matchDistance {
                    return left.matchDistance < right.matchDistance
                }
                if left.item.checked != right.item.checked {
                    return (left.item.checked ? 1 : 0) < (right.item.checked ? 1 : 0)
                }
                return left.item.name.localizedCaseInsensitiveCompare(right.item.name) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    public static func fuzzyItemNameDistance(itemName: String, query: String) -> Int? {
        if query.count < 3 {
            return nil
        }

        let maxDistance = query.count <= 4 ? 1 : 2
        var bestDistance = boundedEditDistance(itemName, query, maxDistance: maxDistance)
        let minWindowLength = max(1, query.count - maxDistance)
        let maxWindowLength = min(itemName.count, query.count + maxDistance)
        let itemCharacters = Array(itemName)

        if minWindowLength <= maxWindowLength {
            for startIndex in itemCharacters.indices {
                for windowLength in minWindowLength...maxWindowLength {
                    let endIndex = startIndex + windowLength
                    guard endIndex <= itemCharacters.count else { continue }
                    let candidate = String(itemCharacters[startIndex..<endIndex])
                    bestDistance = min(bestDistance, boundedEditDistance(candidate, query, maxDistance: maxDistance))
                    if bestDistance == 0 {
                        return bestDistance
                    }
                }
            }
        }

        return bestDistance <= maxDistance ? bestDistance : nil
    }

    public static func itemSuggestionMatch(itemName: String, query: String) -> (distance: Int, rank: Int)? {
        let normalizedName = normalizeSearchText(itemName)
        let normalizedQuery = normalizeSearchText(query)
        if normalizedName == normalizedQuery {
            return (0, 0)
        }
        if normalizedName.hasPrefix(normalizedQuery) {
            return (0, 1)
        }
        if normalizedName.contains(normalizedQuery) {
            return (0, 2)
        }

        guard let distance = fuzzyItemNameDistance(itemName: normalizedName, query: normalizedQuery) else {
            return nil
        }
        return (distance, 3)
    }

    private static func normalizeSearchText(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func boundedEditDistance(_ left: String, _ right: String, maxDistance: Int) -> Int {
        if left == right {
            return 0
        }
        if abs(left.count - right.count) > maxDistance {
            return maxDistance + 1
        }

        let leftCharacters = Array(left)
        let rightCharacters = Array(right)
        var previous = Array(0...rightCharacters.count)

        for leftIndex in 1...leftCharacters.count {
            var current = [leftIndex] + Array(repeating: 0, count: rightCharacters.count)
            var rowBest = current[0]
            for rightIndex in 1...rightCharacters.count {
                let substitutionCost = leftCharacters[leftIndex - 1] == rightCharacters[rightIndex - 1] ? 0 : 1
                let value = min(
                    previous[rightIndex] + 1,
                    current[rightIndex - 1] + 1,
                    previous[rightIndex - 1] + substitutionCost
                )
                current[rightIndex] = value
                rowBest = min(rowBest, value)
            }
            if rowBest > maxDistance {
                return maxDistance + 1
            }
            previous = current
        }

        return previous[rightCharacters.count]
    }
}

public enum GroceryItemSectionKind: Hashable, Sendable {
    case uncategorized
    case category(UUID)
    case checked
}

public struct GroceryItemSection: Identifiable, Equatable, Sendable {
    public let kind: GroceryItemSectionKind
    public let title: String
    public let itemCount: Int
    public let colorHex: String?
    public let items: [GroceryItemRecord]

    public init(
        kind: GroceryItemSectionKind,
        title: String,
        itemCount: Int,
        colorHex: String?,
        items: [GroceryItemRecord]
    ) {
        self.kind = kind
        self.title = title
        self.itemCount = itemCount
        self.colorHex = colorHex
        self.items = items
    }

    public var id: String {
        switch kind {
        case .uncategorized:
            return "uncategorized"
        case let .category(categoryID):
            return "category-\(categoryID.uuidString)"
        case .checked:
            return "checked"
        }
    }
}

public enum GroceryItemSectionBuilder {
    public static func build(
        items: [GroceryItemRecord],
        categories: [GroceryCategorySummary],
        categoryOrder: [ListCategoryOrderEntry]
    ) -> [GroceryItemSection] {
        let categoryLookup = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let explicitOrder = Dictionary(uniqueKeysWithValues: categoryOrder.map { ($0.categoryID, $0.sortOrder) })

        let activeItems = items
            .filter { $0.checked == false }
            .sorted { left, right in
                compareActiveItems(
                    left,
                    right,
                    categoryLookup: categoryLookup,
                    explicitOrder: explicitOrder
                )
            }
        let checkedItems = items
            .filter(\.checked)
            .sorted(by: compareCheckedItems)

        var sections: [GroceryItemSection] = []

        let groupedActiveItems = Dictionary(grouping: activeItems) { item in
            item.categoryID.map(GroceryItemSectionKind.category) ?? .uncategorized
        }

        if let uncategorizedItems = groupedActiveItems[GroceryItemSectionKind.uncategorized], uncategorizedItems.isEmpty == false {
            sections.append(
                GroceryItemSection(
                    kind: .uncategorized,
                    title: "Uncategorized",
                    itemCount: uncategorizedItems.count,
                    colorHex: nil,
                    items: uncategorizedItems
                )
            )
        }

        let orderedCategoryIDs = categoryOrder
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.categoryID)

        for categoryID in orderedCategoryIDs {
            guard
                let category = categoryLookup[categoryID],
                let sectionItems = groupedActiveItems[GroceryItemSectionKind.category(categoryID)],
                sectionItems.isEmpty == false
            else {
                continue
            }

            sections.append(
                GroceryItemSection(
                    kind: .category(categoryID),
                    title: category.name,
                    itemCount: sectionItems.count,
                    colorHex: category.colorHex,
                    items: sectionItems
                )
            )
        }

        let unorderedCategories = groupedActiveItems.keys.compactMap { key -> UUID? in
            guard case let .category(categoryID) = key, explicitOrder[categoryID] == nil else {
                return nil
            }
            return categoryID
        }
        .sorted {
            (categoryLookup[$0]?.name ?? "").localizedCaseInsensitiveCompare(categoryLookup[$1]?.name ?? "") == .orderedAscending
        }

        for categoryID in unorderedCategories {
            guard
                let category = categoryLookup[categoryID],
                let sectionItems = groupedActiveItems[GroceryItemSectionKind.category(categoryID)],
                sectionItems.isEmpty == false
            else {
                continue
            }

            sections.append(
                GroceryItemSection(
                    kind: .category(categoryID),
                    title: category.name,
                    itemCount: sectionItems.count,
                    colorHex: category.colorHex,
                    items: sectionItems
                )
            )
        }

        if checkedItems.isEmpty == false {
            sections.append(
                GroceryItemSection(
                    kind: .checked,
                    title: "Checked off",
                    itemCount: checkedItems.count,
                    colorHex: "#94a3b8",
                    items: checkedItems
                )
            )
        }

        return sections
    }

    private static func compareActiveItems(
        _ left: GroceryItemRecord,
        _ right: GroceryItemRecord,
        categoryLookup: [UUID: GroceryCategorySummary],
        explicitOrder: [UUID: Int]
    ) -> Bool {
        let leftIsUncategorized = left.categoryID == nil
        let rightIsUncategorized = right.categoryID == nil
        if leftIsUncategorized != rightIsUncategorized {
            return leftIsUncategorized
        }

        if let leftCategoryID = left.categoryID, let rightCategoryID = right.categoryID {
            let leftSortOrder = explicitOrder[leftCategoryID] ?? Int.max
            let rightSortOrder = explicitOrder[rightCategoryID] ?? Int.max

            let leftIsExplicit = explicitOrder[leftCategoryID] != nil
            let rightIsExplicit = explicitOrder[rightCategoryID] != nil
            if leftIsExplicit != rightIsExplicit {
                return leftIsExplicit
            }

            if leftSortOrder != rightSortOrder {
                return leftSortOrder < rightSortOrder
            }

            let leftCategoryName = categoryLookup[leftCategoryID]?.name ?? ""
            let rightCategoryName = categoryLookup[rightCategoryID]?.name ?? ""
            let categoryNameOrdering = leftCategoryName.localizedCaseInsensitiveCompare(rightCategoryName)
            if categoryNameOrdering != .orderedSame {
                return categoryNameOrdering == .orderedAscending
            }
        }

        if left.sortOrder != right.sortOrder {
            return left.sortOrder < right.sortOrder
        }
        return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
    }

    private static func compareCheckedItems(_ left: GroceryItemRecord, _ right: GroceryItemRecord) -> Bool {
        let leftCheckedAt = left.checkedAt ?? .distantPast
        let rightCheckedAt = right.checkedAt ?? .distantPast
        if leftCheckedAt != rightCheckedAt {
            return leftCheckedAt > rightCheckedAt
        }
        return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
    }
}

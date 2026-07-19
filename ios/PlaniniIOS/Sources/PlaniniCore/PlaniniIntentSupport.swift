import Foundation

public enum PlaniniIntentError: LocalizedError, Equatable, Sendable {
    case emptyItemName
    case missingSession
    case missingFavoriteList
    case listNotFound
    case invalidResponse
    case unauthorized
    case serverMessage(String)

    public var errorDescription: String? {
        switch self {
        case .emptyItemName:
            return "Tell Planini which item to add."
        case .missingSession:
            return "Open Planini and sign in before using Siri."
        case .missingFavoriteList:
            return "Pick a favorite list in Planini before adding items with Siri."
        case .listNotFound:
            return "That Planini list is not available."
        case .invalidResponse:
            return "Planini received an unexpected response."
        case .unauthorized:
            return "Your Planini session expired. Open Planini and sign in again."
        case let .serverMessage(message):
            return message
        }
    }
}

public struct PlaniniIntentAddItemResult: Equatable, Sendable {
    public let item: GroceryItemRecord
    public let list: GroceryListSummary

    public init(item: GroceryItemRecord, list: GroceryListSummary) {
        self.item = item
        self.list = list
    }

    public var dialogText: String {
        "\(item.name) added to \(list.name)."
    }
}

public enum PlaniniIntentSupport {
    public static func normalizedItemName(_ rawName: String) throws -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else {
            throw PlaniniIntentError.emptyItemName
        }
        return name
    }

    public static func availableLists(in state: SharedAppState) -> [GroceryListSummary] {
        state.lists
            .filter { $0.archived == false }
            .sorted(by: compareLists)
    }

    public static func matchingLists(_ query: String, in state: SharedAppState) -> [GroceryListSummary] {
        let normalizedQuery = normalizedSearchText(query)
        guard normalizedQuery.isEmpty == false else {
            return availableLists(in: state)
        }

        return availableLists(in: state).filter { list in
            normalizedSearchText(list.name).contains(normalizedQuery)
                || normalizedSearchText(list.householdName).contains(normalizedQuery)
        }
    }

    public static func targetList(
        requestedListID: UUID?,
        in state: SharedAppState
    ) throws -> GroceryListSummary {
        guard state.hasAuthenticatedSession else {
            throw PlaniniIntentError.missingSession
        }

        let lists = availableLists(in: state)
        if let requestedListID {
            guard let list = lists.first(where: { $0.id == requestedListID }) else {
                throw PlaniniIntentError.listNotFound
            }
            return list
        }

        guard
            let favoriteListID = state.favoriteListID,
            let favoriteList = lists.first(where: { $0.id == favoriteListID })
        else {
            throw PlaniniIntentError.missingFavoriteList
        }
        return favoriteList
    }

    private static func compareLists(_ left: GroceryListSummary, _ right: GroceryListSummary) -> Bool {
        if left.householdName != right.householdName {
            return left.householdName.localizedCaseInsensitiveCompare(right.householdName) == .orderedAscending
        }
        return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
    }

    private static func normalizedSearchText(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

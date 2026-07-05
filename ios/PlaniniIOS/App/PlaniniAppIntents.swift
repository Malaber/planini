import Foundation
import PlaniniCore

#if canImport(AppIntents)
import AppIntents

struct PlaniniListEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Planini List")
    static var defaultQuery = PlaniniListEntityQuery()

    let id: UUID
    let name: String
    let householdName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(householdName)")
    }

    init(list: GroceryListSummary) {
        id = list.id
        name = list.name
        householdName = list.householdName
    }
}

struct PlaniniListEntityQuery: EntityStringQuery {
    func entities(for identifiers: [PlaniniListEntity.ID]) async throws -> [PlaniniListEntity] {
        let lists = PlaniniIntentAddItemExecutor().availableLists()
        return lists
            .filter { identifiers.contains($0.id) }
            .map(PlaniniListEntity.init)
    }

    func entities(matching string: String) async throws -> [PlaniniListEntity] {
        PlaniniIntentAddItemExecutor()
            .matchingLists(string)
            .map(PlaniniListEntity.init)
    }

    func suggestedEntities() async throws -> [PlaniniListEntity] {
        PlaniniIntentAddItemExecutor()
            .availableLists()
            .map(PlaniniListEntity.init)
    }
}

struct AddPlaniniItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Item to Planini"
    static var description = IntentDescription(
        "Adds an item to your favorite Planini list, or to a specific list when you name one."
    )
    static var openAppWhenRun = false

    @Parameter(title: "Item")
    var itemName: String

    @Parameter(title: "List")
    var list: PlaniniListEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try await PlaniniIntentAddItemExecutor().addItem(
            named: itemName,
            requestedListID: list?.id
        )
        return .result(dialog: IntentDialog(stringLiteral: result.dialogText))
    }
}

struct PlaniniAppShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddPlaniniItemIntent(),
            phrases: [
                "Add Item in \(.applicationName)",
                "Add Item to \(\.$list) in \(.applicationName)",
            ],
            shortTitle: "Add Item",
            systemImageName: "cart.badge.plus"
        )
    }
}
#endif

struct PlaniniIntentAddItemExecutor {
    private let stateStore: SharedAppStateStore
    private let backendClient: PlaniniIntentBackendClient

    init(
        stateStore: SharedAppStateStore = SharedAppStateStore(
            userDefaults: UserDefaults(suiteName: PlaniniSharedConstants.watchAppGroupID) ?? .standard
        ),
        backendClient: PlaniniIntentBackendClient = PlaniniIntentBackendClient()
    ) {
        self.stateStore = stateStore
        self.backendClient = backendClient
    }

    func availableLists() -> [GroceryListSummary] {
        PlaniniIntentSupport.availableLists(in: stateStore.load())
    }

    func matchingLists(_ query: String) -> [GroceryListSummary] {
        PlaniniIntentSupport.matchingLists(query, in: stateStore.load())
    }

    func addItem(named rawName: String, requestedListID: UUID?) async throws -> PlaniniIntentAddItemResult {
        let state = stateStore.load()
        let itemName = try PlaniniIntentSupport.normalizedItemName(rawName)
        let list = try PlaniniIntentSupport.targetList(requestedListID: requestedListID, in: state)
        let item = try await backendClient.addItem(named: itemName, to: list.id, using: state)

        if state.favoriteListID == list.id {
            var updatedState = state
            updatedState.items.removeAll { $0.id == item.id }
            updatedState.items.append(item)
            stateStore.save(updatedState)
        }

        return PlaniniIntentAddItemResult(item: item, list: list)
    }
}

struct PlaniniIntentBackendClient {
    func addItem(named itemName: String, to listID: UUID, using state: SharedAppState) async throws -> GroceryItemRecord {
        guard
            let backendURL = state.backendURL,
            let authToken = state.authToken,
            authToken.isEmpty == false
        else {
            throw PlaniniIntentError.missingSession
        }

        let payload = try await requestJSON(
            backendURL: backendURL,
            path: "/api/v1/lists/\(listID.uuidString)/items",
            method: "POST",
            body: [
                "name": itemName,
                "quantity_text": NSNull(),
                "note": NSNull(),
                "category_id": NSNull(),
            ],
            token: authToken
        )

        guard let item = GroceryItemRecord(json: payload) else {
            throw PlaniniIntentError.invalidResponse
        }
        return item
    }

    private func requestJSON(
        backendURL: URL,
        path: String,
        method: String,
        body: [String: Any],
        token: String
    ) async throws -> [String: Any] {
        var request = URLRequest(url: backendURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PlaniniIntentError.invalidResponse
        }
        if http.statusCode == 401 {
            throw PlaniniIntentError.unauthorized
        }
        guard (200 ... 299).contains(http.statusCode) else {
            if
                let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let detail = payload["detail"] as? String,
                detail.isEmpty == false
            {
                throw PlaniniIntentError.serverMessage(detail)
            }
            throw PlaniniIntentError.serverMessage(HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
        }
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlaniniIntentError.invalidResponse
        }
        return payload
    }
}

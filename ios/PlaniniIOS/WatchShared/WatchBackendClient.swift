import Foundation
import PlaniniCore

struct WatchListSnapshot {
    let state: SharedAppState
    let categories: [GroceryCategorySummary]
    let categoryOrder: [ListCategoryOrderEntry]
}

struct WatchListMutationResult {
    let snapshot: WatchListSnapshot
    let item: GroceryItemRecord
}

enum WatchBackendClientError: LocalizedError, Equatable {
    case missingSession
    case missingFavoriteList
    case unauthorized
    case invalidResponse
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .missingSession:
            return "Open the iPhone app to sync your account to the watch."
        case .missingFavoriteList:
            return "Pick a favorite list on iPhone before using the watch app."
        case .unauthorized:
            return "Your watch session expired. Open the iPhone app to refresh watch login."
        case .invalidResponse:
            return "The watch received an unexpected response from the backend."
        case let .serverMessage(message):
            return message
        }
    }
}

struct WatchBackendClient {
    func refreshFavoriteItems(using state: SharedAppState) async throws -> WatchListSnapshot {
        let favoriteListID = try requireFavoriteListID(from: state)
        return try await refreshList(for: favoriteListID, using: state)
    }

    func refreshList(for listID: UUID, using state: SharedAppState) async throws -> WatchListSnapshot {
        let session = try requireSession(from: state)
        async let itemsPayload = requestArray(
            backendURL: session.backendURL,
            path: "/api/v1/lists/\(listID.uuidString)/items",
            token: session.authToken
        )
        async let categoriesPayload = requestArray(
            backendURL: session.backendURL,
            path: "/api/v1/lists/\(listID.uuidString)/categories",
            token: session.authToken
        )
        async let categoryOrderPayload = requestArray(
            backendURL: session.backendURL,
            path: "/api/v1/lists/\(listID.uuidString)/category-order",
            token: session.authToken
        )

        let items = try await itemsPayload.compactMap(GroceryItemRecord.init)
        let categories = try await categoriesPayload.compactMap(GroceryCategorySummary.init)
        let categoryOrder = try await categoryOrderPayload.compactMap(ListCategoryOrderEntry.init)

        var updatedState = state
        updatedState.items = items
        updatedState.categories = categories
        updatedState.categoryOrder = categoryOrder
        return WatchListSnapshot(state: updatedState, categories: categories, categoryOrder: categoryOrder)
    }

    func refreshItems(for listID: UUID, using state: SharedAppState) async throws -> SharedAppState {
        try await refreshList(for: listID, using: state).state
    }

    func addItem(named name: String, using state: SharedAppState) async throws -> SharedAppState {
        let favoriteListID = try requireFavoriteListID(from: state)
        return try await addItem(named: name, to: favoriteListID, using: state)
    }

    func addItem(named name: String, to listID: UUID, using state: SharedAppState) async throws -> SharedAppState {
        try await addItemResult(named: name, to: listID, using: state).snapshot.state
    }

    func addItemResult(named name: String, to listID: UUID, using state: SharedAppState) async throws -> WatchListMutationResult {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else {
            throw WatchBackendClientError.serverMessage("Enter an item name before adding it.")
        }

        let item = GroceryItemRecord(
            id: UUID(),
            listID: listID,
            name: trimmedName,
            quantityText: nil,
            note: nil,
            categoryID: nil,
            checked: false,
            checkedAt: nil,
            sortOrder: 0
        )
        return try await recreateItem(item, in: listID, using: state)
    }

    func recreateItem(
        _ item: GroceryItemRecord,
        in listID: UUID,
        using state: SharedAppState
    ) async throws -> WatchListMutationResult {
        let session = try requireSession(from: state)
        let createdPayload = try await requestJSON(
            backendURL: session.backendURL,
            path: "/api/v1/lists/\(listID.uuidString)/items",
            method: "POST",
            body: [
                "name": item.name,
                "quantity_text": item.quantityText ?? NSNull(),
                "note": item.note ?? NSNull(),
                "category_id": item.categoryID?.uuidString ?? NSNull(),
            ],
            token: session.authToken
        )
        guard let createdItem = GroceryItemRecord(json: createdPayload) else {
            throw WatchBackendClientError.invalidResponse
        }

        let snapshot = try await refreshList(for: listID, using: state)
        let resolvedItem = snapshot.state.items.first { $0.id == createdItem.id } ?? createdItem
        return WatchListMutationResult(snapshot: snapshot, item: resolvedItem)
    }

    func toggle(_ item: GroceryItemRecord, in listID: UUID, using state: SharedAppState) async throws -> SharedAppState {
        try await toggleResult(item, in: listID, using: state).snapshot.state
    }

    func toggleResult(
        _ item: GroceryItemRecord,
        in listID: UUID,
        using state: SharedAppState
    ) async throws -> WatchListMutationResult {
        try await setChecked(!item.checked, for: item, in: listID, using: state)
    }

    func setChecked(
        _ checked: Bool,
        for item: GroceryItemRecord,
        in listID: UUID,
        using state: SharedAppState
    ) async throws -> WatchListMutationResult {
        let session = try requireSession(from: state)
        let suffix = checked ? "check" : "uncheck"

        let updatedPayload = try await requestJSON(
            backendURL: session.backendURL,
            path: "/api/v1/items/\(item.id.uuidString)/\(suffix)",
            method: "POST",
            body: [:],
            token: session.authToken
        )
        guard let updatedItem = GroceryItemRecord(json: updatedPayload) else {
            throw WatchBackendClientError.invalidResponse
        }

        let snapshot = try await refreshList(for: listID, using: state)
        let resolvedItem = snapshot.state.items.first { $0.id == updatedItem.id } ?? updatedItem
        return WatchListMutationResult(snapshot: snapshot, item: resolvedItem)
    }

    func saveEdit(
        item: GroceryItemRecord,
        note: String,
        categoryID: UUID?,
        in listID: UUID,
        using state: SharedAppState
    ) async throws -> WatchListSnapshot {
        try await saveEditResult(
            item: item,
            note: note,
            categoryID: categoryID,
            in: listID,
            using: state
        ).snapshot
    }

    func saveEditResult(
        item: GroceryItemRecord,
        note: String,
        categoryID: UUID?,
        in listID: UUID,
        using state: SharedAppState
    ) async throws -> WatchListMutationResult {
        let session = try requireSession(from: state)

        let updatedPayload = try await requestJSON(
            backendURL: session.backendURL,
            path: "/api/v1/items/\(item.id.uuidString)",
            method: "PATCH",
            body: [
                "note": note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? NSNull() : note,
                "category_id": categoryID?.uuidString ?? NSNull(),
            ],
            token: session.authToken
        )
        guard let updatedItem = GroceryItemRecord(json: updatedPayload) else {
            throw WatchBackendClientError.invalidResponse
        }

        let snapshot = try await refreshList(for: listID, using: state)
        let resolvedItem = snapshot.state.items.first { $0.id == updatedItem.id } ?? updatedItem
        return WatchListMutationResult(snapshot: snapshot, item: resolvedItem)
    }

    func saveItem(
        _ item: GroceryItemRecord,
        in listID: UUID,
        using state: SharedAppState
    ) async throws -> WatchListMutationResult {
        try await saveItem(item, payload: GroceryItemEditPayload(item: item), in: listID, using: state)
    }

    func deleteItem(_ item: GroceryItemRecord, in listID: UUID, using state: SharedAppState) async throws -> WatchListSnapshot {
        let session = try requireSession(from: state)

        _ = try await requestData(
            backendURL: session.backendURL,
            path: "/api/v1/items/\(item.id.uuidString)",
            method: "DELETE",
            body: nil,
            token: session.authToken
        )

        return try await refreshList(for: listID, using: state)
    }

    private func saveItem(
        _ item: GroceryItemRecord,
        payload: GroceryItemEditPayload,
        in listID: UUID,
        using state: SharedAppState
    ) async throws -> WatchListMutationResult {
        let session = try requireSession(from: state)

        let updatedPayload = try await requestJSON(
            backendURL: session.backendURL,
            path: "/api/v1/items/\(item.id.uuidString)",
            method: "PATCH",
            body: payload.jsonBody,
            token: session.authToken
        )
        guard let updatedItem = GroceryItemRecord(json: updatedPayload) else {
            throw WatchBackendClientError.invalidResponse
        }

        let snapshot = try await refreshList(for: listID, using: state)
        let resolvedItem = snapshot.state.items.first { $0.id == updatedItem.id } ?? updatedItem
        return WatchListMutationResult(snapshot: snapshot, item: resolvedItem)
    }

    private func requireSession(from state: SharedAppState) throws -> (
        backendURL: URL,
        authToken: String
    ) {
        guard
            let backendURL = state.backendURL,
            let authToken = state.authToken,
            authToken.isEmpty == false
        else {
            throw WatchBackendClientError.missingSession
        }
        return (backendURL, authToken)
    }

    private func requireFavoriteListID(from state: SharedAppState) throws -> UUID {
        guard let favoriteListID = state.favoriteListID else {
            throw WatchBackendClientError.missingFavoriteList
        }
        return favoriteListID
    }

    private func requestArray(
        backendURL: URL,
        path: String,
        token: String
    ) async throws -> [[String: Any]] {
        let data = try await requestData(
            backendURL: backendURL,
            path: path,
            method: "GET",
            body: nil,
            token: token
        )
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw WatchBackendClientError.invalidResponse
        }
        return payload
    }

    private func requestJSON(
        backendURL: URL,
        path: String,
        method: String,
        body: [String: Any]?,
        token: String
    ) async throws -> [String: Any] {
        let data = try await requestData(
            backendURL: backendURL,
            path: path,
            method: method,
            body: body,
            token: token
        )
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WatchBackendClientError.invalidResponse
        }
        return payload
    }

    private func requestData(
        backendURL: URL,
        path: String,
        method: String,
        body: [String: Any]?,
        token: String
    ) async throws -> Data {
        var request = URLRequest(url: backendURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw WatchBackendClientError.invalidResponse
        }
        if http.statusCode == 401 {
            throw WatchBackendClientError.unauthorized
        }
        guard (200 ... 299).contains(http.statusCode) else {
            if
                let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let detail = payload["detail"] as? String,
                detail.isEmpty == false
            {
                throw WatchBackendClientError.serverMessage(detail)
            }
            throw WatchBackendClientError.serverMessage(
                HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            )
        }
        return data
    }
}

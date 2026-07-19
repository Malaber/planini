import Foundation
import Testing
@testable import PlaniniCore

struct SharedAppStateTests {
    @Test func defaultStateUsesQuickAddFallback() {
        let state = SharedAppState()

        #expect(state.quickAddItemName == "Milk")
        #expect(state.favoriteList == nil)
        #expect(state.favoriteListName == nil)
        #expect(state.hasAuthenticatedSession == false)
        #expect(state.canQuickAdd == false)
        #expect(PlaniniSharedConstants.watchAppGroupID == "group.de.malaber.planini.watch")
        #expect(PlaniniSharedConstants.sharedAppStateKey == "planini.shared-app-state")
        #expect(PlaniniSharedConstants.watchContextPayloadKey == "state")

        let missingTokenState = SharedAppState(backendURL: URL(string: "https://api.example.com"))

        #expect(missingTokenState.hasAuthenticatedSession == false)
    }

    @Test func favoriteListResolvesFromLists() {
        let favoriteListID = UUID()
        let categoryID = UUID()
        let state = SharedAppState(
            backendURL: URL(string: "https://api.example.com"),
            authToken: "token",
            favoriteListID: favoriteListID,
            quickAddItemName: "Bananas",
            lists: [
                GroceryListSummary(
                    id: favoriteListID,
                    householdID: UUID(),
                    householdName: "Home",
                    name: "Weekly shop",
                    archived: false
                )
            ],
            categories: [
                GroceryCategorySummary(id: categoryID, name: "Produce", colorHex: "#00ff00")
            ],
            categoryOrder: [
                ListCategoryOrderEntry(categoryID: categoryID, sortOrder: 0)
            ]
        )

        #expect(state.favoriteList?.id == favoriteListID)
        #expect(state.favoriteListName == "Weekly shop")
        #expect(state.canQuickAdd == true)
        #expect(state.categories.map(\.name) == ["Produce"])
        #expect(state.categoryOrder.map(\.categoryID) == [categoryID])
    }

    @Test func decodesLegacyStateWithoutSyncedCategoryMetadata() throws {
        let listID = UUID()
        let payload = """
        {
          "backendURL": "https://api.example.com",
          "authToken": "token",
          "favoriteListID": "\(listID.uuidString)",
          "quickAddItemName": "Milk",
          "lists": [],
          "items": []
        }
        """

        let state = try JSONDecoder().decode(SharedAppState.self, from: Data(payload.utf8))

        #expect(state.backendURL == URL(string: "https://api.example.com"))
        #expect(state.authToken == "token")
        #expect(state.favoriteListID == listID)
        #expect(state.syncedListID == nil)
        #expect(state.categories == [])
        #expect(state.categoryOrder == [])
    }

    @Test func decodesEmptyLegacyStateWithDefaults() throws {
        let state = try JSONDecoder().decode(SharedAppState.self, from: Data("{}".utf8))

        #expect(state.quickAddItemName == SharedAppState.defaultQuickAddItemName)
        #expect(state.lists == [])
        #expect(state.items == [])
    }

    @Test func quickAddRequiresTrimmedNameFavoriteListAndSession() {
        let state = SharedAppState(
            backendURL: URL(string: "https://api.example.com"),
            authToken: "token",
            favoriteListID: UUID(),
            quickAddItemName: "   "
        )

        #expect(state.canQuickAdd == false)
    }

    @Test func listItemsUseSyncedListWhenPresent() {
        let syncedListID = UUID()
        let favoriteListID = UUID()
        let syncedItem = GroceryItemRecord(
            id: UUID(),
            listID: syncedListID,
            name: "Apples",
            quantityText: nil,
            note: nil,
            categoryID: nil,
            checked: false,
            checkedAt: nil,
            sortOrder: 2
        )
        let checkedItem = GroceryItemRecord(
            id: UUID(),
            listID: syncedListID,
            name: "Bread",
            quantityText: nil,
            note: nil,
            categoryID: nil,
            checked: true,
            checkedAt: nil,
            sortOrder: 1
        )
        let favoriteItem = GroceryItemRecord(
            id: UUID(),
            listID: favoriteListID,
            name: "Milk",
            quantityText: nil,
            note: nil,
            categoryID: nil,
            checked: false,
            checkedAt: nil,
            sortOrder: 0
        )
        let state = SharedAppState(
            favoriteListID: favoriteListID,
            syncedListID: syncedListID,
            lists: [
                GroceryListSummary(
                    id: syncedListID,
                    householdID: UUID(),
                    householdName: "Home",
                    name: "Errands",
                    archived: false
                ),
                GroceryListSummary(
                    id: favoriteListID,
                    householdID: UUID(),
                    householdName: "Home",
                    name: "Groceries",
                    archived: false
                ),
            ],
            items: [checkedItem, favoriteItem, syncedItem]
        )

        #expect(state.syncedListName == "Errands")
        #expect(state.items(for: syncedListID).map(\.name) == ["Apples", "Bread"])
        #expect(state.items(for: favoriteListID).isEmpty)
    }

    @Test func shoppingSnapshotRunsForThreeHours() throws {
        let listID = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let state = SharedAppState(
            backendURL: URL(string: "https://api.example.com"),
            authToken: "token",
            syncedListID: listID,
            quickAddItemName: "Coffee",
            lists: [
                GroceryListSummary(
                    id: listID,
                    householdID: UUID(),
                    householdName: "Home",
                    name: "Weekly",
                    archived: false
                )
            ],
            items: [
                GroceryItemRecord(
                    id: UUID(),
                    listID: listID,
                    name: "Eggs",
                    quantityText: nil,
                    note: nil,
                    categoryID: nil,
                    checked: false,
                    checkedAt: nil,
                    sortOrder: 0
                ),
                GroceryItemRecord(
                    id: UUID(),
                    listID: listID,
                    name: "Butter",
                    quantityText: nil,
                    note: nil,
                    categoryID: nil,
                    checked: true,
                    checkedAt: nil,
                    sortOrder: 1
                ),
            ]
        )

        let snapshot = try #require(state.shoppingSnapshot(for: listID, startedAt: start))

        #expect(snapshot.listName == "Weekly")
        #expect(snapshot.totalItemCount == 2)
        #expect(snapshot.checkedItemCount == 1)
        #expect(snapshot.remainingItemCount == 1)
        #expect(snapshot.uncheckedItemNames == ["Eggs"])
        #expect(snapshot.quickAddItemName == "Coffee")
        #expect(snapshot.expiresAt == start.addingTimeInterval(ShoppingListSnapshot.liveActivityDuration))
        #expect(snapshot.isExpired(at: start.addingTimeInterval(ShoppingListSnapshot.liveActivityDuration)) == true)
    }

    @Test func storeLoadsDefaultWhenMissingOrInvalid() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = SharedAppStateStore(userDefaults: defaults, storageKey: "state")

        #expect(store.load() == SharedAppState())

        defaults.set(Data("not-json".utf8), forKey: "state")

        #expect(store.load() == SharedAppState())
    }

    @Test func storePersistsAndClearsState() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = SharedAppStateStore(userDefaults: defaults, storageKey: "state")
        let listID = UUID()
        let itemID = UUID()
        let categoryID = UUID()
        let state = SharedAppState(
            backendURL: URL(string: "https://api.example.com"),
            authToken: "secret",
            displayName: "Alex",
            favoriteListID: listID,
            syncedListID: listID,
            quickAddItemName: "Apples",
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
                    id: itemID,
                    listID: listID,
                    name: "Bread",
                    quantityText: "2",
                    note: nil,
                    categoryID: nil,
                    checked: false,
                    checkedAt: nil,
                    sortOrder: 1
                )
            ],
            categories: [
                GroceryCategorySummary(id: categoryID, name: "Bakery", colorHex: "#cccccc")
            ],
            categoryOrder: [
                ListCategoryOrderEntry(categoryID: categoryID, sortOrder: 1)
            ]
        )

        store.save(state)

        #expect(store.load() == state)

        store.clear()

        #expect(store.load() == SharedAppState())
    }
}

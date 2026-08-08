import Foundation
import Testing
@testable import PlaniniCore

struct LocalDemoStoreTests {
    @Test func seededSnapshotContainsUsefulLocalDemoData() {
        let snapshot = LocalDemoSnapshot.seeded()
        let household = try! #require(snapshot.households.first)
        let list = try! #require(snapshot.lists.first)
        let listData = try! #require(snapshot.listData[list.id])

        #expect(household.name == "Demo household")
        #expect(list.householdID == household.id)
        #expect(list.householdName == household.name)
        #expect(list.name == "Weekly groceries")
        #expect(list.accentColorHex == "#3b82f6")
        #expect(snapshot.favoriteListID == list.id)
        #expect(snapshot.selectedListID == list.id)
        #expect(listData.items.map(\.name) == ["Apples", "Milk", "Pasta"])
        #expect(listData.items.last?.checked == true)
        #expect(listData.items.last?.checkedAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(listData.categories.map(\.name) == ["Gemuese", "Milch & Eier", "Nudeln", "Haushalt"])
        #expect(listData.categoryOrder.map(\.sortOrder) == [0, 1, 2, 3])
        #expect(listData.disabledCategoryIDs == [])
    }

    @Test func listDataDecodesLegacyPayloadWithoutDisabledCategories() throws {
        let listID = UUID()
        let payload = """
        {
          "items": [],
          "categories": [],
          "categoryOrder": []
        }
        """

        let data = try JSONDecoder().decode(LocalDemoListData.self, from: Data(payload.utf8))
        let explicitlyInitialized = LocalDemoListData(
            items: [
                GroceryItemRecord(
                    id: UUID(),
                    listID: listID,
                    name: "Bread",
                    quantityText: nil,
                    note: nil,
                    categoryID: nil,
                    checked: false,
                    checkedAt: nil,
                    sortOrder: 0
                )
            ],
            categories: [],
            categoryOrder: [],
            disabledCategoryIDs: [UUID()]
        )

        #expect(data == LocalDemoListData(items: [], categories: [], categoryOrder: []))
        #expect(explicitlyInitialized.items.first?.listID == listID)
        #expect(explicitlyInitialized.disabledCategoryIDs.count == 1)
    }

    @Test func snapshotInitializerKeepsAllValues() {
        let household = HouseholdSummary(id: UUID(), name: "Home")
        let list = GroceryListSummary(
            id: UUID(),
            householdID: household.id,
            householdName: household.name,
            name: "Tasks",
            archived: false
        )
        let data = LocalDemoListData(items: [], categories: [], categoryOrder: [])
        let snapshot = LocalDemoSnapshot(
            households: [household],
            lists: [list],
            listData: [list.id: data],
            favoriteListID: nil,
            selectedListID: list.id
        )

        #expect(snapshot.households == [household])
        #expect(snapshot.lists == [list])
        #expect(snapshot.listData == [list.id: data])
        #expect(snapshot.favoriteListID == nil)
        #expect(snapshot.selectedListID == list.id)
    }

    @Test func storeSeedsPersistsReloadsAndClearsSnapshot() {
        let suiteName = #function
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = LocalDemoStore(userDefaults: defaults, storageKey: "local-demo")

        #expect(store.load() == nil)

        let seeded = store.loadOrSeed()
        #expect(store.load() == seeded)
        #expect(store.loadOrSeed() == seeded)

        var changed = seeded
        changed.favoriteListID = nil
        store.save(changed)
        #expect(store.load() == changed)

        defaults.set(Data("invalid".utf8), forKey: "local-demo")
        #expect(store.load() == nil)

        store.save(changed)
        store.clear()
        #expect(store.load() == nil)
    }
}

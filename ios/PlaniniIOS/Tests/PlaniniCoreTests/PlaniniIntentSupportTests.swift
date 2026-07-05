import Foundation
import Testing
@testable import PlaniniCore

struct PlaniniIntentSupportTests {
    @Test func normalizesItemNamesAndRejectsBlankInput() throws {
        #expect(try PlaniniIntentSupport.normalizedItemName("  Apples  ") == "Apples")

        #expect(throws: PlaniniIntentError.emptyItemName) {
            try PlaniniIntentSupport.normalizedItemName(" \n ")
        }
    }

    @Test func favoriteListIsDefaultWhenIntentDoesNotSpecifyList() throws {
        let favoriteList = groceryList(name: "Weekly Shop")
        let otherList = groceryList(name: "Hardware")
        let state = SharedAppState(
            backendURL: URL(string: "https://api.example.com"),
            authToken: "token",
            favoriteListID: favoriteList.id,
            lists: [otherList, favoriteList]
        )

        let resolved = try PlaniniIntentSupport.targetList(requestedListID: nil, in: state)

        #expect(resolved == favoriteList)
    }

    @Test func requestedListOverridesFavoriteList() throws {
        let favoriteList = groceryList(name: "Weekly Shop")
        let partyList = groceryList(name: "Party")
        let state = SharedAppState(
            backendURL: URL(string: "https://api.example.com"),
            authToken: "token",
            favoriteListID: favoriteList.id,
            lists: [favoriteList, partyList]
        )

        let resolved = try PlaniniIntentSupport.targetList(
            requestedListID: partyList.id,
            in: state
        )

        #expect(resolved == partyList)
    }

    @Test func targetListRequiresSessionAndAvailableFavorite() {
        let favoriteList = groceryList(name: "Weekly Shop")
        let archivedFavorite = groceryList(id: favoriteList.id, name: "Old Shop", archived: true)

        #expect(throws: PlaniniIntentError.missingSession) {
            _ = try PlaniniIntentSupport.targetList(
                requestedListID: nil,
                in: SharedAppState(favoriteListID: favoriteList.id, lists: [favoriteList])
            )
        }

        #expect(throws: PlaniniIntentError.missingFavoriteList) {
            _ = try PlaniniIntentSupport.targetList(
                requestedListID: nil,
                in: SharedAppState(
                    backendURL: URL(string: "https://api.example.com"),
                    authToken: "token",
                    favoriteListID: favoriteList.id,
                    lists: [archivedFavorite]
                )
            )
        }

        #expect(throws: PlaniniIntentError.listNotFound) {
            _ = try PlaniniIntentSupport.targetList(
                requestedListID: archivedFavorite.id,
                in: SharedAppState(
                    backendURL: URL(string: "https://api.example.com"),
                    authToken: "token",
                    favoriteListID: favoriteList.id,
                    lists: [archivedFavorite]
                )
            )
        }
    }

    @Test func availableAndMatchingListsExcludeArchivedAndSortByHouseholdThenName() {
        let pantry = groceryList(householdName: "Home", name: "Pantry")
        let market = groceryList(householdName: "Home", name: "Market")
        let office = groceryList(householdName: "Office", name: "Supplies")
        let archived = groceryList(householdName: "Home", name: "Archive", archived: true)
        let state = SharedAppState(lists: [pantry, archived, office, market])

        #expect(PlaniniIntentSupport.availableLists(in: state).map(\.name) == ["Market", "Pantry", "Supplies"])
        #expect(PlaniniIntentSupport.matchingLists("home", in: state).map(\.name) == ["Market", "Pantry"])
        #expect(PlaniniIntentSupport.matchingLists("pan", in: state).map(\.name) == ["Pantry"])
    }

    private func groceryList(
        id: UUID = UUID(),
        householdName: String = "Home",
        name: String,
        archived: Bool = false
    ) -> GroceryListSummary {
        GroceryListSummary(
            id: id,
            householdID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            householdName: householdName,
            name: name,
            archived: archived
        )
    }
}

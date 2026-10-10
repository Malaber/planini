import Foundation
import Testing
@testable import PlaniniCore

struct PlaniniIntentSupportTests {
    @Test func intentErrorsExposeActionableDialogs() {
        #expect(PlaniniIntentError.emptyItemName.errorDescription == "Tell Planini which item to add.")
        #expect(PlaniniIntentError.missingSession.errorDescription == "Open Planini and sign in before using Siri.")
        #expect(
            PlaniniIntentError.missingFavoriteList.errorDescription
                == "Pick a favorite list in Planini before adding items with Siri."
        )
        #expect(PlaniniIntentError.listNotFound.errorDescription == "That Planini list is not available.")
        #expect(PlaniniIntentError.invalidResponse.errorDescription == "Planini received an unexpected response.")
        #expect(
            PlaniniIntentError.unauthorized.errorDescription
                == "Your Planini session expired. Open Planini and sign in again."
        )
        #expect(PlaniniIntentError.serverMessage("Try again later.").errorDescription == "Try again later.")
    }

    @Test func addItemResultBuildsSuccessDialog() {
        let list = groceryList(name: "Weekly Shop")
        let item = GroceryItemRecord(
            id: UUID(),
            listID: list.id,
            name: "Apples",
            quantityText: nil,
            note: nil,
            categoryID: nil,
            checked: false,
            checkedAt: nil,
            sortOrder: 0
        )

        let result = PlaniniIntentAddItemResult(item: item, list: list)

        #expect(result.dialogText == "Apples added to Weekly Shop.")
    }

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
        let market = groceryList(householdName: "Home", name: "Marché")
        let office = groceryList(householdName: "Office", name: "Supplies")
        let archived = groceryList(householdName: "Home", name: "Archive", archived: true)
        let state = SharedAppState(lists: [pantry, archived, office, market])

        #expect(PlaniniIntentSupport.availableLists(in: state).map(\.name) == ["Marché", "Pantry", "Supplies"])
        #expect(PlaniniIntentSupport.matchingLists("  ", in: state).map(\.name) == ["Marché", "Pantry", "Supplies"])
        #expect(PlaniniIntentSupport.matchingLists("home", in: state).map(\.name) == ["Marché", "Pantry"])
        #expect(PlaniniIntentSupport.matchingLists("marche", in: state).map(\.name) == ["Marché"])
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

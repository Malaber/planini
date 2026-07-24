import Crypto
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PlaniniCore
import Testing

@Suite(.serialized)
struct LiveBackendE2ETests {
    @Test("Account registration creates a passkey-backed account against a live backend")
    func accountRegistrationCreatesUsableAccount() async throws {
        guard let config = LiveBackendE2EConfiguration.fromEnvironment() else {
            return
        }

        let client = LiveBackendClient(baseURL: config.baseURL)
        let uniqueSuffix = UUID().uuidString.lowercased()
        let email = "ios-registration-\(uniqueSuffix)@example.com"
        let displayName = "iOS Registration E2E"

        let registrationOptions = try await client.jsonObject(
            path: "/api/v1/auth/register/options",
            method: "POST",
            body: [
                "email": email,
                "display_name": displayName,
            ],
            token: nil
        )
        let generatedPasskey = try GeneratedRegistrationFactory.makePasskey(
            options: registrationOptions,
            origin: config.origin,
            fallbackRelyingPartyIdentifier: config.rpID
        )
        let registeredUser = try await client.jsonObject(
            path: "/api/v1/auth/register/verify",
            method: "POST",
            body: ["credential": generatedPasskey.registrationCredential],
            token: nil
        )
        #expect(registeredUser["email"] as? String == email)
        #expect(registeredUser["display_name"] as? String == displayName)

        let loginOptions = try await client.jsonObject(
            path: "/api/v1/auth/login/options",
            method: "POST",
            body: [:],
            token: nil
        )
        let loginCredential = try SeededAssertionFactory.makeCredential(
            options: loginOptions,
            origin: config.origin,
            fallbackRelyingPartyIdentifier: config.rpID,
            credentialID: generatedPasskey.credentialID,
            signCount: 0,
            privateKey: generatedPasskey.privateKey,
            userHandle: generatedPasskey.userHandle
        )
        let tokenPayload = try await client.jsonObject(
            path: "/api/v1/auth/login/verify",
            method: "POST",
            body: ["credential": loginCredential],
            token: nil
        )
        let accessToken = try #require(tokenPayload["access_token"] as? String)

        let me = try await client.jsonObject(
            path: "/api/v1/auth/me",
            method: "GET",
            body: nil,
            token: accessToken
        )
        #expect(me["email"] as? String == email)
        #expect(me["display_name"] as? String == displayName)

        let household = try await client.jsonObject(
            path: "/api/v1/households",
            method: "POST",
            body: ["name": "iOS Registration Home"],
            token: accessToken
        )
        let householdID = try #require(household["id"] as? String)
        let list = try await client.jsonObject(
            path: "/api/v1/households/\(householdID)/lists",
            method: "POST",
            body: ["name": "First iOS List"],
            token: accessToken
        )
        #expect(list["name"] as? String == "First iOS List")
    }

    @Test("Seeded passkey login and list CRUD against a live backend")
    func seededPasskeyLoginAndListCrud() async throws {
        guard let config = LiveBackendE2EConfiguration.fromEnvironment() else {
            return
        }

        let fixture = try SeedFixture.load(from: config.seedPath, userEmail: config.userEmail)
        let client = LiveBackendClient(baseURL: config.baseURL)
        let accessToken = try await loginSeededUser(
            fixture: fixture,
            client: client,
            config: config
        )

        let me = try await client.jsonObject(
            path: "/api/v1/auth/me",
            method: "GET",
            body: nil,
            token: accessToken
        )
        #expect(me["email"] as? String == fixture.email)
        #expect(me["display_name"] as? String == fixture.displayName)

        let households = try await client.jsonArray(
            path: "/api/v1/households",
            token: accessToken
        )
        let household = try #require(households.first { $0["name"] as? String == fixture.primaryHouseholdName })
        let householdID = try #require(household["id"] as? String)

        let accentListName = "iOS Accent \(UUID().uuidString.prefix(8))"
        let createdAccentList = try await client.jsonObject(
            path: "/api/v1/households/\(householdID)/lists",
            method: "POST",
            body: ["name": accentListName],
            token: accessToken
        )
        let accentListID = try #require(createdAccentList["id"] as? String)
        #expect(createdAccentList["accent_color"] is NSNull)

        let tintedAccentList = try await client.jsonObject(
            path: "/api/v1/lists/\(accentListID)",
            method: "PATCH",
            body: ["accent_color": "#af52de"],
            token: accessToken
        )
        #expect(tintedAccentList["name"] as? String == accentListName)
        #expect(tintedAccentList["accent_color"] as? String == "#af52de")

        let renamedAccentListName = "\(accentListName) renamed"
        let renamedAccentList = try await client.jsonObject(
            path: "/api/v1/lists/\(accentListID)",
            method: "PATCH",
            body: ["name": renamedAccentListName],
            token: accessToken
        )
        #expect(renamedAccentList["name"] as? String == renamedAccentListName)
        #expect(renamedAccentList["accent_color"] as? String == "#af52de")

        let clearedAccentList = try await client.jsonObject(
            path: "/api/v1/lists/\(accentListID)",
            method: "PATCH",
            body: ["accent_color": NSNull()],
            token: accessToken
        )
        #expect(clearedAccentList["accent_color"] is NSNull)
        _ = try await client.jsonObject(
            path: "/api/v1/lists/\(accentListID)",
            method: "DELETE",
            body: nil,
            token: accessToken
        )

        let lists = try await client.jsonArray(
            path: "/api/v1/households/\(householdID)/lists",
            token: accessToken
        )
        let list = try #require(lists.first { $0["name"] as? String == fixture.primaryListName })
        let listID = try #require(list["id"] as? String)
        let moveTargetList = try #require(lists.first { ($0["id"] as? String) != listID })
        let moveTargetListID = try #require(moveTargetList["id"] as? String)

        let categoriesPayload = try await client.jsonArray(
            path: "/api/v1/lists/\(listID)/categories",
            token: accessToken
        )
        let categories = categoriesPayload.compactMap(GroceryCategorySummary.init)
        #expect(categories.contains(where: { $0.name == "Konserven" }))
        #expect(categories.contains(where: { $0.name == "Gemuese" }))

        let categoryOrderPayload = try await client.jsonArray(
            path: "/api/v1/lists/\(listID)/category-order",
            token: accessToken
        )
        let categoryOrder = categoryOrderPayload.compactMap(ListCategoryOrderEntry.init)
        #expect(categoryOrder.count >= 10)

        let initialItemsPayload = try await client.jsonArray(
            path: "/api/v1/lists/\(listID)/items",
            token: accessToken
        )
        let initialItems = initialItemsPayload.compactMap(GroceryItemRecord.init)
        let initialSections = GroceryItemSectionBuilder.build(
            items: initialItems,
            categories: categories,
            categoryOrder: categoryOrder
        )
        #expect(initialSections.map(\.title).prefix(5).elementsEqual(["On sale", "Uncategorized", "Konserven", "Milch & Eier", "Nudeln"]))
        #expect(initialSections.first?.items.map(\.name) == ["Sale apples"])
        #expect(initialSections.dropFirst().first?.items.contains(where: { $0.name == "Loose item" }) == true)
        #expect(initialSections.dropFirst().first?.items.contains(where: { $0.name == "Sale apples" }) == true)
        #expect(initialSections.last?.title == "Checked off")
        #expect(initialSections.last?.items.contains(where: { $0.name == "Brot" }) == true)

        let originalCategoryOrderIDs = categoryOrder.map(\.categoryID)
        if originalCategoryOrderIDs.count >= 2 {
            let reorderedCategoryIDs = [originalCategoryOrderIDs[1], originalCategoryOrderIDs[0]]
                + originalCategoryOrderIDs.dropFirst(2)
            let reorderedPayload = try await client.jsonArray(
                path: "/api/v1/lists/\(listID)/category-order",
                method: "PUT",
                body: ["category_ids": reorderedCategoryIDs.map(\.uuidString)],
                token: accessToken
            )
            let reorderedCategoryOrder = reorderedPayload.compactMap(ListCategoryOrderEntry.init)
            #expect(reorderedCategoryOrder.first?.categoryID == originalCategoryOrderIDs[1])

            _ = try await client.jsonArray(
                path: "/api/v1/lists/\(listID)/category-order",
                method: "PUT",
                body: ["category_ids": originalCategoryOrderIDs.map(\.uuidString)],
                token: accessToken
            )
        }

        let usedCategoryIDs = Set(initialItems.compactMap(\.categoryID))
        if let unusedCategory = categories.first(where: { usedCategoryIDs.contains($0.id) == false }) {
            let disabledPayload = try await client.jsonObject(
                path: "/api/v1/lists/\(listID)/disabled-categories",
                method: "PUT",
                body: ["category_ids": [unusedCategory.id.uuidString]],
                token: accessToken
            )
            let disabledCategoryIDs = (disabledPayload["category_ids"] as? [String] ?? [])
                .compactMap(UUID.init(uuidString:))
            #expect(disabledCategoryIDs == [unusedCategory.id])

            let enabledPayload = try await client.jsonObject(
                path: "/api/v1/lists/\(listID)/disabled-categories",
                method: "PUT",
                body: ["category_ids": []],
                token: accessToken
            )
            #expect((enabledPayload["category_ids"] as? [String] ?? []).isEmpty)
        }

        let sharedState = SharedAppState(
            authToken: accessToken,
            favoriteListID: UUID(uuidString: listID),
            items: initialItems,
            categories: categories,
            categoryOrder: categoryOrder
        )
        let restoredState = try JSONDecoder().decode(
            SharedAppState.self,
            from: JSONEncoder().encode(sharedState)
        )
        let restoredSections = GroceryItemSectionBuilder.build(
            items: restoredState.items,
            categories: restoredState.categories,
            categoryOrder: restoredState.categoryOrder
        )
        #expect(restoredSections.map(\.title).prefix(5).elementsEqual(["On sale", "Uncategorized", "Konserven", "Milch & Eier", "Nudeln"]))

        let konservenID = try #require(categories.first { $0.name == "Konserven" }?.id)
        let gemueseID = try #require(categories.first { $0.name == "Gemuese" }?.id)

        let uniqueSuffix = UUID().uuidString.prefix(8)
        let originalName = "iOS E2E \(uniqueSuffix)"
        let updatedName = "\(originalName) Updated"
        let saleReferenceDate = Date()
        let saleStartsAt = saleReferenceDate.addingTimeInterval(-60 * 60)
        let saleEndsAt = saleReferenceDate.addingTimeInterval(60 * 60)
        let saleStartsAtText = apiTimestamp(from: saleStartsAt)
        let saleEndsAtText = apiTimestamp(from: saleEndsAt)

        let created = try await client.jsonObject(
            path: "/api/v1/lists/\(listID)/items",
            method: "POST",
            body: [
                "name": originalName,
                "quantity_text": "2 jars",
                "note": "Created by iOS backend e2e",
                "category_id": konservenID.uuidString,
                "sale_starts_at": saleStartsAtText,
                "sale_ends_at": saleEndsAtText,
            ],
            token: accessToken
        )
        let itemID = try #require(created["id"] as? String)
        #expect(created["name"] as? String == originalName)
        #expect(created["checked"] as? Bool == false)
        #expect((created["category_id"] as? String)?.lowercased() == konservenID.uuidString.lowercased())
        #expect(created["sale_starts_at"] as? String != nil)
        #expect(created["sale_ends_at"] as? String != nil)

        let itemsAfterCreate = try await client.jsonArray(
            path: "/api/v1/lists/\(listID)/items",
            token: accessToken
        )
        #expect(itemsAfterCreate.contains(where: { ($0["id"] as? String) == itemID }))
        let itemsAfterCreateRecords = itemsAfterCreate.compactMap(GroceryItemRecord.init)
        let createdRecord = try #require(itemsAfterCreateRecords.first { $0.id.uuidString.lowercased() == itemID.lowercased() })
        #expect(createdRecord.isOnSale(at: saleReferenceDate))
        let sectionsAfterCreate = GroceryItemSectionBuilder.build(
            items: itemsAfterCreateRecords,
            categories: categories,
            categoryOrder: categoryOrder,
            now: saleReferenceDate
        )
        let onSaleSection = try #require(sectionsAfterCreate.first { $0.kind == .onSale })
        let createdCategorySection = try #require(
            sectionsAfterCreate.first { $0.kind == .category(konservenID) }
        )
        #expect(onSaleSection.items.contains(where: { $0.id == createdRecord.id }))
        #expect(createdCategorySection.items.contains(where: { $0.id == createdRecord.id }))

        let updated = try await client.jsonObject(
            path: "/api/v1/items/\(itemID)",
            method: "PATCH",
            body: [
                "name": updatedName,
                "quantity_text": "3 jars",
                "note": "Updated by iOS backend e2e",
                "category_id": gemueseID.uuidString
            ],
            token: accessToken
        )
        #expect(updated["name"] as? String == updatedName)
        #expect(updated["quantity_text"] as? String == "3 jars")
        #expect(updated["note"] as? String == "Updated by iOS backend e2e")
        #expect((updated["category_id"] as? String)?.lowercased() == gemueseID.uuidString.lowercased())

        let itemsAfterUpdate = try await client.jsonArray(
            path: "/api/v1/lists/\(listID)/items",
            token: accessToken
        )
        let updatedSections = GroceryItemSectionBuilder.build(
            items: itemsAfterUpdate.compactMap(GroceryItemRecord.init),
            categories: categories,
            categoryOrder: categoryOrder
        )
        let gemueseSection = try #require(updatedSections.first { $0.title == "Gemuese" })
        #expect(gemueseSection.items.contains(where: { $0.name == updatedName }))

        let moved = try await client.jsonObject(
            path: "/api/v1/items/\(itemID)",
            method: "PATCH",
            body: [
                "list_id": moveTargetListID,
            ],
            token: accessToken
        )
        #expect((moved["list_id"] as? String)?.lowercased() == moveTargetListID.lowercased())

        let targetItemsAfterMove = try await client.jsonArray(
            path: "/api/v1/lists/\(moveTargetListID)/items",
            token: accessToken
        )
        #expect(targetItemsAfterMove.contains(where: { ($0["id"] as? String) == itemID }))

        let movedBack = try await client.jsonObject(
            path: "/api/v1/items/\(itemID)",
            method: "PATCH",
            body: [
                "list_id": listID,
            ],
            token: accessToken
        )
        #expect((movedBack["list_id"] as? String)?.lowercased() == listID.lowercased())

        let checked = try await client.jsonObject(
            path: "/api/v1/items/\(itemID)/check",
            method: "POST",
            body: [:],
            token: accessToken
        )
        #expect(checked["checked"] as? Bool == true)
        let checkedRecord = try #require(GroceryItemRecord(json: checked))
        #expect(checkedRecord.saleStartsAt == createdRecord.saleStartsAt)
        #expect(checkedRecord.saleEndsAt == createdRecord.saleEndsAt)
        let sectionsAfterCheck = GroceryItemSectionBuilder.build(
            items: [checkedRecord],
            categories: categories,
            categoryOrder: categoryOrder,
            now: saleReferenceDate
        )
        let checkedSaleItem = try #require(
            sectionsAfterCheck.first { $0.kind == .onSale }?.items.first
        )
        let checkedNormalItem = try #require(
            sectionsAfterCheck.first { $0.kind == .checked }?.items.first
        )
        #expect(checkedSaleItem.id == checkedNormalItem.id)
        #expect(checkedSaleItem.checked)
        #expect(checkedNormalItem.checked)

        let unchecked = try await client.jsonObject(
            path: "/api/v1/items/\(itemID)/uncheck",
            method: "POST",
            body: [:],
            token: accessToken
        )
        #expect(unchecked["checked"] as? Bool == false)

        let hiddenUntil = ISO8601DateFormatter()
            .string(from: Date().addingTimeInterval(4 * 60 * 60))
        let hidden = try await client.jsonObject(
            path: "/api/v1/items/\(itemID)",
            method: "PATCH",
            body: ["hidden_until": hiddenUntil],
            token: accessToken
        )
        #expect(hidden["hidden_until"] as? String != nil)

        let itemsAfterHide = try await client.jsonArray(
            path: "/api/v1/lists/\(listID)/items",
            token: accessToken
        )
        let sectionsAfterHide = GroceryItemSectionBuilder.build(
            items: itemsAfterHide.compactMap(GroceryItemRecord.init),
            categories: categories,
            categoryOrder: categoryOrder
        )
        let hiddenSection = try #require(sectionsAfterHide.first { $0.kind == .hidden })
        let checkedIndex = try #require(sectionsAfterHide.firstIndex { $0.kind == .checked })
        let hiddenIndex = try #require(sectionsAfterHide.firstIndex { $0.kind == .hidden })
        #expect(hiddenIndex < checkedIndex)
        #expect(hiddenSection.title == "Saved for later")
        #expect(hiddenSection.items.contains(where: { $0.name == updatedName }))

        let restoredHidden = try await client.jsonObject(
            path: "/api/v1/items/\(itemID)",
            method: "PATCH",
            body: ["hidden_until": NSNull()],
            token: accessToken
        )
        #expect(restoredHidden["hidden_until"] is NSNull || restoredHidden["hidden_until"] == nil)

        let clearedSale = try await client.jsonObject(
            path: "/api/v1/items/\(itemID)",
            method: "PATCH",
            body: [
                "sale_starts_at": NSNull(),
                "sale_ends_at": NSNull(),
            ],
            token: accessToken
        )
        #expect(clearedSale["sale_starts_at"] is NSNull || clearedSale["sale_starts_at"] == nil)
        #expect(clearedSale["sale_ends_at"] is NSNull || clearedSale["sale_ends_at"] == nil)

        _ = try await client.data(
            path: "/api/v1/items/\(itemID)",
            method: "DELETE",
            body: nil,
            token: accessToken
        )

        let itemsAfterDelete = try await client.jsonArray(
            path: "/api/v1/lists/\(listID)/items",
            token: accessToken
        )
        #expect(itemsAfterDelete.contains(where: { ($0["id"] as? String) == itemID }) == false)
    }

    @Test("List websocket emits live item lifecycle events against a live backend")
    func listWebsocketEmitsItemLifecycleEvents() async throws {
        guard let config = LiveBackendE2EConfiguration.fromEnvironment() else {
            return
        }

        let fixture = try SeedFixture.load(from: config.seedPath, userEmail: config.userEmail)
        let client = LiveBackendClient(baseURL: config.baseURL)
        let accessToken = try await loginSeededUser(
            fixture: fixture,
            client: client,
            config: config
        )

        let households = try await client.jsonArray(
            path: "/api/v1/households",
            token: accessToken
        )
        let household = try #require(households.first { $0["name"] as? String == fixture.primaryHouseholdName })
        let householdID = try #require(household["id"] as? String)
        let lists = try await client.jsonArray(
            path: "/api/v1/households/\(householdID)/lists",
            token: accessToken
        )
        let list = try #require(lists.first { $0["name"] as? String == fixture.primaryListName })
        let listID = try #require(list["id"] as? String)

        let socket = try client.openListWebSocket(listID: listID, token: accessToken)
        defer {
            socket.cancel(with: .normalClosure, reason: nil)
        }

        let snapshot = try await client.receiveWebSocketEvent(from: socket)
        #expect(snapshot.type == "list_snapshot")

        let uniqueSuffix = UUID().uuidString.prefix(8)
        let originalName = "WebSocket E2E \(uniqueSuffix)"
        let updatedName = "\(originalName) Updated"
        let saleStartsAt = apiTimestamp(from: Date().addingTimeInterval(-60 * 60))
        let saleEndsAt = apiTimestamp(from: Date().addingTimeInterval(60 * 60))

        let created = try await client.jsonObject(
            path: "/api/v1/lists/\(listID)/items",
            method: "POST",
            body: [
                "name": originalName,
                "quantity_text": NSNull(),
                "note": "Created by websocket e2e",
                "category_id": NSNull(),
                "sale_starts_at": saleStartsAt,
                "sale_ends_at": saleEndsAt,
            ],
            token: accessToken
        )
        let itemID = try #require(created["id"] as? String)

        let createdEvent = try await client.receiveWebSocketEvent(from: socket)
        #expect(createdEvent.type == "item_created")
        #expect(createdEvent.itemID?.lowercased() == itemID.lowercased())
        #expect(createdEvent.saleStartsAt != nil)
        #expect(createdEvent.saleEndsAt != nil)

        _ = try await client.jsonObject(
            path: "/api/v1/items/\(itemID)",
            method: "PATCH",
            body: [
                "name": updatedName,
                "note": "Updated by websocket e2e",
            ],
            token: accessToken
        )

        let updatedEvent = try await client.receiveWebSocketEvent(from: socket)
        #expect(updatedEvent.type == "item_updated")
        #expect(updatedEvent.itemName == updatedName)

        _ = try await client.jsonObject(
            path: "/api/v1/items/\(itemID)/check",
            method: "POST",
            body: [:],
            token: accessToken
        )
        let checkedEvent = try await client.receiveWebSocketEvent(from: socket)
        #expect(checkedEvent.type == "item_checked")

        _ = try await client.jsonObject(
            path: "/api/v1/items/\(itemID)/uncheck",
            method: "POST",
            body: [:],
            token: accessToken
        )
        let uncheckedEvent = try await client.receiveWebSocketEvent(from: socket)
        #expect(uncheckedEvent.type == "item_unchecked")

        _ = try await client.data(
            path: "/api/v1/items/\(itemID)",
            method: "DELETE",
            body: nil,
            token: accessToken
        )
        let deletedEvent = try await client.receiveWebSocketEvent(from: socket)
        #expect(deletedEvent.type == "item_deleted")
        #expect(deletedEvent.itemID?.lowercased() == itemID.lowercased())
    }
}

private func loginSeededUser(
    fixture: SeedFixture,
    client: LiveBackendClient,
    config: LiveBackendE2EConfiguration
) async throws -> String {
    let loginOptions = try await client.jsonObject(
        path: "/api/v1/auth/login/options",
        method: "POST",
        body: [:],
        token: nil
    )

    var lastError: Error?
    for signCountOffset in 1 ... 4 {
        do {
            let credential = try SeededAssertionFactory.makeCredential(
                options: loginOptions,
                origin: config.origin,
                fallbackRelyingPartyIdentifier: config.rpID,
                passkey: fixture.passkey,
                signCountOffset: signCountOffset
            )
            let tokenPayload = try await client.jsonObject(
                path: "/api/v1/auth/login/verify",
                method: "POST",
                body: ["credential": credential],
                token: nil
            )
            return try #require(tokenPayload["access_token"] as? String)
        } catch {
            lastError = error
        }
    }

    throw lastError ?? LiveBackendE2EError("Seeded login failed without a specific error.")
}

private func apiTimestamp(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private struct LiveBackendE2EConfiguration {
    let baseURL: URL
    let seedPath: URL
    let userEmail: String
    let rpID: String?
    let configuredOrigin: String?

    var origin: String {
        configuredOrigin?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            ?? baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func fromEnvironment() -> Self? {
        let environment = ProcessInfo.processInfo.environment
        guard
            let baseURLText = environment["PLANINI_E2E_BASE_URL"],
            let baseURL = URL(string: baseURLText),
            let seedPathText = environment["PLANINI_E2E_SEED_PATH"],
            seedPathText.isEmpty == false
        else {
            return nil
        }

        let seedPath = URL(fileURLWithPath: seedPathText)
        let userEmail = environment["PLANINI_E2E_USER_EMAIL"] ?? "planini@schaedler.rocks"
        let rpID = environment["PLANINI_E2E_RP_ID"]
        let origin = environment["PLANINI_E2E_ORIGIN"].flatMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return Self(
            baseURL: baseURL,
            seedPath: seedPath,
            userEmail: userEmail,
            rpID: rpID,
            configuredOrigin: origin
        )
    }
}

private struct SeedFixture: Decodable {
    struct E2EMetadata: Decodable {
        let primaryHousehold: String
        let primaryList: String

        private enum CodingKeys: String, CodingKey {
            case primaryHousehold = "primary_household"
            case primaryList = "primary_list"
        }
    }

    struct User: Decodable {
        let email: String
        let displayName: String
        let passkey: Passkey?

        private enum CodingKeys: String, CodingKey {
            case email
            case displayName = "display_name"
            case passkey
        }
    }

    struct Passkey: Decodable {
        let credentialID: String
        let signCount: Int
        let privateKeyPKCS8Base64: String
        let userHandleBase64: String

        private enum CodingKeys: String, CodingKey {
            case credentialID = "credential_id"
            case signCount = "sign_count"
            case privateKeyPKCS8Base64 = "private_key_pkcs8_b64"
            case userHandleBase64 = "user_handle_b64"
        }
    }

    let e2e: E2EMetadata
    let users: [User]

    var email: String
    var displayName: String
    var passkey: Passkey
    var primaryHouseholdName: String
    var primaryListName: String

    private enum CodingKeys: String, CodingKey {
        case e2e
        case users
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        e2e = try container.decode(E2EMetadata.self, forKey: .e2e)
        users = try container.decode([User].self, forKey: .users)
        email = ""
        displayName = ""
        passkey = Passkey(
            credentialID: "",
            signCount: 0,
            privateKeyPKCS8Base64: "",
            userHandleBase64: ""
        )
        primaryHouseholdName = e2e.primaryHousehold
        primaryListName = e2e.primaryList
    }

    static func load(from url: URL, userEmail: String) throws -> SeedFixture {
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(SeedFixture.self, from: data)
        guard let user = decoded.users.first(where: { $0.email == userEmail }), let passkey = user.passkey else {
            throw LiveBackendE2EError("Seed fixture does not contain a passkey for \(userEmail).")
        }

        var resolved = decoded
        resolved.email = user.email
        resolved.displayName = user.displayName
        resolved.passkey = passkey
        return resolved
    }
}

private final class LiveBackendClient {
    let baseURL: URL
    let session: URLSession
    private var sessionCookie: String?

    init(baseURL: URL) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        // Keep cookie handling isolated and portable. FoundationNetworking does
        // not expose HTTPCookieStorage's empty initializer on Linux, while this
        // client already captures and sends the session cookie explicitly.
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration)
    }

    func jsonObject(
        path: String,
        method: String,
        body: [String: Any]?,
        token: String?
    ) async throws -> [String: Any] {
        let data = try await data(path: path, method: method, body: body, token: token)
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LiveBackendE2EError("Expected JSON object for \(path).")
        }
        return payload
    }

    func jsonArray(
        path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        token: String
    ) async throws -> [[String: Any]] {
        let data = try await data(path: path, method: method, body: body, token: token)
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw LiveBackendE2EError("Expected JSON array for \(path).")
        }
        return payload
    }

    func data(
        path: String,
        method: String,
        body: [String: Any]?,
        token: String?
    ) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw LiveBackendE2EError("Invalid URL path \(path).")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let sessionCookie {
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LiveBackendE2EError("Expected HTTP response for \(path).")
        }
        if let setCookie = httpResponse.value(forHTTPHeaderField: "Set-Cookie") {
            let sessionCookies: [String] = setCookie
                .split(separator: ",")
                .map(String.init)
                .compactMap { cookie -> String? in
                    let trimmed = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmed.hasPrefix("session=") else { return nil }
                    return trimmed.split(separator: ";", maxSplits: 1).first.map(String.init)
                }
            sessionCookie = sessionCookies.first ?? sessionCookie
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw LiveBackendE2EError("Request \(method) \(path) failed with status \(httpResponse.statusCode): \(bodyText)")
        }
        return data
    }

    func openListWebSocket(listID: String, token: String) throws -> URLSessionWebSocketTask {
        guard
            var components = URLComponents(
                url: URL(string: "/api/v1/ws/lists/\(listID)", relativeTo: baseURL)!,
                resolvingAgainstBaseURL: true
            )
        else {
            throw LiveBackendE2EError("Could not build websocket URL for list \(listID).")
        }
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = components.url else {
            throw LiveBackendE2EError("Could not resolve websocket URL for list \(listID).")
        }
        let task = session.webSocketTask(with: url)
        task.resume()
        return task
    }

    func receiveWebSocketEvent(from socket: URLSessionWebSocketTask) async throws -> LiveListSocketEvent {
        let message = try await socket.receive()
        let payloadData: Data
        switch message {
        case let .string(text):
            guard let data = text.data(using: .utf8) else {
                throw LiveBackendE2EError("Websocket text event was not valid UTF-8.")
            }
            payloadData = data
        case let .data(data):
            payloadData = data
        @unknown default:
            throw LiveBackendE2EError("Received unknown websocket message type.")
        }

        return try JSONDecoder().decode(LiveListSocketEvent.self, from: payloadData)
    }
}

private struct LiveListSocketEvent: Decodable {
    struct Payload: Decodable {
        struct Item: Decodable {
            let id: String?
            let name: String?
            let saleStartsAt: String?
            let saleEndsAt: String?

            private enum CodingKeys: String, CodingKey {
                case id
                case name
                case saleStartsAt = "sale_starts_at"
                case saleEndsAt = "sale_ends_at"
            }
        }

        let item: Item?
    }

    let type: String
    let payload: Payload?

    var itemID: String? {
        payload?.item?.id
    }

    var itemName: String? {
        payload?.item?.name
    }

    var saleStartsAt: String? {
        payload?.item?.saleStartsAt
    }

    var saleEndsAt: String? {
        payload?.item?.saleEndsAt
    }
}

private enum SeededAssertionFactory {
    static func makeCredential(
        options: [String: Any],
        origin: String,
        fallbackRelyingPartyIdentifier: String?,
        passkey: SeedFixture.Passkey,
        signCountOffset: Int = 1
    ) throws -> [String: Any] {
        guard let privateKeyData = Data(base64Encoded: passkey.privateKeyPKCS8Base64) else {
            throw LiveBackendE2EError("Passkey fixture has an invalid private key.")
        }
        let privateKey = try P256.Signing.PrivateKey(derRepresentation: privateKeyData)
        guard let userHandle = Data(base64Encoded: passkey.userHandleBase64) else {
            throw LiveBackendE2EError("Passkey fixture has an invalid user handle.")
        }

        return try makeCredential(
            options: options,
            origin: origin,
            fallbackRelyingPartyIdentifier: fallbackRelyingPartyIdentifier,
            credentialID: passkey.credentialID,
            signCount: passkey.signCount,
            privateKey: privateKey,
            userHandle: userHandle,
            signCountOffset: signCountOffset
        )
    }

    static func makeCredential(
        options: [String: Any],
        origin: String,
        fallbackRelyingPartyIdentifier: String?,
        credentialID: String,
        signCount: Int,
        privateKey: P256.Signing.PrivateKey,
        userHandle: Data,
        signCountOffset: Int = 1
    ) throws -> [String: Any] {
        let publicKey = (options["publicKey"] as? [String: Any]) ?? options
        guard let challenge = publicKey["challenge"] as? String else {
            throw LiveBackendE2EError("Login options are missing a challenge.")
        }

        let rpID = (publicKey["rpId"] as? String) ?? fallbackRelyingPartyIdentifier
        guard let rpID, rpID.isEmpty == false else {
            throw LiveBackendE2EError("Login options are missing an rpId.")
        }

        let clientDataJSON = try JSONSerialization.data(
            withJSONObject: [
                "type": "webauthn.get",
                "challenge": challenge,
                "origin": origin,
                "crossOrigin": false
            ]
        )
        let clientDataHash = Data(SHA256.hash(data: clientDataJSON))
        let authenticatorData = makeAuthenticatorData(
            rpID: rpID,
            nextSignCount: UInt32(signCount + signCountOffset)
        )

        var signaturePayload = Data()
        signaturePayload.append(authenticatorData)
        signaturePayload.append(clientDataHash)
        let signature = try privateKey.signature(for: signaturePayload).derRepresentation

        return [
            "id": credentialID,
            "rawId": credentialID,
            "type": "public-key",
            "response": [
                "authenticatorData": authenticatorData.base64URLEncodedString(),
                "clientDataJSON": clientDataJSON.base64URLEncodedString(),
                "signature": signature.base64URLEncodedString(),
                "userHandle": userHandle.base64URLEncodedString()
            ],
            "clientExtensionResults": [:]
        ]
    }

    private static func makeAuthenticatorData(rpID: String, nextSignCount: UInt32) -> Data {
        var data = Data(SHA256.hash(data: Data(rpID.utf8)))
        data.append(0x05)
        var counter = nextSignCount.bigEndian
        withUnsafeBytes(of: &counter) { rawBuffer in
            data.append(contentsOf: rawBuffer)
        }
        return data
    }
}

private struct GeneratedPasskey {
    let credentialID: String
    let privateKey: P256.Signing.PrivateKey
    let userHandle: Data
    let registrationCredential: [String: Any]
}

private enum GeneratedRegistrationFactory {
    static func makePasskey(
        options: [String: Any],
        origin: String,
        fallbackRelyingPartyIdentifier: String?
    ) throws -> GeneratedPasskey {
        let publicKey = (options["publicKey"] as? [String: Any]) ?? options
        guard
            let challenge = publicKey["challenge"] as? String,
            let user = publicKey["user"] as? [String: Any],
            let userIDText = user["id"] as? String,
            let userHandle = Data(base64URLEncoded: userIDText)
        else {
            throw LiveBackendE2EError("Registration options are missing challenge or user data.")
        }

        let rp = publicKey["rp"] as? [String: Any]
        let rpID = (rp?["id"] as? String) ?? fallbackRelyingPartyIdentifier
        guard let rpID, rpID.isEmpty == false else {
            throw LiveBackendE2EError("Registration options are missing an rpId.")
        }

        let privateKey = P256.Signing.PrivateKey()
        let credentialIDData = Data(SHA256.hash(data: privateKey.publicKey.rawRepresentation))
        let credentialID = credentialIDData.base64URLEncodedString()
        let clientDataJSON = try JSONSerialization.data(
            withJSONObject: [
                "type": "webauthn.create",
                "challenge": challenge,
                "origin": origin,
                "crossOrigin": false
            ]
        )
        let authenticatorData = try makeAuthenticatorData(
            rpID: rpID,
            credentialID: credentialIDData,
            publicKey: privateKey.publicKey
        )
        let attestationObject = CBOR.map([
            (CBOR.text("fmt"), CBOR.text("none")),
            (CBOR.text("authData"), CBOR.bytes(authenticatorData)),
            (CBOR.text("attStmt"), CBOR.map([])),
        ])
        let registrationCredential: [String: Any] = [
            "id": credentialID,
            "rawId": credentialID,
            "type": "public-key",
            "response": [
                "clientDataJSON": clientDataJSON.base64URLEncodedString(),
                "attestationObject": attestationObject.base64URLEncodedString(),
            ],
            "clientExtensionResults": [:],
        ]

        return GeneratedPasskey(
            credentialID: credentialID,
            privateKey: privateKey,
            userHandle: userHandle,
            registrationCredential: registrationCredential
        )
    }

    private static func makeAuthenticatorData(
        rpID: String,
        credentialID: Data,
        publicKey: P256.Signing.PublicKey
    ) throws -> Data {
        let rawPublicKey = publicKey.rawRepresentation
        let coordinateBytes: Data
        if rawPublicKey.count == 65, rawPublicKey.first == 0x04 {
            coordinateBytes = Data(rawPublicKey.dropFirst())
        } else if rawPublicKey.count == 64 {
            coordinateBytes = rawPublicKey
        } else {
            throw LiveBackendE2EError("Generated passkey has an invalid P-256 public key.")
        }

        let xCoordinate = coordinateBytes.prefix(32)
        let yCoordinate = coordinateBytes.suffix(32)
        let cosePublicKey = CBOR.map([
            (CBOR.unsigned(1), CBOR.unsigned(2)),
            (CBOR.unsigned(3), CBOR.negative(-7)),
            (CBOR.negative(-1), CBOR.unsigned(1)),
            (CBOR.negative(-2), CBOR.bytes(Data(xCoordinate))),
            (CBOR.negative(-3), CBOR.bytes(Data(yCoordinate))),
        ])

        var data = Data(SHA256.hash(data: Data(rpID.utf8)))
        data.append(0x45)
        data.append(contentsOf: [0, 0, 0, 0])
        data.append(Data(repeating: 0, count: 16))
        var credentialLength = UInt16(credentialID.count).bigEndian
        withUnsafeBytes(of: &credentialLength) { data.append(contentsOf: $0) }
        data.append(credentialID)
        data.append(cosePublicKey)
        return data
    }
}

private enum CBOR {
    static func unsigned(_ value: UInt64) -> Data {
        encodedMajorType(0, value: value)
    }

    static func negative(_ value: Int64) -> Data {
        precondition(value < 0)
        return encodedMajorType(1, value: UInt64(-1 - value))
    }

    static func bytes(_ value: Data) -> Data {
        encodedMajorType(2, value: UInt64(value.count)) + value
    }

    static func text(_ value: String) -> Data {
        let bytes = Data(value.utf8)
        return encodedMajorType(3, value: UInt64(bytes.count)) + bytes
    }

    static func map(_ entries: [(Data, Data)]) -> Data {
        var data = encodedMajorType(5, value: UInt64(entries.count))
        for (key, value) in entries {
            data.append(key)
            data.append(value)
        }
        return data
    }

    private static func encodedMajorType(_ majorType: UInt8, value: UInt64) -> Data {
        let prefix = majorType << 5
        switch value {
        case 0 ..< 24:
            return Data([prefix | UInt8(value)])
        case 24 ... UInt64(UInt8.max):
            return Data([prefix | 24, UInt8(value)])
        case UInt64(UInt8.max) + 1 ... UInt64(UInt16.max):
            var encoded = UInt16(value).bigEndian
            var data = Data([prefix | 25])
            withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
            return data
        case UInt64(UInt16.max) + 1 ... UInt64(UInt32.max):
            var encoded = UInt32(value).bigEndian
            var data = Data([prefix | 26])
            withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
            return data
        default:
            var encoded = value.bigEndian
            var data = Data([prefix | 27])
            withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
            return data
        }
    }
}

private struct LiveBackendE2EError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        let normalized = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padded = normalized + String(repeating: "=", count: (4 - normalized.count % 4) % 4)
        self.init(base64Encoded: padded)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

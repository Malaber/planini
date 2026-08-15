import XCTest
#if canImport(UIKit)
import UIKit
#endif

final class PlaniniUITests: XCTestCase {
    private let seededEmail = "planini@schaedler.rocks"
    private let initialListName = "Browser Test Shop"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMarketingScreenshots() throws {
        try assertLocalTestBackend()

        let primarySession = if let injectedSession {
            injectedSession
        } else {
            try bootstrapSession(email: userEmail)
        }
        var variants = [
            MarketingScreenshotVariant(
                localeDirectory: "en-US",
                language: "en",
                initialListName: configuredInitialListName,
                session: primarySession
            )
        ]
        if let germanSession = injectedGermanMarketingSession,
            let germanListName = environmentValue(
                "PLANINI_UI_TEST_MARKETING_GERMAN_INITIAL_LIST_NAME"
            )
        {
            variants.append(
                MarketingScreenshotVariant(
                    localeDirectory: "de-DE",
                    language: "de",
                    initialListName: germanListName,
                    session: germanSession
                )
            )
        }

        for variant in variants {
            captureMarketingScreenshots(for: variant)
        }
    }

    func testAppleIntelligenceCategorySuggestion() throws {
        try assertLocalTestBackend()
        let session = if let injectedSession {
            injectedSession
        } else {
            try bootstrapSession(email: userEmail)
        }

        let unavailableApp = launchedApp(
            session: session,
            initialListName: initialListName,
            extraLaunchEnvironment: [
                "PLANINI_UI_TEST_APPLE_INTELLIGENCE_AVAILABLE": "0",
            ]
        )
        let unavailableListTitle = unavailableApp.staticTexts["list-detail-title"]
        XCTAssertTrue(
            openInitialListDetail(in: unavailableApp, listTitle: unavailableListTitle),
            "Expected initial list before checking unavailable Apple Intelligence UI."
        )
        XCTAssertTrue(openAddItemSheet(in: unavailableApp))
        XCTAssertFalse(
            unavailableApp.buttons["add-item-suggest-category-button"].exists,
            "Suggestion control must stay hidden when Apple Intelligence is unavailable."
        )
        terminateAndWait(unavailableApp)

        let itemName = "AI category \(UUID().uuidString.prefix(8))"
        let itemQuantity = "2 cartons"
        let itemNote = "for breakfast"
        let categoryName = "Dairy & Eggs"
        let app = launchedApp(
            session: session,
            initialListName: initialListName,
            extraLaunchEnvironment: [
                "PLANINI_UI_TEST_APPLE_INTELLIGENCE_AVAILABLE": "1",
                "PLANINI_UI_TEST_CATEGORY_SUGGESTION": categoryName,
                "PLANINI_UI_TEST_CATEGORY_SUGGESTION_EXPECTED_NAME": itemName,
                "PLANINI_UI_TEST_CATEGORY_SUGGESTION_EXPECTED_QUANTITY": itemQuantity,
                "PLANINI_UI_TEST_CATEGORY_SUGGESTION_EXPECTED_NOTE": itemNote,
            ]
        )
        var createdItemID: UUID?
        defer {
            terminateAndWait(app)
            if let createdItemID {
                try? deleteItem(itemID: createdItemID, accessToken: session.accessToken)
            }
        }

        let listTitle = app.staticTexts["list-detail-title"]
        XCTAssertTrue(
            openInitialListDetail(in: app, listTitle: listTitle),
            "Expected initial list before checking Apple Intelligence suggestion."
        )
        XCTAssertTrue(openAddItemSheet(in: app))

        let suggestionButton = app.buttons["add-item-suggest-category-button"]
        XCTAssertTrue(suggestionButton.waitForExistence(timeout: 5))
        XCTAssertFalse(suggestionButton.isEnabled, "Suggestion needs an item name.")

        let nameField = app.textFields["add-item-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        XCTAssertTrue(prepareKeyboardForTyping(in: app, timeout: 3))
        nameField.typeText(itemName)
        XCTAssertTrue(waitForFieldValue(nameField, contains: itemName))

        let quantityField = app.textFields["add-item-quantity-field"]
        quantityField.tap()
        quantityField.typeText(itemQuantity)
        XCTAssertTrue(waitForFieldValue(quantityField, contains: itemQuantity))

        let noteField = app.textFields["add-item-note-field"]
        scrollToHittable(noteField, in: app)
        noteField.tap()
        noteField.typeText(itemNote)
        XCTAssertTrue(waitForFieldValue(noteField, contains: itemNote))

        scrollToHittable(suggestionButton, in: app)
        XCTAssertTrue(suggestionButton.isEnabled)
        tapElement(suggestionButton)
        XCTAssertTrue(
            waitForElementLabel(
                app.staticTexts["add-item-category-suggestion-status"],
                containing: "Suggested \(categoryName).",
                timeout: 8
            )
        )
        XCTAssertTrue(
            waitForElementLabel(
                app.buttons["add-item-category-link"].firstMatch,
                containing: categoryName
            )
        )

        XCTAssertTrue(tapAddItemSaveAndWaitForDismissal(in: app))
        XCTAssertTrue(
            waitForItemCategory(
                named: itemName,
                categoryNamed: categoryName,
                inListNamed: initialListName,
                accessToken: session.accessToken,
                timeout: 20
            )
        )
        createdItemID = try itemID(
            named: itemName,
            inListNamed: initialListName,
            accessToken: session.accessToken
        )
    }

    private func captureMarketingScreenshots(for variant: MarketingScreenshotVariant) {
        let platformDirectory = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        let artifactDirectory = "\(platformDirectory)/\(variant.localeDirectory)"
        let app = launchedApp(
            session: variant.session,
            initialListName: variant.initialListName,
            language: variant.language
        )
        defer { terminateAndWait(app) }

        let listTitle = app.staticTexts["list-detail-title"]
        XCTAssertTrue(
            openInitialListDetail(
                in: app,
                listTitle: listTitle,
                listName: variant.initialListName
            ),
            "Expected marketing list to open."
        )
        XCTAssertEqual(listTitle.label, variant.initialListName)
        captureScreenshot(
            named: "app-store-\(platformDirectory)-02-weekly-groceries",
            relativeArtifactDirectory: artifactDirectory
        )

        XCTAssertTrue(
            openMarketingListsRoot(in: app, listName: variant.initialListName),
            "Expected marketing lists overview to open."
        )
        let marketingListRow = app.buttons["list-row-\(variant.initialListName)"]
        XCTAssertTrue(marketingListRow.waitForExistence(timeout: 10))
        captureScreenshot(
            named: "app-store-\(platformDirectory)-01-lists",
            relativeArtifactDirectory: artifactDirectory
        )

        tapElement(marketingListRow)
        XCTAssertTrue(listTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(openAddItemSheet(in: app))
        let nameField = app.textFields["add-item-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        tapElement(nameField)
        XCTAssertTrue(prepareKeyboardForTyping(in: app, timeout: 5))
        let itemName = variant.language == "de" ? "Dunkle Schokolade" : "Dark chocolate"
        replaceText(in: nameField, with: itemName)
        XCTAssertTrue(waitForFieldValue(nameField, contains: itemName))
        captureScreenshot(
            named: "app-store-\(platformDirectory)-03-add-item",
            relativeArtifactDirectory: artifactDirectory
        )
    }

    private func openMarketingListsRoot(in app: XCUIApplication, listName: String) -> Bool {
        let listRow = app.buttons["list-row-\(listName)"]
        let listsLabels = ["Lists", "Listen"]
        var candidates = [
            app.tabBars.buttons.matching(identifier: "tab-lists-button").firstMatch,
            app.buttons.matching(identifier: "tab-lists-button").firstMatch,
        ]
        candidates += listsLabels.flatMap { label in
            [
                app.tabBars.buttons.matching(
                    NSPredicate(format: "label == %@", label)
                ).firstMatch,
                app.buttons.matching(
                    NSPredicate(format: "label == %@", label)
                ).firstMatch,
            ]
        }

        for candidate in candidates where candidate.exists {
            tapElement(candidate)
            returnToListsRootIfNeeded(app, listName: listName)
            if listRow.waitForExistence(timeout: 3) {
                return true
            }
        }
        return listRow.exists
    }

    func testListViewFlow() throws {
        try assertLocalTestBackend()
        let loginApp = XCUIApplication()
        configureLaunchLanguage(for: loginApp)
        loginApp.launchEnvironment["PLANINI_UI_TEST_MODE"] = "1"
        loginApp.launchEnvironment["PLANINI_BACKEND_BASE_URL_OVERRIDE"] = baseURL.absoluteString
        loginApp.launch()
        XCTAssertTrue(loginApp.buttons["login-passkey-button"].waitForExistence(timeout: 10))
        captureScreenshot(named: "promotion-login-dialogue")
        assertAccountRegistrationAvailable(in: loginApp)
        terminateAndWait(loginApp)
        loginApp.launch()
        XCTAssertTrue(loginApp.buttons["login-passkey-button"].waitForExistence(timeout: 10))
        assertReviewerOnboardingAvailable(in: loginApp)
        terminateAndWait(loginApp)

        let session = if let injectedSession {
            injectedSession
        } else {
            try bootstrapSession(email: userEmail)
        }

        let app = XCUIApplication()
        configureLaunchLanguage(for: app)
        app.launchEnvironment["PLANINI_UI_TEST_MODE"] = "1"
        app.launchEnvironment["PLANINI_BACKEND_BASE_URL_OVERRIDE"] = baseURL.absoluteString
        app.launchEnvironment["PLANINI_UI_TEST_ACCESS_TOKEN"] = session.accessToken
        app.launchEnvironment["PLANINI_UI_TEST_DISPLAY_NAME"] = session.displayName
        app.launchEnvironment["PLANINI_UI_TEST_INITIAL_LIST_NAME"] = initialListName
        app.launchEnvironment["PLANINI_UI_TEST_RESET_APPEARANCE_MODE"] = "1"
        app.launchEnvironment["PLANINI_UI_TEST_CATEGORY_ORDER_SAVE_DELAY_MS"] = "5000"

        let hostingListName = "Hosting errands"
        let hostingListID = try normalizeListName(
            prefixedBy: hostingListName,
            to: hostingListName,
            accessToken: session.accessToken
        )
        app.launch()

        let listTitle = app.staticTexts["list-detail-title"]
        XCTAssertTrue(
            openInitialListDetail(in: app, listTitle: listTitle),
            "Expected bootstrapped initial list to open."
        )
        XCTAssertTrue(tapTab("Lists", in: app))
        let initialListRow = app.buttons["list-row-\(initialListName)"]
        XCTAssertTrue(initialListRow.waitForExistence(timeout: 10))
        captureScreenshot(named: "promotion-list-of-lists")
        tapElement(initialListRow)
        XCTAssertTrue(listTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(listTitle.label, initialListName)
        captureScreenshot(named: "ios-ui-list-detail")

        guard let visibleQuickAddSection = firstVisibleQuickAddSection(in: app, timeout: 5) else {
            XCTFail("Expected at least one list section with quick-add controls.")
            return
        }
        XCTAssertTrue(app.staticTexts[visibleQuickAddSection.title].waitForExistence(timeout: 3))
        let favoriteButton = app.buttons["favorite-list-button"]
        XCTAssertTrue(favoriteButton.waitForExistence(timeout: 3))
        favoriteButton.tap()
        XCTAssertTrue(waitForElementToDisappear(app.tabBars.buttons[initialListName], timeout: 5))
        XCTAssertTrue(favoriteButton.waitForExistence(timeout: 5))
        favoriteButton.tap()
        XCTAssertTrue(app.tabBars.buttons[initialListName].waitForExistence(timeout: 5))

        XCTAssertTrue(tapTab(initialListName, in: app))
        XCTAssertTrue(listTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(listTitle.label, initialListName)
        captureScreenshot(named: "ios-ui-favorite-list")

        let favoriteSwitcherButton = app.buttons["list-switcher-button"]
        XCTAssertTrue(favoriteSwitcherButton.waitForExistence(timeout: 5))
        tapElement(favoriteSwitcherButton)
        let hostingFavoriteSwitchTarget = firstExistingElement(
            [
                app.buttons["switch-list-\(hostingListName)"],
                app.buttons[hostingListName],
                app.menuItems[hostingListName],
            ],
            timeout: 8
        )
        XCTAssertTrue(hostingFavoriteSwitchTarget.waitForExistence(timeout: 8))
        tapElement(hostingFavoriteSwitchTarget)
        XCTAssertTrue(listTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(listTitle.label, hostingListName)

        XCTAssertTrue(tapTab(initialListName, in: app))
        XCTAssertTrue(listTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(listTitle.label, initialListName)

        let konservenCountBadge = firstExistingElement(
            [
                app.staticTexts.matching(
                    NSPredicate(format: "label BEGINSWITH %@", "\(visibleQuickAddSection.title) count,")
                ).firstMatch,
                app.otherElements.matching(
                    NSPredicate(format: "label BEGINSWITH %@", "\(visibleQuickAddSection.title) count,")
                ).firstMatch,
            ],
            timeout: 3
        )
        XCTAssertTrue(konservenCountBadge.waitForExistence(timeout: 3))
        XCTAssertTrue(konservenCountBadge.label.hasPrefix("\(visibleQuickAddSection.title) count,"))

        let quickAddButton = visibleQuickAddSection.button
        XCTAssertTrue(quickAddButton.waitForExistence(timeout: 3))
        XCTAssertTrue(openAddItemSheet(using: quickAddButton, in: app))
        XCTAssertTrue(app.buttons["add-item-save-button"].waitForExistence(timeout: 3))
        captureScreenshot(named: "ios-ui-category-quick-add")
        tapCancelButton(in: app)
        XCTAssertTrue(waitForElementToDisappear(app.otherElements["add-item-sheet"], timeout: 3))

        XCTAssertTrue(openAddItemSheet(in: app))
        XCTAssertTrue(prepareKeyboardForTyping(in: app, timeout: 3))
        captureScreenshot(named: "ios-ui-add-item-sheet")

        let suggestionProbeField = app.textFields["add-item-name-field"]
        XCTAssertTrue(suggestionProbeField.waitForExistence(timeout: 3))
        let seededItemID = try itemID(named: "Brot", inListNamed: initialListName, accessToken: session.accessToken)
        replaceText(in: suggestionProbeField, with: "Bro")
        let seededCheckedSuggestion = app.buttons["add-item-suggestion-\(seededItemID.uuidString)"]
        if seededCheckedSuggestion.waitForExistence(timeout: 10) {
            XCTAssertFalse(seededCheckedSuggestion.images["scope"].exists, "Suggestion rows should not show a crosshair icon.")
            XCTAssertTrue(tapSuggestionAndWaitForSheetDismissal(seededCheckedSuggestion, app: app))
            XCTAssertTrue(
                waitForItemCheckedState(
                    named: "Brot",
                    checked: false,
                    inListNamed: initialListName,
                    accessToken: session.accessToken
                )
            )
            let suggestionUndoButton = app.buttons["list-undo-button"]
            let suggestionUndoMessage = app.staticTexts["list-undo-message"]
            XCTAssertTrue(suggestionUndoButton.waitForExistence(timeout: 5))
            XCTAssertTrue(suggestionUndoMessage.label.contains("Brot added back to the list."))
            captureScreenshot(named: "ios-ui-floating-undo-suggestion")
            tapElement(suggestionUndoButton)
        } else {
            tapCancelButton(in: app)
            XCTAssertTrue(waitForElementToDisappear(app.otherElements["add-item-sheet"], timeout: 3))
            XCTAssertTrue(waitForItemRow(itemID: seededItemID, named: "Brot", in: app, timeout: 15))
            let brotToggle = app.buttons["toggle-item-\(seededItemID.uuidString)"]
            XCTAssertTrue(brotToggle.waitForExistence(timeout: 5))
            tapElement(brotToggle)
            XCTAssertTrue(
                waitForItemCheckedState(
                    named: "Brot",
                    checked: false,
                    inListNamed: initialListName,
                    accessToken: session.accessToken
                )
            )
            let rowUndoButton = app.buttons["list-undo-button"]
            let rowUndoMessage = app.staticTexts["list-undo-message"]
            XCTAssertTrue(rowUndoButton.waitForExistence(timeout: 5))
            XCTAssertTrue(rowUndoMessage.label.contains("Brot unchecked."))
            captureScreenshot(named: "ios-ui-floating-undo-suggestion")
            tapElement(rowUndoButton)
        }
        XCTAssertTrue(
            waitForItemCheckedState(
                named: "Brot",
                checked: true,
                inListNamed: initialListName,
                accessToken: session.accessToken
            )
        )
        XCTAssertTrue(waitForElementToDisappear(app.otherElements["list-undo-toast"], timeout: 10))

        let seededCheckedItemID = try itemID(
            named: "Brot",
            inListNamed: initialListName,
            accessToken: session.accessToken
        )
        XCTAssertTrue(
            tapItemToggleButton(
                itemID: seededCheckedItemID,
                named: "Brot",
                checked: false,
                in: app,
                inListNamed: initialListName,
                accessToken: session.accessToken
            )
        )
        let uncheckUndoButton = app.buttons["list-undo-button"]
        let uncheckUndoMessage = app.staticTexts["list-undo-message"]
        XCTAssertTrue(uncheckUndoButton.waitForExistence(timeout: 5))
        XCTAssertTrue(uncheckUndoMessage.label.contains("Brot unchecked."))
        tapElement(uncheckUndoButton)
        XCTAssertTrue(
            waitForItemCheckedState(
                named: "Brot",
                checked: true,
                inListNamed: initialListName,
                accessToken: session.accessToken
            )
        )
        XCTAssertTrue(waitForElementToDisappear(app.otherElements["list-undo-toast"], timeout: 10))

        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        captureScreenshot(named: "ios-ui-suggestion-reactivated")

        XCTAssertTrue(openAddItemSheet(in: app))

        let uniqueSuffix = UUID().uuidString.prefix(8)
        let enterSavedItemName = "UI Test Enter \(uniqueSuffix)"
        let itemName = "UI Test Item \(uniqueSuffix)"
        let itemQuantity = "1 bunch"
        let updatedName = "\(itemName) Updated"

        let nameField = app.textFields["add-item-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        XCTAssertTrue(prepareKeyboardForTyping(in: app, timeout: 3))
        nameField.typeText(enterSavedItemName)
        XCTAssertTrue(waitForFieldValue(nameField, contains: enterSavedItemName))
        XCTAssertTrue(tapAddItemSaveAndWaitForDismissal(in: app))
        XCTAssertTrue(
            waitForItem(
                named: enterSavedItemName,
                inListNamed: initialListName,
                accessToken: session.accessToken,
                timeout: 20
            )
        )
        let enterSavedItemID = try itemID(
            named: enterSavedItemName,
            inListNamed: initialListName,
            accessToken: session.accessToken
        )
        XCTAssertTrue(waitForItemRow(itemID: enterSavedItemID, named: enterSavedItemName, in: app, timeout: 15))

        XCTAssertTrue(
            hideItemUsingSwipe(
                itemID: enterSavedItemID,
                named: enterSavedItemName,
                in: app,
                inListNamed: initialListName,
                accessToken: session.accessToken
            )
        )
        let hideUndoButton = app.buttons["list-undo-button"]
        let hideUndoMessage = app.staticTexts["list-undo-message"]
        XCTAssertTrue(hideUndoButton.waitForExistence(timeout: 5))
        XCTAssertTrue(hideUndoMessage.label.contains("\(enterSavedItemName) saved for later."))
        tapElement(hideUndoButton)
        XCTAssertTrue(
            waitForItemHiddenState(
                named: enterSavedItemName,
                hidden: false,
                inListNamed: initialListName,
                accessToken: session.accessToken,
                timeout: 20
            )
        )
        XCTAssertTrue(waitForElementToDisappear(app.otherElements["list-undo-toast"], timeout: 10))

        XCTAssertTrue(
            hideItemUsingSwipe(
                itemID: enterSavedItemID,
                named: enterSavedItemName,
                in: app,
                inListNamed: initialListName,
                accessToken: session.accessToken
            )
        )
        XCTAssertTrue(waitForElementToDisappear(app.otherElements["list-undo-toast"], timeout: 10))

        let hiddenForLaterHeader = app.staticTexts["section-count-badge-hidden"]
        scrollToElement(hiddenForLaterHeader, in: app)
        XCTAssertTrue(hiddenForLaterHeader.waitForExistence(timeout: 5))
        let restoreHiddenButton = app.buttons["toggle-item-\(enterSavedItemID.uuidString)"]
        scrollToHittable(restoreHiddenButton, in: app)
        XCTAssertTrue(restoreHiddenButton.waitForExistence(timeout: 5))
        XCTAssertTrue(restoreHiddenButton.isHittable)
        captureScreenshot(named: "ios-ui-item-hidden-for-later")
        XCTAssertTrue(
            unhideItemUsingSwipe(
                itemID: enterSavedItemID,
                named: enterSavedItemName,
                in: app,
                inListNamed: initialListName,
                accessToken: session.accessToken
            ),
            "Expected swiping hidden item right to show it now."
        )
        let unhideUndoButton = app.buttons["list-undo-button"]
        let unhideUndoMessage = app.staticTexts["list-undo-message"]
        XCTAssertTrue(unhideUndoButton.waitForExistence(timeout: 5))
        XCTAssertTrue(unhideUndoMessage.label.contains("\(enterSavedItemName) shown now."))
        tapElement(unhideUndoButton)
        XCTAssertTrue(
            waitForItemHiddenState(
                named: enterSavedItemName,
                hidden: true,
                inListNamed: initialListName,
                accessToken: session.accessToken,
                timeout: 20
            )
        )
        XCTAssertTrue(waitForElementToDisappear(app.otherElements["list-undo-toast"], timeout: 10))

        scrollToElement(hiddenForLaterHeader, in: app)
        scrollToHittable(restoreHiddenButton, in: app)
        XCTAssertTrue(restoreHiddenButton.waitForExistence(timeout: 5))
        XCTAssertTrue(restoreHiddenButton.isHittable)
        tapElement(restoreHiddenButton)
        XCTAssertTrue(
            waitForItemHiddenState(
                named: enterSavedItemName,
                hidden: false,
                inListNamed: initialListName,
                accessToken: session.accessToken,
                timeout: 20
            )
        )
        XCTAssertTrue(waitForElementToDisappear(hiddenForLaterHeader, timeout: 8))
        XCTAssertTrue(waitForElementToDisappear(app.otherElements["list-undo-toast"], timeout: 10))

        scrollToListTop(in: app)
        XCTAssertTrue(
            openEditItemSheet(
                itemID: enterSavedItemID,
                using: itemRow(itemID: enterSavedItemID, in: app),
                in: app
            )
        )
        let editHideForLaterButton = app.buttons["edit-item-hide-for-later-button"]
        scrollToElement(editHideForLaterButton, in: app)
        XCTAssertTrue(editHideForLaterButton.waitForExistence(timeout: 5))
        captureScreenshot(named: "ios-ui-edit-hide-for-later")
        tapElement(editHideForLaterButton)
        XCTAssertTrue(waitForElementToDisappear(app.otherElements["edit-item-sheet"], timeout: 12))
        XCTAssertTrue(
            waitForItemHiddenState(
                named: enterSavedItemName,
                hidden: true,
                inListNamed: initialListName,
                accessToken: session.accessToken,
                timeout: 20
            )
        )
        let editHideUndoButton = app.buttons["list-undo-button"]
        let editHideUndoMessage = app.staticTexts["list-undo-message"]
        XCTAssertTrue(editHideUndoButton.waitForExistence(timeout: 5))
        XCTAssertTrue(editHideUndoMessage.label.contains("\(enterSavedItemName) saved for later."))
        tapElement(editHideUndoButton)
        XCTAssertTrue(
            waitForItemHiddenState(
                named: enterSavedItemName,
                hidden: false,
                inListNamed: initialListName,
                accessToken: session.accessToken,
                timeout: 20
            )
        )
        XCTAssertTrue(waitForElementToDisappear(app.otherElements["list-undo-toast"], timeout: 10))

        XCTAssertTrue(openAddItemSheet(in: app))
        XCTAssertTrue(prepareKeyboardForTyping(in: app, timeout: 3))
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText(itemName)
        XCTAssertTrue(waitForFieldValue(nameField, contains: itemName))

        let quantityField = app.textFields["add-item-quantity-field"]
        quantityField.tap()
        quantityField.typeText(itemQuantity)
        XCTAssertTrue(waitForFieldValue(quantityField, contains: itemQuantity))

        chooseCategory(
            named: "Dairy & Eggs",
            using: "add-item-category-link",
            in: app,
            searchText: "dairy",
            sortOption: "A-Z",
            screenshotName: "ios-ui-category-picker"
        )
        XCTAssertTrue(
            waitForElementLabel(
                app.buttons["add-item-category-link"].firstMatch,
                containing: "Dairy & Eggs"
            )
        )

        let noteField = app.textFields["add-item-note-field"]
        noteField.tap()
        noteField.typeText("for pasta")
        XCTAssertTrue(waitForFieldValue(noteField, contains: "for pasta"))
        XCTAssertTrue(tapAddItemSaveAndWaitForDismissal(in: app))
        XCTAssertTrue(
            waitForItem(
                named: itemName,
                inListNamed: initialListName,
                accessToken: session.accessToken,
                timeout: 20
            )
        )
        let createdItemID = try itemID(
            named: itemName,
            inListNamed: initialListName,
            accessToken: session.accessToken
        )
        XCTAssertTrue(waitForItemRow(itemID: createdItemID, named: itemName, in: app, timeout: 15))
        captureScreenshot(named: "ios-ui-added-item")
        XCTAssertTrue(
            waitForItemCategory(
                named: itemName,
                categoryNamed: "Dairy & Eggs",
                inListNamed: initialListName,
                accessToken: session.accessToken
            )
        )

        let createdItemRow = itemRow(itemID: createdItemID, in: app)
        scrollToHittable(createdItemRow, in: app)
        createdItemRow.swipeLeft()
        let deleteButton = firstExistingElement(
            [
                app.buttons["delete-item-\(createdItemID.uuidString)"],
                app.buttons["Delete"],
            ],
            timeout: 3
        )
        XCTAssertTrue(deleteButton.exists)
        tapElement(deleteButton)
        let deleteUndoButton = app.buttons["list-undo-button"]
        let deleteUndoMessage = app.staticTexts["list-undo-message"]
        XCTAssertTrue(deleteUndoButton.waitForExistence(timeout: 20))
        XCTAssertTrue(deleteUndoMessage.label.contains("\(itemName) deleted."))
        XCTAssertTrue(
            waitForItemAbsent(
                named: itemName,
                inListNamed: initialListName,
                accessToken: session.accessToken
            )
        )
        captureScreenshot(named: "ios-ui-floating-undo-delete")
        tapElement(deleteUndoButton)
        XCTAssertTrue(
            waitForItem(
                named: itemName,
                inListNamed: initialListName,
                accessToken: session.accessToken
            )
        )
        let restoredItemID = try itemID(
            named: itemName,
            inListNamed: initialListName,
            accessToken: session.accessToken
        )
        XCTAssertTrue(
            waitForItemRow(itemID: restoredItemID, named: itemName, in: app, timeout: 15),
            "Expected restored item row to be visible after undoing delete."
        )
        XCTAssertTrue(
            waitForItemCategory(
                named: itemName,
                categoryNamed: "Dairy & Eggs",
                inListNamed: initialListName,
                accessToken: session.accessToken
            )
        )

        let restoredItemRow = itemRow(itemID: restoredItemID, in: app)
        XCTAssertTrue(openEditItemSheet(itemID: restoredItemID, using: restoredItemRow, in: app))
        let undoButton = firstExistingElement(
            [
                app.buttons["edit-item-undo-button"],
                app.buttons["Undo"],
                app.buttons["Ruckgangig"],
            ],
            timeout: 3
        )
        let redoButton = firstExistingElement(
            [
                app.buttons["edit-item-redo-button"],
                app.buttons["Redo"],
                app.buttons["Wiederholen"],
            ],
            timeout: 3
        )
        let closeButton = app.buttons["edit-item-close-button"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3))
        XCTAssertEqual(closeButton.label, "Done")
        XCTAssertTrue(closeButton.isHittable)
        captureScreenshot(named: "promotion-edit-item-dialogue")

        let editNameField = app.textFields["edit-item-name-field"]
        editNameField.tap()
        XCTAssertTrue(prepareKeyboardForTyping(in: app, timeout: 5))
        editNameField.typeText(" Updated")
        XCTAssertTrue(waitForFieldValue(editNameField, contains: updatedName))
        XCTAssertTrue(
            waitForItem(
                named: updatedName,
                inListNamed: initialListName,
                accessToken: session.accessToken,
                timeout: 20
            )
        )

        XCTAssertTrue(undoButton.waitForExistence(timeout: 3))
        undoButton.tap()
        XCTAssertTrue(waitForFieldValue(editNameField, contains: itemName))
        XCTAssertFalse(editNameField.valueText.contains("Updated"))
        XCTAssertTrue(
            waitForItem(
                named: itemName,
                inListNamed: initialListName,
                accessToken: session.accessToken,
                timeout: 20
            )
        )

        XCTAssertTrue(redoButton.waitForExistence(timeout: 3))
        redoButton.tap()
        XCTAssertTrue(waitForFieldValue(editNameField, contains: updatedName))
        XCTAssertTrue(
            waitForItem(
                named: updatedName,
                inListNamed: initialListName,
                accessToken: session.accessToken,
                timeout: 20
            )
        )

        chooseCategory(
            named: "Canned Goods",
            using: "edit-item-category-link",
            in: app,
            searchText: "can",
            sortOption: "most-used",
            screenshotName: "ios-ui-edit-category-picker"
        )
        XCTAssertTrue(
            waitForElementLabel(
                app.buttons["edit-item-category-link"].firstMatch,
                containing: "Canned Goods"
            )
        )
        XCTAssertTrue(
            waitForItemCategory(
                named: updatedName,
                categoryNamed: "Canned Goods",
                inListNamed: initialListName,
                accessToken: session.accessToken,
                timeout: 20
            )
        )
        captureScreenshot(named: "ios-ui-live-edit-autosave")
        tapElement(closeButton)
        XCTAssertTrue(
            waitForItem(
                named: updatedName,
                inListNamed: initialListName,
                accessToken: session.accessToken,
                timeout: 20
            )
        )
        let updatedItemID = try itemID(
            named: updatedName,
            inListNamed: initialListName,
            accessToken: session.accessToken
        )
        XCTAssertTrue(
            waitForItemRow(itemID: updatedItemID, named: updatedName, in: app, timeout: 20),
            "Expected updated item row to be visible after closing edit sheet."
        )
        XCTAssertTrue(
            waitForItemCategory(
                named: updatedName,
                categoryNamed: "Canned Goods",
                inListNamed: initialListName,
                accessToken: session.accessToken
            )
        )
        XCTAssertTrue(
            tapItemToggleButton(
                itemID: updatedItemID,
                named: updatedName,
                checked: true,
                in: app,
                inListNamed: initialListName,
                accessToken: session.accessToken,
                timeout: 20
            ),
            "Expected tapping the item check button to mark the item checked."
        )
        captureScreenshot(named: "ios-ui-checked-item")
        let haushaltCategoryID = try categoryID(
            named: "Household",
            inListNamed: hostingListName,
            accessToken: session.accessToken
        )
        let backwarenCategoryID = try categoryID(
            named: "Bakery",
            inListNamed: hostingListName,
            accessToken: session.accessToken
        )
        let hostingKonservenCategoryID = try categoryID(
            named: "Canned Goods",
            inListNamed: hostingListName,
            accessToken: session.accessToken
        )

        captureScreenshot(named: "promotion-filled-list")

        app.buttons["add-item-button"].tap()
        XCTAssertTrue(app.otherElements["add-item-sheet"].waitForExistence(timeout: 3))
        let checkedSuggestionField = app.textFields["add-item-name-field"]
        XCTAssertTrue(checkedSuggestionField.waitForExistence(timeout: 5))
        checkedSuggestionField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        checkedSuggestionField.typeText(updatedName)
        let checkedSuggestion = app.buttons["add-item-suggestion-\(updatedItemID.uuidString)"]
        XCTAssertTrue(checkedSuggestion.waitForExistence(timeout: 10))
        scrollToHittable(checkedSuggestion, in: app)
        captureScreenshot(named: "ios-ui-checked-item-suggestion")
        let addItemSheet = app.otherElements["add-item-sheet"]
        let cancelButton = app.buttons["Cancel"]
        if cancelButton.waitForExistence(timeout: 3) {
            cancelButton.tap()
        }
        XCTAssertTrue(waitForElementToDisappear(addItemSheet, timeout: 10))

        XCTAssertTrue(
            tapItemToggleButton(
                itemID: seededItemID,
                named: "Brot",
                checked: true,
                in: app,
                inListNamed: initialListName,
                accessToken: session.accessToken,
                timeout: 20
            ),
            "Expected tapping the seeded item check button to mark it checked."
        )
        XCTAssertTrue(
            waitForItemRow(itemID: seededItemID, named: "Brot", in: app, timeout: 20),
            "Expected checked seeded item row to be visible before opening edit sheet."
        )
        let seededMoveRow = itemRow(itemID: seededItemID, in: app)
        XCTAssertTrue(openEditItemSheet(itemID: seededItemID, using: seededMoveRow, in: app))
        let hostingMoveButton = app.buttons["edit-item-move-list-\(hostingListID.uuidString)"]
        XCTAssertTrue(hostingMoveButton.waitForExistence(timeout: 3))
        scrollToHittable(hostingMoveButton, in: app)
        tapElement(hostingMoveButton)
        XCTAssertTrue(waitForElementToDisappear(app.otherElements["edit-item-sheet"], timeout: 8))
        XCTAssertTrue(
            waitForItem(
                named: "Brot",
                inListNamed: "Hosting errands",
                accessToken: session.accessToken
            )
        )
        let moveNotice = app.otherElements["item-move-notice-\(seededItemID.uuidString)"]
        XCTAssertTrue(moveNotice.waitForExistence(timeout: 5))
        let moveNoticeMessage = app.staticTexts["item-move-notice-message-\(seededItemID.uuidString)"]
        XCTAssertTrue(moveNoticeMessage.waitForExistence(timeout: 3))
        XCTAssertTrue(moveNoticeMessage.label.contains("Brot"))
        XCTAssertTrue(moveNoticeMessage.label.contains("Hosting errands"))
        captureScreenshot(named: "ios-ui-moved-item-notice")
        let moveUndoButtonID = "move-item-undo-button-\(seededItemID.uuidString)"
        scrollToHittable(app.buttons[moveUndoButtonID], in: app, maxSwipes: 12)
        let moveUndoButton = app.buttons[moveUndoButtonID]
        XCTAssertTrue(moveUndoButton.waitForExistence(timeout: 5))
        tapElement(moveUndoButton)
        XCTAssertTrue(
            waitForItem(
                named: "Brot",
                inListNamed: initialListName,
                accessToken: session.accessToken
            )
        )
        XCTAssertTrue(
            waitForItemCheckedState(
                named: "Brot",
                checked: true,
                inListNamed: initialListName,
                accessToken: session.accessToken
            )
        )
        XCTAssertTrue(
            waitForItemCategory(
                named: "Brot",
                categoryNamed: "Bakery",
                inListNamed: initialListName,
                accessToken: session.accessToken
            )
        )
        XCTAssertTrue(
            waitForItemAbsent(
                named: "Brot",
                inListNamed: "Hosting errands",
                accessToken: session.accessToken
            )
        )
        XCTAssertTrue(waitForItemRow(itemID: seededItemID, named: "Brot", in: app, timeout: 20))

        XCTAssertTrue(
            waitForItemRow(itemID: updatedItemID, named: updatedName, in: app, timeout: 20),
            "Expected categorized updated item row to be visible before failed undo coverage."
        )
        let updatedMoveRow = itemRow(itemID: updatedItemID, in: app)
        XCTAssertTrue(openEditItemSheet(itemID: updatedItemID, using: updatedMoveRow, in: app))
        let failedUndoMoveButton = app.buttons["edit-item-move-list-\(hostingListID.uuidString)"]
        XCTAssertTrue(failedUndoMoveButton.waitForExistence(timeout: 3))
        scrollToHittable(failedUndoMoveButton, in: app)
        tapElement(failedUndoMoveButton)
        XCTAssertTrue(waitForElementToDisappear(app.otherElements["edit-item-sheet"], timeout: 8))
        XCTAssertTrue(
            waitForItem(
                named: updatedName,
                inListNamed: hostingListName,
                accessToken: session.accessToken
            )
        )
        let failedUndoNotice = app.otherElements["item-move-notice-\(updatedItemID.uuidString)"]
        XCTAssertTrue(failedUndoNotice.waitForExistence(timeout: 5))
        try deleteItem(itemID: updatedItemID, accessToken: session.accessToken)
        let failedUndoButtonID = "move-item-undo-button-\(updatedItemID.uuidString)"
        scrollToHittable(app.buttons[failedUndoButtonID], in: app, maxSwipes: 12)
        let failedUndoButton = app.buttons[failedUndoButtonID]
        XCTAssertTrue(failedUndoButton.waitForExistence(timeout: 5))
        tapElement(failedUndoButton)
        let failedUndoError = app.staticTexts["item-move-notice-error-\(updatedItemID.uuidString)"]
        XCTAssertTrue(failedUndoError.waitForExistence(timeout: 5))
        XCTAssertTrue(failedUndoNotice.exists)

        XCTAssertTrue(tapTab("Lists", in: app))
        returnToListsRootIfNeeded(app)
        let hostingListRow = app.buttons["list-row-\(hostingListName)"]
        scrollToHittable(hostingListRow, in: app, maxSwipes: 4)
        XCTAssertTrue(hostingListRow.waitForExistence(timeout: 10))
        hostingListRow.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        XCTAssertTrue(listTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(listTitle.label, hostingListName)
        captureScreenshot(named: "ios-ui-list-switcher")

        let switcherButton = app.buttons["list-switcher-button"]
        XCTAssertTrue(switcherButton.waitForExistence(timeout: 5))
        tapElement(switcherButton)
        let initialSwitchTarget = firstExistingElement(
            [
                app.buttons["switch-list-\(initialListName)"],
                app.buttons[initialListName],
                app.menuItems[initialListName],
            ],
            timeout: 8
        )
        XCTAssertTrue(initialSwitchTarget.waitForExistence(timeout: 8))
        tapElement(initialSwitchTarget)
        XCTAssertTrue(listTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(listTitle.label, initialListName)

        tapElement(switcherButton)
        let hostingSwitchTarget = firstExistingElement(
            [
                app.buttons["switch-list-\(hostingListName)"],
                app.buttons[hostingListName],
                app.menuItems[hostingListName],
            ],
            timeout: 8
        )
        XCTAssertTrue(hostingSwitchTarget.waitForExistence(timeout: 8))
        tapElement(hostingSwitchTarget)
        XCTAssertTrue(listTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(listTitle.label, hostingListName)

        let listSettingsButton = app.buttons["list-settings-button"]
        XCTAssertTrue(listSettingsButton.waitForExistence(timeout: 5))
        listSettingsButton.tap()
        XCTAssertTrue(app.otherElements["list-settings-sheet"].waitForExistence(timeout: 5))
        let settingsSaveState = app.descendants(matching: .any)["list-settings-save-state"].firstMatch
        XCTAssertTrue(settingsSaveState.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["list-settings-save-state"].exists)
        let listSettingsDoneButton = app.buttons["list-settings-done-button"]
        XCTAssertTrue(listSettingsDoneButton.waitForExistence(timeout: 3))
        XCTAssertEqual(listSettingsDoneButton.label, "Done")
        XCTAssertTrue(listSettingsDoneButton.isHittable)
        XCTAssertLessThan(settingsSaveState.frame.midX, listSettingsDoneButton.frame.midX)

        let renamedHostingName = "Hosting errands \(UUID().uuidString.prefix(6))"
        let listNameField = app.textFields["list-name-field"]
        XCTAssertTrue(listNameField.waitForExistence(timeout: 3))
        replaceText(in: listNameField, with: renamedHostingName)
        XCTAssertTrue(
            waitForListName(
                listID: hostingListID,
                name: renamedHostingName,
                accessToken: session.accessToken
            )
        )
        dismissKeyboard(in: app)
        XCTAssertTrue(waitForElementLabel(settingsSaveState, containing: "Saved", timeout: 8))

        let purpleAccentButton = app.buttons["list-accent-color-purple"]
        scrollToHittable(purpleAccentButton, in: app)
        XCTAssertTrue(purpleAccentButton.waitForExistence(timeout: 5))
        tapElement(purpleAccentButton)
        XCTAssertTrue(
            waitForListAccentColor(
                listID: hostingListID,
                accentColorHex: "#af52de",
                accessToken: session.accessToken
            )
        )
        XCTAssertTrue(waitForElementLabel(settingsSaveState, containing: "Saved", timeout: 8))
        XCTAssertTrue(waitForElementLabel(purpleAccentButton, containing: "Selected", timeout: 3))

        let haushaltRow = app.descendants(matching: .any)["category-settings-row-\(haushaltCategoryID.uuidString)"]
        let backwarenRow = app.descendants(matching: .any)["category-settings-row-\(backwarenCategoryID.uuidString)"]
        let konservenRow = app.descendants(matching: .any)["category-settings-row-\(hostingKonservenCategoryID.uuidString)"]
        let backwarenHandle = app.descendants(matching: .any)["category-drag-handle-\(backwarenCategoryID.uuidString)"]
        let konservenHandle = app.descendants(matching: .any)["category-drag-handle-\(hostingKonservenCategoryID.uuidString)"]
        scrollToHittable(haushaltRow, in: app)
        scrollToHittable(backwarenRow, in: app)
        XCTAssertTrue(haushaltRow.waitForExistence(timeout: 5))
        XCTAssertTrue(backwarenRow.waitForExistence(timeout: 5))
        XCTAssertTrue(konservenRow.waitForExistence(timeout: 5))
        XCTAssertTrue(backwarenHandle.waitForExistence(timeout: 5))
        XCTAssertTrue(konservenHandle.waitForExistence(timeout: 5))
        XCTAssertTrue(
            dragCategoryRow(
                backwarenRow,
                using: backwarenHandle,
                before: haushaltRow,
                in: app
            )
        )
        XCTAssertTrue(
            dragCategoryRow(
                konservenRow,
                using: konservenHandle,
                before: backwarenRow,
                in: app
            )
        )
        XCTAssertTrue(waitForElementLabel(settingsSaveState, containing: "Saving", timeout: 3))
        XCTAssertTrue(
            waitForFirstCategoryOrder(
                listID: hostingListID,
                categoryID: hostingKonservenCategoryID,
                accessToken: session.accessToken,
                timeout: 45
            ),
            "Expected queued category-order saves to persist the latest drag result."
        )
        XCTAssertTrue(waitForElementLabel(settingsSaveState, containing: "Saved", timeout: 8))

        let konservenToggle = firstExistingElement(
            [
                app.switches["category-enabled-toggle-\(hostingKonservenCategoryID.uuidString)"],
                app.buttons["category-enabled-toggle-\(hostingKonservenCategoryID.uuidString)"],
            ],
            timeout: 3
        )
        scrollToHittable(konservenToggle, in: app)
        XCTAssertTrue(konservenToggle.waitForExistence(timeout: 5))
        tapElement(konservenToggle)
        XCTAssertTrue(
            waitForDisabledCategory(
                listID: hostingListID,
                categoryID: hostingKonservenCategoryID,
                disabled: true,
                accessToken: session.accessToken
            )
        )
        captureScreenshot(named: "ios-ui-list-settings")

        let disabledKonservenToggle = firstExistingElement(
            [
                app.switches["category-enabled-toggle-\(hostingKonservenCategoryID.uuidString)"],
                app.buttons["category-enabled-toggle-\(hostingKonservenCategoryID.uuidString)"],
            ],
            timeout: 3
        )
        scrollToHittable(disabledKonservenToggle, in: app)
        XCTAssertTrue(disabledKonservenToggle.waitForExistence(timeout: 5))
        tapElement(disabledKonservenToggle)
        XCTAssertTrue(
            waitForDisabledCategory(
                listID: hostingListID,
                categoryID: hostingKonservenCategoryID,
                disabled: false,
                accessToken: session.accessToken
            )
        )
        tapElement(listSettingsDoneButton)
        XCTAssertTrue(listTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(listTitle.label, renamedHostingName)

        let tintedListDetail = app.descendants(matching: .any)["list-detail-screen"].firstMatch
        XCTAssertTrue(tintedListDetail.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForElementLabel(tintedListDetail, containing: "Purple", timeout: 5))
        captureScreenshot(named: "ios-ui-list-accent-color")

        tapElement(listSettingsButton)
        XCTAssertTrue(app.otherElements["list-settings-sheet"].waitForExistence(timeout: 5))
        let persistedPurpleAccentButton = app.buttons["list-accent-color-purple"]
        scrollToHittable(persistedPurpleAccentButton, in: app)
        XCTAssertTrue(
            waitForElementLabel(
                persistedPurpleAccentButton,
                containing: "Selected",
                timeout: 5
            )
        )

        let noAccentButton = app.buttons["list-accent-color-none"]
        scrollToHittable(noAccentButton, in: app)
        tapElement(noAccentButton)
        XCTAssertTrue(
            waitForListAccentColor(
                listID: hostingListID,
                accentColorHex: nil,
                accessToken: session.accessToken
            )
        )
        let reopenedSaveState = app.descendants(matching: .any)[
            "list-settings-save-state"
        ].firstMatch
        XCTAssertTrue(waitForElementLabel(reopenedSaveState, containing: "Saved", timeout: 8))
        tapElement(app.buttons["list-settings-done-button"])
        XCTAssertTrue(tintedListDetail.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForElementLabel(tintedListDetail, containing: "No color", timeout: 5))

        XCTAssertTrue(openSettings(in: app, timeout: 10))
        XCTAssertTrue(app.buttons["settings-sign-out-button"].waitForExistence(timeout: 5))
        try exerciseHouseholdManagement(in: app, accessToken: session.accessToken)
        assertAppearanceMode("System", in: app)
        selectAppearanceMode("Dark", in: app)
        assertAppearanceMode("Dark", in: app)
        captureScreenshot(named: "ios-ui-settings-dark-mode")

        terminateAndWait(app)
        app.launchEnvironment.removeValue(forKey: "PLANINI_UI_TEST_RESET_APPEARANCE_MODE")
        app.launch()
        XCTAssertTrue(openSettings(in: app, timeout: 15))
        assertAppearanceMode("Dark", in: app)
        selectAppearanceMode("Light", in: app)
        assertAppearanceMode("Light", in: app)
        selectAppearanceMode("System", in: app)
        assertAppearanceMode("System", in: app)
        captureScreenshot(named: "ios-ui-settings")
        assertLanguageSettings(in: app)
    }

    func testListLayoutMatchesCompactWebDensity() throws {
        try assertLocalTestBackend()
        let session = if let injectedSession {
            injectedSession
        } else {
            try bootstrapSession(email: userEmail)
        }
        let cannedItemID = try itemID(
            named: "Tomaten",
            inListNamed: initialListName,
            accessToken: session.accessToken
        )
        let cannedGoodsID = try categoryID(
            named: "Canned Goods",
            inListNamed: initialListName,
            accessToken: session.accessToken
        )
        let dairyAndEggsID = try categoryID(
            named: "Dairy & Eggs",
            inListNamed: initialListName,
            accessToken: session.accessToken
        )
        let app = launchedApp(session: session, initialListName: initialListName)
        defer { terminateAndWait(app) }

        let listTitle = app.staticTexts["list-detail-title"]
        XCTAssertTrue(
            openInitialListDetail(in: app, listTitle: listTitle),
            "Expected bootstrapped initial list before checking compact layout."
        )
        scrollToListTop(in: app)

        let cannedGoodsHeader = app.descendants(matching: .any)[
            "category-drop-target-category-\(cannedGoodsID.uuidString)"
        ]
        let cannedItemRow = itemRow(itemID: cannedItemID, in: app)
        let dairyAndEggsHeader = app.descendants(matching: .any)[
            "category-drop-target-category-\(dairyAndEggsID.uuidString)"
        ]

        XCTAssertTrue(cannedGoodsHeader.waitForExistence(timeout: 5))
        XCTAssertTrue(cannedItemRow.waitForExistence(timeout: 5))
        scrollToHittable(dairyAndEggsHeader, in: app, maxSwipes: 2)
        XCTAssertTrue(dairyAndEggsHeader.waitForExistence(timeout: 5))

        let headerToItemGap = cannedItemRow.frame.minY - cannedGoodsHeader.frame.maxY
        let itemToNextHeaderGap = dairyAndEggsHeader.frame.minY - cannedItemRow.frame.maxY
        let sectionStride = dairyAndEggsHeader.frame.minY - cannedGoodsHeader.frame.minY
        captureScreenshot(named: "ios-ui-compact-list-layout")

        XCTAssertLessThanOrEqual(
            sectionStride,
            120,
            "A single-item category should fit within 120 points vertically."
        )
        XCTAssertLessThanOrEqual(
            cannedGoodsHeader.frame.height,
            36,
            "Category headers should stay compact."
        )
        XCTAssertLessThanOrEqual(
            cannedItemRow.frame.height,
            60,
            "Single-line item rows should stay compact."
        )
        XCTAssertGreaterThanOrEqual(headerToItemGap, 0)
        XCTAssertLessThanOrEqual(
            headerToItemGap,
            16,
            "Category header and first item should form one compact group."
        )
        XCTAssertGreaterThanOrEqual(itemToNextHeaderGap, 0)
        XCTAssertLessThanOrEqual(
            itemToNextHeaderGap,
            16,
            "Adjacent categories should use web-sized vertical separation."
        )
    }

    func testLocalDemoPersistsAndSyncsIntoAccount() throws {
        try assertLocalTestBackend()
        let session = if let injectedSession {
            injectedSession
        } else {
            try bootstrapSession(email: userEmail)
        }
        let localItemName = "Local demo \(UUID().uuidString.prefix(8))"

        let app = XCUIApplication()
        configureLaunchLanguage(for: app)
        app.launchEnvironment["PLANINI_UI_TEST_MODE"] = "1"
        app.launchEnvironment["PLANINI_BACKEND_BASE_URL_OVERRIDE"] = baseURL.absoluteString
        app.launch()

        let promoLink = app.buttons["login-promo-link"]
        XCTAssertTrue(promoLink.waitForExistence(timeout: 10))
        promoLink.tap()
        let startDemoButton = app.buttons["promo-start-local-demo-button"]
        XCTAssertTrue(startDemoButton.waitForExistence(timeout: 5))
        scrollToHittable(startDemoButton, in: app)
        startDemoButton.tap()

        let localModeBanner = app.buttons["local-mode-banner"]
        XCTAssertTrue(localModeBanner.waitForExistence(timeout: 10))
        XCTAssertTrue(localModeBanner.label.contains("Using in local mode"))
        XCTAssertTrue(app.staticTexts["list-detail-title"].waitForExistence(timeout: 5))

        XCTAssertTrue(openAddItemSheet(in: app))
        let nameField = app.textFields["add-item-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText(localItemName)
        XCTAssertTrue(tapAddItemSaveAndWaitForDismissal(in: app))

        XCTAssertTrue(tapTab("Settings", in: app))
        let householdManagementLink = app.buttons["settings-household-management-link"]
        XCTAssertTrue(householdManagementLink.waitForExistence(timeout: 5))
        householdManagementLink.tap()
        let demoHouseholdRow = app.buttons["household-row-Demo household"]
        XCTAssertTrue(demoHouseholdRow.waitForExistence(timeout: 5))
        demoHouseholdRow.tap()
        let inviteButton = app.buttons["open-household-invite-sheet-button"]
        XCTAssertTrue(inviteButton.waitForExistence(timeout: 5))
        inviteButton.tap()
        XCTAssertTrue(app.otherElements["account-registration-sheet"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["local-mode-sync-explainer"].waitForExistence(timeout: 3)
        )
        app.buttons["reviewer-onboarding-cancel-button"].tap()
        XCTAssertTrue(waitForElementToDisappear(app.otherElements["account-registration-sheet"], timeout: 5))
        terminateAndWait(app)

        let syncApp = XCUIApplication()
        configureLaunchLanguage(for: syncApp)
        syncApp.launchEnvironment["PLANINI_UI_TEST_MODE"] = "1"
        syncApp.launchEnvironment["PLANINI_BACKEND_BASE_URL_OVERRIDE"] = baseURL.absoluteString
        syncApp.launchEnvironment["PLANINI_UI_TEST_RESTORE_LOCAL_MODE"] = "1"
        syncApp.launchEnvironment["PLANINI_UI_TEST_RESTORE_STORED_SESSION"] = "1"
        syncApp.launchEnvironment["PLANINI_UI_TEST_STORED_ACCESS_TOKEN_OVERRIDE"] = session.accessToken
        syncApp.launchEnvironment["PLANINI_UI_TEST_STORED_DISPLAY_NAME_OVERRIDE"] = session.displayName
        syncApp.launch()

        let restoredBanner = syncApp.buttons["local-mode-banner"]
        XCTAssertTrue(restoredBanner.waitForExistence(timeout: 10))
        restoredBanner.tap()

        XCTAssertTrue(syncApp.otherElements["account-registration-sheet"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            syncApp.descendants(matching: .any)["local-mode-sync-explainer"].waitForExistence(timeout: 3)
        )
        let syncButton = syncApp.buttons["registration-submit-button"]
        XCTAssertTrue(syncButton.waitForExistence(timeout: 3))
        XCTAssertTrue(syncButton.isEnabled)
        syncButton.tap()

        XCTAssertTrue(waitForElementToDisappear(restoredBanner, timeout: 30))
        XCTAssertTrue(
            waitForItem(
                named: localItemName,
                inListNamed: "Weekly groceries",
                accessToken: session.accessToken,
                timeout: 30
            )
        )

        XCTAssertTrue(tapTab("Settings", in: syncApp))
        let settingsPromoLink = syncApp.buttons["settings-promo-link"]
        XCTAssertTrue(settingsPromoLink.waitForExistence(timeout: 5))
        settingsPromoLink.tap()
        XCTAssertTrue(syncApp.navigationBars["Discover Planini"].waitForExistence(timeout: 5))
        XCTAssertFalse(syncApp.buttons["promo-start-local-demo-button"].exists)
        syncApp.navigationBars.buttons.firstMatch.tap()

        let signOutButton = syncApp.buttons["settings-sign-out-button"]
        XCTAssertTrue(signOutButton.waitForExistence(timeout: 5))
        signOutButton.tap()
        XCTAssertTrue(syncApp.buttons["login-passkey-button"].waitForExistence(timeout: 10))
        terminateAndWait(syncApp)

        let syncedListID = try listID(named: "Weekly groceries", accessToken: session.accessToken)
        try deleteList(listID: syncedListID, accessToken: session.accessToken)
    }

    func testPasskeyManagementScreen() throws {
        try assertLocalTestBackend()
        let session = if let injectedSession {
            injectedSession
        } else {
            try bootstrapSession(email: userEmail)
        }
        let app = launchedApp(session: session)

        XCTAssertTrue(openSettings(in: app, timeout: 10))
        try exercisePasskeyManagement(in: app, accessToken: session.accessToken)
        terminateAndWait(app)
    }

    func testForceClosedAppRestoresSavedSession() throws {
        try assertLocalTestBackend()
        let session = if let injectedSession {
            injectedSession
        } else {
            try bootstrapSession(email: userEmail)
        }
        let app = XCUIApplication()
        configureLaunchLanguage(for: app)
        app.launchEnvironment["PLANINI_UI_TEST_MODE"] = "1"
        app.launchEnvironment["PLANINI_BACKEND_BASE_URL_OVERRIDE"] = baseURL.absoluteString
        app.launchEnvironment["PLANINI_UI_TEST_ACCESS_TOKEN"] = session.accessToken
        app.launchEnvironment["PLANINI_UI_TEST_DISPLAY_NAME"] = session.displayName
        app.launchEnvironment["PLANINI_UI_TEST_INITIAL_LIST_NAME"] = initialListName
        app.launch()

        let listTitle = app.staticTexts["list-detail-title"]
        XCTAssertTrue(
            openInitialListDetail(in: app, listTitle: listTitle),
            "Expected bootstrapped list before force-closing the app."
        )
        XCTAssertFalse(app.buttons["login-passkey-button"].exists)
        terminateAndWait(app)

        let relaunchedApp = XCUIApplication()
        configureLaunchLanguage(for: relaunchedApp)
        relaunchedApp.launchEnvironment["PLANINI_UI_TEST_MODE"] = "1"
        relaunchedApp.launchEnvironment["PLANINI_UI_TEST_RESTORE_STORED_SESSION"] = "1"
        relaunchedApp.launchEnvironment["PLANINI_BACKEND_BASE_URL_OVERRIDE"] = baseURL.absoluteString
        relaunchedApp.launch()

        let restoredListTitle = relaunchedApp.staticTexts["list-detail-title"]
        XCTAssertTrue(
            openInitialListDetail(in: relaunchedApp, listTitle: restoredListTitle),
            "Expected saved session to survive force-close and restore the initial list."
        )
        XCTAssertFalse(relaunchedApp.buttons["login-passkey-button"].exists)
        terminateAndWait(relaunchedApp)
    }

    func testEmptyOnboardingGuidesListSetupAndFavoriteChoice() throws {
        try assertLocalTestBackend()

        let emptySession = try bootstrapSession(email: "ios-empty@example.com")
        let emptyApp = launchedApp(session: emptySession)

        XCTAssertTrue(emptyApp.staticTexts["No favorite list yet"].waitForExistence(timeout: 10))
        let favoriteSettingsButton = firstExistingElement(
            [
                emptyApp.buttons["favorite-empty-open-settings-button"],
                emptyApp.buttons["Open Settings"],
            ],
            timeout: 3
        )
        XCTAssertTrue(favoriteSettingsButton.waitForExistence(timeout: 3))
        favoriteSettingsButton.tap()
        XCTAssertTrue(emptyApp.buttons["settings-household-management-link"].waitForExistence(timeout: 5))

        XCTAssertTrue(tapTab("Lists", in: emptyApp))
        XCTAssertTrue(emptyApp.staticTexts["No lists yet"].waitForExistence(timeout: 5))
        let listsSettingsButton = firstExistingElement(
            [
                emptyApp.buttons["lists-empty-open-settings-button"],
                emptyApp.buttons["Open Settings"],
            ],
            timeout: 3
        )
        XCTAssertTrue(listsSettingsButton.waitForExistence(timeout: 3))
        listsSettingsButton.tap()
        XCTAssertTrue(emptyApp.buttons["settings-household-management-link"].waitForExistence(timeout: 5))
        terminateAndWait(emptyApp)

        let ownerSession = try bootstrapSession(email: seededEmail)
        let favoriteApp = launchedApp(session: ownerSession)
        let favoriteMenu = firstExistingElement(
            [
                favoriteApp.buttons["favorite-empty-choose-list-menu"],
                favoriteApp.buttons["Choose favorite list"],
            ],
            timeout: 5
        )
        XCTAssertTrue(favoriteMenu.waitForExistence(timeout: 10))
        favoriteMenu.tap()

        let favoriteListID = try listID(named: initialListName, accessToken: ownerSession.accessToken)
        let favoriteChoice = firstExistingElement(
            [
                favoriteApp.buttons["favorite-choice-\(favoriteListID.uuidString)"],
                favoriteApp.buttons[initialListName],
                favoriteApp.menuItems[initialListName],
            ],
            timeout: 5
        )
        XCTAssertTrue(favoriteChoice.waitForExistence(timeout: 5))
        favoriteChoice.tap()

        let listTitle = favoriteApp.staticTexts["list-detail-title"]
        XCTAssertTrue(listTitle.waitForExistence(timeout: 10))
        XCTAssertEqual(listTitle.label, initialListName)
        terminateAndWait(favoriteApp)
    }

    func testInvalidStoredSessionShowsLogin() throws {
        try assertLocalTestBackend()
        let session = if let injectedSession {
            injectedSession
        } else {
            try bootstrapSession(email: userEmail)
        }

        let expiredApp = XCUIApplication()
        configureLaunchLanguage(for: expiredApp)
        expiredApp.launchEnvironment["PLANINI_UI_TEST_MODE"] = "1"
        expiredApp.launchEnvironment["PLANINI_UI_TEST_RESTORE_STORED_SESSION"] = "1"
        expiredApp.launchEnvironment["PLANINI_UI_TEST_STORED_ACCESS_TOKEN_OVERRIDE"] = "expired-ui-test-token"
        expiredApp.launchEnvironment["PLANINI_UI_TEST_STORED_DISPLAY_NAME_OVERRIDE"] = session.displayName
        expiredApp.launchEnvironment["PLANINI_BACKEND_BASE_URL_OVERRIDE"] = baseURL.absoluteString
        expiredApp.launch()

        XCTAssertTrue(expiredApp.buttons["login-passkey-button"].waitForExistence(timeout: 15))
        XCTAssertFalse(tabCandidates(for: "Lists", in: expiredApp).contains { $0.exists })
        XCTAssertTrue(expiredApp.descendants(matching: .any)["login-last-account"].waitForExistence(timeout: 3))
        let alert = expiredApp.alerts["Error"]
        if alert.waitForExistence(timeout: 3) {
            XCTAssertTrue(alert.staticTexts["Session expired. Sign in again with your passkey."].exists)
            alert.buttons["OK"].tap()
        }
        XCTAssertTrue(expiredApp.buttons["login-passkey-button"].waitForExistence(timeout: 3))
        terminateAndWait(expiredApp)
    }

    func testListReceivesLiveUpdates() throws {
        try assertLocalTestBackend()
        let session = if let injectedSession {
            injectedSession
        } else {
            try bootstrapSession(email: userEmail)
        }
        let app = XCUIApplication()
        configureLaunchLanguage(for: app)
        app.launchEnvironment["PLANINI_UI_TEST_MODE"] = "1"
        app.launchEnvironment["PLANINI_BACKEND_BASE_URL_OVERRIDE"] = baseURL.absoluteString
        app.launchEnvironment["PLANINI_UI_TEST_ACCESS_TOKEN"] = session.accessToken
        app.launchEnvironment["PLANINI_UI_TEST_DISPLAY_NAME"] = session.displayName
        app.launchEnvironment["PLANINI_UI_TEST_INITIAL_LIST_NAME"] = initialListName
        app.launch()

        let listTitle = app.staticTexts["list-detail-title"]
        XCTAssertTrue(
            openInitialListDetail(in: app, listTitle: listTitle),
            "Expected bootstrapped initial list to open before live-update checks."
        )
        XCTAssertEqual(listTitle.label, initialListName)
        XCTAssertTrue(
            waitForLiveUpdatesConnection(
                app: app,
                listName: initialListName,
                accessToken: session.accessToken
            ),
            "Expected live updates to connect before checking external mutations."
        )

        let uniqueSuffix = UUID().uuidString.prefix(8)
        let itemName = "A UI Live \(uniqueSuffix)"
        let updatedName = "\(itemName) Updated"
        let itemID = try createItem(
            named: itemName,
            note: "",
            inListNamed: initialListName,
            accessToken: session.accessToken
        )

        XCTAssertTrue(
            waitForItemRow(itemID: itemID, named: itemName, in: app, timeout: 20),
            "Expected live-created item to appear without manual refresh."
        )
        captureScreenshot(named: "ios-ui-live-item-created")

        try updateItem(
            itemID: itemID,
            name: updatedName,
            note: "",
            accessToken: session.accessToken
        )
        XCTAssertTrue(
            waitForItemRow(itemID: itemID, named: updatedName, in: app, timeout: 20),
            "Expected live-updated item to rename without manual refresh."
        )

        try deleteItem(itemID: itemID, accessToken: session.accessToken)
        XCTAssertTrue(
            waitForElementToDisappear(itemRow(itemID: itemID, in: app), timeout: 20),
            "Expected live-deleted item to disappear without manual refresh."
        )
    }

    func testOnSaleItemStaysInSyncAcrossPromotedAndNormalRows() throws {
        try assertLocalTestBackend()
        let session = if let injectedSession {
            injectedSession
        } else {
            try bootstrapSession(email: userEmail)
        }
        let uniqueSuffix = UUID().uuidString.prefix(8)
        let itemName = "A UI Sale \(uniqueSuffix)"
        let itemID = try createItem(
            named: itemName,
            note: "On-sale UI e2e",
            inListNamed: initialListName,
            accessToken: session.accessToken
        )

        let app = launchedApp(session: session, initialListName: initialListName)
        defer {
            terminateAndWait(app)
            try? deleteItem(itemID: itemID, accessToken: session.accessToken)
        }

        let listTitle = app.staticTexts["list-detail-title"]
        XCTAssertTrue(
            openInitialListDetail(in: app, listTitle: listTitle),
            "Expected bootstrapped initial list before on-sale checks."
        )
        XCTAssertEqual(listTitle.label, initialListName)
        XCTAssertTrue(
            waitForItemRow(itemID: itemID, named: itemName, in: app, timeout: 20),
            "Expected created item row before enabling sale window."
        )

        try setItemSaleWindow(
            itemID: itemID,
            startsAt: Date().addingTimeInterval(-60 * 60),
            endsAt: Date().addingTimeInterval(60 * 60),
            accessToken: session.accessToken
        )
        XCTAssertTrue(
            waitForItemSaleWindow(
                named: itemName,
                active: true,
                inListNamed: initialListName,
                accessToken: session.accessToken,
                timeout: 20
            ),
            "Expected backend sale window after scheduling sale."
        )

        let onSaleBadge = app.staticTexts["section-count-badge-on-sale"]
        XCTAssertTrue(
            onSaleBadge.waitForExistence(timeout: 15),
            "Expected On sale section after scheduling sale window."
        )
        let promotedRow = app.descendants(matching: .any)[
            "item-row-on-sale-\(itemID.uuidString)"
        ]
        let normalRow = app.descendants(matching: .any)["item-row-\(itemID.uuidString)"]
        scrollToListTop(in: app, maxSwipes: 12)
        XCTAssertTrue(
            promotedRow.waitForExistence(timeout: 10),
            "Expected promoted On sale item row."
        )
        XCTAssertTrue(
            normalRow.waitForExistence(timeout: 10),
            "Expected normal category item row to remain visible."
        )

        let promotedToggle = app.buttons["toggle-item-on-sale-\(itemID.uuidString)"]
        XCTAssertTrue(
            waitForElementLabel(promotedToggle, containing: "Check \(itemName)"),
            "Expected promoted toggle to start unchecked."
        )
        captureScreenshot(named: "ios-ui-on-sale-item")
        tapElement(promotedToggle)
        XCTAssertTrue(
            waitForItemCheckedState(
                named: itemName,
                checked: true,
                inListNamed: initialListName,
                accessToken: session.accessToken
            )
        )
        XCTAssertTrue(
            waitForElementLabel(promotedToggle, containing: "Uncheck \(itemName)"),
            "Expected promoted toggle to reflect checked state."
        )

        let normalToggle = app.buttons["toggle-item-\(itemID.uuidString)"]
        scrollToHittable(normalToggle, in: app, maxSwipes: 20)
        XCTAssertTrue(
            normalToggle.waitForExistence(timeout: 10),
            "Expected normal toggle in the checked-items area after the promoted row update."
        )
        XCTAssertTrue(
            waitForElementLabel(normalToggle, containing: "Uncheck \(itemName)"),
            "Expected normal toggle to mirror promoted checked state."
        )
        XCTAssertTrue(
            normalToggle.isHittable,
            "Expected normal toggle to be on-screen before tapping it."
        )

        XCTAssertTrue(
            tapItemToggleButton(
                itemID: itemID,
                named: itemName,
                checked: false,
                in: app,
                inListNamed: initialListName,
                accessToken: session.accessToken
            ),
            "Expected tapping the on-screen normal toggle to uncheck the item."
        )
        scrollToListTop(in: app, maxSwipes: 16)
        XCTAssertTrue(
            waitForElementLabel(promotedToggle, containing: "Check \(itemName)"),
            "Expected promoted toggle to mirror unchecked state."
        )
        XCTAssertTrue(
            waitForElementLabel(normalToggle, containing: "Check \(itemName)"),
            "Expected normal toggle to mirror unchecked state."
        )
    }

    func testLongPressDragMovesItemToCategory() throws {
        try assertLocalTestBackend()
        let session = if let injectedSession {
            injectedSession
        } else {
            try bootstrapSession(email: userEmail)
        }
        let targetCategoryID = try categoryID(
            named: "Canned Goods",
            inListNamed: initialListName,
            accessToken: session.accessToken
        )
        let sourceCategoryID = try categoryID(
            named: "Dairy & Eggs",
            inListNamed: initialListName,
            accessToken: session.accessToken
        )
        try updateCategoryOrder(
            listID: listID(named: initialListName, accessToken: session.accessToken),
            categoryIDs: [sourceCategoryID, targetCategoryID],
            accessToken: session.accessToken
        )

        let app = XCUIApplication()
        configureLaunchLanguage(for: app)
        app.launchEnvironment["PLANINI_UI_TEST_MODE"] = "1"
        app.launchEnvironment["PLANINI_BACKEND_BASE_URL_OVERRIDE"] = baseURL.absoluteString
        app.launchEnvironment["PLANINI_UI_TEST_ACCESS_TOKEN"] = session.accessToken
        app.launchEnvironment["PLANINI_UI_TEST_DISPLAY_NAME"] = session.displayName
        app.launchEnvironment["PLANINI_UI_TEST_INITIAL_LIST_NAME"] = initialListName
        app.launch()

        let listTitle = app.staticTexts["list-detail-title"]
        XCTAssertTrue(
            openInitialListDetail(in: app, listTitle: listTitle),
            "Expected bootstrapped initial list to open before item drag checks."
        )
        XCTAssertEqual(listTitle.label, initialListName)
        XCTAssertTrue(
            waitForLiveUpdatesConnection(
                app: app,
                listName: initialListName,
                accessToken: session.accessToken
            ),
            "Expected live updates before creating drag item."
        )

        let targetItemName = "A UI Drag Target \(UUID().uuidString.prefix(8))"
        let targetItemID = try createItem(
            named: targetItemName,
            note: "",
            inListNamed: initialListName,
            categoryID: targetCategoryID,
            accessToken: session.accessToken
        )
        XCTAssertTrue(waitForItemRow(itemID: targetItemID, named: targetItemName, in: app, timeout: 20))

        let itemName = "A UI Drag \(UUID().uuidString.prefix(8))"
        let itemID = try createItem(
            named: itemName,
            note: "",
            inListNamed: initialListName,
            categoryID: sourceCategoryID,
            sortOrder: -1_000_000,
            accessToken: session.accessToken
        )
        XCTAssertTrue(waitForItemRow(itemID: itemID, named: itemName, in: app, timeout: 20))

        let targetHeader = app.descendants(matching: .any)[
            "category-drop-target-category-\(targetCategoryID.uuidString)"
        ].firstMatch
        XCTAssertTrue(
            dragItemRow(
                itemID: itemID,
                named: itemName,
                toCategoryTarget: targetHeader,
                in: app,
                categoryName: "Canned Goods",
                listName: initialListName,
                accessToken: session.accessToken
            ),
            "Expected long-press drag to move item to target category."
        )
        captureScreenshot(named: "ios-ui-drag-item-to-category")

        let undoButton = app.buttons["list-undo-button"]
        let undoMessage = app.staticTexts["list-undo-message"]
        XCTAssertTrue(undoButton.waitForExistence(timeout: 5))
        XCTAssertTrue(undoMessage.label.contains(itemName))
        XCTAssertTrue(undoMessage.label.contains("Canned Goods"))
        tapElement(undoButton)
        XCTAssertTrue(
            waitForItemCategory(
                named: itemName,
                categoryNamed: "Dairy & Eggs",
                inListNamed: initialListName,
                accessToken: session.accessToken,
                timeout: 20
            )
        )
    }

    func testCachedListDoesNotShowErrorAlertWhenBackendIsOffline() throws {
        try assertLocalTestBackend()
        let session = if let injectedSession {
            injectedSession
        } else {
            try bootstrapSession(email: userEmail)
        }
        let offlineCreatedName = "Offline UI \(UUID().uuidString.prefix(8))"

        let app = XCUIApplication()
        configureLaunchLanguage(for: app)
        app.launchEnvironment["PLANINI_UI_TEST_MODE"] = "1"
        app.launchEnvironment["PLANINI_BACKEND_BASE_URL_OVERRIDE"] = baseURL.absoluteString
        app.launchEnvironment["PLANINI_UI_TEST_ACCESS_TOKEN"] = session.accessToken
        app.launchEnvironment["PLANINI_UI_TEST_DISPLAY_NAME"] = session.displayName
        app.launchEnvironment["PLANINI_UI_TEST_INITIAL_LIST_NAME"] = initialListName
        app.launch()

        let listTitle = app.staticTexts["list-detail-title"]
        XCTAssertTrue(
            openInitialListDetail(in: app, listTitle: listTitle, timeout: 90),
            "Expected online launch to cache the initial list before offline relaunch."
        )
        XCTAssertTrue(
            firstVisibleUncheckedToggle(in: app, timeout: 20) != nil,
            "Expected online launch to cache at least one unchecked seeded item before offline relaunch."
        )
        terminateAndWait(app)

        let offlineApp = XCUIApplication()
        configureLaunchLanguage(for: offlineApp)
        offlineApp.launchEnvironment["PLANINI_UI_TEST_MODE"] = "1"
        offlineApp.launchEnvironment["PLANINI_BACKEND_BASE_URL_OVERRIDE"] = unavailableBaseURL.absoluteString
        offlineApp.launchEnvironment["PLANINI_UI_TEST_ACCESS_TOKEN"] = session.accessToken
        offlineApp.launchEnvironment["PLANINI_UI_TEST_DISPLAY_NAME"] = session.displayName
        offlineApp.launchEnvironment["PLANINI_UI_TEST_INITIAL_LIST_NAME"] = initialListName
        offlineApp.launch()

        let offlineListTitle = offlineApp.staticTexts["list-detail-title"]
        XCTAssertTrue(
            openInitialListDetail(in: offlineApp, listTitle: offlineListTitle, timeout: 15),
            "Expected cached list to open while the backend is offline."
        )
        XCTAssertTrue(
            waitForOfflineStatus(in: offlineApp),
            "Expected visible offline status banner instead of a blocking alert."
        )
        XCTAssertFalse(
            offlineApp.alerts["Error"].waitForExistence(timeout: 2),
            "Expected offline cache fallback to avoid the generic error popup."
        )
        guard let (offlineToggle, offlineItemName) = firstVisibleUncheckedToggle(in: offlineApp, timeout: 8) else {
            XCTFail("Expected an unchecked cached item to be visible while offline.")
            return
        }
        tapElement(offlineToggle)
        XCTAssertTrue(
            waitForElementToDisappear(offlineToggle, timeout: 2)
                || waitForToggleLabel(offlineToggle, containsAny: ["Uncheck", "wieder öffnen"]),
            "Expected offline item toggle to update locally."
        )
        XCTAssertFalse(
            offlineApp.alerts["Error"].waitForExistence(timeout: 2),
            "Expected offline item toggle to avoid the generic error popup."
        )
        XCTAssertTrue(
            openAddItemSheet(in: offlineApp),
            "Expected add-item sheet to remain available while offline."
        )
        let offlineNameField = offlineApp.textFields["add-item-name-field"]
        XCTAssertTrue(offlineNameField.waitForExistence(timeout: 3))
        offlineNameField.tap()
        XCTAssertTrue(prepareKeyboardForTyping(in: offlineApp, timeout: 3))
        offlineNameField.typeText(offlineCreatedName)
        XCTAssertTrue(tapAddItemSaveAndWaitForDismissal(in: offlineApp))
        let offlineCreatedRow = offlineApp.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                "edit-item-row-",
                offlineCreatedName
            )
        ).firstMatch
        scrollToElement(offlineCreatedRow, in: offlineApp)
        XCTAssertTrue(
            offlineCreatedRow.waitForExistence(timeout: 5),
            "Expected offline-created item to appear immediately."
        )
        XCTAssertFalse(
            offlineApp.alerts["Error"].waitForExistence(timeout: 2),
            "Expected offline item creation to avoid the generic error popup."
        )
        captureScreenshot(named: "ios-ui-offline-cache-banner")
        terminateAndWait(offlineApp)

        let syncApp = XCUIApplication()
        configureLaunchLanguage(for: syncApp)
        syncApp.launchEnvironment["PLANINI_UI_TEST_MODE"] = "1"
        syncApp.launchEnvironment["PLANINI_BACKEND_BASE_URL_OVERRIDE"] = baseURL.absoluteString
        syncApp.launchEnvironment["PLANINI_UI_TEST_ACCESS_TOKEN"] = session.accessToken
        syncApp.launchEnvironment["PLANINI_UI_TEST_DISPLAY_NAME"] = session.displayName
        syncApp.launchEnvironment["PLANINI_UI_TEST_INITIAL_LIST_NAME"] = initialListName
        syncApp.launch()

        let syncedListTitle = syncApp.staticTexts["list-detail-title"]
        XCTAssertTrue(
            openInitialListDetail(in: syncApp, listTitle: syncedListTitle, timeout: 20),
            "Expected online relaunch to open the cached list and flush offline toggles."
        )
        XCTAssertTrue(
            waitForItemCheckedState(
                named: offlineItemName,
                checked: true,
                inListNamed: initialListName,
                accessToken: session.accessToken,
                timeout: 20
            ),
            "Expected offline item toggle to sync after connection returns."
        )
        XCTAssertTrue(
            waitForItem(
                named: offlineCreatedName,
                inListNamed: initialListName,
                accessToken: session.accessToken,
                timeout: 20
            ),
            "Expected offline-created item to sync after connection returns."
        )
        let offlineItemID = try itemID(
            named: offlineItemName,
            inListNamed: initialListName,
            accessToken: session.accessToken
        )
        try syncItemCheckedState(
            itemID: offlineItemID,
            checked: false,
            inListNamed: initialListName,
            accessToken: session.accessToken
        )
        let offlineCreatedItemID = try itemID(
            named: offlineCreatedName,
            inListNamed: initialListName,
            accessToken: session.accessToken
        )
        try deleteItem(itemID: offlineCreatedItemID, accessToken: session.accessToken)
        syncApp.terminate()
    }

    func testStaleOfflineBannerClearsAfterOnlineAdd() throws {
        try assertLocalTestBackend()
        let session = if let injectedSession {
            injectedSession
        } else {
            try bootstrapSession(email: userEmail)
        }
        let pendingCreatedName = "Pending Banner UI \(UUID().uuidString.prefix(8))"
        let onlineCreatedName = "Online Banner UI \(UUID().uuidString.prefix(8))"

        let app = XCUIApplication()
        configureLaunchLanguage(for: app)
        app.launchEnvironment["PLANINI_UI_TEST_MODE"] = "1"
        app.launchEnvironment["PLANINI_BACKEND_BASE_URL_OVERRIDE"] = baseURL.absoluteString
        app.launchEnvironment["PLANINI_UI_TEST_ACCESS_TOKEN"] = session.accessToken
        app.launchEnvironment["PLANINI_UI_TEST_DISPLAY_NAME"] = session.displayName
        app.launchEnvironment["PLANINI_UI_TEST_INITIAL_LIST_NAME"] = initialListName
        app.launchEnvironment["PLANINI_UI_TEST_PENDING_ITEM_CREATE_NAME"] = pendingCreatedName
        app.launchEnvironment["PLANINI_UI_TEST_OFFLINE_STATUS_MESSAGE"] =
            "Changes saved offline. They will sync when the backend is reachable."
        app.launch()

        let listTitle = app.staticTexts["list-detail-title"]
        XCTAssertTrue(
            openInitialListDetail(in: app, listTitle: listTitle, timeout: 20),
            "Expected online launch to open the initial list."
        )
        XCTAssertTrue(
            waitForOfflineStatus(in: app, timeout: 5),
            "Expected pending-mutation banner fixture to be visible before adding online."
        )
        XCTAssertTrue(openAddItemSheet(in: app))
        let nameField = app.textFields["add-item-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        XCTAssertTrue(prepareKeyboardForTyping(in: app, timeout: 3))
        nameField.typeText(onlineCreatedName)
        XCTAssertTrue(tapAddItemSaveAndWaitForDismissal(in: app))
        XCTAssertTrue(
            waitForItem(
                named: onlineCreatedName,
                inListNamed: initialListName,
                accessToken: session.accessToken,
                timeout: 20
            ),
            "Expected item added under a stale offline banner to save to the backend."
        )
        XCTAssertTrue(
            waitForItem(
                named: pendingCreatedName,
                inListNamed: initialListName,
                accessToken: session.accessToken,
                timeout: 20
            ),
            "Expected an older pending create to sync without delaying the new online add."
        )
        XCTAssertTrue(
            waitForOfflineStatusToDisappear(in: app, timeout: 8),
            "Expected successful authenticated requests to clear the pending-mutation banner."
        )

        for createdName in [onlineCreatedName, pendingCreatedName] {
            let createdItemID = try itemID(
                named: createdName,
                inListNamed: initialListName,
                accessToken: session.accessToken
            )
            try deleteItem(itemID: createdItemID, accessToken: session.accessToken)
        }
        terminateAndWait(app)
    }

    func testUsesNativeIPadCanvasWhenRunningOnIPad() throws {
        #if canImport(UIKit)
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)

        let app = XCUIApplication()
        configureLaunchLanguage(for: app)
        app.launchEnvironment["PLANINI_UI_TEST_MODE"] = "1"
        app.launchEnvironment["PLANINI_BACKEND_BASE_URL_OVERRIDE"] = baseURL.absoluteString
        app.launch()

        XCTAssertTrue(app.buttons["login-passkey-button"].waitForExistence(timeout: 10))
        let screenSize = XCUIScreen.main.screenshot().image.size
        XCTAssertGreaterThanOrEqual(app.frame.width, screenSize.width * 0.9)
        XCTAssertGreaterThanOrEqual(app.frame.height, screenSize.height * 0.9)
        #else
        throw XCTSkip("UIKit unavailable")
        #endif
    }

    func testPlaniniLinksOpenListsAndAcceptInvites() throws {
        try assertLocalTestBackend()
        let ownerSession = try bootstrapSession(email: seededEmail)
        let inviteeSession = try bootstrapSession(email: "preview-invitee@example.com")
        let linkedListID = try listID(named: initialListName, accessToken: ownerSession.accessToken)
        let inviteToken = try createInvite(
            householdName: "Review Household",
            accessToken: ownerSession.accessToken
        )

        let ownerApp = launchedApp(
            session: ownerSession,
            initialListName: nil,
            openedLink: baseURL.appending(path: "/lists/\(linkedListID.uuidString)")
        )
        XCTAssertTrue(ownerApp.staticTexts["list-detail-title"].waitForExistence(timeout: 10))
        XCTAssertEqual(ownerApp.staticTexts["list-detail-title"].label, initialListName)
        terminateAndWait(ownerApp)

        let inviteeApp = launchedApp(
            session: inviteeSession,
            initialListName: nil,
            openedLink: baseURL.appending(path: "/invite/\(inviteToken)")
        )
        XCTAssertTrue(
            waitForList(named: initialListName, accessToken: inviteeSession.accessToken, timeout: 12),
            "Expected invitee API access after opening invite link."
        )
        XCTAssertTrue(inviteeApp.staticTexts["list-detail-title"].waitForExistence(timeout: 10))
        XCTAssertEqual(inviteeApp.staticTexts["list-detail-title"].label, initialListName)
    }

    func testPublicListLinkWorksSignedOutAndRemainsRemovable() throws {
        try assertLocalTestBackend()
        let ownerSession = try bootstrapSession(email: seededEmail)
        let listID = try listID(named: initialListName, accessToken: ownerSession.accessToken)
        let itemName = "Public iOS \(UUID().uuidString.prefix(8))"

        let ownerApp = launchedApp(session: ownerSession, initialListName: initialListName)
        XCTAssertTrue(ownerApp.staticTexts["list-detail-title"].waitForExistence(timeout: 12))
        let listSettingsButton = ownerApp.buttons["list-settings-button"]
        XCTAssertTrue(listSettingsButton.waitForExistence(timeout: 5))
        listSettingsButton.tap()
        XCTAssertTrue(ownerApp.otherElements["list-settings-sheet"].waitForExistence(timeout: 5))

        let createLinkButton = ownerApp.buttons["create-public-list-link-button"]
        scrollToHittable(createLinkButton, in: ownerApp)
        XCTAssertTrue(createLinkButton.isHittable)
        createLinkButton.tap()

        let publicLinkValue = ownerApp.staticTexts["public-list-link-url-value"]
        scrollToHittable(publicLinkValue, in: ownerApp)
        XCTAssertTrue(publicLinkValue.waitForExistence(timeout: 12))
        guard let publicURL = URL(string: publicLinkValue.label) else {
            XCTFail("Expected the iOS list settings to display a valid public link URL.")
            return
        }
        XCTAssertTrue(ownerApp.buttons["copy-public-list-link-button"].exists)
        XCTAssertTrue(ownerApp.buttons["share-public-list-link-button"].exists)
        terminateAndWait(ownerApp)

        let signedInApp = launchedApp(
            session: ownerSession,
            initialListName: nil,
            openedLink: publicURL
        )
        XCTAssertTrue(signedInApp.staticTexts["list-detail-title"].waitForExistence(timeout: 12))
        XCTAssertEqual(signedInApp.staticTexts["list-detail-title"].label, initialListName)
        XCTAssertTrue(openAddItemSheet(using: signedInApp.buttons["add-item-button"], in: signedInApp))
        signedInApp.textFields["add-item-name-field"].tap()
        signedInApp.textFields["add-item-name-field"].typeText(itemName)
        XCTAssertTrue(saveAddItemSheet(in: signedInApp))
        XCTAssertTrue(
            waitForItem(named: itemName, inListNamed: initialListName, accessToken: ownerSession.accessToken)
        )
        let itemID = try itemID(
            named: itemName,
            inListNamed: initialListName,
            accessToken: ownerSession.accessToken
        )
        terminateAndWait(signedInApp)

        let signedOutApp = XCUIApplication()
        configureLaunchLanguage(for: signedOutApp)
        signedOutApp.launchEnvironment["PLANINI_UI_TEST_MODE"] = "1"
        signedOutApp.launchEnvironment["PLANINI_BACKEND_BASE_URL_OVERRIDE"] = baseURL.absoluteString
        signedOutApp.launchEnvironment["PLANINI_UI_TEST_OPEN_URL"] = publicURL.absoluteString
        signedOutApp.launch()
        XCTAssertTrue(signedOutApp.staticTexts["list-detail-title"].waitForExistence(timeout: 12))
        XCTAssertEqual(signedOutApp.staticTexts["list-detail-title"].label, initialListName)
        XCTAssertTrue(
            signedOutApp.buttons["add-item-button"].waitForExistence(timeout: 5),
            "Expected a public editor link to keep list editing enabled."
        )
        XCTAssertTrue(
            tapItemToggleButton(
                itemID: itemID,
                named: itemName,
                checked: true,
                in: signedOutApp,
                inListNamed: initialListName,
                accessToken: ownerSession.accessToken
            )
        )

        signedOutApp.buttons["public-list-close-button"].tap()
        XCTAssertTrue(signedOutApp.buttons["login-passkey-button"].waitForExistence(timeout: 5))
        let rememberedRow = signedOutApp.buttons["public-list-row-\(listID.uuidString)"]
        XCTAssertTrue(rememberedRow.waitForExistence(timeout: 5))
        rememberedRow.swipeLeft()
        let removeButton = signedOutApp.buttons["remove-public-list-\(listID.uuidString)"]
        XCTAssertTrue(removeButton.waitForExistence(timeout: 3))
        removeButton.tap()
        XCTAssertTrue(waitForElementToDisappear(rememberedRow, timeout: 5))

        try deleteItem(itemID: itemID, accessToken: ownerSession.accessToken)
    }

    func testSiriIntentAddsItemsToFavoriteAndSpecificLists() throws {
        try assertLocalTestBackend()
        let session = if let injectedSession {
            injectedSession
        } else {
            try bootstrapSession(email: userEmail)
        }
        let favoriteItemName = "Siri Favorite \(UUID().uuidString.prefix(8))"
        let favoriteApp = launchedApp(
            session: session,
            initialListName: initialListName,
            extraLaunchEnvironment: [
                "PLANINI_UI_TEST_SIRI_ADD_ITEM_NAME": favoriteItemName,
            ]
        )
        XCTAssertTrue(
            waitForItem(
                named: favoriteItemName,
                inListNamed: initialListName,
                accessToken: session.accessToken,
                timeout: 20
            ),
            "Expected Siri add item intent to use the favorite list when no list is named."
        )
        terminateAndWait(favoriteApp)

        let specificListName = "Hosting errands"
        _ = try normalizeListName(
            prefixedBy: specificListName,
            to: specificListName,
            accessToken: session.accessToken
        )
        let specificItemName = "Siri Hosting \(UUID().uuidString.prefix(8))"
        let specificApp = launchedApp(
            session: session,
            initialListName: initialListName,
            extraLaunchEnvironment: [
                "PLANINI_UI_TEST_LANGUAGE": "de",
                "PLANINI_UI_TEST_SIRI_ADD_ITEM_NAME": specificItemName,
                "PLANINI_UI_TEST_SIRI_ADD_ITEM_LIST_NAME": specificListName,
            ]
        )
        XCTAssertTrue(
            waitForItem(
                named: specificItemName,
                inListNamed: specificListName,
                accessToken: session.accessToken,
                timeout: 20
            ),
            "Expected Siri add item intent to add to the named list."
        )
        XCTAssertTrue(
            waitForItemAbsent(
                named: specificItemName,
                inListNamed: initialListName,
                accessToken: session.accessToken,
                timeout: 4
            ),
            "Expected named-list Siri add not to fall back to the favorite list."
        )
        terminateAndWait(specificApp)
    }

    private var baseURL: URL {
        if
            let value = environmentValue("PLANINI_UI_TEST_BASE_URL"),
            let url = URL(string: value)
        {
            return url
        }
        return URL(string: "http://localhost:8018")!
    }

    private var unavailableBaseURL: URL {
        URL(string: "http://localhost:9")!
    }

    private var bootstrapBaseURL: URL {
        if
            let value = environmentValue("PLANINI_UI_TEST_BOOTSTRAP_BASE_URL"),
            let url = URL(string: value)
        {
            return url
        }
        return URL(string: "http://localhost:8018")!
    }

    private var userEmail: String {
        guard let configuredEmail = environmentValue("PLANINI_UI_TEST_USER_EMAIL")
        else {
            return seededEmail
        }
        return configuredEmail
    }

    private var configuredInitialListName: String {
        environmentValue("PLANINI_UI_TEST_INITIAL_LIST_NAME") ?? initialListName
    }

    private var injectedSession: UITestSession? {
        guard
            let accessToken = environmentValue("PLANINI_UI_TEST_ACCESS_TOKEN"),
            let displayName = environmentValue("PLANINI_UI_TEST_DISPLAY_NAME")
        else {
            return nil
        }
        return UITestSession(accessToken: accessToken, displayName: displayName)
    }

    private var injectedGermanMarketingSession: UITestSession? {
        guard
            let accessToken = environmentValue(
                "PLANINI_UI_TEST_MARKETING_GERMAN_ACCESS_TOKEN"
            ),
            let displayName = environmentValue(
                "PLANINI_UI_TEST_MARKETING_GERMAN_DISPLAY_NAME"
            )
        else {
            return nil
        }
        return UITestSession(accessToken: accessToken, displayName: displayName)
    }

    private func environmentValue(_ key: String) -> String? {
        guard
            let value = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            value.isEmpty == false,
            value.hasPrefix("$(") == false
        else {
            return nil
        }
        return value
    }

    private func assertLocalTestBackend() throws {
        try assertLoopbackURL(baseURL, label: "app backend")
        try assertLoopbackURL(bootstrapBaseURL, label: "bootstrap backend")
    }

    private func assertLoopbackURL(_ url: URL, label: String) throws {
        guard let host = url.host?.lowercased(),
            ["localhost", "127.0.0.1", "::1"].contains(host)
        else {
            throw NSError(
                domain: "PlaniniUITests",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Refusing to run iOS UI tests against a non-local \(label) URL: \(url.absoluteString)"
                ]
            )
        }
    }

    private func bootstrapSession(email: String) throws -> UITestSession {
        let request = jsonRequest(
            path: "/api/v1/auth/ui-test-bootstrap",
            method: "POST",
            token: nil,
            body: ["email": email],
            baseURL: bootstrapBaseURL
        )
        let capturedData = try performRequest(request)
        return try JSONDecoder().decode(UITestSession.self, from: capturedData)
    }

    private func launchedApp(
        session: UITestSession,
        initialListName: String? = nil,
        openedLink: URL? = nil,
        language: String? = nil,
        extraLaunchEnvironment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        configureLaunchLanguage(for: app, language: language)
        app.launchEnvironment["PLANINI_UI_TEST_MODE"] = "1"
        app.launchEnvironment["PLANINI_BACKEND_BASE_URL_OVERRIDE"] = baseURL.absoluteString
        app.launchEnvironment["PLANINI_UI_TEST_ACCESS_TOKEN"] = session.accessToken
        app.launchEnvironment["PLANINI_UI_TEST_DISPLAY_NAME"] = session.displayName
        if let initialListName {
            app.launchEnvironment["PLANINI_UI_TEST_INITIAL_LIST_NAME"] = initialListName
        }
        if let openedLink {
            app.launchEnvironment["PLANINI_UI_TEST_OPEN_URL"] = openedLink.absoluteString
        }
        for (key, value) in extraLaunchEnvironment {
            app.launchEnvironment[key] = value
        }
        app.launch()
        XCTAssertTrue(firstExistingElement(tabCandidates(for: "Lists", in: app), timeout: 10).exists)
        return app
    }

    private func configureLaunchLanguage(
        for app: XCUIApplication,
        language: String? = nil
    ) {
        let language = language ?? "en"
        let locale = language == "de" ? "de_DE" : "en_US"
        app.launchEnvironment["PLANINI_UI_TEST_LANGUAGE"] = language
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
    }

    private func tapItemToggleButton(
        itemID: UUID,
        named itemName: String,
        checked: Bool,
        in app: XCUIApplication,
        inListNamed listName: String,
        accessToken: String,
        timeout: TimeInterval = 20
    ) -> Bool {
        let button = app.buttons["toggle-item-\(itemID.uuidString)"]
        let editSheet = app.otherElements["edit-item-sheet"]
        let deadline = Date().addingTimeInterval(timeout)

        if waitForItemCheckedState(
            named: itemName,
            checked: checked,
            inListNamed: listName,
            accessToken: accessToken,
            timeout: 0.5
        ) {
            return true
        }

        if editSheet.exists {
            app.buttons["Done"].tap()
            _ = waitForElementToDisappear(editSheet, timeout: 3)
        }

        if button.exists == false {
            _ = waitForItemRow(itemID: itemID, named: itemName, in: app, timeout: 2)
        }
        guard button.exists else { return false }

        scrollToHittable(button, in: app, maxSwipes: 2)
        if button.isHittable {
            button.tap()
        } else {
            tapElement(button)
        }

        return waitForItemCheckedState(
            named: itemName,
            checked: checked,
            inListNamed: listName,
            accessToken: accessToken,
            timeout: max(0.5, deadline.timeIntervalSinceNow)
        )
    }

    private func hideItemUsingSwipe(
        itemID: UUID,
        named itemName: String,
        in app: XCUIApplication,
        inListNamed listName: String,
        accessToken: String,
        timeout: TimeInterval = 20
    ) -> Bool {
        let row = itemRow(itemID: itemID, in: app)
        let hideButton = app.buttons["hide-item-\(itemID.uuidString)"]

        scrollToListTop(in: app, maxSwipes: 10)
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if waitForItemHiddenState(
                named: itemName,
                hidden: true,
                inListNamed: listName,
                accessToken: accessToken,
                timeout: 0.5
            ) {
                return true
            }

            if hideButton.exists {
                tapElement(hideButton)
            } else {
                _ = waitForItemRow(itemID: itemID, named: itemName, in: app, timeout: 2)
                scrollToHittable(row, in: app, maxSwipes: 10)
                if row.exists && row.isHittable {
                    let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
                    let end = row.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
                    start.press(forDuration: 0.1, thenDragTo: end)
                    if hideButton.waitForExistence(timeout: 2) {
                        tapElement(hideButton)
                    }
                }
            }

            if waitForItemHiddenState(
                named: itemName,
                hidden: true,
                inListNamed: listName,
                accessToken: accessToken,
                timeout: 3
            ) {
                return true
            }
        }

        return waitForItemHiddenState(
            named: itemName,
            hidden: true,
            inListNamed: listName,
            accessToken: accessToken,
            timeout: 0.5
        )
    }

    private func unhideItemUsingSwipe(
        itemID: UUID,
        named itemName: String,
        in app: XCUIApplication,
        inListNamed listName: String,
        accessToken: String,
        timeout: TimeInterval = 20
    ) -> Bool {
        let row = itemRow(itemID: itemID, in: app)
        let unhideButton = app.buttons["unhide-item-\(itemID.uuidString)"]
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if waitForItemHiddenState(
                named: itemName,
                hidden: false,
                inListNamed: listName,
                accessToken: accessToken,
                timeout: 0.5
            ) {
                return true
            }

            if unhideButton.exists {
                tapElement(unhideButton)
            } else {
                _ = waitForItemRow(itemID: itemID, named: itemName, in: app, timeout: 2)
                scrollToHittable(row, in: app, maxSwipes: 10)
                if row.exists && row.isHittable {
                    let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
                    let end = row.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5))
                    start.press(forDuration: 0.08, thenDragTo: end)
                    if unhideButton.waitForExistence(timeout: 2) {
                        tapElement(unhideButton)
                    } else if waitForItemHiddenState(
                        named: itemName,
                        hidden: false,
                        inListNamed: listName,
                        accessToken: accessToken,
                        timeout: 1
                    ) == false {
                        row.swipeRight()
                        if unhideButton.waitForExistence(timeout: 2) {
                            tapElement(unhideButton)
                        }
                    }
                }
            }

            if waitForItemHiddenState(
                named: itemName,
                hidden: false,
                inListNamed: listName,
                accessToken: accessToken,
                timeout: 3
            ) {
                return true
            }
        }

        return waitForItemHiddenState(
            named: itemName,
            hidden: false,
            inListNamed: listName,
            accessToken: accessToken,
            timeout: 0.5
        )
    }

    private func openAddItemSheet(in app: XCUIApplication, timeout: TimeInterval = 10) -> Bool {
        openAddItemSheet(using: app.buttons["add-item-button"], in: app, timeout: timeout)
    }

    private func waitForItemCheckedState(
        named itemName: String,
        checked: Bool,
        inListNamed listName: String,
        accessToken: String,
        timeout: TimeInterval = 8
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let items = try? fetchItems(inListNamed: listName, accessToken: accessToken),
                items.contains(where: { $0.name == itemName && $0.checked == checked })
            {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }
        return false
    }

    private func waitForItemHiddenState(
        named itemName: String,
        hidden: Bool,
        inListNamed listName: String,
        accessToken: String,
        timeout: TimeInterval = 8
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let item = try? fetchItems(inListNamed: listName, accessToken: accessToken)
                .first(where: { $0.name == itemName }),
                (item.hiddenUntil != nil) == hidden
            {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }
        return false
    }

    private func waitForItemSaleWindow(
        named itemName: String,
        active: Bool,
        inListNamed listName: String,
        accessToken: String,
        timeout: TimeInterval = 8
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let item = try? fetchItems(inListNamed: listName, accessToken: accessToken)
                .first(where: { $0.name == itemName }),
                (item.saleStartsAt != nil && item.saleEndsAt != nil) == active
            {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }
        return false
    }

    private func waitForItem(
        named itemName: String,
        inListNamed listName: String,
        accessToken: String,
        timeout: TimeInterval = 8
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let items = try? fetchItems(inListNamed: listName, accessToken: accessToken),
                items.contains(where: { $0.name == itemName })
            {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }
        return false
    }

    private func waitForItemAbsent(
        named itemName: String,
        inListNamed listName: String,
        accessToken: String,
        timeout: TimeInterval = 8
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let items = try? fetchItems(inListNamed: listName, accessToken: accessToken),
                items.contains(where: { $0.name == itemName }) == false
            {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }
        return false
    }

    private func waitForList(
        named listName: String,
        accessToken: String,
        timeout: TimeInterval = 8
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (try? listID(named: listName, accessToken: accessToken)) != nil {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }
        return false
    }

    private func waitForListName(
        listID: UUID,
        name: String,
        accessToken: String,
        timeout: TimeInterval = 8
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let groceryList = try? fetchList(listID: listID, accessToken: accessToken),
                groceryList.name == name
            {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }
        return false
    }

    private func waitForListAccentColor(
        listID: UUID,
        accentColorHex: String?,
        accessToken: String,
        timeout: TimeInterval = 8
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let groceryList = try? fetchList(listID: listID, accessToken: accessToken),
                groceryList.accentColorHex == accentColorHex
            {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }
        return false
    }

    private func waitForItemCategory(
        named itemName: String,
        categoryNamed categoryName: String,
        inListNamed listName: String,
        accessToken: String,
        timeout: TimeInterval = 8
    ) -> Bool {
        guard
            let categoryID = try? categoryID(
                named: categoryName,
                inListNamed: listName,
                accessToken: accessToken
            )
        else {
            return false
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let items = try? fetchItems(inListNamed: listName, accessToken: accessToken),
                items.contains(where: { $0.name == itemName && $0.categoryID == categoryID })
            {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }
        return false
    }

    private func waitForFirstCategoryOrder(
        listID: UUID,
        categoryID: UUID,
        accessToken: String,
        timeout: TimeInterval = 8
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let categoryOrder = try? fetchCategoryOrder(listID: listID, accessToken: accessToken),
                categoryOrder.first?.categoryID == categoryID
            {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }
        return false
    }

    private func dragItemRow(
        itemID: UUID,
        named itemName: String,
        toCategoryTarget targetElement: XCUIElement,
        in app: XCUIApplication,
        categoryName: String,
        listName: String,
        accessToken: String
    ) -> Bool {
        let sourceRow = itemRow(itemID: itemID, in: app)
        let dropOffsets: [CGFloat] = [0.5, 0.3, 0.7]

        for dropOffset in dropOffsets {
            scrollToHittable(sourceRow, in: app, maxSwipes: 4)
            scrollToHittable(targetElement, in: app, maxSwipes: 4)
            guard
                sourceRow.waitForExistence(timeout: 3),
                targetElement.waitForExistence(timeout: 3),
                sourceRow.isHittable,
                targetElement.isHittable
            else {
                continue
            }

            let source = sourceRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let target = targetElement.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: dropOffset)
            )
            source.press(
                forDuration: 1.2,
                thenDragTo: target,
                withVelocity: .slow,
                thenHoldForDuration: 1.2
            )
            if waitForItemCategory(
                named: itemName,
                categoryNamed: categoryName,
                inListNamed: listName,
                accessToken: accessToken,
                timeout: 12
            ) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        return false
    }

    private func dragCategoryRow(
        _ movingRow: XCUIElement,
        using dragHandle: XCUIElement,
        before targetRow: XCUIElement,
        in app: XCUIApplication
    ) -> Bool {
        let targetOffsets: [CGFloat] = [0.5, 0.25, 0.75]
        for targetOffset in targetOffsets {
            scrollToHittable(movingRow, in: app, maxSwipes: 2)
            scrollToHittable(targetRow, in: app, maxSwipes: 2)
            guard
                movingRow.waitForExistence(timeout: 3),
                dragHandle.waitForExistence(timeout: 3),
                targetRow.waitForExistence(timeout: 3)
            else {
                return false
            }

            let grabber = dragHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let target = targetRow.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: targetOffset))
            grabber.press(forDuration: 1.2, thenDragTo: target)
            if waitForCategoryRow(movingRow, before: targetRow, timeout: 1) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        return false
    }

    private func waitForCategoryRow(
        _ movingRow: XCUIElement,
        before targetRow: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if movingRow.exists && targetRow.exists && movingRow.frame.minY < targetRow.frame.minY {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    private func waitForDisabledCategory(
        listID: UUID,
        categoryID: UUID,
        disabled: Bool,
        accessToken: String,
        timeout: TimeInterval = 8
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let disabledCategoryIDs = try? fetchDisabledCategoryIDs(listID: listID, accessToken: accessToken),
                disabledCategoryIDs.contains(categoryID) == disabled
            {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }
        return false
    }

    private func waitForElementLabel(
        _ element: XCUIElement,
        containing text: String,
        timeout: TimeInterval = 8
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && (element.label.contains(text) || element.valueText.contains(text)) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return element.exists && (element.label.contains(text) || element.valueText.contains(text))
    }

    private func terminateAndWait(_ app: XCUIApplication, timeout: TimeInterval = 8) {
        app.terminate()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.state == .notRunning {
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }

    private func waitForFieldValue(
        _ field: XCUIElement,
        contains expectedText: String,
        timeout: TimeInterval = 8
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if field.valueText.contains(expectedText) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return field.valueText.contains(expectedText)
    }

    private func prepareKeyboardForTyping(in app: XCUIApplication, timeout: TimeInterval = 3) -> Bool {
        guard app.keyboards.firstMatch.waitForExistence(timeout: timeout) else {
            return false
        }
        dismissKeyboardTipsIfPresent(in: app)
        return true
    }

    private func dismissKeyboardTipsIfPresent(in app: XCUIApplication) {
        let continueButton = app.buttons["Continue"]
        let deadline = Date().addingTimeInterval(2)

        while Date() < deadline {
            if continueButton.exists {
                tapElement(continueButton)
                _ = waitForElementToDisappear(continueButton, timeout: 2)
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
    }

    private func exerciseHouseholdManagement(in app: XCUIApplication, accessToken: String) throws {
        let suffix = UUID().uuidString.prefix(8)
        let householdName = "UI Household \(suffix)"
        let listName = "UI Household List \(suffix)"

        let managementLink = app.buttons["settings-household-management-link"]
        XCTAssertTrue(managementLink.waitForExistence(timeout: 5))
        tapElement(managementLink)

        let managementScreen = app.descendants(matching: .any)["household-management-screen"]
        XCTAssertTrue(managementScreen.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["new-household-button"].waitForExistence(timeout: 5))

        tapElement(app.buttons["new-household-button"])
        let householdField = app.textFields["new-household-name-field"]
        XCTAssertTrue(householdField.waitForExistence(timeout: 5))
        householdField.tap()
        householdField.typeText(householdName)
        tapElement(app.buttons["new-household-save-button"])

        let householdRow = app.buttons["household-row-\(householdName)"]
        XCTAssertTrue(householdRow.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForHousehold(named: householdName, accessToken: accessToken))
        tapElement(householdRow)

        let householdDetail = app.descendants(matching: .any)["household-detail-management-screen"]
        XCTAssertTrue(householdDetail.waitForExistence(timeout: 5))
        tapElement(app.buttons["new-household-list-button"])

        let listField = app.textFields["new-household-list-name-field"]
        XCTAssertTrue(listField.waitForExistence(timeout: 5))
        listField.tap()
        listField.typeText(listName)
        tapElement(app.buttons["new-household-list-save-button"])

        let listRow = app.buttons["managed-list-row-\(listName)"]
        XCTAssertTrue(listRow.waitForExistence(timeout: 10))
        XCTAssertTrue(
            waitForList(named: listName, inHouseholdNamed: householdName, accessToken: accessToken)
        )

        let inviteSheet = app.descendants(matching: .any)["household-invite-sheet"]
        XCTAssertFalse(inviteSheet.exists)
        XCTAssertFalse(app.segmentedControls["household-invite-mode-picker"].exists)

        tapElement(app.buttons["open-household-invite-sheet-button"])
        XCTAssertTrue(inviteSheet.waitForExistence(timeout: 5))
        let rolePicker = app.segmentedControls["household-invite-role-picker"]
        XCTAssertTrue(rolePicker.waitForExistence(timeout: 5))
        tapElement(rolePicker.buttons["Viewer"])
        XCTAssertTrue(app.steppers["household-invite-hours-stepper"].waitForExistence(timeout: 5))

        let durationLabel = app.staticTexts["household-invite-duration-label"]
        XCTAssertTrue(waitForElementLabel(durationLabel, containing: "1 day", timeout: 3))
        tapElement(app.buttons["household-invite-quick-3-days-button"])
        XCTAssertTrue(waitForElementLabel(durationLabel, containing: "3 days", timeout: 3))

        let usageMode = firstExistingElement(
            [
                app.buttons["household-invite-mode-uses"],
                app.buttons["Limit by uses"],
            ],
            timeout: 5
        )
        XCTAssertTrue(usageMode.exists)
        tapElement(usageMode)
        XCTAssertTrue(app.steppers["household-invite-max-uses-stepper"].waitForExistence(timeout: 3))

        tapElement(app.buttons["create-household-invite-button"])
        let inviteValue = app.staticTexts["household-invite-url-value"]
        XCTAssertTrue(inviteValue.waitForExistence(timeout: 10))
        let inviteURL = inviteValue.label
        XCTAssertTrue(inviteURL.contains("/invite/"))
        XCTAssertTrue(
            waitForInvitePreview(
                inviteURL: inviteURL,
                householdName: householdName,
                accessToken: accessToken,
                expectedMaxUses: 5,
                expectedRemainingUses: 5,
                expectedRole: "viewer"
            )
        )
        captureScreenshot(named: "ios-ui-household-management")

        tapElement(app.buttons["close-household-invite-sheet-button"])
        XCTAssertTrue(waitForElementToDisappear(inviteSheet, timeout: 3))
        navigateBack(in: app)
        XCTAssertTrue(managementScreen.waitForExistence(timeout: 3))
        navigateBack(in: app)
        XCTAssertTrue(app.buttons["settings-sign-out-button"].waitForExistence(timeout: 5))
    }

    private func exercisePasskeyManagement(in app: XCUIApplication, accessToken: String) throws {
        let passkeys = try fetchPasskeys(accessToken: accessToken)
        let passkey = try XCTUnwrap(passkeys.first)

        let managementLink = app.buttons["settings-passkey-management-link"]
        XCTAssertTrue(managementLink.waitForExistence(timeout: 5))
        tapElement(managementLink)

        let managementScreen = app.descendants(matching: .any)["passkey-management-screen"]
        XCTAssertTrue(managementScreen.waitForExistence(timeout: 5))

        let passkeyID = passkey.id.uuidString.lowercased()
        let passkeyName = app.descendants(matching: .any)["passkey-name-\(passkeyID)"]
        XCTAssertTrue(passkeyName.waitForExistence(timeout: 10))
        XCTAssertEqual(passkeyName.label, passkey.name)

        let deleteButton = app.descendants(matching: .any)["passkey-delete-\(passkeyID)"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3))
        if passkeys.count == 1 {
            XCTAssertFalse(deleteButton.isEnabled)
            XCTAssertTrue(
                app.descendants(matching: .any)["passkey-delete-disabled-help"]
                    .waitForExistence(timeout: 3)
            )
        }

        let addButton = app.buttons["passkey-add-button"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 3))
        tapElement(addButton)

        let addSheet = app.descendants(matching: .any)["passkey-add-name-sheet"]
        let addNameField = app.textFields["passkey-add-name-field"]
        let addSubmitButton = app.buttons["passkey-add-submit-button"]
        XCTAssertTrue(addSheet.waitForExistence(timeout: 3))
        XCTAssertTrue(addNameField.waitForExistence(timeout: 3))
        XCTAssertTrue(addSubmitButton.isEnabled)
        replaceText(in: addNameField, with: "")
        XCTAssertFalse(addSubmitButton.isEnabled)
        tapElement(app.buttons["passkey-add-cancel-button"])
        XCTAssertTrue(waitForElementToDisappear(addSheet, timeout: 3))

        let renameButton = app.descendants(matching: .any)["passkey-rename-\(passkeyID)"]
        XCTAssertTrue(renameButton.waitForExistence(timeout: 3))
        tapElement(renameButton)

        let renameSheet = app.descendants(matching: .any)["passkey-rename-name-sheet"]
        XCTAssertTrue(renameSheet.waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["passkey-rename-name-field"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["passkey-rename-submit-button"].isEnabled)
        tapElement(app.buttons["passkey-rename-cancel-button"])
        XCTAssertTrue(waitForElementToDisappear(renameSheet, timeout: 3))

        captureScreenshot(named: "ios-ui-passkey-management")
        navigateBack(in: app)
        XCTAssertTrue(app.buttons["settings-sign-out-button"].waitForExistence(timeout: 5))
    }

    private func assertLanguageSettings(in app: XCUIApplication) {
        let languageRow = app.buttons["settings-language-row"]
        scrollToElement(languageRow, in: app, maxSwipes: 3)
        XCTAssertTrue(languageRow.waitForExistence(timeout: 3))
        tapElement(languageRow)

        let germanOption = app.buttons["language-option-de"]
        XCTAssertTrue(
            firstExistingElement(
                [app.navigationBars["Language"], app.staticTexts["Choose language"], germanOption],
                timeout: 5
            ).exists
        )
        scrollToElement(germanOption, in: app, maxSwipes: 3)
        XCTAssertTrue(germanOption.waitForExistence(timeout: 3))
        tapElement(germanOption)

        XCTAssertTrue(
            firstExistingElement(
                [app.navigationBars["Sprache"], app.staticTexts["Sprache"]],
                timeout: 3
            ).exists
        )
        XCTAssertTrue(waitForLanguageOptionSelected(app.buttons["language-option-de"]))
        captureScreenshot(named: "ios-ui-settings-german")

        let backButton = firstExistingElement(
            [
                app.navigationBars.buttons["Einstellungen"],
                app.navigationBars.buttons["Settings"],
                app.navigationBars.buttons.element(boundBy: 0),
            ],
            timeout: 3
        )
        XCTAssertTrue(backButton.exists)
        tapElement(backButton)
        XCTAssertTrue(app.buttons["settings-sign-out-button"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["settings-sign-out-button"].label.contains("Abmelden"))

        let localizedLanguageRow = app.buttons["settings-language-row"]
        scrollToElement(localizedLanguageRow, in: app, maxSwipes: 3)
        XCTAssertTrue(localizedLanguageRow.waitForExistence(timeout: 3))
        tapElement(localizedLanguageRow)

        let systemOption = app.buttons["language-option-system"]
        scrollToElement(systemOption, in: app, maxSwipes: 3)
        XCTAssertTrue(systemOption.waitForExistence(timeout: 3))
        tapElement(systemOption)

        XCTAssertTrue(waitForLanguageOptionSelected(app.buttons["language-option-system"]))
    }

    private func waitForLanguageOptionSelected(
        _ element: XCUIElement,
        timeout: TimeInterval = 3
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let value = element.valueText
            if value.contains("Selected") || value.contains("Ausgewählt") {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        let value = element.valueText
        return value.contains("Selected") || value.contains("Ausgewählt")
    }

    private func waitForToggleLabel(
        _ element: XCUIElement,
        containsAny fragments: [String],
        timeout: TimeInterval = 5
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if fragments.contains(where: { element.label.contains($0) }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return fragments.contains(where: { element.label.contains($0) })
    }

    private func firstVisibleUncheckedToggle(
        in app: XCUIApplication,
        timeout: TimeInterval = 5
    ) -> (button: XCUIElement, itemName: String)? {
        let candidateNames = ["Loose item", "Tomaten", "Eier", "Spaghetti", "Putzmittel", "Erbsen", "Tofu"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for itemName in candidateNames {
                let button = app.buttons["Check \(itemName)"]
                if button.waitForExistence(timeout: 0.2) {
                    return (button, itemName)
                }
            }
            app.swipeUp()
        }
        for itemName in candidateNames {
            let button = app.buttons["Check \(itemName)"]
            if button.exists {
                return (button, itemName)
            }
        }
        return nil
    }

    private func firstVisibleQuickAddSection(
        in app: XCUIApplication,
        timeout: TimeInterval = 5
    ) -> (title: String, button: XCUIElement)? {
        let candidates = [
            ("Uncategorized", "Quick add uncategorized item"),
            ("Canned Goods", "Quick add to Canned Goods"),
            ("Dairy & Eggs", "Quick add to Dairy & Eggs"),
            ("Pasta", "Quick add to Pasta"),
            ("Cleaning", "Quick add to Cleaning"),
            ("Frozen Foods", "Quick add to Frozen Foods"),
            ("Vegan", "Quick add to Vegan"),
        ]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for (title, label) in candidates {
                let button = app.buttons[label]
                if button.waitForExistence(timeout: 0.2) {
                    return (title, button)
                }
            }
            app.swipeUp()
        }
        for (title, label) in candidates {
            let button = app.buttons[label]
            if button.exists {
                return (title, button)
            }
        }
        return nil
    }

    private func waitForElementToDisappear(_ element: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists == false {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return element.exists == false
    }

    private func saveAddItemSheet(in app: XCUIApplication, timeout: TimeInterval = 10) -> Bool {
        let sheet = app.otherElements["add-item-sheet"]
        let saveButton = app.buttons["add-item-save-button"]
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if saveButton.exists && saveButton.isEnabled {
                tapElement(saveButton)
                return waitForElementToDisappear(sheet, timeout: timeout)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        return waitForElementToDisappear(sheet, timeout: 1)
    }

    private func waitForLiveUpdatesConnection(
        app: XCUIApplication,
        listName: String,
        accessToken: String,
        timeout: TimeInterval = 45
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let probeName = "A UI Live Ready \(UUID().uuidString.prefix(8))"
            if let probeID = try? createItem(
                named: probeName,
                note: "",
                inListNamed: listName,
                accessToken: accessToken
            ) {
                let appeared = waitForItemRow(itemID: probeID, named: probeName, in: app, timeout: 8)
                try? deleteItem(itemID: probeID, accessToken: accessToken)
                let disappeared = waitForElementToDisappear(
                    itemRow(itemID: probeID, in: app),
                    timeout: 8
                )
                if appeared && disappeared {
                    return true
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        return false
    }

    private func waitForOfflineStatus(in app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.descendants(matching: .any)["offline-status-banner"].exists {
                return true
            }
            if app.staticTexts["Offline. Showing saved list."].exists {
                return true
            }
            let matchingStatusText = app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS %@", "Offline. Showing saved list.")
            ).firstMatch
            if matchingStatusText.exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return app.descendants(matching: .any)["offline-status-banner"].exists
            || app.staticTexts["Offline. Showing saved list."].exists
    }

    private func waitForOfflineStatusToDisappear(in app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        let banner = app.descendants(matching: .any)["offline-status-banner"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if banner.exists == false {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return banner.exists == false
    }

    private func openInitialListDetail(
        in app: XCUIApplication,
        listTitle: XCUIElement,
        listName: String? = nil,
        timeout: TimeInterval = 45
    ) -> Bool {
        let expectedListName = listName ?? initialListName
        guard app.wait(for: .runningForeground, timeout: min(timeout, 15)) else {
            return false
        }

        let deadline = Date().addingTimeInterval(timeout)
        let initialListRow = app.buttons["list-row-\(expectedListName)"]

        while Date() < deadline {
            if listTitle.exists && listTitle.label == expectedListName {
                return true
            }

            if tapTab("Lists", in: app, timeout: 1) {
                returnToListsRootIfNeeded(app, listName: expectedListName)
                if initialListRow.waitForExistence(timeout: 2) {
                    initialListRow.tap()
                    if listTitle.waitForExistence(timeout: 5), listTitle.label == expectedListName {
                        return true
                    }
                }
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }

        return listTitle.exists && listTitle.label == expectedListName
    }

    private func tapTab(_ label: String, in app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for tabButton in tabCandidates(for: label, in: app) where tabButton.exists {
                tapElement(tabButton)
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    private func openSettings(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let picker = app.segmentedControls["settings-appearance-picker"]
        while Date() < deadline {
            if picker.exists {
                return true
            }
            _ = tapTab("Settings", in: app, timeout: 2)
            if picker.waitForExistence(timeout: 2) {
                return true
            }
        }
        return picker.exists
    }

    private func tabCandidates(for label: String, in app: XCUIApplication) -> [XCUIElement] {
        let labels: [String]
        let ids: [String]
        switch label {
        case "Lists":
            labels = ["Lists", "Listen"]
            ids = ["tab-lists-button", "tab-lists"]
        case "Settings":
            labels = ["Settings", "Einstellungen"]
            ids = ["tab-settings-button", "tab-settings"]
        case "Favorite":
            labels = ["Favorite", "Favorit"]
            ids = ["tab-favorite-button", "tab-favorite"]
        default:
            labels = [label]
            ids = []
        }
        var candidates = ids.flatMap { id in
            [
                app.tabBars.buttons.matching(identifier: id).firstMatch,
                app.buttons.matching(identifier: id).firstMatch,
            ]
        }
        candidates += labels.flatMap { tabLabel in
            let predicate = NSPredicate(format: "label == %@", tabLabel)
            return [
                app.tabBars.buttons.matching(predicate).firstMatch,
                app.buttons.matching(predicate).firstMatch,
            ]
        }
        return candidates
    }

    private func chooseCategory(
        named categoryName: String,
        using linkIdentifier: String,
        in app: XCUIApplication,
        searchText: String?,
        sortOption: String?,
        screenshotName: String?
    ) {
        let link = app.buttons[linkIdentifier]
        scrollToHittable(link, in: app)
        XCTAssertTrue(link.waitForExistence(timeout: 3))
        tapElement(link)

        let categoryScreen = app.descendants(matching: .any)["category-selection-screen"]
        XCTAssertTrue(categoryScreen.waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["category-search-field"].waitForExistence(timeout: 3))

        if let sortOption {
            let option = firstExistingElement(
                categorySortElements(for: sortOption, in: app),
                timeout: 3
            )
            XCTAssertTrue(option.waitForExistence(timeout: 3))
            tapElement(option)
        }

        if let searchText {
            let searchField = app.textFields["category-search-field"]
            searchField.tap()
            searchField.typeText(searchText)
        }

        let categoryOption = app.buttons["category-option-\(categoryName)"]
        XCTAssertTrue(categoryOption.waitForExistence(timeout: 3))
        if let screenshotName {
            captureScreenshot(named: screenshotName)
        }
        tapElement(categoryOption)
        XCTAssertTrue(waitForElementToDisappear(categoryScreen, timeout: 3))
    }

    private func categorySortElements(for sortOption: String, in app: XCUIApplication) -> [XCUIElement] {
        let labels: [String]
        switch sortOption {
        case "most-used":
            labels = ["Most used", "Used", "Meistgenutzt", "Genutzt"]
        default:
            labels = [sortOption]
        }
        return labels.flatMap { label in
            [
                app.buttons[label],
                app.segmentedControls.buttons[label],
                app.staticTexts[label],
            ]
        }
    }

    private func selectAppearanceMode(_ label: String, in app: XCUIApplication) {
        let picker = app.segmentedControls["settings-appearance-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let option = firstExistingElement(appearanceModeElements(for: label, in: app), timeout: 3)
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        tapElement(option)
    }

    private func assertAppearanceMode(
        _ label: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let picker = app.segmentedControls["settings-appearance-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), file: file, line: line)
        let option = firstExistingElement(appearanceModeElements(for: label, in: app), timeout: 3)
        XCTAssertTrue(option.waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertTrue(
            waitForAppearanceMode(label, picker: picker, option: option),
            "Expected \(label) appearance mode to be selected.",
            file: file,
            line: line
        )
    }

    private func waitForAppearanceMode(
        _ label: String,
        picker: XCUIElement,
        option: XCUIElement,
        timeout: TimeInterval = 5
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if option.isSelected || appearanceModeLabels(for: label).contains(picker.valueText) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return option.isSelected || appearanceModeLabels(for: label).contains(picker.valueText)
    }

    private func appearanceModeElements(for label: String, in app: XCUIApplication) -> [XCUIElement] {
        appearanceModeLabels(for: label).flatMap { modeLabel in
            [
                app.buttons[modeLabel],
                app.segmentedControls.buttons[modeLabel],
            ]
        }
    }

    private func appearanceModeLabels(for label: String) -> [String] {
        switch label {
        case "Light":
            return ["Light", "Hell"]
        case "Dark":
            return ["Dark", "Dunkel"]
        default:
            return [label]
        }
    }

    private func tapElement(_ element: XCUIElement, timeout: TimeInterval = 3) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.isHittable {
                element.tap()
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        let frame = element.frame
        guard element.exists, frame.isEmpty == false, frame.isNull == false else {
            XCTFail("Could not tap \(element.identifier): element never gained a valid frame.")
            return
        }
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func dismissKeyboard(in app: XCUIApplication) {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }
        if keyboard.buttons["done"].exists {
            keyboard.buttons["done"].tap()
        } else if keyboard.buttons["Done"].exists {
            keyboard.buttons["Done"].tap()
        } else {
            app.swipeDown()
        }
        XCTAssertTrue(waitForElementToDisappear(keyboard, timeout: 3))
    }

    private func tapCancelButton(in app: XCUIApplication) {
        let button = firstExistingElement(
            [
                app.buttons["add-item-cancel-button"],
                app.buttons["reviewer-onboarding-cancel-button"],
                app.buttons["Cancel"],
                app.buttons["Abbrechen"],
            ],
            timeout: 3
        )
        XCTAssertTrue(button.exists)
        tapElement(button)
    }

    private func replaceText(in element: XCUIElement, with value: String) {
        element.tap()
        let deleteSequence = String(repeating: XCUIKeyboardKey.delete.rawValue, count: element.valueText.count)
        if deleteSequence.isEmpty == false {
            element.typeText(deleteSequence)
        }
        element.typeText(value)
    }

    private func tapTrailingControl(in element: XCUIElement, app: XCUIApplication) {
        let frame = element.frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.maxX - 115, dy: frame.midY))
            .tap()
    }

    private func tapTrailingAction(in element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }

    private func openAddItemSheet(
        using trigger: XCUIElement,
        in app: XCUIApplication,
        timeout: TimeInterval = 10
    ) -> Bool {
        let sheet = app.otherElements["add-item-sheet"]
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if sheet.exists {
                return true
            }
            if trigger.exists {
                scrollToHittable(trigger, in: app, maxSwipes: 2)
                tapElement(trigger)
            }
            if sheet.waitForExistence(timeout: 1) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        return sheet.exists
    }

    private func openEditItemSheet(
        itemID: UUID,
        using row: XCUIElement,
        in app: XCUIApplication,
        timeout: TimeInterval = 10
    ) -> Bool {
        let sheet = app.otherElements["edit-item-sheet"]
        let editTrigger = app.buttons["edit-item-row-\(itemID.uuidString)"]
        let editButton = app.buttons["edit-item-\(itemID.uuidString)"]
        let detailScreen = app.descendants(matching: .any)["list-detail-screen"]
        let undoToast = app.otherElements["list-undo-toast"]
        if undoToast.exists && waitForElementToDisappear(undoToast, timeout: 12) == false {
            return false
        }
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if sheet.exists {
                return true
            }
            if detailScreen.exists == false {
                _ = tapTab(initialListName, in: app, timeout: 2)
            }
            if detailScreen.exists {
                scrollToHittable(row, in: app, maxSwipes: 12)
            }
            if row.exists {
                let navigationBar = app.navigationBars.firstMatch
                let tabBar = app.tabBars.firstMatch
                let rowIsBelowNavigationBar =
                    navigationBar.exists == false || row.frame.minY >= navigationBar.frame.maxY
                let rowIsAboveTabBar = tabBar.exists == false || row.frame.maxY <= tabBar.frame.minY
                if rowIsBelowNavigationBar == false {
                    app.swipeDown()
                } else if rowIsAboveTabBar == false {
                    app.swipeUp()
                } else {
                    if editTrigger.exists && editTrigger.isHittable {
                        tapElement(editTrigger)
                    } else if row.isHittable {
                        row.swipeLeft()
                        if editButton.waitForExistence(timeout: 1) {
                            tapElement(editButton)
                        }
                    }
                }
            }
            if sheet.waitForExistence(timeout: 1) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        return sheet.exists
    }

    private func tapSuggestionAndWaitForSheetDismissal(_ element: XCUIElement, app: XCUIApplication) -> Bool {
        let sheet = app.otherElements["add-item-sheet"]
        let deadline = Date().addingTimeInterval(12)

        while Date() < deadline {
            if waitForElementToDisappear(sheet, timeout: 1) {
                return true
            }
            if element.exists {
                scrollToHittable(element, in: app, maxSwipes: 2)
                tapTrailingAction(in: element)
            }
            if waitForElementToDisappear(sheet, timeout: 2) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        return !sheet.exists
    }

    private func tapAddItemSaveAndWaitForDismissal(in app: XCUIApplication, timeout: TimeInterval = 12) -> Bool {
        saveAddItemSheet(in: app, timeout: timeout)
    }

    private func waitForItemRow(
        itemID: UUID,
        named itemName: String,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let row = itemRow(itemID: itemID, in: app)
        let toggle = app.buttons["toggle-item-\(itemID.uuidString)"]
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if row.exists && toggle.exists && toggle.label.contains(itemName) {
                return true
            }

            for _ in 0..<8 {
                app.swipeUp()
                if row.exists && toggle.exists && toggle.label.contains(itemName) {
                    return true
                }
            }
            for _ in 0..<8 {
                app.swipeDown()
                if row.exists && toggle.exists && toggle.label.contains(itemName) {
                    return true
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return row.exists && toggle.exists && toggle.label.contains(itemName)
    }

    private func itemRow(itemID: UUID, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["item-row-\(itemID.uuidString)"]
    }

    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 10) {
        if element.waitForExistence(timeout: 0.25) {
            return
        }
        for _ in 0..<maxSwipes {
            app.swipeUp()
            if element.waitForExistence(timeout: 0.25) {
                return
            }
        }
        for _ in 0..<maxSwipes {
            app.swipeDown()
            if element.waitForExistence(timeout: 0.25) {
                return
            }
        }
    }

    private func scrollToListTop(in app: XCUIApplication, maxSwipes: Int = 8) {
        for _ in 0..<maxSwipes {
            app.swipeDown()
        }
    }

    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) {
        scrollToElement(element, in: app, maxSwipes: maxSwipes)
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable {
                return
            }
            app.swipeUp()
        }
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable {
                return
            }
            app.swipeDown()
        }
    }

    private func assertReviewerOnboardingAvailable(in app: XCUIApplication) {
        let helpMenu = app.buttons["login-help-menu"]
        XCTAssertTrue(helpMenu.waitForExistence(timeout: 3))
        helpMenu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let helpButton = firstExistingElement(
            [
                app.buttons["login-help-trouble-button"],
                app.buttons["Having trouble signing in?"],
                app.menuItems["Having trouble signing in?"],
                app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "trouble signing in")).firstMatch,
            ],
            timeout: 3
        )
        XCTAssertTrue(helpButton.exists)
        tapElement(helpButton)

        XCTAssertTrue(app.otherElements["reviewer-onboarding-sheet"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["passkey-add-link-field"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["registration-display-name-field"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["registration-email-field"].waitForExistence(timeout: 3))
        captureScreenshot(named: "ios-ui-reviewer-onboarding")

        XCTAssertFalse(app.buttons["passkey-add-submit-button"].isEnabled)
        XCTAssertFalse(app.buttons["registration-submit-button"].isEnabled)

        let onboardingSheet = app.otherElements["reviewer-onboarding-sheet"]
        let passkeyField = app.textFields["passkey-add-link-field"]
        passkeyField.tap()
        passkeyField.typeText("\(baseURL.absoluteString)/passkey-add/missing-reviewer-token")
        XCTAssertTrue(app.buttons["passkey-add-submit-button"].isEnabled)

        let nameField = app.textFields["registration-display-name-field"]
        nameField.tap()
        nameField.typeText("App Reviewer")
        let emailField = app.textFields["registration-email-field"]
        emailField.tap()
        emailField.typeText("reviewer@example.com")
        XCTAssertTrue(app.buttons["registration-submit-button"].isEnabled)

        tapCancelButton(in: app)
        XCTAssertTrue(waitForElementToDisappear(onboardingSheet, timeout: 5))
        XCTAssertTrue(app.buttons["login-passkey-button"].waitForExistence(timeout: 3))
    }

    private func assertAccountRegistrationAvailable(in app: XCUIApplication) {
        let createAccountButton = app.buttons["login-create-account-button"]
        XCTAssertTrue(createAccountButton.waitForExistence(timeout: 3))
        tapElement(createAccountButton)

        let registrationSheet = app.otherElements["account-registration-sheet"]
        XCTAssertTrue(registrationSheet.waitForExistence(timeout: 3))
        XCTAssertFalse(app.textFields["passkey-add-link-field"].exists)

        let submitButton = app.buttons["registration-submit-button"]
        XCTAssertFalse(submitButton.isEnabled)

        let nameField = app.textFields["registration-display-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("New iOS User")

        let emailField = app.textFields["registration-email-field"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 3))
        emailField.tap()
        emailField.typeText("new-ios-user@example.com")

        XCTAssertTrue(submitButton.isEnabled)
        captureScreenshot(named: "ios-ui-account-registration")

        tapCancelButton(in: app)
        XCTAssertTrue(waitForElementToDisappear(registrationSheet, timeout: 5))
        XCTAssertTrue(app.buttons["login-passkey-button"].waitForExistence(timeout: 3))
    }

    private func firstExistingElement(_ elements: [XCUIElement], timeout: TimeInterval) -> XCUIElement {
        for element in elements {
            if element.waitForExistence(timeout: timeout) {
                return element
            }
        }
        return elements.first ?? XCUIApplication().buttons.firstMatch
    }

    private func fetchItems(inListNamed listName: String, accessToken: String) throws -> [UITestItem] {
        let households = try fetchHouseholds(accessToken: accessToken)

        for household in households {
            let lists = try fetchLists(householdID: household.id, accessToken: accessToken)
            guard let matchingList = lists.first(where: { $0.name == listName }) else {
                continue
            }

            let itemsRequest = jsonRequest(
                path: "/api/v1/lists/\(matchingList.id.uuidString)/items",
                method: "GET",
                token: accessToken
            )
            let itemData = try performRequest(itemsRequest)
            return try JSONDecoder().decode([UITestItem].self, from: itemData)
        }

        return []
    }

    private func fetchPasskeys(accessToken: String) throws -> [UITestPasskey] {
        let request = jsonRequest(
            path: "/api/v1/auth/passkeys",
            method: "GET",
            token: accessToken
        )
        return try JSONDecoder().decode([UITestPasskey].self, from: performRequest(request))
    }

    private func waitForHousehold(
        named householdName: String,
        accessToken: String,
        timeout: TimeInterval = 8
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let households = try? fetchHouseholds(accessToken: accessToken),
                households.contains(where: { $0.name == householdName })
            {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }
        return false
    }

    private func waitForList(
        named listName: String,
        inHouseholdNamed householdName: String,
        accessToken: String,
        timeout: TimeInterval = 8
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let households = try? fetchHouseholds(accessToken: accessToken),
                let household = households.first(where: { $0.name == householdName }),
                let lists = try? fetchLists(householdID: household.id, accessToken: accessToken),
                lists.contains(where: { $0.name == listName })
            {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }
        return false
    }

    private func waitForInvitePreview(
        inviteURL: String,
        householdName: String,
        accessToken: String,
        expectedMaxUses: Int? = nil,
        expectedRemainingUses: Int? = nil,
        expectedRole: String? = nil,
        timeout: TimeInterval = 8
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let preview = try? invitePreview(inviteURL: inviteURL, accessToken: accessToken),
                preview.householdName == householdName,
                preview.alreadyMember,
                preview.maxUses == expectedMaxUses,
                preview.remainingUses == expectedRemainingUses,
                expectedRole == nil || preview.role == expectedRole
            {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }
        return false
    }

    private func fetchHouseholds(accessToken: String) throws -> [UITestHousehold] {
        let request = jsonRequest(
            path: "/api/v1/households",
            method: "GET",
            token: accessToken
        )
        let data = try performRequest(request)
        return try JSONDecoder().decode([UITestHousehold].self, from: data)
    }

    private func fetchLists(householdID: UUID, accessToken: String) throws -> [UITestList] {
        let request = jsonRequest(
            path: "/api/v1/households/\(householdID.uuidString)/lists",
            method: "GET",
            token: accessToken
        )
        let data = try performRequest(request)
        return try JSONDecoder().decode([UITestList].self, from: data)
    }

    private func invitePreview(inviteURL: String, accessToken: String) throws -> UITestInvitePreview {
        guard
            let url = URL(string: inviteURL),
            let token = url.pathComponents.last,
            token.isEmpty == false
        else {
            throw NSError(
                domain: "PlaniniUITests",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "Could not parse invite URL."]
            )
        }

        let request = jsonRequest(
            path: "/api/v1/households/invites/\(token)",
            method: "GET",
            token: accessToken
        )
        let data = try performRequest(request)
        return try JSONDecoder().decode(UITestInvitePreview.self, from: data)
    }

    private func fetchList(listID: UUID, accessToken: String) throws -> UITestList {
        let request = jsonRequest(
            path: "/api/v1/lists/\(listID.uuidString)",
            method: "GET",
            token: accessToken
        )
        let data = try performRequest(request)
        return try JSONDecoder().decode(UITestList.self, from: data)
    }

    private func fetchCategories(listID: UUID, accessToken: String) throws -> [UITestCategory] {
        let request = jsonRequest(
            path: "/api/v1/lists/\(listID.uuidString)/categories",
            method: "GET",
            token: accessToken
        )
        let data = try performRequest(request)
        return try JSONDecoder().decode([UITestCategory].self, from: data)
    }

    private func fetchCategoryOrder(listID: UUID, accessToken: String) throws -> [UITestCategoryOrderEntry] {
        let request = jsonRequest(
            path: "/api/v1/lists/\(listID.uuidString)/category-order",
            method: "GET",
            token: accessToken
        )
        let data = try performRequest(request)
        return try JSONDecoder().decode([UITestCategoryOrderEntry].self, from: data)
    }

    private func updateCategoryOrder(listID: UUID, categoryIDs: [UUID], accessToken: String) throws {
        let request = jsonRequest(
            path: "/api/v1/lists/\(listID.uuidString)/category-order",
            method: "PUT",
            token: accessToken,
            body: ["category_ids": categoryIDs.map(\.uuidString)]
        )
        _ = try performRequest(request)
    }

    private func fetchDisabledCategoryIDs(listID: UUID, accessToken: String) throws -> [UUID] {
        let request = jsonRequest(
            path: "/api/v1/lists/\(listID.uuidString)/disabled-categories",
            method: "GET",
            token: accessToken
        )
        let data = try performRequest(request)
        return try JSONDecoder().decode(UITestDisabledCategories.self, from: data).categoryIDs
    }

    private func itemID(named itemName: String, inListNamed listName: String, accessToken: String) throws -> UUID {
        if let item = try fetchItems(inListNamed: listName, accessToken: accessToken)
            .first(where: { $0.name == itemName })
        {
            return item.id
        }
        throw NSError(
            domain: "PlaniniUITests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not find item named \(itemName)."]
        )
    }

    private func categoryID(named categoryName: String, inListNamed listName: String, accessToken: String) throws -> UUID {
        let listID = try listID(named: listName, accessToken: accessToken)
        if let category = try fetchCategories(listID: listID, accessToken: accessToken)
            .first(where: { $0.name == categoryName })
        {
            return category.id
        }
        throw NSError(
            domain: "PlaniniUITests",
            code: 5,
            userInfo: [NSLocalizedDescriptionKey: "Could not find category named \(categoryName)."]
        )
    }

    private func createItem(
        named name: String,
        note: String,
        inListNamed listName: String,
        categoryID: UUID? = nil,
        sortOrder: Int = -1_000,
        accessToken: String
    ) throws -> UUID {
        let listID = try listID(named: listName, accessToken: accessToken)
        let request = jsonRequest(
            path: "/api/v1/lists/\(listID.uuidString)/items",
            method: "POST",
            token: accessToken,
            body: [
                "name": name,
                "quantity_text": NSNull(),
                "note": note,
                "category_id": categoryID?.uuidString ?? NSNull(),
                "sort_order": sortOrder,
            ]
        )
        let data = try performRequest(request)
        let item = try JSONDecoder().decode(UITestIdentifiedItem.self, from: data)
        return item.id
    }

    private func updateItem(
        itemID: UUID,
        name: String,
        note: String,
        accessToken: String
    ) throws {
        let request = jsonRequest(
            path: "/api/v1/items/\(itemID.uuidString)",
            method: "PATCH",
            token: accessToken,
            body: [
                "name": name,
                "note": note,
            ]
        )
        _ = try performRequest(request)
    }

    private func setItemSaleWindow(
        itemID: UUID,
        startsAt: Date,
        endsAt: Date,
        accessToken: String
    ) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let request = jsonRequest(
            path: "/api/v1/items/\(itemID.uuidString)",
            method: "PATCH",
            token: accessToken,
            body: [
                "sale_starts_at": formatter.string(from: startsAt),
                "sale_ends_at": formatter.string(from: endsAt),
            ]
        )
        _ = try performRequest(request)
    }

    private func checkItem(itemID: UUID, accessToken: String) throws {
        let request = jsonRequest(
            path: "/api/v1/items/\(itemID.uuidString)/check",
            method: "POST",
            token: accessToken
        )
        _ = try performRequest(request)
    }

    private func syncItemCheckedState(
        itemID: UUID,
        checked: Bool,
        inListNamed listName: String,
        accessToken: String
    ) throws {
        let listID = try listID(named: listName, accessToken: accessToken)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let request = jsonRequest(
            path: "/api/v1/lists/\(listID.uuidString)/items/sync",
            method: "POST",
            token: accessToken,
            body: [
                "mutations": [
                    [
                        "mutation_id": UUID().uuidString,
                        "type": "set_checked",
                        "item_id": itemID.uuidString,
                        "checked": checked,
                        "recorded_at": formatter.string(from: Date()),
                    ],
                ],
            ]
        )
        _ = try performRequest(request)
    }

    private func deleteItem(itemID: UUID, accessToken: String) throws {
        let request = jsonRequest(
            path: "/api/v1/items/\(itemID.uuidString)",
            method: "DELETE",
            token: accessToken
        )
        _ = try performRequest(request)
    }

    private func deleteList(listID: UUID, accessToken: String) throws {
        let request = jsonRequest(
            path: "/api/v1/lists/\(listID.uuidString)",
            method: "DELETE",
            token: accessToken
        )
        _ = try performRequest(request)
    }

    private func createInvite(householdName: String, accessToken: String) throws -> String {
        let householdID = try householdID(named: householdName, accessToken: accessToken)
        let request = jsonRequest(
            path: "/api/v1/households/\(householdID.uuidString)/invites",
            method: "POST",
            token: accessToken,
            body: [:]
        )
        let data = try performRequest(request)
        let invite = try JSONDecoder().decode(UITestInvite.self, from: data)
        guard let token = invite.inviteURL.split(separator: "/").last else {
            throw NSError(
                domain: "PlaniniUITests",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Could not extract invite token."]
            )
        }
        return String(token)
    }

    private func householdID(named householdName: String, accessToken: String) throws -> UUID {
        let request = jsonRequest(path: "/api/v1/households", method: "GET", token: accessToken)
        let data = try performRequest(request)
        let households = try JSONDecoder().decode([UITestHousehold].self, from: data)
        if let household = households.first(where: { $0.name == householdName }) {
            return household.id
        }
        throw NSError(
            domain: "PlaniniUITests",
            code: 6,
            userInfo: [NSLocalizedDescriptionKey: "Could not find household named \(householdName)."]
        )
    }

    private func listID(named listName: String, accessToken: String) throws -> UUID {
        let households = try fetchHouseholds(accessToken: accessToken)

        for household in households {
            let lists = try fetchLists(householdID: household.id, accessToken: accessToken)
            if let matchingList = lists.first(where: { $0.name == listName }) {
                return matchingList.id
            }
        }

        throw NSError(
            domain: "PlaniniUITests",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Could not find seeded list named \(listName)."]
        )
    }

    private func normalizeListName(prefixedBy prefix: String, to canonicalName: String, accessToken: String) throws -> UUID {
        let households = try fetchHouseholds(accessToken: accessToken)

        for household in households {
            let lists = try fetchLists(householdID: household.id, accessToken: accessToken)
            if let matchingList = lists.first(where: { $0.name == canonicalName || $0.name.hasPrefix(prefix) }) {
                if matchingList.name != canonicalName {
                    let request = jsonRequest(
                        path: "/api/v1/lists/\(matchingList.id.uuidString)",
                        method: "PATCH",
                        token: accessToken,
                        body: ["name": canonicalName]
                    )
                    _ = try performRequest(request)
                }
                return matchingList.id
            }
        }

        throw NSError(
            domain: "PlaniniUITests",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Could not find seeded list prefixed by \(prefix)."]
        )
    }

    private func jsonRequest(
        path: String,
        method: String,
        token: String?,
        body: [String: Any]? = nil,
        baseURL overrideBaseURL: URL? = nil
    ) -> URLRequest {
        let targetBaseURL = overrideBaseURL ?? baseURL
        var request = URLRequest(url: targetBaseURL.appending(path: path))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        request.httpMethod = method
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private func performRequest(_ request: URLRequest) throws -> Data {
        var lastError: Error?
        for attempt in 1...3 {
            do {
                return try performSingleRequest(request)
            } catch {
                lastError = error
                guard isTransientNetworkError(error), attempt < 3 else {
                    throw error
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.4 * Double(attempt)))
            }
        }

        throw lastError ?? NSError(domain: "PlaniniUITests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing response"])
    }

    private func performSingleRequest(_ request: URLRequest) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        var capturedData: Data?
        var capturedError: Error?
        var capturedResponse: URLResponse?
        URLSession.shared.dataTask(with: request) { data, response, error in
            capturedData = data
            capturedError = error
            capturedResponse = response
            semaphore.signal()
        }.resume()
        let waitResult = semaphore.wait(timeout: .now() + 10)

        if let capturedError {
            throw capturedError
        }
        if waitResult == .timedOut {
            throw NSError(
                domain: "PlaniniUITests",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Timed out waiting for response from \(request.url?.absoluteString ?? "unknown request")"
                ]
            )
        }
        guard let capturedData else {
            throw NSError(domain: "PlaniniUITests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing bootstrap response"])
        }
        if let response = capturedResponse as? HTTPURLResponse,
            (200..<300).contains(response.statusCode) == false
        {
            let responseBody = String(data: capturedData, encoding: .utf8) ?? "<non-UTF-8 body>"
            throw NSError(
                domain: "PlaniniUITests",
                code: response.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "HTTP \(response.statusCode) from \(request.url?.absoluteString ?? "unknown request"): \(responseBody)"
                ]
            )
        }
        return capturedData
    }

    private func isTransientNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return false
        }
        return [
            NSURLErrorNetworkConnectionLost,
            NSURLErrorTimedOut,
            NSURLErrorCannotConnectToHost,
        ].contains(nsError.code)
    }

    private func returnToListsRootIfNeeded(_ app: XCUIApplication, listName: String? = nil) {
        let expectedListName = listName ?? initialListName
        if app.buttons["list-row-\(expectedListName)"].waitForExistence(timeout: 1) {
            return
        }

        let backButton = firstExistingElement(
            [
                app.navigationBars.buttons["Lists"],
                app.navigationBars.buttons["Listen"],
            ],
            timeout: 1
        )
        if backButton.exists {
            tapElement(backButton)
        }
    }

    private func navigateBack(in app: XCUIApplication) {
        let backButton = app.navigationBars.buttons.firstMatch
        if backButton.waitForExistence(timeout: 3) {
            tapElement(backButton)
        }
    }

    private func captureScreenshot(
        named name: String,
        relativeArtifactDirectory: String? = nil
    ) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = [relativeArtifactDirectory, name]
            .compactMap { $0 }
            .joined(separator: "-")
        attachment.lifetime = .keepAlways
        add(attachment)

        let directoryURL = if let relativeArtifactDirectory {
            screenshotArtifactDirectory()
                .appending(path: relativeArtifactDirectory, directoryHint: .isDirectory)
        } else {
            screenshotArtifactDirectory()
        }
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appending(path: "\(name).png")
        try? screenshot.pngRepresentation.write(to: fileURL)
    }

    private func screenshotArtifactDirectory() -> URL {
        if let artifactDirectory = ProcessInfo.processInfo.environment["PLANINI_UI_TEST_ARTIFACT_DIR"],
            artifactDirectory.isEmpty == false
        {
            return URL(fileURLWithPath: artifactDirectory, isDirectory: true)
        }

        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "e2e-artifacts/ios-ui-e2e", directoryHint: .isDirectory)
    }

}

private struct MarketingScreenshotVariant {
    let localeDirectory: String
    let language: String
    let initialListName: String
    let session: UITestSession
}

private struct UITestSession: Decodable {
    let accessToken: String
    let displayName: String

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case displayName = "display_name"
    }
}

private struct UITestPasskey: Decodable {
    let id: UUID
    let name: String
}

private struct UITestHousehold: Decodable {
    let id: UUID
    let name: String
}

private struct UITestList: Decodable {
    let id: UUID
    let name: String
    let accentColorHex: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case accentColorHex = "accent_color"
    }
}

private struct UITestCategory: Decodable {
    let id: UUID
    let name: String
}

private struct UITestCategoryOrderEntry: Decodable {
    let categoryID: UUID
    let sortOrder: Int

    private enum CodingKeys: String, CodingKey {
        case categoryID = "category_id"
        case sortOrder = "sort_order"
    }
}

private struct UITestDisabledCategories: Decodable {
    let categoryIDs: [UUID]

    private enum CodingKeys: String, CodingKey {
        case categoryIDs = "category_ids"
    }
}

private struct UITestItem: Decodable {
    let id: UUID
    let name: String
    let checked: Bool
    let categoryID: UUID?
    let hiddenUntil: String?
    let saleStartsAt: String?
    let saleEndsAt: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case checked
        case categoryID = "category_id"
        case hiddenUntil = "hidden_until"
        case saleStartsAt = "sale_starts_at"
        case saleEndsAt = "sale_ends_at"
    }
}

private struct UITestIdentifiedItem: Decodable {
    let id: UUID
}

private struct UITestInvitePreview: Decodable {
    let householdName: String
    let alreadyMember: Bool
    let maxUses: Int?
    let remainingUses: Int?
    let role: String?

    private enum CodingKeys: String, CodingKey {
        case householdName = "household_name"
        case alreadyMember = "already_member"
        case maxUses = "max_uses"
        case remainingUses = "remaining_uses"
        case role
    }
}

private struct UITestInvite: Decodable {
    let inviteURL: String

    private enum CodingKeys: String, CodingKey {
        case inviteURL = "invite_url"
    }
}

private extension XCUIElement {
    var valueText: String {
        value as? String ?? ""
    }
}

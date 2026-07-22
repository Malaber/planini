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
        let initialListNameText = app.staticTexts[initialListName]
        XCTAssertTrue(initialListNameText.waitForExistence(timeout: 3))
        captureScreenshot(named: "promotion-list-of-lists")
        initialListNameText.tap()
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
            named: "Milch & Eier",
            using: "add-item-category-link",
            in: app,
            searchText: "molkrei",
            sortOption: "A-Z",
            screenshotName: "ios-ui-category-picker"
        )
        XCTAssertTrue(
            waitForElementLabel(
                app.buttons["add-item-category-link"].firstMatch,
                containing: "Milch & Eier"
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
                categoryNamed: "Milch & Eier",
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
                categoryNamed: "Milch & Eier",
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
        captureScreenshot(named: "promotion-edit-item-dialogue")

        let editNameField = app.textFields["edit-item-name-field"]
        editNameField.tap()
        XCTAssertTrue(prepareKeyboardForTyping(in: app, timeout: 5))
        editNameField.typeText(" Updated")
        XCTAssertTrue(waitForFieldValue(editNameField, contains: updatedName))
        XCTAssertTrue(waitForEditStatus("saved", app: app))

        XCTAssertTrue(undoButton.waitForExistence(timeout: 3))
        undoButton.tap()
        XCTAssertTrue(waitForFieldValue(editNameField, contains: itemName))
        XCTAssertFalse(editNameField.valueText.contains("Updated"))
        XCTAssertTrue(waitForEditStatus("saved", app: app))

        XCTAssertTrue(redoButton.waitForExistence(timeout: 3))
        redoButton.tap()
        XCTAssertTrue(waitForFieldValue(editNameField, contains: updatedName))
        XCTAssertTrue(waitForEditStatus("saved", app: app))

        chooseCategory(
            named: "Konserven",
            using: "edit-item-category-link",
            in: app,
            searchText: "kon",
            sortOption: "most-used",
            screenshotName: "ios-ui-edit-category-picker"
        )
        XCTAssertTrue(
            waitForElementLabel(
                app.buttons["edit-item-category-link"].firstMatch,
                containing: "Konserven"
            )
        )
        XCTAssertTrue(waitForEditStatus("saved", app: app))
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
                categoryNamed: "Konserven",
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
            named: "Haushalt",
            inListNamed: hostingListName,
            accessToken: session.accessToken
        )
        let backwarenCategoryID = try categoryID(
            named: "Backwaren",
            inListNamed: hostingListName,
            accessToken: session.accessToken
        )
        let hostingKonservenCategoryID = try categoryID(
            named: "Konserven",
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
                categoryNamed: "Backwaren",
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
                timeout: 20
            )
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
        app.buttons["Done"].tap()
        XCTAssertTrue(listTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(listTitle.label, renamedHostingName)

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

    func testLongPressDragMovesItemToCategory() throws {
        try assertLocalTestBackend()
        let session = if let injectedSession {
            injectedSession
        } else {
            try bootstrapSession(email: userEmail)
        }
        let targetCategoryID = try categoryID(
            named: "Konserven",
            inListNamed: initialListName,
            accessToken: session.accessToken
        )
        let sourceCategoryID = try categoryID(
            named: "Milch & Eier",
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
                categoryName: "Konserven",
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
        XCTAssertTrue(undoMessage.label.contains("Konserven"))
        tapElement(undoButton)
        XCTAssertTrue(
            waitForItemCategory(
                named: itemName,
                categoryNamed: "Milch & Eier",
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

    private var injectedSession: UITestSession? {
        guard
            let accessToken = environmentValue("PLANINI_UI_TEST_ACCESS_TOKEN"),
            let displayName = environmentValue("PLANINI_UI_TEST_DISPLAY_NAME")
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
        extraLaunchEnvironment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        configureLaunchLanguage(for: app)
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

    private func configureLaunchLanguage(for app: XCUIApplication) {
        app.launchEnvironment["PLANINI_UI_TEST_LANGUAGE"] = "en"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
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
        let deadline = Date().addingTimeInterval(timeout)

        scrollToListTop(in: app, maxSwipes: 10)

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

        scrollToHittable(sourceRow, in: app, maxSwipes: 4)
        scrollToHittable(targetElement, in: app, maxSwipes: 4)
        guard
            sourceRow.waitForExistence(timeout: 3),
            targetElement.waitForExistence(timeout: 3),
            sourceRow.isHittable,
            targetElement.isHittable
        else {
            return false
        }

        let source = sourceRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let target = targetElement.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        source.press(
            forDuration: 1.2,
            thenDragTo: target,
            withVelocity: .slow,
            thenHoldForDuration: 1.2
        )
        return waitForItemCategory(
            named: itemName,
            categoryNamed: categoryName,
            inListNamed: listName,
            accessToken: accessToken,
            timeout: 8
        )
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

    private func waitForEditStatus(
        _ status: String,
        app: XCUIApplication,
        timeout: TimeInterval = 20
    ) -> Bool {
        let statusLabel = app.staticTexts["edit-item-save-status"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if statusLabel.exists && statusLabel.valueText == status {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return statusLabel.exists && statusLabel.valueText == status
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
                expectedRemainingUses: 5
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
            ("Konserven", "Quick add to Konserven"),
            ("Milch & Eier", "Quick add to Milch & Eier"),
            ("Nudeln", "Quick add to Nudeln"),
            ("Reinigung", "Quick add to Reinigung"),
            ("Tiefkuehlkost", "Quick add to Tiefkuehlkost"),
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

    private func openInitialListDetail(
        in app: XCUIApplication,
        listTitle: XCUIElement,
        timeout: TimeInterval = 45
    ) -> Bool {
        guard app.wait(for: .runningForeground, timeout: min(timeout, 15)) else {
            return false
        }

        let deadline = Date().addingTimeInterval(timeout)
        let initialListRow = app.buttons["list-row-\(initialListName)"]

        while Date() < deadline {
            if listTitle.exists && listTitle.label == initialListName {
                return true
            }

            if tapTab("Lists", in: app, timeout: 1) {
                returnToListsRootIfNeeded(app)
                if initialListRow.waitForExistence(timeout: 2) {
                    initialListRow.tap()
                    if listTitle.waitForExistence(timeout: 5), listTitle.label == initialListName {
                        return true
                    }
                }
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }

        return listTitle.exists && listTitle.label == initialListName
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
            [app.tabBars.buttons[id], app.buttons[id]]
        }
        candidates += labels.flatMap { tabLabel in
            [app.tabBars.buttons[tabLabel], app.buttons[tabLabel]]
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
                let tabBar = app.tabBars.firstMatch
                let rowIsAboveTabBar = tabBar.exists == false || row.frame.maxY <= tabBar.frame.minY
                if rowIsAboveTabBar {
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
        timeout: TimeInterval = 8
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let preview = try? invitePreview(inviteURL: inviteURL, accessToken: accessToken),
                preview.householdName == householdName,
                preview.alreadyMember,
                preview.maxUses == expectedMaxUses,
                preview.remainingUses == expectedRemainingUses
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
                        "operation": "set_checked",
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
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
        URLSession.shared.dataTask(with: request) { data, _, error in
            capturedData = data
            capturedError = error
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

    private func returnToListsRootIfNeeded(_ app: XCUIApplication) {
        if app.buttons["list-row-\(initialListName)"].waitForExistence(timeout: 1) {
            return
        }

        let backButton = app.navigationBars.buttons.firstMatch
        if backButton.exists {
            backButton.tap()
        }
    }

    private func navigateBack(in app: XCUIApplication) {
        let backButton = app.navigationBars.buttons.firstMatch
        if backButton.waitForExistence(timeout: 3) {
            tapElement(backButton)
        }
    }

    private func captureScreenshot(named name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let directoryURL = screenshotArtifactDirectory()
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

private struct UITestSession: Decodable {
    let accessToken: String
    let displayName: String

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case displayName = "display_name"
    }
}

private struct UITestHousehold: Decodable {
    let id: UUID
    let name: String
}

private struct UITestList: Decodable {
    let id: UUID
    let name: String
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

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case checked
        case categoryID = "category_id"
        case hiddenUntil = "hidden_until"
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

    private enum CodingKeys: String, CodingKey {
        case householdName = "household_name"
        case alreadyMember = "already_member"
        case maxUses = "max_uses"
        case remainingUses = "remaining_uses"
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

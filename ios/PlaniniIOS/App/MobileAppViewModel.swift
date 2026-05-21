import Foundation
import PlaniniCore
import os.log

private let netLog = Logger(subsystem: "com.example.PlaniniIOS", category: "network")

private enum AppBuildConfiguration {
    private static let backendURLKey = "PlaniniBackendBaseURL"
    private static let backendURLOverrideKey = "PLANINI_BACKEND_BASE_URL_OVERRIDE"
    static let uiTestRestoreStoredSessionKey = "PLANINI_UI_TEST_RESTORE_STORED_SESSION"
    static let uiTestStoredAccessTokenOverrideKey = "PLANINI_UI_TEST_STORED_ACCESS_TOKEN_OVERRIDE"
    static let uiTestStoredDisplayNameOverrideKey = "PLANINI_UI_TEST_STORED_DISPLAY_NAME_OVERRIDE"

    static var backendURL: URL? {
        if let overriddenURL = validatedURL(from: ProcessInfo.processInfo.environment[backendURLOverrideKey]) {
            return overriddenURL
        }
        if let generatedURL = validatedURL(from: GeneratedBuildConfiguration.backendURL) {
            return generatedURL
        }
        return validatedURL(
            from: Bundle.main.object(forInfoDictionaryKey: backendURLKey) as? String
        )
    }

    private static func validatedURL(from rawValue: String?) -> URL? {
        guard
            let rawValue,
            let url = URL(string: rawValue),
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            url.host != nil
        else {
            return nil
        }
        return url
    }
}

private struct MobileListData: Codable {
    let items: [GroceryItemRecord]
    let categories: [GroceryCategorySummary]
    let categoryOrder: [ListCategoryOrderEntry]
    let disabledCategoryIDs: [UUID]

    init(
        items: [GroceryItemRecord],
        categories: [GroceryCategorySummary],
        categoryOrder: [ListCategoryOrderEntry],
        disabledCategoryIDs: [UUID] = []
    ) {
        self.items = items
        self.categories = categories
        self.categoryOrder = categoryOrder
        self.disabledCategoryIDs = disabledCategoryIDs
    }

    private enum CodingKeys: String, CodingKey {
        case items
        case categories
        case categoryOrder
        case disabledCategoryIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([GroceryItemRecord].self, forKey: .items)
        categories = try container.decode([GroceryCategorySummary].self, forKey: .categories)
        categoryOrder = try container.decode([ListCategoryOrderEntry].self, forKey: .categoryOrder)
        disabledCategoryIDs = try container.decodeIfPresent([UUID].self, forKey: .disabledCategoryIDs) ?? []
    }
}

private struct PendingItemEdit: Codable, Equatable {
    let listID: UUID
    let itemID: UUID
    var payload: GroceryItemEditPayload
    var updatedAt: Date
}

struct LinkedListNavigationRequest: Equatable {
    let id = UUID()
    let listID: UUID
}

@MainActor
final class MobileAppViewModel: ObservableObject {
    private static let favoriteListKey = "planini.favoriteListID"
    private static let authTokenKey = "planini.authToken"
    private static let displayNameKey = "planini.displayName"
    private static let quickAddItemKey = "planini.quickAddItemName"
    private static let pendingItemEditsKey = "planini.pendingItemEdits"
    private static let cachedListsKey = "planini.cachedLists"
    private static let cachedListDataPrefix = "planini.cachedListData."
    private static let passkeyTokenAllowedCharacters = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "-._~"))

    @Published private(set) var backendURL: URL?
    @Published private(set) var isAuthenticating = false
    @Published private(set) var authToken: String?
    @Published private(set) var displayName: String?
    @Published private(set) var households: [HouseholdSummary] = []
    @Published private(set) var lists: [GroceryListSummary] = []
    @Published private(set) var items: [GroceryItemRecord] = []
    @Published private(set) var categories: [GroceryCategorySummary] = []
    @Published private(set) var categoryOrder: [ListCategoryOrderEntry] = []
    @Published private(set) var disabledCategoryIDs: Set<UUID> = []
    @Published var selectedListID: UUID?
    @Published private(set) var favoriteListID: UUID?
    @Published var quickAddItemName: String
    @Published var errorMessage: String?
    @Published var reviewerOnboardingMessage: String?
    @Published private(set) var linkedListNavigationRequest: LinkedListNavigationRequest?

    private let passkeyClient: ApplePasskeyClient
    private let userDefaults: UserDefaults
    private let processInfo: ProcessInfo
    private let watchSyncCoordinator: WatchSyncCoordinator
    private let sharedStateStore: SharedAppStateStore
    private let liveUpdates: MobileListLiveUpdateClient
    private let isSimulatorBuild: Bool
    private var didAttemptLaunchBootstrap = false
    private var itemReloadGeneration = 0
    private var pendingItemEdits: [PendingItemEdit]
    private var itemEditSaveRevisions: [UUID: Int] = [:]
    private var pendingPlaniniLink: PlaniniLink?

    init(
        passkeyClient: ApplePasskeyClient = ApplePasskeyClient(),
        userDefaults: UserDefaults = .standard,
        processInfo: ProcessInfo = .processInfo,
        watchSyncCoordinator: WatchSyncCoordinator = .shared,
        liveUpdates: MobileListLiveUpdateClient = MobileListLiveUpdateClient()
    ) {
        self.passkeyClient = passkeyClient
        self.userDefaults = userDefaults
        self.processInfo = processInfo
        self.watchSyncCoordinator = watchSyncCoordinator
        self.liveUpdates = liveUpdates
        self.sharedStateStore = SharedAppStateStore(
            userDefaults: UserDefaults(suiteName: PlaniniSharedConstants.watchAppGroupID) ?? .standard
        )
        #if targetEnvironment(simulator)
            isSimulatorBuild = true
        #else
            isSimulatorBuild = false
        #endif
        backendURL = AppBuildConfiguration.backendURL
        let shouldLoadStoredSession = processInfo.environment["PLANINI_UI_TEST_MODE"] != "1"
            || processInfo.environment[AppBuildConfiguration.uiTestRestoreStoredSessionKey] == "1"
        if shouldLoadStoredSession {
            favoriteListID = userDefaults.string(forKey: Self.favoriteListKey).flatMap(UUID.init(uuidString:))
            authToken = userDefaults.string(forKey: Self.authTokenKey)
            if
                processInfo.environment["PLANINI_UI_TEST_MODE"] == "1",
                processInfo.environment[AppBuildConfiguration.uiTestRestoreStoredSessionKey] == "1",
                let tokenOverride = processInfo.environment[AppBuildConfiguration.uiTestStoredAccessTokenOverrideKey],
                tokenOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            {
                authToken = tokenOverride
                userDefaults.set(tokenOverride, forKey: Self.authTokenKey)
            }
            if
                processInfo.environment["PLANINI_UI_TEST_MODE"] == "1",
                processInfo.environment[AppBuildConfiguration.uiTestRestoreStoredSessionKey] == "1",
                let displayNameOverride = processInfo.environment[
                    AppBuildConfiguration.uiTestStoredDisplayNameOverrideKey
                ]?.trimmingCharacters(in: .whitespacesAndNewlines),
                displayNameOverride.isEmpty == false
            {
                displayName = displayNameOverride
                userDefaults.set(displayNameOverride, forKey: Self.displayNameKey)
            } else {
                displayName = userDefaults.string(forKey: Self.displayNameKey)
            }
            quickAddItemName = userDefaults.string(forKey: Self.quickAddItemKey) ?? SharedAppState.defaultQuickAddItemName
        } else {
            favoriteListID = nil
            authToken = nil
            displayName = nil
            quickAddItemName = SharedAppState.defaultQuickAddItemName
        }
        pendingItemEdits = Self.loadPendingItemEdits(from: userDefaults)
        watchSyncCoordinator.setStateProvider { [weak self] in
            let state = self?.makeSharedAppState() ?? SharedAppState()
            self?.sharedStateStore.save(state)
            return state
        }
        self.liveUpdates.onListChanged = { [weak self] listID in
            Task { @MainActor in
                await self?.handleLiveListChanged(listID)
            }
        }
        sharedStateStore.save(makeSharedAppState())
        watchSyncCoordinator.publishCurrentState()
    }

    var backendDisplayName: String {
        backendURL?.host ?? backendURL?.absoluteString ?? "Not configured"
    }

    var selectedList: GroceryListSummary? {
        lists.first { $0.id == selectedListID }
    }

    var favoriteList: GroceryListSummary? {
        lists.first { $0.id == favoriteListID }
    }

    var sortedHouseholdsForManagement: [HouseholdSummary] {
        households.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var availableCategories: [GroceryCategorySummary] {
        ListCategoryPresentation.availableCategories(
            categories: categories,
            disabledCategoryIDs: disabledCategoryIDs
        )
    }

    var categoriesForSettings: [GroceryCategorySummary] {
        ListCategoryPresentation.orderedCategories(categories: categories, categoryOrder: categoryOrder)
    }

    var sections: [GroceryItemSection] {
        GroceryItemSectionBuilder.build(
            items: items,
            categories: categories,
            categoryOrder: categoryOrder
        )
    }

    var isRunningUITests: Bool {
        processInfo.environment["PLANINI_UI_TEST_MODE"] == "1"
    }

    nonisolated static func passkeyAddToken(from rawValue: String) -> String? {
        PlaniniLinkParser.passkeyAddToken(from: rawValue)
    }

    func handleIncomingPlaniniLink(_ rawValue: String) async {
        guard let link = PlaniniLinkParser.parse(rawValue, allowedWebHosts: allowedPlaniniLinkHosts) else {
            return
        }

        switch link {
        case .passkeyAdd:
            return
        case let .invite(token):
            await acceptInviteFromLink(token: token)
        case let .list(id):
            await openListFromLink(id: id)
        }
    }

    func loginWithPasskey() async {
        guard let backendURL else {
            errorMessage = "This build is missing a backend URL configuration."
            return
        }

        netLog.debug("Starting passkey login flow for backend: \(backendURL.absoluteString, privacy: .public)")
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            try await performPasskeyLogin(backendURL: backendURL)
            reviewerOnboardingMessage = nil
            watchSyncCoordinator.publishCurrentState()
        } catch {
            let nsErr = error as NSError
            netLog.error("Passkey login failed. Type=\(String(describing: type(of: error)), privacy: .public) Domain=\(nsErr.domain, privacy: .public) Code=\(nsErr.code) Desc=\(nsErr.localizedDescription, privacy: .public)")
            reviewerOnboardingMessage = nil
            if handleSessionExpired(error) == false {
                errorMessage = nsErr.localizedDescription
            }
        }
    }

    @discardableResult
    func addPasskeyFromLinkInput(_ rawValue: String) async -> Bool {
        guard let backendURL else {
            errorMessage = "This build is missing a backend URL configuration."
            return false
        }
        guard let token = Self.passkeyAddToken(from: rawValue) else {
            errorMessage = "Enter a passkey add link or key."
            return false
        }

        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            try await ensureBackendReady(backendURL: backendURL)
            let encodedToken = token.addingPercentEncoding(withAllowedCharacters: Self.passkeyTokenAllowedCharacters) ?? token
            let options = try await requestJSON(
                backendURL: backendURL,
                path: "/api/v1/auth/passkey-add/\(encodedToken)/options",
                method: "POST",
                body: [:],
                token: nil
            )
            let relyingPartyIdentifier = rpID(from: options) ?? backendURL.host ?? ""
            #if DEBUG
            logPasskeyOptions(
                context: "add-passkey",
                backendURL: backendURL,
                optionsPayload: options,
                relyingPartyIdentifier: relyingPartyIdentifier
            )
            #endif
            let credential = try await passkeyClient.register(
                optionsPayload: options,
                relyingPartyIdentifier: relyingPartyIdentifier
            )
            _ = try await requestJSON(
                backendURL: backendURL,
                path: "/api/v1/auth/passkey-add/\(encodedToken)/verify",
                method: "POST",
                body: ["credential": credential],
                token: nil
            )

            reviewerOnboardingMessage = "Passkey added. Signing in…"
            try await performPasskeyLogin(backendURL: backendURL)
            reviewerOnboardingMessage = nil
            return true
        } catch {
            #if DEBUG
            let nsErr = error as NSError
            netLog.error(
                "Add passkey failed. type=\(String(describing: type(of: error)), privacy: .public) domain=\(nsErr.domain, privacy: .public) code=\(nsErr.code) description=\(nsErr.localizedDescription, privacy: .public) userInfo=\(String(describing: nsErr.userInfo), privacy: .public)"
            )
            #endif
            reviewerOnboardingMessage = nil
            if handleSessionExpired(error) == false {
                errorMessage = (error as NSError).localizedDescription
            }
            return false
        }
    }

    @discardableResult
    func registerAccount(displayName rawDisplayName: String, email rawEmail: String) async -> Bool {
        guard let backendURL else {
            errorMessage = "This build is missing a backend URL configuration."
            return false
        }

        let displayName = rawDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard displayName.isEmpty == false, email.isEmpty == false else {
            errorMessage = "Enter a name and email address."
            return false
        }

        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            try await ensureBackendReady(backendURL: backendURL)
            let options = try await requestJSON(
                backendURL: backendURL,
                path: "/api/v1/auth/register/options",
                method: "POST",
                body: [
                    "email": email,
                    "display_name": displayName,
                ],
                token: nil
            )
            let relyingPartyIdentifier = rpID(from: options) ?? backendURL.host ?? ""
            #if DEBUG
            logPasskeyOptions(
                context: "register",
                backendURL: backendURL,
                optionsPayload: options,
                relyingPartyIdentifier: relyingPartyIdentifier
            )
            #endif
            let credential = try await passkeyClient.register(
                optionsPayload: options,
                relyingPartyIdentifier: relyingPartyIdentifier
            )
            _ = try await requestJSON(
                backendURL: backendURL,
                path: "/api/v1/auth/register/verify",
                method: "POST",
                body: ["credential": credential],
                token: nil
            )

            reviewerOnboardingMessage = "Account created. Signing in…"
            try await performPasskeyLogin(backendURL: backendURL)
            reviewerOnboardingMessage = nil
            return true
        } catch {
            #if DEBUG
            let nsErr = error as NSError
            netLog.error(
                "Register account failed. type=\(String(describing: type(of: error)), privacy: .public) domain=\(nsErr.domain, privacy: .public) code=\(nsErr.code) description=\(nsErr.localizedDescription, privacy: .public) userInfo=\(String(describing: nsErr.userInfo), privacy: .public)"
            )
            #endif
            reviewerOnboardingMessage = nil
            if handleSessionExpired(error) == false {
                errorMessage = (error as NSError).localizedDescription
            }
            return false
        }
    }

    private func performPasskeyLogin(backendURL: URL) async throws {
        try await ensureBackendReady(backendURL: backendURL)
        let options = try await requestJSON(
            backendURL: backendURL,
            path: "/api/v1/auth/login/options",
            method: "POST",
            body: [:],
            token: nil
        )
        let relyingPartyIdentifier = rpID(from: options) ?? backendURL.host ?? ""
        #if DEBUG
        logPasskeyOptions(
            context: "login",
            backendURL: backendURL,
            optionsPayload: options,
            relyingPartyIdentifier: relyingPartyIdentifier
        )
        await logAssociatedDomainProbe(domain: relyingPartyIdentifier)
        #endif
        let credential = try await passkeyClient.authenticate(
            optionsPayload: options,
            relyingPartyIdentifier: relyingPartyIdentifier
        )
        let tokenJson = try await requestJSON(
            backendURL: backendURL,
            path: "/api/v1/auth/login/verify",
            method: "POST",
            body: ["credential": credential],
            token: nil
        )

        guard let accessToken = tokenJson["access_token"] as? String else {
            throw AppError.invalidResponse
        }

        authToken = accessToken
        userDefaults.set(accessToken, forKey: Self.authTokenKey)

        let me = try await requestJSON(
            backendURL: backendURL,
            path: "/api/v1/auth/me",
            method: "GET",
            body: nil,
            token: accessToken
        )
        displayName = me["display_name"] as? String
        userDefaults.set(displayName, forKey: Self.displayNameKey)
        try await reloadAllData()
        errorMessage = nil
        await processPendingPlaniniLinkIfPossible()
        watchSyncCoordinator.publishCurrentState()
    }

    func bootstrapLaunchSessionIfNeeded() async {
        guard didAttemptLaunchBootstrap == false else { return }
        didAttemptLaunchBootstrap = true

        let environment = processInfo.environment
        do {
            if
                environment["PLANINI_UI_TEST_MODE"] == "1",
                let accessToken = environment["PLANINI_UI_TEST_ACCESS_TOKEN"],
                accessToken.isEmpty == false
            {
                try await applyBootstrappedSession(
                    accessToken: accessToken,
                    displayNameOverride: environment["PLANINI_UI_TEST_DISPLAY_NAME"],
                    preferredListName: environment["PLANINI_UI_TEST_INITIAL_LIST_NAME"]
                )
                await handleUITestOpenURLIfNeeded()
                return
            }

            if authToken?.isEmpty == false {
                try await reloadAllData()
                errorMessage = nil
                watchSyncCoordinator.publishCurrentState()
                return
            }

            if
                isSimulatorBuild,
                let bootstrapEmail = environment["PLANINI_SIMULATOR_BOOTSTRAP_EMAIL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                bootstrapEmail.isEmpty == false
            {
                try await bootstrapSimulatorSession(
                    email: bootstrapEmail,
                    preferredListName: environment["PLANINI_SIMULATOR_INITIAL_LIST_NAME"]
                )
                await handleUITestOpenURLIfNeeded()
            }
        } catch {
            if handleSessionExpired(error) == false {
                authToken = nil
                userDefaults.removeObject(forKey: Self.authTokenKey)
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleUITestOpenURLIfNeeded() async {
        guard
            processInfo.environment["PLANINI_UI_TEST_MODE"] == "1",
            let urlString = processInfo.environment["PLANINI_UI_TEST_OPEN_URL"]?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            urlString.isEmpty == false
        else {
            return
        }
        await handleIncomingPlaniniLink(urlString)
    }

    private func bootstrapSimulatorSession(email: String, preferredListName: String?) async throws {
        guard let backendURL else {
            throw AppError.invalidResponse
        }

        let payload = try await requestJSON(
            backendURL: backendURL,
            path: "/api/v1/auth/ui-test-bootstrap",
            method: "POST",
            body: ["email": email],
            token: nil
        )

        guard let accessToken = payload["access_token"] as? String else {
            throw AppError.invalidResponse
        }

        try await applyBootstrappedSession(
            accessToken: accessToken,
            displayNameOverride: payload["display_name"] as? String,
            preferredListName: preferredListName
        )
    }

    private func applyBootstrappedSession(
        accessToken: String,
        displayNameOverride: String?,
        preferredListName: String?
    ) async throws {
        authToken = accessToken
        userDefaults.set(accessToken, forKey: Self.authTokenKey)

        if let backendURL {
            let me = try await requestJSON(
                backendURL: backendURL,
                path: "/api/v1/auth/me",
                method: "GET",
                body: nil,
                token: accessToken
            )
            displayName = me["display_name"] as? String
        } else if let displayNameOverride, displayNameOverride.isEmpty == false {
            displayName = displayNameOverride
        }

        userDefaults.set(displayName, forKey: Self.displayNameKey)

        try await reloadAllData()

        if
            let preferredListName = preferredListName?.trimmingCharacters(in: .whitespacesAndNewlines),
            preferredListName.isEmpty == false,
            let matchingList = lists.first(where: { $0.name == preferredListName })
        {
            selectedListID = matchingList.id
            setFavoriteList(id: matchingList.id)
            try await reloadItems()
        }

        errorMessage = nil
        await processPendingPlaniniLinkIfPossible()
        watchSyncCoordinator.publishCurrentState()
    }

    func signOut() {
        liveUpdates.disconnect()
        authToken = nil
        displayName = nil
        households = []
        lists = []
        items = []
        categories = []
        categoryOrder = []
        disabledCategoryIDs = []
        selectedListID = nil
        errorMessage = nil
        reviewerOnboardingMessage = nil
        userDefaults.removeObject(forKey: Self.authTokenKey)
        userDefaults.removeObject(forKey: Self.displayNameKey)
        watchSyncCoordinator.publishCurrentState()
    }

    func showFavoriteList() async {
        guard let targetID = favoriteListID else { return }
        guard lists.contains(where: { $0.id == targetID }) else { return }
        await selectList(id: targetID)
    }

    func toggleFavoriteList(id: UUID) {
        if favoriteListID == id {
            favoriteListID = nil
            userDefaults.removeObject(forKey: Self.favoriteListKey)
        } else {
            favoriteListID = id
            userDefaults.set(id.uuidString, forKey: Self.favoriteListKey)
        }
        watchSyncCoordinator.publishCurrentState()
    }

    func setFavoriteList(id: UUID) {
        favoriteListID = id
        userDefaults.set(id.uuidString, forKey: Self.favoriteListKey)
        watchSyncCoordinator.publishCurrentState()
    }

    func updateQuickAddItemName(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        quickAddItemName = trimmed.isEmpty ? SharedAppState.defaultQuickAddItemName : trimmed
        userDefaults.set(quickAddItemName, forKey: Self.quickAddItemKey)
        watchSyncCoordinator.publishCurrentState()
    }

    func isCategoryDisabled(_ categoryID: UUID) -> Bool {
        disabledCategoryIDs.contains(categoryID)
    }

    func itemCount(inCategory categoryID: UUID) -> Int {
        items.filter { $0.categoryID == categoryID }.count
    }

    func hasPendingEdit(for itemID: UUID) -> Bool {
        pendingItemEdits.contains { $0.itemID == itemID }
    }

    func moveTargetLists(for item: GroceryItemRecord) -> [GroceryListSummary] {
        guard let sourceList = lists.first(where: { $0.id == item.listID }) else {
            return lists.filter { $0.archived == false }
        }
        return lists.filter {
            $0.archived == false && $0.householdID == sourceList.householdID
        }
    }

    func reloadAllData() async throws {
        guard let backendURL, let authToken else { return }

        do {
            let householdPayloads = try await requestArray(
                backendURL: backendURL,
                path: "/api/v1/households",
                token: authToken
            )
            households = sortedHouseholds(
                householdPayloads.compactMap { HouseholdSummary(json: $0) }
            )

            var loadedLists: [GroceryListSummary] = []
            for household in householdPayloads {
                guard
                    let householdIDText = household["id"] as? String,
                    let householdID = UUID(uuidString: householdIDText),
                    let householdName = household["name"] as? String
                else {
                    continue
                }

                let householdLists = try await requestArray(
                    backendURL: backendURL,
                    path: "/api/v1/households/\(householdID.uuidString)/lists",
                    token: authToken
                )

                loadedLists.append(
                    contentsOf: householdLists.compactMap { listJSON in
                        guard
                            let idText = listJSON["id"] as? String,
                            let id = UUID(uuidString: idText),
                            let name = listJSON["name"] as? String
                        else {
                            return nil
                        }

                        return GroceryListSummary(
                            id: id,
                            householdID: householdID,
                            householdName: householdName,
                            name: name,
                            archived: (listJSON["archived"] as? Bool) ?? false
                        )
                    }
                )
            }

            lists = sortedLists(loadedLists)
            cacheLists(lists)
        } catch {
            if handleSessionExpired(error) {
                throw error
            }
            if let cachedLists = cachedLists(), cachedLists.isEmpty == false {
                lists = cachedLists
                households = sortedHouseholds(Self.households(from: cachedLists))
                errorMessage = "Offline. Showing saved list."
            } else {
                throw error
            }
        }

        if let favoriteListID, lists.contains(where: { $0.id == favoriteListID }) == false {
            self.favoriteListID = nil
            userDefaults.removeObject(forKey: Self.favoriteListKey)
        }

        if let selectedListID, lists.contains(where: { $0.id == selectedListID }) == false {
            self.selectedListID = nil
        }

        if selectedListID == nil {
            selectedListID = favoriteListID ?? lists.first?.id
        }

        try await reloadItems()
        await flushPendingItemEdits()
        updateLiveUpdatesConnection()
        watchSyncCoordinator.publishCurrentState()
    }

    @discardableResult
    func createHousehold(name rawName: String) async -> HouseholdSummary? {
        guard let backendURL, let authToken else { return nil }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else {
            errorMessage = "Enter a household name."
            return nil
        }

        do {
            let payload = try await requestJSON(
                backendURL: backendURL,
                path: "/api/v1/households",
                method: "POST",
                body: ["name": name],
                token: authToken
            )
            guard let household = HouseholdSummary(json: payload) else {
                throw AppError.invalidResponse
            }
            try await reloadAllData()
            return households.first { $0.id == household.id } ?? household
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func createList(householdID: UUID, name rawName: String) async -> GroceryListSummary? {
        guard let backendURL, let authToken else { return nil }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else {
            errorMessage = "Enter a list name."
            return nil
        }

        do {
            let payload = try await requestJSON(
                backendURL: backendURL,
                path: "/api/v1/households/\(householdID.uuidString)/lists",
                method: "POST",
                body: ["name": name],
                token: authToken
            )
            guard
                let listIDText = payload["id"] as? String,
                let listID = UUID(uuidString: listIDText)
            else {
                throw AppError.invalidResponse
            }

            try await reloadAllData()
            if lists.contains(where: { $0.id == listID }) {
                selectedListID = listID
                try await reloadItems()
            }
            return lists.first { $0.id == listID }
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func createInvite(householdID: UUID) async -> HouseholdInviteLink? {
        guard let backendURL, let authToken else { return nil }

        do {
            let payload = try await requestJSON(
                backendURL: backendURL,
                path: "/api/v1/households/\(householdID.uuidString)/invites",
                method: "POST",
                body: [:],
                token: authToken
            )
            guard let invite = HouseholdInviteLink(json: payload) else {
                throw AppError.invalidResponse
            }
            errorMessage = nil
            return invite
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func selectList(id: UUID) async {
        guard selectedListID != id else {
            updateLiveUpdatesConnection()
            return
        }
        selectedListID = id
        try? await reloadItems()
        updateLiveUpdatesConnection()
    }

    private var allowedPlaniniLinkHosts: Set<String> {
        var hosts: Set<String> = ["planini.top", "www.planini.top"]
        if let host = backendURL?.host?.lowercased(), host.isEmpty == false {
            hosts.insert(host)
        }
        return hosts
    }

    private func processPendingPlaniniLinkIfPossible() async {
        guard let pendingPlaniniLink, authToken != nil else { return }
        self.pendingPlaniniLink = nil
        switch pendingPlaniniLink {
        case .passkeyAdd:
            return
        case let .invite(token):
            await acceptInviteFromLink(token: token)
        case let .list(id):
            await openListFromLink(id: id)
        }
    }

    private func openListFromLink(id: UUID) async {
        guard authToken != nil else {
            pendingPlaniniLink = .list(id: id)
            errorMessage = "Sign in to open that list."
            return
        }

        do {
            try await reloadAllData()
            guard lists.contains(where: { $0.id == id }) else {
                errorMessage = "That list is not available for this account."
                return
            }
            await selectList(id: id)
            linkedListNavigationRequest = LinkedListNavigationRequest(listID: id)
            errorMessage = nil
            watchSyncCoordinator.publishCurrentState()
        } catch {
            errorMessage = (error as NSError).localizedDescription
        }
    }

    private func acceptInviteFromLink(token: String) async {
        guard let backendURL, let authToken else {
            pendingPlaniniLink = .invite(token: token)
            errorMessage = "Sign in to accept this invite."
            return
        }

        do {
            let encodedToken = token.addingPercentEncoding(withAllowedCharacters: Self.passkeyTokenAllowedCharacters) ?? token
            let household = try await requestJSON(
                backendURL: backendURL,
                path: "/api/v1/households/invites/\(encodedToken)/accept",
                method: "POST",
                body: [:],
                token: authToken
            )
            let householdID = (household["id"] as? String).flatMap(UUID.init(uuidString:))
            try await reloadAllData()
            if
                let householdID,
                let linkedList = lists.first(where: { $0.householdID == householdID })
            {
                await selectList(id: linkedList.id)
                linkedListNavigationRequest = LinkedListNavigationRequest(listID: linkedList.id)
            }
            errorMessage = nil
            watchSyncCoordinator.publishCurrentState()
        } catch {
            errorMessage = (error as NSError).localizedDescription
        }
    }

    func reloadItems() async throws {
        guard let backendURL, let authToken, let selectedListID else {
            itemReloadGeneration += 1
            items = []
            categories = []
            categoryOrder = []
            disabledCategoryIDs = []
            updateLiveUpdatesConnection()
            watchSyncCoordinator.publishCurrentState()
            return
        }

        itemReloadGeneration += 1
        let generation = itemReloadGeneration
        let reloadedListID = selectedListID
        let reloadedBackendURL = backendURL
        let reloadedAuthToken = authToken

        let listData: MobileListData
        do {
            listData = try await loadListData(
                backendURL: reloadedBackendURL,
                authToken: reloadedAuthToken,
                listID: reloadedListID
            )
            cacheListData(listData, listID: reloadedListID)
        } catch {
            if handleSessionExpired(error) {
                throw error
            }
            if let cachedListData = cachedListData(listID: reloadedListID) {
                listData = cachedListData
                errorMessage = "Offline. Showing saved list."
            } else {
                throw error
            }
        }

        guard
            generation == itemReloadGeneration,
            self.selectedListID == reloadedListID,
            self.backendURL == reloadedBackendURL,
            self.authToken == reloadedAuthToken
        else {
            return
        }

        applyListData(listData)
        await flushPendingItemEdits()
        updateLiveUpdatesConnection()
        watchSyncCoordinator.publishCurrentState()
    }

    @discardableResult
    func addItem(name: String, quantity: String, note: String, categoryID: UUID?) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let backendURL, let authToken, let selectedListID, trimmed.isEmpty == false else {
            return false
        }

        var body: [String: Any] = ["name": trimmed]
        body["quantity_text"] = quantity.isEmpty ? NSNull() : quantity
        body["note"] = note.isEmpty ? NSNull() : note
        body["category_id"] = categoryID?.uuidString ?? NSNull()

        do {
            _ = try await requestJSON(
                backendURL: backendURL,
                path: "/api/v1/lists/\(selectedListID.uuidString)/items",
                method: "POST",
                body: body,
                token: authToken
            )
            try await reloadItems()
            watchSyncCoordinator.publishCurrentState()
            return true
        } catch {
            if handleSessionExpired(error) == false {
                errorMessage = error.localizedDescription
            }
            return false
        }
    }

    @discardableResult
    func toggle(_ item: GroceryItemRecord) async -> Bool {
        await setChecked(itemID: item.id, checked: item.checked == false)
    }

    @discardableResult
    func setChecked(itemID: UUID, checked: Bool) async -> Bool {
        guard let backendURL, let authToken else { return false }
        let suffix = checked ? "check" : "uncheck"
        do {
            _ = try await requestJSON(
                backendURL: backendURL,
                path: "/api/v1/items/\(itemID.uuidString)/\(suffix)",
                method: "POST",
                body: [:],
                token: authToken
            )
            try await reloadItems()
            watchSyncCoordinator.publishCurrentState()
            return true
        } catch {
            if handleSessionExpired(error) == false {
                errorMessage = error.localizedDescription
            }
            return false
        }
    }

    @discardableResult
    func saveEdit(
        item: GroceryItemRecord,
        name: String,
        quantity: String,
        note: String,
        categoryID: UUID?
    ) async -> Bool {
        let payload = GroceryItemEditPayload(
            name: name,
            quantityText: quantity,
            note: note,
            categoryID: categoryID
        )
        return await saveEdit(item: item, payload: payload)
    }

    @discardableResult
    func saveEdit(item: GroceryItemRecord, payload: GroceryItemEditPayload) async -> Bool {
        guard payload.isValid else { return false }

        let revision = (itemEditSaveRevisions[item.id] ?? 0) + 1
        itemEditSaveRevisions[item.id] = revision
        applyLocalEdit(itemID: item.id, payload: payload)

        guard let backendURL, let authToken else {
            queuePendingItemEdit(listID: item.listID, itemID: item.id, payload: payload)
            return true
        }

        do {
            let saved = try await requestJSON(
                backendURL: backendURL,
                path: "/api/v1/items/\(item.id.uuidString)",
                method: "PATCH",
                body: payload.jsonBody,
                token: authToken
            )
            removePendingItemEdit(itemID: item.id)
            if itemEditSaveRevisions[item.id] == revision, let savedItem = GroceryItemRecord(json: saved) {
                upsertLocalItem(savedItem)
            }
            watchSyncCoordinator.publishCurrentState()
            return true
        } catch {
            if let appError = error as? AppError, case .sessionExpired = appError {
                queuePendingItemEdit(listID: item.listID, itemID: item.id, payload: payload)
                _ = handleSessionExpired(appError)
                return false
            }
            if itemEditSaveRevisions[item.id] == revision {
                queuePendingItemEdit(listID: item.listID, itemID: item.id, payload: payload)
                errorMessage = "Changes saved offline. They will sync when the backend is reachable."
            }
            return true
        }
    }

    @discardableResult
    func move(
        item: GroceryItemRecord,
        to targetListID: UUID,
        payload: GroceryItemEditPayload
    ) async -> GroceryItemRecord? {
        guard payload.isValid else { return nil }
        guard targetListID != item.listID else { return item }
        guard let backendURL, let authToken else {
            errorMessage = "Move items while online so both lists stay in sync."
            return nil
        }

        var body = payload.jsonBody
        body["list_id"] = targetListID.uuidString

        do {
            let saved = try await requestJSON(
                backendURL: backendURL,
                path: "/api/v1/items/\(item.id.uuidString)",
                method: "PATCH",
                body: body,
                token: authToken
            )
            removePendingItemEdit(itemID: item.id)
            let movedItem = GroceryItemRecord(json: saved)
                ?? item.applyingEditPayload(payload).moving(to: targetListID)
            if movedItem.listID == selectedListID {
                upsertLocalItem(movedItem)
            } else {
                items.removeAll { $0.id == item.id }
            }
            watchSyncCoordinator.publishCurrentState()
            return movedItem
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func delete(item: GroceryItemRecord) async -> Bool {
        guard let backendURL, let authToken else { return false }

        do {
            _ = try await requestData(
                backendURL: backendURL,
                path: "/api/v1/items/\(item.id.uuidString)",
                method: "DELETE",
                body: nil,
                token: authToken
            )
            try await reloadItems()
            watchSyncCoordinator.publishCurrentState()
            return true
        } catch {
            if handleSessionExpired(error) == false {
                errorMessage = error.localizedDescription
            }
            return false
        }
    }

    @discardableResult
    func restoreDeleted(item: GroceryItemRecord) async -> Bool {
        guard let backendURL, let authToken else { return false }

        var body: [String: Any] = [
            "name": item.name,
            "sort_order": item.sortOrder,
        ]
        body["quantity_text"] = item.quantityText ?? NSNull()
        body["note"] = item.note ?? NSNull()
        body["category_id"] = item.categoryID?.uuidString ?? NSNull()

        do {
            let createdJSON = try await requestJSON(
                backendURL: backendURL,
                path: "/api/v1/lists/\(item.listID.uuidString)/items",
                method: "POST",
                body: body,
                token: authToken
            )

            if
                item.checked,
                let createdItem = GroceryItemRecord(json: createdJSON)
            {
                _ = try await requestJSON(
                    backendURL: backendURL,
                    path: "/api/v1/items/\(createdItem.id.uuidString)/check",
                    method: "POST",
                    body: [:],
                    token: authToken
                )
            }

            try await reloadItems()
            watchSyncCoordinator.publishCurrentState()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func renameList(id listID: UUID, name rawName: String) async -> Bool {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, let backendURL, let authToken else { return false }
        guard let listIndex = lists.firstIndex(where: { $0.id == listID }) else { return false }

        do {
            let payload = try await requestJSON(
                backendURL: backendURL,
                path: "/api/v1/lists/\(listID.uuidString)",
                method: "PATCH",
                body: ["name": trimmed],
                token: authToken
            )
            let previous = lists[listIndex]
            let updatedName = (payload["name"] as? String) ?? trimmed
            lists[listIndex] = GroceryListSummary(
                id: previous.id,
                householdID: previous.householdID,
                householdName: previous.householdName,
                name: updatedName,
                archived: previous.archived
            )
            lists = sortedLists(lists)
            cacheLists(lists)
            watchSyncCoordinator.publishCurrentState()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func moveCategory(id categoryID: UUID, direction: ListCategoryMoveDirection) async -> Bool {
        guard
            let categoryIDs = ListCategoryPresentation.movedCategoryIDs(
                categories: categories,
                categoryOrder: categoryOrder,
                moving: categoryID,
                direction: direction
            )
        else {
            return false
        }

        return await saveCategoryOrder(categoryIDs: categoryIDs)
    }

    @discardableResult
    func setCategory(id categoryID: UUID, disabled: Bool) async -> Bool {
        guard categories.contains(where: { $0.id == categoryID }) else { return false }
        guard disabledCategoryIDs.contains(categoryID) != disabled else { return true }
        guard let backendURL, let authToken, let selectedListID else { return false }

        let previousDisabledCategoryIDs = disabledCategoryIDs
        if disabled {
            disabledCategoryIDs.insert(categoryID)
        } else {
            disabledCategoryIDs.remove(categoryID)
        }

        do {
            let payload = try await requestJSON(
                backendURL: backendURL,
                path: "/api/v1/lists/\(selectedListID.uuidString)/disabled-categories",
                method: "PUT",
                body: ["category_ids": disabledCategoryIDs.map(\.uuidString)],
                token: authToken
            )
            disabledCategoryIDs = Set(parseDisabledCategoryIDs(from: payload))
            try await reloadItems()
            watchSyncCoordinator.publishCurrentState()
            return true
        } catch {
            disabledCategoryIDs = previousDisabledCategoryIDs
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func makeSharedAppState() -> SharedAppState {
        let syncsFavoriteList = selectedListID == favoriteListID
        let syncedItems = syncsFavoriteList ? items : []
        let syncedCategories = syncsFavoriteList ? categories : []
        let syncedCategoryOrder = syncsFavoriteList ? categoryOrder : []
        return SharedAppState(
            backendURL: backendURL,
            authToken: authToken,
            displayName: displayName,
            favoriteListID: favoriteListID,
            quickAddItemName: quickAddItemName,
            lists: lists,
            items: syncedItems,
            categories: syncedCategories,
            categoryOrder: syncedCategoryOrder
        )
    }

    private func updateLiveUpdatesConnection() {
        guard
            let backendURL,
            let authToken,
            authToken.isEmpty == false,
            let selectedListID
        else {
            liveUpdates.disconnect()
            return
        }

        liveUpdates.connect(
            listID: selectedListID,
            backendURL: backendURL,
            authToken: authToken
        )
    }

    private func handleSessionExpired(_ error: Error) -> Bool {
        guard let appError = error as? AppError, case .sessionExpired = appError else { return false }
        expireSession()
        return true
    }

    private func expireSession() {
        liveUpdates.disconnect()
        authToken = nil
        lists = []
        items = []
        categories = []
        categoryOrder = []
        selectedListID = nil
        reviewerOnboardingMessage = nil
        userDefaults.removeObject(forKey: Self.authTokenKey)
        errorMessage = AppError.sessionExpired.errorDescription
        watchSyncCoordinator.publishCurrentState()
    }

    private func handleLiveListChanged(_ listID: UUID) async {
        guard selectedListID == listID else { return }
        netLog.debug(
            "Received live list update for selected iPhone list \(listID.uuidString, privacy: .public)."
        )
        do {
            try await reloadItems()
        } catch {
            netLog.error(
                "Failed to reload items after live update: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func loadListData(
        backendURL: URL,
        authToken: String,
        listID: UUID
    ) async throws -> MobileListData {
        async let itemPayload = requestArray(
            backendURL: backendURL,
            path: "/api/v1/lists/\(listID.uuidString)/items",
            token: authToken
        )
        async let categoryPayload = requestArray(
            backendURL: backendURL,
            path: "/api/v1/lists/\(listID.uuidString)/categories",
            token: authToken
        )
        async let categoryOrderPayload = requestArray(
            backendURL: backendURL,
            path: "/api/v1/lists/\(listID.uuidString)/category-order",
            token: authToken
        )
        async let disabledCategoriesPayload = requestJSON(
            backendURL: backendURL,
            path: "/api/v1/lists/\(listID.uuidString)/disabled-categories",
            method: "GET",
            body: nil,
            token: authToken
        )

        let loadedItems = try await itemPayload.compactMap(GroceryItemRecord.init)
        let loadedCategories = try await categoryPayload.compactMap(GroceryCategorySummary.init)
        let loadedCategoryOrder = try await categoryOrderPayload.compactMap(
            ListCategoryOrderEntry.init
        )
        let disabledCategories = try await disabledCategoriesPayload
        let loadedDisabledCategoryIDs = parseDisabledCategoryIDs(from: disabledCategories)
        return MobileListData(
            items: loadedItems,
            categories: loadedCategories,
            categoryOrder: loadedCategoryOrder,
            disabledCategoryIDs: loadedDisabledCategoryIDs
        )
    }

    private func applyListData(_ listData: MobileListData) {
        items = applyPendingItemEdits(to: listData.items)
        categories = listData.categories
        categoryOrder = listData.categoryOrder
        disabledCategoryIDs = Set(listData.disabledCategoryIDs)
    }

    private func cacheCurrentListData() {
        guard let selectedListID else { return }
        cacheListData(
            MobileListData(
                items: items,
                categories: categories,
                categoryOrder: categoryOrder,
                disabledCategoryIDs: Array(disabledCategoryIDs)
            ),
            listID: selectedListID
        )
    }

    private func parseDisabledCategoryIDs(from payload: [String: Any]) -> [UUID] {
        (payload["category_ids"] as? [String] ?? []).compactMap(UUID.init(uuidString:))
    }

    @discardableResult
    func saveCategoryOrder(categoryIDs: [UUID]) async -> Bool {
        guard let backendURL, let authToken, let selectedListID else { return false }
        let previousCategoryOrder = categoryOrder
        categoryOrder = categoryIDs.enumerated().map { index, categoryID in
            ListCategoryOrderEntry(categoryID: categoryID, sortOrder: index)
        }

        do {
            let response = try await requestArray(
                backendURL: backendURL,
                path: "/api/v1/lists/\(selectedListID.uuidString)/category-order",
                method: "PUT",
                body: ["category_ids": categoryIDs.map(\.uuidString)],
                token: authToken
            )
            categoryOrder = response.compactMap(ListCategoryOrderEntry.init)
            cacheCurrentListData()
            watchSyncCoordinator.publishCurrentState()
            return true
        } catch {
            categoryOrder = previousCategoryOrder
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func sortedLists(_ lists: [GroceryListSummary]) -> [GroceryListSummary] {
        lists.sorted {
            if $0.householdName != $1.householdName {
                return $0.householdName.localizedCaseInsensitiveCompare($1.householdName) == .orderedAscending
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func sortedHouseholds(_ households: [HouseholdSummary]) -> [HouseholdSummary] {
        households.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func households(from lists: [GroceryListSummary]) -> [HouseholdSummary] {
        let uniqueHouseholds = Dictionary(
            grouping: lists,
            by: \.householdID
        ).compactMap { householdID, lists -> HouseholdSummary? in
            guard let householdName = lists.first?.householdName else { return nil }
            return HouseholdSummary(id: householdID, name: householdName)
        }
        return uniqueHouseholds
    }

    private func cacheLists(_ lists: [GroceryListSummary]) {
        guard let data = try? JSONEncoder().encode(lists) else { return }
        userDefaults.set(data, forKey: Self.cachedListsKey)
    }

    private func cachedLists() -> [GroceryListSummary]? {
        guard let data = userDefaults.data(forKey: Self.cachedListsKey) else { return nil }
        return try? JSONDecoder().decode([GroceryListSummary].self, from: data)
    }

    private static func cachedListDataKey(listID: UUID) -> String {
        "\(cachedListDataPrefix)\(listID.uuidString)"
    }

    private func cacheListData(_ listData: MobileListData, listID: UUID) {
        guard let data = try? JSONEncoder().encode(listData) else { return }
        userDefaults.set(data, forKey: Self.cachedListDataKey(listID: listID))
    }

    private func cachedListData(listID: UUID) -> MobileListData? {
        guard let data = userDefaults.data(forKey: Self.cachedListDataKey(listID: listID)) else {
            return nil
        }
        return try? JSONDecoder().decode(MobileListData.self, from: data)
    }

    private static func loadPendingItemEdits(from userDefaults: UserDefaults) -> [PendingItemEdit] {
        guard let data = userDefaults.data(forKey: pendingItemEditsKey) else { return [] }
        return (try? JSONDecoder().decode([PendingItemEdit].self, from: data)) ?? []
    }

    private func savePendingItemEdits() {
        guard let data = try? JSONEncoder().encode(pendingItemEdits) else { return }
        userDefaults.set(data, forKey: Self.pendingItemEditsKey)
    }

    private func queuePendingItemEdit(listID: UUID, itemID: UUID, payload: GroceryItemEditPayload) {
        if let index = pendingItemEdits.firstIndex(where: { $0.itemID == itemID }) {
            pendingItemEdits[index].payload = payload
            pendingItemEdits[index].updatedAt = Date()
        } else {
            pendingItemEdits.append(
                PendingItemEdit(
                    listID: listID,
                    itemID: itemID,
                    payload: payload,
                    updatedAt: Date()
                )
            )
        }
        savePendingItemEdits()
        applyLocalEdit(itemID: itemID, payload: payload)
    }

    private func removePendingItemEdit(itemID: UUID) {
        pendingItemEdits.removeAll { $0.itemID == itemID }
        savePendingItemEdits()
    }

    private func applyPendingItemEdits(to loadedItems: [GroceryItemRecord]) -> [GroceryItemRecord] {
        guard let selectedListID else { return loadedItems }
        let pendingByItemID = Dictionary(
            uniqueKeysWithValues: pendingItemEdits
                .filter { $0.listID == selectedListID }
                .map { ($0.itemID, $0.payload) }
        )
        return loadedItems.map { item in
            guard let payload = pendingByItemID[item.id] else { return item }
            return item.applyingEditPayload(payload)
        }
    }

    private func applyLocalEdit(itemID: UUID, payload: GroceryItemEditPayload) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index] = items[index].applyingEditPayload(payload)
        watchSyncCoordinator.publishCurrentState()
    }

    private func upsertLocalItem(_ item: GroceryItemRecord) {
        guard selectedListID == item.listID else { return }
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }

    private func flushPendingItemEdits() async {
        guard let backendURL, let authToken else { return }
        for edit in pendingItemEdits.sorted(by: { $0.updatedAt < $1.updatedAt }) {
            do {
                let saved = try await requestJSON(
                    backendURL: backendURL,
                    path: "/api/v1/items/\(edit.itemID.uuidString)",
                    method: "PATCH",
                    body: edit.payload.jsonBody,
                    token: authToken
                )
                removePendingItemEdit(itemID: edit.itemID)
                if let savedItem = GroceryItemRecord(json: saved) {
                    upsertLocalItem(savedItem)
                }
            } catch {
                if handleSessionExpired(error) {
                    return
                }
                netLog.error(
                    "Pending iPhone item edit sync failed: \(error.localizedDescription, privacy: .public)"
                )
                return
            }
        }
        watchSyncCoordinator.publishCurrentState()
    }

    private func rpID(from optionsPayload: [String: Any]) -> String? {
        let publicKey = (optionsPayload["publicKey"] as? [String: Any]) ?? optionsPayload
        if let rpID = publicKey["rpId"] as? String, rpID.isEmpty == false {
            return rpID
        }
        if
            let relyingParty = publicKey["rp"] as? [String: Any],
            let rpID = relyingParty["id"] as? String,
            rpID.isEmpty == false
        {
            return rpID
        }
        return nil
    }

    #if DEBUG
    private func logPasskeyOptions(
        context: String,
        backendURL: URL,
        optionsPayload: [String: Any],
        relyingPartyIdentifier: String
    ) {
        let publicKey = (optionsPayload["publicKey"] as? [String: Any]) ?? optionsPayload
        let optionRPID = rpID(from: optionsPayload) ?? "<missing>"
        let challengeText = publicKey["challenge"] as? String ?? "<missing>"
        let allowCredentialCount = (publicKey["allowCredentials"] as? [[String: Any]])?.count ?? 0
        let userVerification = publicKey["userVerification"] as? String ?? "<missing>"
        netLog.notice(
            "Passkey options \(context, privacy: .public). backend=\(backendURL.absoluteString, privacy: .public) backendHost=\(backendURL.host ?? "<missing>", privacy: .public) optionRPID=\(optionRPID, privacy: .public) chosenRPID=\(relyingPartyIdentifier, privacy: .public) challengeLength=\(challengeText.count) allowCredentials=\(allowCredentialCount) userVerification=\(userVerification, privacy: .public)"
        )
    }

    private func logAssociatedDomainProbe(domain: String) async {
        let urls = [
            "https://\(domain)/.well-known/apple-app-site-association",
            "https://\(domain)/apple-app-site-association",
            "https://app-site-association.cdn-apple.com/a/v1/\(domain)",
        ]
        for urlText in urls {
            guard let url = URL(string: urlText) else { continue }
            do {
                var request = URLRequest(url: url)
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                let contentType = (response as? HTTPURLResponse)?.value(
                    forHTTPHeaderField: "Content-Type"
                ) ?? "<missing>"
                let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                let containsAppID = body.contains("VWKG94374J.de.malaber.planini")
                netLog.notice(
                    "AASA probe url=\(urlText, privacy: .public) status=\(status) contentType=\(contentType, privacy: .public) containsAppID=\(containsAppID) bodyPrefix=\(String(body.prefix(300)), privacy: .public)"
                )
            } catch {
                let nsErr = error as NSError
                netLog.error(
                    "AASA probe failed url=\(urlText, privacy: .public) domain=\(nsErr.domain, privacy: .public) code=\(nsErr.code) description=\(nsErr.localizedDescription, privacy: .public)"
                )
            }
        }
    }
    #endif

    private func ensureBackendReady(backendURL: URL) async throws {
        let data = try await requestData(
            backendURL: backendURL,
            path: "/health",
            method: "GET",
            body: nil,
            token: nil
        )
        guard
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let status = payload["status"] as? String,
            status == "ok"
        else {
            throw AppError.backendUnavailable(
                "The backend is not ready yet. It may still be starting or redeploying."
            )
        }
    }

    private func requestArray(
        backendURL: URL,
        path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        token: String
    ) async throws -> [[String: Any]] {
        let data = try await requestData(
            backendURL: backendURL,
            path: path,
            method: method,
            body: body,
            token: token
        )
        do {
            let obj = try JSONSerialization.jsonObject(with: data)
            guard let array = obj as? [[String: Any]] else {
                throw AppError.invalidResponse
            }
            return array
        } catch {
            netLog.error("JSON decode error: \(String(describing: error), privacy: .public). Raw: \(String(data: data, encoding: .utf8) ?? "<non-utf8>", privacy: .public)")
            throw error
        }
    }

    private func requestJSON(backendURL: URL, path: String, method: String, body: [String: Any]?, token: String?) async throws -> [String: Any] {
        let data = try await requestData(
            backendURL: backendURL,
            path: path,
            method: method,
            body: body,
            token: token
        )
        do {
            let obj = try JSONSerialization.jsonObject(with: data)
            guard let payload = obj as? [String: Any] else {
                throw AppError.invalidResponse
            }
            return payload
        } catch {
            netLog.error("JSON decode error: \(String(describing: error), privacy: .public). Raw: \(String(data: data, encoding: .utf8) ?? "<non-utf8>", privacy: .public)")
            throw error
        }
    }

    private func requestData(backendURL: URL, path: String, method: String, body: [String: Any]?, token: String?) async throws -> Data {
        var request = URLRequest(url: backendURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            if http.statusCode == 401, token != nil {
                throw AppError.sessionExpired
            }
            if let temporaryBackendError = backendAvailabilityError(response: http, data: data) {
                throw temporaryBackendError
            }
            if
                let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let detail = payload["detail"] as? String
            {
                throw AppError.server(detail)
            }
            throw AppError.server("Request failed (\(http.statusCode)).")
        }
        return data
    }

    private func backendAvailabilityError(response: HTTPURLResponse, data: Data) -> AppError? {
        let serverHeader = response.value(forHTTPHeaderField: "Server") ?? ""
        let contentType = response.value(forHTTPHeaderField: "Content-Type") ?? ""
        let bodyString = String(data: data, encoding: .utf8) ?? ""

        if response.statusCode == 501 && serverHeader.contains("BaseHTTP") {
            return .backendUnavailable(
                "The backend is not ready yet. This URL is currently serving a temporary placeholder while the deployment is rebuilding."
            )
        }
        if contentType.contains("text/html") && bodyString.contains("Unsupported method") {
            return .backendUnavailable(
                "The backend is not ready yet. This URL is currently serving a temporary placeholder while the deployment is rebuilding."
            )
        }
        return nil
    }
}

final class MobileListLiveUpdateClient {
    var onListChanged: ((UUID) -> Void)?

    private var webSocketTask: URLSessionWebSocketTask?
    private var reconnectTask: Task<Void, Never>?
    private var currentListID: UUID?
    private var backendURL: URL?
    private var authToken: String?

    func connect(listID: UUID, backendURL: URL, authToken: String) {
        if
            currentListID == listID,
            self.backendURL == backendURL,
            self.authToken == authToken,
            webSocketTask != nil
        {
            return
        }

        disconnect()
        currentListID = listID
        self.backendURL = backendURL
        self.authToken = authToken
        openSocket()
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        currentListID = nil
        backendURL = nil
        authToken = nil
    }

    private func openSocket() {
        guard
            let currentListID,
            let backendURL,
            let authToken,
            let url = makeWebSocketURL(
                backendURL: backendURL,
                listID: currentListID,
                authToken: authToken
            )
        else {
            return
        }

        netLog.debug(
            "Connecting live updates socket for iPhone list \(currentListID.uuidString, privacy: .public)."
        )
        let task = URLSession.shared.webSocketTask(with: url)
        webSocketTask = task
        task.resume()
        receiveNextMessage(from: task, listID: currentListID)
    }

    private func receiveNextMessage(from task: URLSessionWebSocketTask, listID: UUID) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(message):
                self.handle(message, for: listID)
                if self.webSocketTask === task {
                    self.receiveNextMessage(from: task, listID: listID)
                }
            case let .failure(error):
                netLog.error(
                    "iPhone live updates socket failed: \(error.localizedDescription, privacy: .public)"
                )
                self.scheduleReconnect()
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message, for listID: UUID) {
        let data: Data?
        switch message {
        case let .data(payload):
            data = payload
        case let .string(text):
            data = text.data(using: .utf8)
        @unknown default:
            data = nil
        }

        guard
            let data,
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = payload["type"] as? String
        else {
            return
        }

        let liveUpdateTypes: Set<String> = [
            "list_snapshot",
            "item_created",
            "item_updated",
            "item_checked",
            "item_unchecked",
            "item_deleted",
            "category_order_updated",
            "category_disabled_categories_updated",
        ]
        guard liveUpdateTypes.contains(type) else { return }

        netLog.debug(
            "Received iPhone live updates event \(type, privacy: .public) for list \(listID.uuidString, privacy: .public)."
        )
        onListChanged?(listID)
    }

    private func scheduleReconnect() {
        guard currentListID != nil, backendURL != nil, authToken != nil else { return }
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard Task.isCancelled == false else { return }
            self?.openSocket()
        }
    }

    private func makeWebSocketURL(
        backendURL: URL,
        listID: UUID,
        authToken: String
    ) -> URL? {
        guard var components = URLComponents(url: backendURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = backendURL.scheme == "https" ? "wss" : "ws"
        let basePath = components.path == "/" ? "" : components.path
        components.path = "\(basePath)/api/v1/ws/lists/\(listID.uuidString)"
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "token", value: authToken)
        ]
        return components.url
    }
}

enum AppError: LocalizedError {
    case invalidResponse
    case backendUnavailable(String)
    case sessionExpired
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server returned an invalid response."
        case let .backendUnavailable(message):
            return message
        case .sessionExpired:
            return "Session expired. Sign in again with your passkey."
        case let .server(message):
            return message
        }
    }
}

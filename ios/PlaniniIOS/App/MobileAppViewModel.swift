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
    static let uiTestOfflineStatusMessageKey = "PLANINI_UI_TEST_OFFLINE_STATUS_MESSAGE"
    static let uiTestPendingItemCreateNameKey = "PLANINI_UI_TEST_PENDING_ITEM_CREATE_NAME"
    static let uiTestSiriAddItemNameKey = "PLANINI_UI_TEST_SIRI_ADD_ITEM_NAME"
    static let uiTestSiriAddItemListNameKey = "PLANINI_UI_TEST_SIRI_ADD_ITEM_LIST_NAME"
    static let uiTestRestoreLocalModeKey = "PLANINI_UI_TEST_RESTORE_LOCAL_MODE"

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

private typealias MobileListData = LocalDemoListData

private struct PendingItemEdit: Codable, Equatable {
    let listID: UUID
    var itemID: UUID
    var payload: GroceryItemEditPayload
    var updatedAt: Date
}

private struct PendingItemToggle: Codable, Equatable {
    let mutationID: String
    let listID: UUID
    var itemID: UUID
    var checked: Bool
    var recordedAt: Date
}

private struct PendingItemCreate: Codable, Equatable {
    let mutationID: String
    let clientItemID: String
    let listID: UUID
    let itemID: UUID
    let name: String
    let quantityText: String?
    let note: String?
    let categoryID: UUID?
    let sortOrder: Int
    let recordedAt: Date

    var localItem: GroceryItemRecord {
        GroceryItemRecord(
            id: itemID,
            listID: listID,
            name: name,
            quantityText: quantityText,
            note: note,
            categoryID: categoryID,
            checked: false,
            checkedAt: nil,
            sortOrder: sortOrder
        )
    }
}

private struct PendingCategoryOrderSave {
    let listID: UUID
    let backendURL: URL
    let authToken: String
    let categoryIDs: [UUID]
}

enum CategoryOrderBackgroundSaveState: Equatable {
    case saved
    case saving
    case failed
}

struct LinkedListNavigationRequest: Equatable {
    let id = UUID()
    let listID: UUID
}

@MainActor
final class MobileAppViewModel: ObservableObject {
    private static let itemHideDuration: TimeInterval = 4 * 60 * 60
    private static let favoriteListKey = "planini.favoriteListID"
    private static let authTokenKey = "planini.authToken"
    private static let displayNameKey = "planini.displayName"
    private static let quickAddItemKey = "planini.quickAddItemName"
    private static let pendingItemCreatesKey = "planini.pendingItemCreates"
    private static let pendingItemEditsKey = "planini.pendingItemEdits"
    private static let pendingItemTogglesKey = "planini.pendingItemToggles"
    private static let cachedListsKey = "planini.cachedLists"
    private static let cachedListDataPrefix = "planini.cachedListData."
    private static let localModeEnabledKey = "planini.localModeEnabled"
    private static let passkeyTokenAllowedCharacters = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "-._~"))
    private static let offlineMutationDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    @Published private(set) var backendURL: URL?
    @Published private(set) var isLocalMode = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var authToken: String?
    @Published private(set) var displayName: String?
    @Published private(set) var passkeys: [PasskeyRecord] = []
    @Published private(set) var isManagingPasskeys = false
    @Published private(set) var passkeyManagementErrorMessage: String?
    @Published private(set) var households: [HouseholdSummary] = []
    @Published private(set) var membersByHousehold: [UUID: [HouseholdMemberSummary]] = [:]
    @Published private(set) var listHistory: [ListHistoryEntrySummary] = []
    @Published private(set) var listHistoryListID: UUID?
    @Published private(set) var isLoadingListHistory = false
    @Published private(set) var listHistoryErrorMessage: String?
    @Published private(set) var lists: [GroceryListSummary] = []
    @Published private(set) var items: [GroceryItemRecord] = []
    @Published private(set) var categories: [GroceryCategorySummary] = []
    @Published private(set) var categoryOrder: [ListCategoryOrderEntry] = []
    @Published private(set) var categoryOrderBackgroundSaveState: CategoryOrderBackgroundSaveState = .saved
    @Published private(set) var disabledCategoryIDs: Set<UUID> = []
    @Published var selectedListID: UUID?
    @Published private(set) var favoriteListID: UUID?
    @Published var quickAddItemName: String
    @Published var errorMessage: String?
    @Published var offlineStatusMessage: String?
    @Published var reviewerOnboardingMessage: String?
    @Published private(set) var localModeUpgradeRequestID: UUID?
    @Published private(set) var linkedListNavigationRequest: LinkedListNavigationRequest?

    private let passkeyClient: ApplePasskeyClient
    private let userDefaults: UserDefaults
    private let processInfo: ProcessInfo
    private let watchSyncCoordinator: WatchSyncCoordinator
    private let sharedStateStore: SharedAppStateStore
    private let liveUpdates: MobileListLiveUpdateClient
    private let localDemoStore: LocalDemoStore
    private let isSimulatorBuild: Bool
    private var didAttemptLaunchBootstrap = false
    private var itemReloadGeneration = 0
    private var pendingItemCreates: [PendingItemCreate]
    private var pendingItemEdits: [PendingItemEdit]
    private var pendingItemToggles: [PendingItemToggle]
    private var itemEditSaveRevisions: [UUID: Int] = [:]
    private var pendingPlaniniLink: PlaniniLink?
    private var preservesUITestOfflineStatusUntilMutation = false
    private var defersUITestPendingItemSyncUntilMutation = false
    private var pendingCategoryOrderSaves: [UUID: PendingCategoryOrderSave] = [:]
    private var pendingCategoryOrderSaveListIDs: [UUID] = []
    private var categoryOrderSaveTask: Task<Void, Never>?
    private var optimisticCategoryOrders: [UUID: [ListCategoryOrderEntry]] = [:]
    private var localDemoSnapshot: LocalDemoSnapshot?

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
        let localDemoStore = LocalDemoStore(userDefaults: userDefaults)
        self.localDemoStore = localDemoStore
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
        let shouldLoadLocalMode = processInfo.environment["PLANINI_UI_TEST_MODE"] != "1"
            || processInfo.environment[AppBuildConfiguration.uiTestRestoreLocalModeKey] == "1"
        let loadsLocalMode = shouldLoadLocalMode && userDefaults.bool(forKey: Self.localModeEnabledKey)
        isLocalMode = loadsLocalMode
        if loadsLocalMode {
            localDemoSnapshot = localDemoStore.loadOrSeed()
        }
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
        pendingItemCreates = Self.loadPendingItemCreates(from: userDefaults)
        pendingItemEdits = Self.loadPendingItemEdits(from: userDefaults)
        pendingItemToggles = Self.loadPendingItemToggles(from: userDefaults)
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
        if isLocalMode {
            return "On this iPhone"
        }
        return backendURL?.host ?? backendURL?.absoluteString ?? "Not configured"
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

    func role(for householdID: UUID) -> HouseholdRole {
        households.first { $0.id == householdID }?.role ?? .viewer
    }

    func canEdit(listID: UUID) -> Bool {
        guard let list = lists.first(where: { $0.id == listID }) else {
            return false
        }
        return list.accessRole.canEditItems
    }

    func canManage(householdID: UUID) -> Bool {
        role(for: householdID).canManageHousehold
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

    func startLocalDemo() {
        liveUpdates.disconnect()
        isLocalMode = true
        userDefaults.set(true, forKey: Self.localModeEnabledKey)
        let snapshot = localDemoStore.loadOrSeed()
        localDemoSnapshot = snapshot
        applyLocalDemoSnapshot(snapshot)
        errorMessage = nil
        reviewerOnboardingMessage = nil
        watchSyncCoordinator.publishCurrentState()
    }

    func requestLocalModeAccountCreation() {
        guard isLocalMode else { return }
        localModeUpgradeRequestID = UUID()
    }

    private func applyLocalDemoSnapshot(_ snapshot: LocalDemoSnapshot) {
        households = sortedHouseholds(snapshot.households)
        lists = sortedLists(snapshot.lists)
        favoriteListID = snapshot.favoriteListID
        selectedListID = snapshot.selectedListID.flatMap { selectedID in
            lists.contains(where: { $0.id == selectedID }) ? selectedID : nil
        } ?? favoriteListID ?? lists.first?.id
        displayName = "Local demo"
        if
            let selectedListID,
            let selectedData = snapshot.listData[selectedListID]
        {
            applyLocalDemoListData(selectedData)
        } else {
            items = []
            categories = []
            categoryOrder = []
            disabledCategoryIDs = []
        }
    }

    private func persistLocalDemoState() {
        guard isLocalMode, var snapshot = localDemoSnapshot else { return }
        snapshot.households = households
        snapshot.lists = lists
        snapshot.favoriteListID = favoriteListID
        snapshot.selectedListID = selectedListID
        if let selectedListID {
            snapshot.listData[selectedListID] = MobileListData(
                items: items,
                categories: categories,
                categoryOrder: categoryOrder,
                disabledCategoryIDs: Array(disabledCategoryIDs)
            )
        }
        saveLocalDemoSnapshot(snapshot)
    }

    private func saveLocalDemoSnapshot(_ snapshot: LocalDemoSnapshot) {
        localDemoSnapshot = snapshot
        localDemoStore.save(snapshot)
    }

    private func localDemoTemplateData() -> MobileListData {
        if let data = localDemoSnapshot?.listData.values.first {
            return MobileListData(
                items: [],
                categories: data.categories,
                categoryOrder: data.categoryOrder,
                disabledCategoryIDs: []
            )
        }
        let seeded = LocalDemoSnapshot.seeded()
        let data = seeded.listData.values.first!
        return MobileListData(
            items: [],
            categories: data.categories,
            categoryOrder: data.categoryOrder,
            disabledCategoryIDs: []
        )
    }

    nonisolated static func passkeyAddToken(from rawValue: String) -> String? {
        PlaniniLinkParser.passkeyAddToken(from: rawValue)
    }

    func handleIncomingPlaniniLink(_ rawValue: String) async {
        guard let link = PlaniniLinkParser.parse(rawValue, allowedWebHosts: allowedPlaniniLinkHosts) else {
            return
        }

        if isLocalMode {
            switch link {
            case .passkeyAdd:
                break
            case .invite, .list:
                requestLocalModeAccountCreation()
                return
            }
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
        if isLocalMode, authToken?.isEmpty == false {
            return await syncLocalDemoDataToAuthenticatedAccount()
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
            try await performPasskeyLogin(backendURL: backendURL, reloadData: isLocalMode == false)
            if isLocalMode {
                reviewerOnboardingMessage = "Account created. Syncing local data…"
                guard await syncLocalDemoDataToAuthenticatedAccount() else {
                    return false
                }
            }
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

    @discardableResult
    func loadPasskeys() async -> Bool {
        await performPasskeyManagement { service in
            passkeys = try await service.listPasskeys()
        }
    }

    @discardableResult
    func addPasskey(name: String) async -> Bool {
        await performPasskeyManagement { service in
            let added = try await service.addPasskey(name: name)
            passkeys.removeAll { $0.id == added.id }
            passkeys.append(added)
        }
    }

    @discardableResult
    func renamePasskey(_ passkey: PasskeyRecord, name: String) async -> Bool {
        await performPasskeyManagement { service in
            let renamed = try await service.renamePasskey(id: passkey.id, name: name)
            if let index = passkeys.firstIndex(where: { $0.id == renamed.id }) {
                passkeys[index] = renamed
            } else {
                passkeys.append(renamed)
            }
        }
    }

    @discardableResult
    func deletePasskey(_ passkey: PasskeyRecord) async -> Bool {
        await performPasskeyManagement { service in
            try await service.deletePasskey(id: passkey.id)
            passkeys.removeAll { $0.id == passkey.id }
            do {
                passkeys = try await service.listPasskeys()
            } catch {
                if let appError = error as? AppError, case .sessionExpired = appError {
                    throw appError
                }
            }
        }
    }

    private func performPasskeyManagement(
        operation: (PasskeyManagementService) async throws -> Void
    ) async -> Bool {
        guard isManagingPasskeys == false else { return false }
        guard let backendURL, let authToken else {
            passkeyManagementErrorMessage = AppError.sessionExpired.localizedDescription
            return false
        }

        isManagingPasskeys = true
        passkeyManagementErrorMessage = nil
        defer { isManagingPasskeys = false }

        do {
            try await ensureBackendReady(backendURL: backendURL)
            let service = PasskeyManagementService(
                backendURL: backendURL,
                accessToken: authToken,
                transport: AppPasskeyManagementTransport(backendURL: backendURL),
                credentialProvider: passkeyClient
            )
            try await operation(service)
            return true
        } catch {
            if handleSessionExpired(error) == false {
                passkeyManagementErrorMessage = error.localizedDescription
            }
            return false
        }
    }

    private func performPasskeyLogin(backendURL: URL, reloadData: Bool = true) async throws {
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
        if reloadData {
            try await reloadAllData()
        }
        errorMessage = nil
        await processPendingPlaniniLinkIfPossible()
        watchSyncCoordinator.publishCurrentState()
    }

    func bootstrapLaunchSessionIfNeeded() async {
        guard didAttemptLaunchBootstrap == false else { return }
        didAttemptLaunchBootstrap = true

        let environment = processInfo.environment
        do {
            if isLocalMode {
                let snapshot = localDemoSnapshot ?? localDemoStore.loadOrSeed()
                localDemoSnapshot = snapshot
                applyLocalDemoSnapshot(snapshot)
                return
            }

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
                await runUITestSiriAddItemIfNeeded()
                return
            }

            if authToken?.isEmpty == false {
                try await reloadAllData()
                errorMessage = nil
                watchSyncCoordinator.publishCurrentState()
                await runUITestSiriAddItemIfNeeded()
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
                await runUITestSiriAddItemIfNeeded()
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

    private func runUITestSiriAddItemIfNeeded() async {
        guard
            processInfo.environment["PLANINI_UI_TEST_MODE"] == "1",
            let rawName = processInfo.environment[AppBuildConfiguration.uiTestSiriAddItemNameKey]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            rawName.isEmpty == false
        else {
            return
        }

        let requestedListID: UUID?
        if
            let listName = processInfo.environment[AppBuildConfiguration.uiTestSiriAddItemListNameKey]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            listName.isEmpty == false
        {
            guard let matchingList = lists.first(where: { $0.name == listName }) else {
                errorMessage = "UI test Siri list not found: \(listName)"
                return
            }
            requestedListID = matchingList.id
        } else {
            requestedListID = nil
        }

        do {
            sharedStateStore.save(makeSharedAppState())
            let result = try await PlaniniIntentAddItemExecutor().addItem(
                named: rawName,
                requestedListID: requestedListID
            )
            if result.list.id == selectedListID {
                try await reloadItems()
            }
            watchSyncCoordinator.publishCurrentState()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
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

        if let displayNameOverride, displayNameOverride.isEmpty == false {
            displayName = displayNameOverride
        } else if let backendURL {
            let me = try await requestJSON(
                backendURL: backendURL,
                path: "/api/v1/auth/me",
                method: "GET",
                body: nil,
                token: accessToken
            )
            displayName = me["display_name"] as? String
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
        applyUITestPendingItemCreateIfNeeded()
        applyUITestOfflineStatusOverrideIfNeeded()
        await processPendingPlaniniLinkIfPossible()
        watchSyncCoordinator.publishCurrentState()
    }

    func signOut() {
        liveUpdates.disconnect()
        isLocalMode = false
        authToken = nil
        displayName = nil
        passkeys = []
        passkeyManagementErrorMessage = nil
        households = []
        membersByHousehold = [:]
        listHistory = []
        listHistoryListID = nil
        isLoadingListHistory = false
        listHistoryErrorMessage = nil
        lists = []
        items = []
        categories = []
        categoryOrder = []
        categoryOrderBackgroundSaveState = .saved
        categoryOrderSaveTask?.cancel()
        categoryOrderSaveTask = nil
        pendingCategoryOrderSaves = [:]
        pendingCategoryOrderSaveListIDs = []
        optimisticCategoryOrders = [:]
        disabledCategoryIDs = []
        selectedListID = nil
        errorMessage = nil
        offlineStatusMessage = nil
        reviewerOnboardingMessage = nil
        localModeUpgradeRequestID = nil
        userDefaults.removeObject(forKey: Self.localModeEnabledKey)
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
        persistLocalDemoState()
        watchSyncCoordinator.publishCurrentState()
    }

    func setFavoriteList(id: UUID) {
        favoriteListID = id
        userDefaults.set(id.uuidString, forKey: Self.favoriteListKey)
        persistLocalDemoState()
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
        if isLocalMode {
            persistLocalDemoState()
            if let snapshot = localDemoSnapshot {
                applyLocalDemoSnapshot(snapshot)
            }
            return
        }
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
                            archived: (listJSON["archived"] as? Bool) ?? false,
                            accentColorHex: listJSON["accent_color"] as? String,
                            accessRole: (listJSON["access_role"] as? String)
                                .flatMap(HouseholdRole.init(rawValue:))
                                ?? (household["role"] as? String)
                                    .flatMap(HouseholdRole.init(rawValue:))
                                ?? .editor
                        )
                    }
                )
            }

            lists = sortedLists(loadedLists)
            cacheLists(lists)
            clearOfflineStatusAfterRead()
        } catch {
            if handleSessionExpired(error) {
                throw error
            }
            if
                isOfflineError(error),
                let cachedLists = cachedLists(),
                cachedLists.isEmpty == false
            {
                lists = cachedLists
                households = sortedHouseholds(Self.households(from: cachedLists))
                showOfflineStatus("Offline. Showing saved list.", cause: error)
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
        await flushPendingItemToggles()
        updateLiveUpdatesConnection()
        watchSyncCoordinator.publishCurrentState()
    }

    @discardableResult
    func createHousehold(name rawName: String) async -> HouseholdSummary? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else {
            errorMessage = "Enter a household name."
            return nil
        }
        if isLocalMode {
            let household = HouseholdSummary(id: UUID(), name: name, role: .owner)
            households.append(household)
            households = sortedHouseholds(households)
            persistLocalDemoState()
            return household
        }
        guard let backendURL, let authToken else { return nil }

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
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else {
            errorMessage = "Enter a list name."
            return nil
        }
        if isLocalMode {
            guard
                let household = households.first(where: { $0.id == householdID }),
                var snapshot = localDemoSnapshot
            else {
                return nil
            }
            persistLocalDemoState()
            snapshot = localDemoSnapshot ?? snapshot
            let list = GroceryListSummary(
                id: UUID(),
                householdID: householdID,
                householdName: household.name,
                name: name,
                archived: false,
                accessRole: .owner
            )
            lists.append(list)
            lists = sortedLists(lists)
            snapshot.lists = lists
            snapshot.listData[list.id] = localDemoTemplateData()
            snapshot.selectedListID = list.id
            selectedListID = list.id
            saveLocalDemoSnapshot(snapshot)
            applyLocalDemoListData(snapshot.listData[list.id]!)
            watchSyncCoordinator.publishCurrentState()
            return list
        }
        guard let backendURL, let authToken else { return nil }

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

    func createInvite(
        householdID: UUID,
        role: HouseholdRole = .editor,
        expiresInHours: Int? = 24,
        maxUses: Int? = nil
    ) async -> HouseholdInviteLink? {
        if isLocalMode {
            requestLocalModeAccountCreation()
            return nil
        }
        guard let backendURL, let authToken else { return nil }

        var inviteBody: [String: Any] = [:]
        if let expiresInHours {
            inviteBody["expires_in_hours"] = expiresInHours
        } else {
            inviteBody["expires_in_hours"] = NSNull()
        }
        if let maxUses {
            inviteBody["max_uses"] = maxUses
        }
        inviteBody["role"] = role.rawValue

        do {
            let payload = try await requestJSON(
                backendURL: backendURL,
                path: "/api/v1/households/\(householdID.uuidString)/invites",
                method: "POST",
                body: inviteBody,
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

    func loadHouseholdMembers(householdID: UUID) async {
        guard let backendURL, let authToken else { return }
        do {
            let payload = try await requestArray(
                backendURL: backendURL,
                path: "/api/v1/households/\(householdID.uuidString)/members",
                token: authToken
            )
            membersByHousehold[householdID] = payload.compactMap(HouseholdMemberSummary.init(json:))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadListHistory(listID: UUID) async {
        listHistoryListID = listID
        listHistoryErrorMessage = nil
        if isLocalMode {
            listHistory = []
            isLoadingListHistory = false
            return
        }
        guard let backendURL, let authToken else {
            listHistory = []
            isLoadingListHistory = false
            return
        }

        isLoadingListHistory = true
        defer {
            if listHistoryListID == listID {
                isLoadingListHistory = false
            }
        }
        do {
            let payload = try await requestArray(
                backendURL: backendURL,
                path: "/api/v1/lists/\(listID.uuidString)/history",
                token: authToken
            )
            guard listHistoryListID == listID else { return }
            listHistory = payload.compactMap(ListHistoryEntrySummary.init(json:))
        } catch {
            guard listHistoryListID == listID else { return }
            listHistory = []
            if handleSessionExpired(error) == false {
                listHistoryErrorMessage = error.localizedDescription
            }
        }
    }

    @discardableResult
    func updateHouseholdMemberRole(
        householdID: UUID,
        userID: UUID,
        role: HouseholdRole
    ) async -> Bool {
        guard let backendURL, let authToken, role != .owner else { return false }
        do {
            _ = try await requestJSON(
                backendURL: backendURL,
                path: "/api/v1/households/\(householdID.uuidString)/members/\(userID.uuidString)",
                method: "PATCH",
                body: ["role": role.rawValue],
                token: authToken
            )
            await loadHouseholdMembers(householdID: householdID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func removeHouseholdMember(householdID: UUID, userID: UUID) async -> Bool {
        guard let backendURL, let authToken else { return false }
        do {
            _ = try await requestJSON(
                backendURL: backendURL,
                path: "/api/v1/households/\(householdID.uuidString)/members/\(userID.uuidString)",
                method: "DELETE",
                body: nil,
                token: authToken
            )
            await loadHouseholdMembers(householdID: householdID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func selectList(id: UUID) async {
        if isLocalMode {
            guard lists.contains(where: { $0.id == id }) else { return }
            persistLocalDemoState()
            selectedListID = id
            if let data = localDemoSnapshot?.listData[id] {
                applyLocalDemoListData(data)
            }
            persistLocalDemoState()
            watchSyncCoordinator.publishCurrentState()
            return
        }
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
        if isLocalMode {
            requestLocalModeAccountCreation()
            return
        }
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
        if isLocalMode {
            requestLocalModeAccountCreation()
            return
        }
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
        if isLocalMode {
            guard
                let selectedListID,
                let data = localDemoSnapshot?.listData[selectedListID]
            else {
                items = []
                categories = []
                categoryOrder = []
                disabledCategoryIDs = []
                return
            }
            applyLocalDemoListData(data)
            watchSyncCoordinator.publishCurrentState()
            return
        }
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
            clearOfflineStatusAfterRead()
        } catch {
            if handleSessionExpired(error) {
                throw error
            }
            if isOfflineError(error), let cachedListData = cachedListData(listID: reloadedListID) {
                listData = cachedListData
                showOfflineStatus("Offline. Showing saved list.", cause: error)
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
        await flushPendingItemCreates()
        await flushPendingItemEdits()
        await flushPendingItemToggles()
        updateLiveUpdatesConnection()
        watchSyncCoordinator.publishCurrentState()
    }

    @discardableResult
    func addItem(name: String, quantity: String, note: String, categoryID: UUID?) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let selectedListID, trimmed.isEmpty == false else {
            return false
        }
        defersUITestPendingItemSyncUntilMutation = false
        let quantityText = quantity.isEmpty ? nil : quantity
        let noteText = note.isEmpty ? nil : note

        if isLocalMode {
            let item = GroceryItemRecord(
                id: UUID(),
                listID: selectedListID,
                name: trimmed,
                quantityText: quantityText,
                note: noteText,
                categoryID: categoryID,
                checked: false,
                checkedAt: nil,
                sortOrder: (items.map(\.sortOrder).max() ?? -1) + 1
            )
            upsertLocalItem(item)
            persistLocalDemoState()
            watchSyncCoordinator.publishCurrentState()
            return true
        }

        func queueOfflineCreate() {
            queuePendingItemCreate(
                listID: selectedListID,
                name: trimmed,
                quantityText: quantityText,
                note: noteText,
                categoryID: categoryID
            )
            showOfflineStatus("Changes saved offline. They will sync when the backend is reachable.")
        }

        guard let backendURL, let authToken else {
            queueOfflineCreate()
            return true
        }

        var body: [String: Any] = ["name": trimmed]
        body["quantity_text"] = quantityText ?? NSNull()
        body["note"] = noteText ?? NSNull()
        body["category_id"] = categoryID?.uuidString ?? NSNull()

        let createdPayload: [String: Any]
        do {
            createdPayload = try await requestJSON(
                backendURL: backendURL,
                path: "/api/v1/lists/\(selectedListID.uuidString)/items",
                method: "POST",
                body: body,
                token: authToken
            )
        } catch {
            if handleSessionExpired(error) {
                return false
            }
            guard isOfflineError(error) else {
                errorMessage = error.localizedDescription
                return false
            }
            queuePendingItemCreate(
                listID: selectedListID,
                name: trimmed,
                quantityText: quantityText,
                note: noteText,
                categoryID: categoryID
            )
            showOfflineStatus(
                "Changes saved offline. They will sync when the backend is reachable.",
                cause: error
            )
            return true
        }

        if let createdItem = GroceryItemRecord(json: createdPayload) {
            upsertLocalItem(createdItem)
            cacheCurrentListData()
        }
        do {
            try await reloadItems()
        } catch {
            netLog.error(
                "Item saved, but post-create refresh failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        clearOfflineStatus()
        watchSyncCoordinator.publishCurrentState()
        return true
    }

    @discardableResult
    func toggle(_ item: GroceryItemRecord) async -> Bool {
        await setChecked(itemID: item.id, checked: item.checked == false)
    }

    @discardableResult
    func setChecked(itemID: UUID, checked: Bool) async -> Bool {
        guard let item = items.first(where: { $0.id == itemID }) else { return false }
        let recordedAt = Date()

        if isLocalMode {
            applyLocalToggle(itemID: itemID, checked: checked, recordedAt: recordedAt)
            persistLocalDemoState()
            watchSyncCoordinator.publishCurrentState()
            return true
        }

        func queueOfflineToggle() {
            queuePendingItemToggle(listID: item.listID, itemID: itemID, checked: checked, recordedAt: recordedAt)
            showOfflineStatus("Changes saved offline. They will sync when the backend is reachable.")
        }

        guard let backendURL, let authToken else {
            queueOfflineToggle()
            return true
        }
        let suffix = checked ? "check" : "uncheck"
        do {
            let saved = try await requestJSON(
                backendURL: backendURL,
                path: "/api/v1/items/\(itemID.uuidString)/\(suffix)",
                method: "POST",
                body: [:],
                token: authToken
            )
            if let savedItem = GroceryItemRecord(json: saved) {
                upsertLocalItem(savedItem)
            } else {
                applyLocalToggle(itemID: itemID, checked: checked, recordedAt: recordedAt)
            }
            removePendingItemToggles(itemID: itemID)
            cacheCurrentListData()
            clearOfflineStatus()
            watchSyncCoordinator.publishCurrentState()
            return true
        } catch {
            if handleSessionExpired(error) {
                return false
            }
            guard isOfflineError(error) else {
                errorMessage = error.localizedDescription
                return false
            }
            queuePendingItemToggle(
                listID: item.listID,
                itemID: itemID,
                checked: checked,
                recordedAt: recordedAt
            )
            showOfflineStatus(
                "Changes saved offline. They will sync when the backend is reachable.",
                cause: error
            )
            return true
        }
    }

    @discardableResult
    func hideForLater(_ item: GroceryItemRecord, now: Date = Date()) async -> Bool {
        guard item.checked == false else { return false }
        return await setHiddenUntil(
            itemID: item.id,
            hiddenUntil: now.addingTimeInterval(Self.itemHideDuration)
        )
    }

    @discardableResult
    func restoreHiddenItem(_ item: GroceryItemRecord) async -> Bool {
        await setHiddenUntil(itemID: item.id, hiddenUntil: nil)
    }

    @discardableResult
    func setHiddenUntil(itemID: UUID, hiddenUntil: Date?) async -> Bool {
        if isLocalMode {
            guard
                let index = items.firstIndex(where: { $0.id == itemID })
            else {
                return false
            }
            let item = items[index]
            items[index] = GroceryItemRecord(
                id: item.id,
                listID: item.listID,
                name: item.name,
                quantityText: item.quantityText,
                note: item.note,
                categoryID: item.categoryID,
                checked: item.checked,
                checkedAt: item.checkedAt,
                hiddenUntil: hiddenUntil,
                sortOrder: item.sortOrder
            )
            persistLocalDemoState()
            watchSyncCoordinator.publishCurrentState()
            return true
        }
        guard let backendURL, let authToken else { return false }
        let hiddenUntilBodyValue: Any
        if let hiddenUntil {
            hiddenUntilBodyValue = apiTimestamp(from: hiddenUntil)
        } else {
            hiddenUntilBodyValue = NSNull()
        }

        do {
            let saved = try await requestJSON(
                backendURL: backendURL,
                path: "/api/v1/items/\(itemID.uuidString)",
                method: "PATCH",
                body: ["hidden_until": hiddenUntilBodyValue],
                token: authToken
            )
            if let savedItem = GroceryItemRecord(json: saved) {
                upsertLocalItem(savedItem)
            } else {
                try await reloadItems()
            }
            clearOfflineStatus()
            watchSyncCoordinator.publishCurrentState()
            return true
        } catch {
            errorMessage = error.localizedDescription
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

        if isLocalMode {
            persistLocalDemoState()
            watchSyncCoordinator.publishCurrentState()
            return true
        }

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
            clearOfflineStatus()
            watchSyncCoordinator.publishCurrentState()
            return true
        } catch {
            if let appError = error as? AppError, case .sessionExpired = appError {
                queuePendingItemEdit(listID: item.listID, itemID: item.id, payload: payload)
                _ = handleSessionExpired(appError)
                return false
            }
            guard itemEditSaveRevisions[item.id] == revision else { return true }
            guard isOfflineError(error) else {
                errorMessage = error.localizedDescription
                return false
            }
            queuePendingItemEdit(listID: item.listID, itemID: item.id, payload: payload)
            showOfflineStatus(
                "Changes saved offline. They will sync when the backend is reachable.",
                cause: error
            )
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
        if isLocalMode {
            guard
                var snapshot = localDemoSnapshot,
                let targetData = snapshot.listData[targetListID]
            else {
                return nil
            }
            let movedItem = item.applyingEditPayload(payload).moving(to: targetListID)
            items.removeAll { $0.id == item.id }
            snapshot.listData[item.listID] = MobileListData(
                items: items,
                categories: categories,
                categoryOrder: categoryOrder,
                disabledCategoryIDs: Array(disabledCategoryIDs)
            )
            var targetItems = targetData.items
            targetItems.removeAll { $0.id == movedItem.id }
            targetItems.append(movedItem)
            snapshot.listData[targetListID] = MobileListData(
                items: targetItems,
                categories: targetData.categories,
                categoryOrder: targetData.categoryOrder,
                disabledCategoryIDs: targetData.disabledCategoryIDs
            )
            saveLocalDemoSnapshot(snapshot)
            watchSyncCoordinator.publishCurrentState()
            return movedItem
        }
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
            clearOfflineStatus()
            watchSyncCoordinator.publishCurrentState()
            return movedItem
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func delete(item: GroceryItemRecord) async -> Bool {
        if isLocalMode {
            items.removeAll { $0.id == item.id }
            persistLocalDemoState()
            watchSyncCoordinator.publishCurrentState()
            return true
        }
        guard let backendURL, let authToken else { return false }

        do {
            _ = try await requestData(
                backendURL: backendURL,
                path: "/api/v1/items/\(item.id.uuidString)",
                method: "DELETE",
                body: nil,
                token: authToken
            )
            items.removeAll { $0.id == item.id }
            clearOfflineStatus()
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
        if isLocalMode {
            upsertLocalItem(item)
            persistLocalDemoState()
            watchSyncCoordinator.publishCurrentState()
            return true
        }
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
        guard trimmed.isEmpty == false else { return false }
        guard let listIndex = lists.firstIndex(where: { $0.id == listID }) else { return false }
        if isLocalMode {
            let previous = lists[listIndex]
            lists[listIndex] = GroceryListSummary(
                id: previous.id,
                householdID: previous.householdID,
                householdName: previous.householdName,
                name: trimmed,
                archived: previous.archived,
                accentColorHex: previous.accentColorHex
            )
            lists = sortedLists(lists)
            persistLocalDemoState()
            watchSyncCoordinator.publishCurrentState()
            return true
        }
        guard let backendURL, let authToken else { return false }

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
                archived: (payload["archived"] as? Bool) ?? previous.archived,
                accentColorHex: resolvedAccentColorHex(
                    from: payload,
                    fallback: previous.accentColorHex
                ),
                accessRole: previous.accessRole
            )
            lists = sortedLists(lists)
            cacheLists(lists)
            clearOfflineStatus()
            watchSyncCoordinator.publishCurrentState()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func updateListAccentColor(id listID: UUID, accentColorHex: String?) async -> Bool {
        guard let listIndex = lists.firstIndex(where: { $0.id == listID }) else { return false }
        if isLocalMode {
            let previous = lists[listIndex]
            lists[listIndex] = GroceryListSummary(
                id: previous.id,
                householdID: previous.householdID,
                householdName: previous.householdName,
                name: previous.name,
                archived: previous.archived,
                accentColorHex: accentColorHex
            )
            lists = sortedLists(lists)
            persistLocalDemoState()
            watchSyncCoordinator.publishCurrentState()
            return true
        }
        guard let backendURL, let authToken else { return false }

        var body: [String: Any] = [:]
        body["accent_color"] = accentColorHex ?? NSNull()

        do {
            let payload = try await requestJSON(
                backendURL: backendURL,
                path: "/api/v1/lists/\(listID.uuidString)",
                method: "PATCH",
                body: body,
                token: authToken
            )
            let previous = lists[listIndex]
            lists[listIndex] = GroceryListSummary(
                id: previous.id,
                householdID: previous.householdID,
                householdName: previous.householdName,
                name: (payload["name"] as? String) ?? previous.name,
                archived: (payload["archived"] as? Bool) ?? previous.archived,
                accentColorHex: resolvedAccentColorHex(from: payload, fallback: accentColorHex),
                accessRole: previous.accessRole
            )
            lists = sortedLists(lists)
            cacheLists(lists)
            clearOfflineStatus()
            watchSyncCoordinator.publishCurrentState()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func resolvedAccentColorHex(
        from payload: [String: Any],
        fallback: String?
    ) -> String? {
        guard payload.keys.contains("accent_color") else { return fallback }
        return payload["accent_color"] as? String
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

        let previousDisabledCategoryIDs = disabledCategoryIDs
        if disabled {
            disabledCategoryIDs.insert(categoryID)
        } else {
            disabledCategoryIDs.remove(categoryID)
        }
        if isLocalMode {
            if disabled {
                items = items.map { item in
                    guard item.categoryID == categoryID else { return item }
                    return GroceryItemRecord(
                        id: item.id,
                        listID: item.listID,
                        name: item.name,
                        quantityText: item.quantityText,
                        note: item.note,
                        categoryID: nil,
                        checked: item.checked,
                        checkedAt: item.checkedAt,
                        hiddenUntil: item.hiddenUntil,
                        sortOrder: item.sortOrder
                    )
                }
            }
            persistLocalDemoState()
            watchSyncCoordinator.publishCurrentState()
            return true
        }
        guard let backendURL, let authToken, let selectedListID else {
            disabledCategoryIDs = previousDisabledCategoryIDs
            return false
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
            clearOfflineStatus()
            watchSyncCoordinator.publishCurrentState()
            return true
        } catch {
            disabledCategoryIDs = previousDisabledCategoryIDs
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func syncLocalDemoDataToAuthenticatedAccount() async -> Bool {
        guard
            isLocalMode,
            let backendURL,
            let authToken
        else {
            return false
        }
        persistLocalDemoState()
        guard let snapshot = localDemoSnapshot else { return false }

        do {
            let mappedListIDs = try await uploadLocalDemoSnapshot(
                snapshot,
                backendURL: backendURL,
                authToken: authToken
            )
            let mappedFavoriteListID = snapshot.favoriteListID.flatMap { mappedListIDs[$0] }
            let mappedSelectedListID = snapshot.selectedListID.flatMap { mappedListIDs[$0] }

            isLocalMode = false
            localModeUpgradeRequestID = nil
            userDefaults.removeObject(forKey: Self.localModeEnabledKey)
            localDemoStore.clear()
            localDemoSnapshot = nil
            favoriteListID = mappedFavoriteListID
            if let mappedFavoriteListID {
                userDefaults.set(mappedFavoriteListID.uuidString, forKey: Self.favoriteListKey)
            } else {
                userDefaults.removeObject(forKey: Self.favoriteListKey)
            }

            try await reloadAllData()
            if let mappedSelectedListID, lists.contains(where: { $0.id == mappedSelectedListID }) {
                selectedListID = mappedSelectedListID
                try await reloadItems()
            }
            reviewerOnboardingMessage = nil
            errorMessage = nil
            watchSyncCoordinator.publishCurrentState()
            return true
        } catch {
            reviewerOnboardingMessage = nil
            if handleSessionExpired(error) == false {
                errorMessage = "Account is ready, but local data could not sync: \(error.localizedDescription)"
            }
            return false
        }
    }

    private func uploadLocalDemoSnapshot(
        _ snapshot: LocalDemoSnapshot,
        backendURL: URL,
        authToken: String
    ) async throws -> [UUID: UUID] {
        var remoteHouseholds = try await requestArray(
            backendURL: backendURL,
            path: "/api/v1/households",
            token: authToken
        )
        var mappedListIDs: [UUID: UUID] = [:]

        for localHousehold in snapshot.households {
            let remoteHousehold: [String: Any]
            if let existing = remoteHouseholds.first(where: {
                normalizedSyncName($0["name"] as? String) == normalizedSyncName(localHousehold.name)
            }) {
                remoteHousehold = existing
            } else {
                remoteHousehold = try await requestJSON(
                    backendURL: backendURL,
                    path: "/api/v1/households",
                    method: "POST",
                    body: ["name": localHousehold.name],
                    token: authToken
                )
                remoteHouseholds.append(remoteHousehold)
            }
            guard
                let remoteHouseholdIDText = remoteHousehold["id"] as? String,
                let remoteHouseholdID = UUID(uuidString: remoteHouseholdIDText)
            else {
                throw AppError.invalidResponse
            }

            var remoteLists = try await requestArray(
                backendURL: backendURL,
                path: "/api/v1/households/\(remoteHouseholdID.uuidString)/lists",
                token: authToken
            )
            for localList in snapshot.lists where localList.householdID == localHousehold.id {
                let remoteList: [String: Any]
                if let existing = remoteLists.first(where: {
                    normalizedSyncName($0["name"] as? String) == normalizedSyncName(localList.name)
                }) {
                    remoteList = existing
                    var listBody: [String: Any] = ["name": localList.name]
                    listBody["accent_color"] = localList.accentColorHex ?? NSNull()
                    _ = try await requestJSON(
                        backendURL: backendURL,
                        path: "/api/v1/lists/\((existing["id"] as? String) ?? "")",
                        method: "PATCH",
                        body: listBody,
                        token: authToken
                    )
                } else {
                    var listBody: [String: Any] = ["name": localList.name]
                    listBody["accent_color"] = localList.accentColorHex ?? NSNull()
                    remoteList = try await requestJSON(
                        backendURL: backendURL,
                        path: "/api/v1/households/\(remoteHouseholdID.uuidString)/lists",
                        method: "POST",
                        body: listBody,
                        token: authToken
                    )
                    remoteLists.append(remoteList)
                }
                guard
                    let remoteListIDText = remoteList["id"] as? String,
                    let remoteListID = UUID(uuidString: remoteListIDText),
                    let localData = snapshot.listData[localList.id]
                else {
                    throw AppError.invalidResponse
                }
                mappedListIDs[localList.id] = remoteListID

                let remoteCategories = try await requestArray(
                    backendURL: backendURL,
                    path: "/api/v1/lists/\(remoteListID.uuidString)/categories",
                    token: authToken
                )
                var mappedCategoryIDs: [UUID: UUID] = [:]
                for localCategory in localData.categories {
                    if let existing = remoteCategories.first(where: {
                        normalizedSyncName($0["name"] as? String) == normalizedSyncName(localCategory.name)
                    }) {
                        guard
                            let remoteCategoryIDText = existing["id"] as? String,
                            let remoteCategoryID = UUID(uuidString: remoteCategoryIDText)
                        else {
                            throw AppError.invalidResponse
                        }
                        mappedCategoryIDs[localCategory.id] = remoteCategoryID
                    }
                }

                var remoteItems = try await requestArray(
                    backendURL: backendURL,
                    path: "/api/v1/lists/\(remoteListID.uuidString)/items",
                    token: authToken
                )
                var matchedRemoteItemIDs = Set<UUID>()
                for localItem in localData.items {
                    let matchedRemoteItem = remoteItems.first { payload in
                        guard
                            let idText = payload["id"] as? String,
                            let id = UUID(uuidString: idText),
                            matchedRemoteItemIDs.contains(id) == false
                        else {
                            return false
                        }
                        return (payload["name"] as? String) == localItem.name
                            && (payload["quantity_text"] as? String) == localItem.quantityText
                            && (payload["note"] as? String) == localItem.note
                    }

                    let remoteItem: [String: Any]
                    if let matchedRemoteItem {
                        remoteItem = matchedRemoteItem
                    } else {
                        var itemBody: [String: Any] = [
                            "name": localItem.name,
                            "sort_order": localItem.sortOrder,
                        ]
                        itemBody["quantity_text"] = localItem.quantityText ?? NSNull()
                        itemBody["note"] = localItem.note ?? NSNull()
                        itemBody["category_id"] = localItem.categoryID.flatMap { mappedCategoryIDs[$0] }?.uuidString
                            ?? NSNull()
                        remoteItem = try await requestJSON(
                            backendURL: backendURL,
                            path: "/api/v1/lists/\(remoteListID.uuidString)/items",
                            method: "POST",
                            body: itemBody,
                            token: authToken
                        )
                        remoteItems.append(remoteItem)
                    }
                    guard
                        let remoteItemIDText = remoteItem["id"] as? String,
                        let remoteItemID = UUID(uuidString: remoteItemIDText)
                    else {
                        throw AppError.invalidResponse
                    }
                    matchedRemoteItemIDs.insert(remoteItemID)

                    var itemUpdateBody: [String: Any] = [
                        "name": localItem.name,
                        "sort_order": localItem.sortOrder,
                    ]
                    itemUpdateBody["quantity_text"] = localItem.quantityText ?? NSNull()
                    itemUpdateBody["note"] = localItem.note ?? NSNull()
                    itemUpdateBody["category_id"] = localItem.categoryID.flatMap { mappedCategoryIDs[$0] }?.uuidString
                        ?? NSNull()
                    itemUpdateBody["hidden_until"] = localItem.hiddenUntil.map(apiTimestamp) ?? NSNull()
                    _ = try await requestJSON(
                        backendURL: backendURL,
                        path: "/api/v1/items/\(remoteItemID.uuidString)",
                        method: "PATCH",
                        body: itemUpdateBody,
                        token: authToken
                    )

                    let remoteChecked = (remoteItem["checked"] as? Bool) ?? false
                    if remoteChecked != localItem.checked {
                        _ = try await requestJSON(
                            backendURL: backendURL,
                            path: "/api/v1/items/\(remoteItemID.uuidString)/\(localItem.checked ? "check" : "uncheck")",
                            method: "POST",
                            body: [:],
                            token: authToken
                        )
                    }
                }

                let mappedCategoryOrder = localData.categoryOrder
                    .sorted { $0.sortOrder < $1.sortOrder }
                    .compactMap { mappedCategoryIDs[$0.categoryID] }
                _ = try await requestArray(
                    backendURL: backendURL,
                    path: "/api/v1/lists/\(remoteListID.uuidString)/category-order",
                    method: "PUT",
                    body: ["category_ids": mappedCategoryOrder.map(\.uuidString)],
                    token: authToken
                )
                let mappedDisabledCategoryIDs = localData.disabledCategoryIDs.compactMap {
                    mappedCategoryIDs[$0]
                }
                _ = try await requestJSON(
                    backendURL: backendURL,
                    path: "/api/v1/lists/\(remoteListID.uuidString)/disabled-categories",
                    method: "PUT",
                    body: ["category_ids": mappedDisabledCategoryIDs.map(\.uuidString)],
                    token: authToken
                )
            }
        }

        return mappedListIDs
    }

    private func normalizedSyncName(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private func makeSharedAppState() -> SharedAppState {
        let syncsFavoriteList = selectedListID == favoriteListID
        let syncedItems = syncsFavoriteList ? items : []
        let syncedCategories = syncsFavoriteList ? categories : []
        let syncedCategoryOrder = syncsFavoriteList ? categoryOrder : []
        return SharedAppState(
            backendURL: isLocalMode ? nil : backendURL,
            authToken: isLocalMode ? nil : authToken,
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
        if isLocalMode {
            liveUpdates.disconnect()
            return
        }
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

    private func showOfflineStatus(_ message: String, cause: Error? = nil) {
        errorMessage = nil
        offlineStatusMessage = message
        netLog.notice(
            "Showing offline status. pendingCreates=\(self.pendingItemCreates.count) pendingEdits=\(self.pendingItemEdits.count) pendingToggles=\(self.pendingItemToggles.count) cause=\(cause?.localizedDescription ?? "none", privacy: .public)"
        )
    }

    private func applyUITestPendingItemCreateIfNeeded() {
        guard
            processInfo.environment["PLANINI_UI_TEST_MODE"] == "1",
            let selectedListID,
            let name = processInfo.environment[AppBuildConfiguration.uiTestPendingItemCreateNameKey]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            name.isEmpty == false,
            pendingItemCreates.contains(where: { $0.listID == selectedListID && $0.name == name }) == false
        else {
            return
        }
        queuePendingItemCreate(
            listID: selectedListID,
            name: name,
            quantityText: nil,
            note: nil,
            categoryID: nil
        )
        defersUITestPendingItemSyncUntilMutation = true
    }

    private func applyUITestOfflineStatusOverrideIfNeeded() {
        guard
            processInfo.environment["PLANINI_UI_TEST_MODE"] == "1",
            let offlineStatusOverride = processInfo.environment[
                AppBuildConfiguration.uiTestOfflineStatusMessageKey
            ]?.trimmingCharacters(in: .whitespacesAndNewlines),
            offlineStatusOverride.isEmpty == false
        else {
            return
        }
        preservesUITestOfflineStatusUntilMutation = true
        showOfflineStatus(offlineStatusOverride)
    }

    private func clearOfflineStatusAfterRead() {
        guard preservesUITestOfflineStatusUntilMutation == false else { return }
        clearOfflineStatus()
    }

    private func clearOfflineStatus() {
        if offlineStatusMessage != nil {
            netLog.notice(
                "Clearing offline status. pendingCreates=\(self.pendingItemCreates.count) pendingEdits=\(self.pendingItemEdits.count) pendingToggles=\(self.pendingItemToggles.count)"
            )
        }
        preservesUITestOfflineStatusUntilMutation = false
        offlineStatusMessage = nil
    }

    private func isOfflineError(_ error: Error) -> Bool {
        if error is URLError {
            return true
        }
        guard let appError = error as? AppError else { return false }
        if case .backendUnavailable = appError {
            return true
        }
        return false
    }

    private func handleSessionExpired(_ error: Error) -> Bool {
        guard let appError = error as? AppError, case .sessionExpired = appError else { return false }
        expireSession()
        return true
    }

    private func expireSession() {
        liveUpdates.disconnect()
        authToken = nil
        passkeys = []
        passkeyManagementErrorMessage = nil
        listHistory = []
        listHistoryListID = nil
        isLoadingListHistory = false
        listHistoryErrorMessage = nil
        lists = []
        items = []
        categories = []
        categoryOrder = []
        categoryOrderBackgroundSaveState = .saved
        categoryOrderSaveTask?.cancel()
        categoryOrderSaveTask = nil
        pendingCategoryOrderSaves = [:]
        pendingCategoryOrderSaveListIDs = []
        optimisticCategoryOrders = [:]
        selectedListID = nil
        reviewerOnboardingMessage = nil
        offlineStatusMessage = nil
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
        items = applyPendingItemToggles(
            to: applyPendingItemEdits(
                to: applyPendingItemCreates(to: listData.items)
            )
        )
        categories = listData.categories
        categoryOrder = selectedListID.flatMap { optimisticCategoryOrders[$0] } ?? listData.categoryOrder
        disabledCategoryIDs = Set(listData.disabledCategoryIDs)
    }

    private func applyLocalDemoListData(_ listData: MobileListData) {
        items = listData.items
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
        guard let selectedListID else { return false }
        let previousCategoryOrder = categoryOrder
        categoryOrder = categoryIDs.enumerated().map { index, categoryID in
            ListCategoryOrderEntry(categoryID: categoryID, sortOrder: index)
        }
        if isLocalMode {
            persistLocalDemoState()
            watchSyncCoordinator.publishCurrentState()
            return true
        }
        guard let backendURL, let authToken else {
            categoryOrder = previousCategoryOrder
            return false
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

    func saveCategoryOrderInBackground(categoryIDs: [UUID]) {
        guard let selectedListID else {
            categoryOrderBackgroundSaveState = .failed
            return
        }

        let nextOrder = categoryIDs.enumerated().map { index, categoryID in
            ListCategoryOrderEntry(categoryID: categoryID, sortOrder: index)
        }
        categoryOrder = nextOrder
        if isLocalMode {
            persistLocalDemoState()
            categoryOrderBackgroundSaveState = .saved
            watchSyncCoordinator.publishCurrentState()
            return
        }
        guard let backendURL, let authToken else {
            categoryOrderBackgroundSaveState = .failed
            return
        }
        optimisticCategoryOrders[selectedListID] = nextOrder
        cacheCurrentListData()
        watchSyncCoordinator.publishCurrentState()

        if pendingCategoryOrderSaves[selectedListID] == nil {
            pendingCategoryOrderSaveListIDs.append(selectedListID)
        }
        pendingCategoryOrderSaves[selectedListID] = PendingCategoryOrderSave(
            listID: selectedListID,
            backendURL: backendURL,
            authToken: authToken,
            categoryIDs: categoryIDs
        )
        categoryOrderBackgroundSaveState = .saving

        guard categoryOrderSaveTask == nil else { return }
        categoryOrderSaveTask = Task { [weak self] in
            await self?.flushCategoryOrderSaveQueue()
        }
    }

    private func flushCategoryOrderSaveQueue() async {
        var latestSaveFailed = false

        while Task.isCancelled == false, let listID = pendingCategoryOrderSaveListIDs.first {
            pendingCategoryOrderSaveListIDs.removeFirst()
            guard let request = pendingCategoryOrderSaves.removeValue(forKey: listID) else {
                continue
            }

            if categoryOrderSaveDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: categoryOrderSaveDelayNanoseconds)
            }
            guard Task.isCancelled == false else { return }

            do {
                let response = try await requestArray(
                    backendURL: request.backendURL,
                    path: "/api/v1/lists/\(request.listID.uuidString)/category-order",
                    method: "PUT",
                    body: ["category_ids": request.categoryIDs.map(\.uuidString)],
                    token: request.authToken
                )
                guard Task.isCancelled == false else { return }
                guard pendingCategoryOrderSaves[request.listID] == nil else { continue }

                optimisticCategoryOrders.removeValue(forKey: request.listID)
                if selectedListID == request.listID {
                    categoryOrder = response.compactMap(ListCategoryOrderEntry.init)
                    cacheCurrentListData()
                    watchSyncCoordinator.publishCurrentState()
                }
            } catch {
                guard Task.isCancelled == false else { return }
                if pendingCategoryOrderSaves[request.listID] == nil {
                    latestSaveFailed = true
                    errorMessage = error.localizedDescription
                }
            }
        }

        guard Task.isCancelled == false else { return }
        categoryOrderSaveTask = nil
        categoryOrderBackgroundSaveState = latestSaveFailed ? .failed : .saved
    }

    private var categoryOrderSaveDelayNanoseconds: UInt64 {
        guard
            isRunningUITests,
            let rawDelay = processInfo.environment["PLANINI_UI_TEST_CATEGORY_ORDER_SAVE_DELAY_MS"],
            let delayMilliseconds = UInt64(rawDelay)
        else {
            return 0
        }
        return delayMilliseconds * 1_000_000
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
            return HouseholdSummary(
                id: householdID,
                name: householdName,
                role: lists.first?.accessRole ?? .editor
            )
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

    private static func loadPendingItemCreates(from userDefaults: UserDefaults) -> [PendingItemCreate] {
        guard let data = userDefaults.data(forKey: pendingItemCreatesKey) else { return [] }
        return (try? JSONDecoder().decode([PendingItemCreate].self, from: data)) ?? []
    }

    private static func loadPendingItemEdits(from userDefaults: UserDefaults) -> [PendingItemEdit] {
        guard let data = userDefaults.data(forKey: pendingItemEditsKey) else { return [] }
        return (try? JSONDecoder().decode([PendingItemEdit].self, from: data)) ?? []
    }

    private static func loadPendingItemToggles(from userDefaults: UserDefaults) -> [PendingItemToggle] {
        guard let data = userDefaults.data(forKey: pendingItemTogglesKey) else { return [] }
        return (try? JSONDecoder().decode([PendingItemToggle].self, from: data)) ?? []
    }

    private func savePendingItemCreates() {
        guard let data = try? JSONEncoder().encode(pendingItemCreates) else { return }
        userDefaults.set(data, forKey: Self.pendingItemCreatesKey)
    }

    private func savePendingItemEdits() {
        guard let data = try? JSONEncoder().encode(pendingItemEdits) else { return }
        userDefaults.set(data, forKey: Self.pendingItemEditsKey)
    }

    private func savePendingItemToggles() {
        guard let data = try? JSONEncoder().encode(pendingItemToggles) else { return }
        userDefaults.set(data, forKey: Self.pendingItemTogglesKey)
    }

    private func queuePendingItemCreate(
        listID: UUID,
        name: String,
        quantityText: String?,
        note: String?,
        categoryID: UUID?
    ) {
        let itemID = UUID()
        let create = PendingItemCreate(
            mutationID: UUID().uuidString,
            clientItemID: itemID.uuidString,
            listID: listID,
            itemID: itemID,
            name: name,
            quantityText: quantityText,
            note: note,
            categoryID: categoryID,
            sortOrder: 0,
            recordedAt: Date()
        )
        pendingItemCreates.append(create)
        savePendingItemCreates()
        upsertLocalItem(create.localItem)
        cacheCurrentListData()
        watchSyncCoordinator.publishCurrentState()
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

    private func queuePendingItemToggle(listID: UUID, itemID: UUID, checked: Bool, recordedAt: Date) {
        let toggle = PendingItemToggle(
            mutationID: UUID().uuidString,
            listID: listID,
            itemID: itemID,
            checked: checked,
            recordedAt: recordedAt
        )
        if let index = pendingItemToggles.firstIndex(where: { $0.itemID == itemID }) {
            pendingItemToggles[index] = toggle
        } else {
            pendingItemToggles.append(toggle)
        }
        savePendingItemToggles()
        applyLocalToggle(itemID: itemID, checked: checked, recordedAt: recordedAt)
    }

    private func removePendingItemCreates(mutationIDs: Set<String>) {
        pendingItemCreates.removeAll { mutationIDs.contains($0.mutationID) }
        savePendingItemCreates()
    }

    private func removePendingItemEdit(itemID: UUID) {
        pendingItemEdits.removeAll { $0.itemID == itemID }
        savePendingItemEdits()
    }

    private func removePendingItemToggles(mutationIDs: Set<String>) {
        pendingItemToggles.removeAll { mutationIDs.contains($0.mutationID) }
        savePendingItemToggles()
    }

    private func removePendingItemToggles(itemID: UUID) {
        pendingItemToggles.removeAll { $0.itemID == itemID }
        savePendingItemToggles()
    }

    private func applyPendingItemCreates(to loadedItems: [GroceryItemRecord]) -> [GroceryItemRecord] {
        guard let selectedListID else { return loadedItems }
        var mergedItems = loadedItems
        for create in pendingItemCreates where create.listID == selectedListID {
            if let index = mergedItems.firstIndex(where: { $0.id == create.itemID }) {
                mergedItems[index] = create.localItem
            } else {
                mergedItems.append(create.localItem)
            }
        }
        return mergedItems
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

    private func applyPendingItemToggles(to loadedItems: [GroceryItemRecord]) -> [GroceryItemRecord] {
        guard let selectedListID else { return loadedItems }
        let pendingByItemID = Dictionary(
            uniqueKeysWithValues: pendingItemToggles
                .filter { $0.listID == selectedListID }
                .map { ($0.itemID, $0) }
        )
        return loadedItems.map { item in
            guard let toggle = pendingByItemID[item.id] else { return item }
            return item.applyingCheckedState(toggle.checked, recordedAt: toggle.recordedAt)
        }
    }

    private func applyLocalEdit(itemID: UUID, payload: GroceryItemEditPayload) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index] = items[index].applyingEditPayload(payload)
        watchSyncCoordinator.publishCurrentState()
    }

    private func applyLocalToggle(itemID: UUID, checked: Bool, recordedAt: Date) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index] = items[index].applyingCheckedState(checked, recordedAt: recordedAt)
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

    private func flushPendingItemCreates() async {
        guard defersUITestPendingItemSyncUntilMutation == false else { return }
        guard let backendURL, let authToken else { return }
        let createsByListID = Dictionary(grouping: pendingItemCreates, by: \.listID)
        var didSyncPendingItems = false
        for (listID, creates) in createsByListID {
            let sortedCreates = creates.sorted { $0.recordedAt < $1.recordedAt }
            let body: [String: Any] = [
                "mutations": sortedCreates.map { create in
                    [
                        "mutation_id": create.mutationID,
                        "type": "create",
                        "client_item_id": create.clientItemID,
                        "recorded_at": Self.iso8601String(from: create.recordedAt),
                        "payload": [
                            "name": create.name,
                            "quantity_text": create.quantityText ?? NSNull(),
                            "note": create.note ?? NSNull(),
                            "category_id": create.categoryID?.uuidString ?? NSNull(),
                            "sort_order": create.sortOrder,
                        ] as [String: Any],
                    ] as [String: Any]
                },
            ]

            do {
                let response = try await requestJSON(
                    backendURL: backendURL,
                    path: "/api/v1/lists/\(listID.uuidString)/items/sync",
                    method: "POST",
                    body: body,
                    token: authToken
                )
                let appliedMutationIDs = Set(response["applied_mutation_ids"] as? [String] ?? [])
                let clientItemIDs = response["client_item_ids"] as? [String: String] ?? [:]
                remapPendingItemReferences(clientItemIDs: clientItemIDs, creates: sortedCreates)
                removePendingItemCreates(mutationIDs: appliedMutationIDs)
                if selectedListID == listID {
                    let localItemIDs = Set(
                        sortedCreates
                            .filter { clientItemIDs[$0.clientItemID] != nil }
                            .map(\.itemID)
                    )
                    items.removeAll { localItemIDs.contains($0.id) }
                    if let itemPayloads = response["items"] as? [[String: Any]] {
                        itemPayloads.compactMap(GroceryItemRecord.init).forEach(upsertLocalItem)
                    }
                }
                didSyncPendingItems = true
            } catch {
                if handleSessionExpired(error) {
                    return
                }
                netLog.error(
                    "Pending iPhone item create sync failed: \(error.localizedDescription, privacy: .public)"
                )
                if isOfflineError(error) {
                    showOfflineStatus(
                        "Changes saved offline. They will sync when the backend is reachable.",
                        cause: error
                    )
                }
                return
            }
        }
        watchSyncCoordinator.publishCurrentState()
        if didSyncPendingItems {
            clearOfflineStatusIfPendingItemsSynced()
        }
    }

    private func remapPendingItemReferences(
        clientItemIDs: [String: String],
        creates: [PendingItemCreate]
    ) {
        let serverIDsByLocalID = Dictionary(
            uniqueKeysWithValues: creates.compactMap { create -> (UUID, UUID)? in
                guard
                    let serverIDText = clientItemIDs[create.clientItemID],
                    let serverID = UUID(uuidString: serverIDText)
                else {
                    return nil
                }
                return (create.itemID, serverID)
            }
        )
        guard serverIDsByLocalID.isEmpty == false else { return }
        for index in pendingItemEdits.indices {
            if let serverID = serverIDsByLocalID[pendingItemEdits[index].itemID] {
                pendingItemEdits[index].itemID = serverID
            }
        }
        for index in pendingItemToggles.indices {
            if let serverID = serverIDsByLocalID[pendingItemToggles[index].itemID] {
                pendingItemToggles[index].itemID = serverID
            }
        }
        savePendingItemEdits()
        savePendingItemToggles()
    }

    private func flushPendingItemEdits() async {
        guard let backendURL, let authToken else { return }
        var didSyncPendingItems = false
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
                didSyncPendingItems = true
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
        if didSyncPendingItems {
            clearOfflineStatusIfPendingItemsSynced()
        }
    }

    private func flushPendingItemToggles() async {
        guard let backendURL, let authToken else { return }
        let togglesByListID = Dictionary(grouping: pendingItemToggles, by: \.listID)
        var didSyncPendingItems = false
        for (listID, toggles) in togglesByListID {
            let sortedToggles = toggles.sorted { $0.recordedAt < $1.recordedAt }
            let body: [String: Any] = [
                "mutations": sortedToggles.map { toggle in
                    [
                        "mutation_id": toggle.mutationID,
                        "type": "set_checked",
                        "item_id": toggle.itemID.uuidString,
                        "recorded_at": Self.iso8601String(from: toggle.recordedAt),
                        "checked": toggle.checked,
                    ] as [String: Any]
                },
            ]

            do {
                let response = try await requestJSON(
                    backendURL: backendURL,
                    path: "/api/v1/lists/\(listID.uuidString)/items/sync",
                    method: "POST",
                    body: body,
                    token: authToken
                )
                let appliedMutationIDs = Set(response["applied_mutation_ids"] as? [String] ?? [])
                removePendingItemToggles(mutationIDs: appliedMutationIDs)
                if selectedListID == listID, let itemPayloads = response["items"] as? [[String: Any]] {
                    itemPayloads.compactMap(GroceryItemRecord.init).forEach(upsertLocalItem)
                }
                didSyncPendingItems = true
            } catch {
                if handleSessionExpired(error) {
                    return
                }
                netLog.error(
                    "Pending iPhone item toggle sync failed: \(error.localizedDescription, privacy: .public)"
                )
                if isOfflineError(error) {
                    showOfflineStatus(
                        "Changes saved offline. They will sync when the backend is reachable.",
                        cause: error
                    )
                }
                return
            }
        }
        watchSyncCoordinator.publishCurrentState()
        if didSyncPendingItems {
            clearOfflineStatusIfPendingItemsSynced()
        }
    }

    private static func iso8601String(from date: Date) -> String {
        offlineMutationDateFormatter.string(from: date)
    }

    private func clearOfflineStatusIfPendingItemsSynced() {
        if pendingItemCreates.isEmpty, pendingItemEdits.isEmpty, pendingItemToggles.isEmpty {
            clearOfflineStatus()
        }
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
        request.setValue(
            Locale.preferredLanguages.first ?? "en",
            forHTTPHeaderField: "Accept-Language"
        )
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
        if token != nil {
            if offlineStatusMessage != nil {
                netLog.notice(
                    "Authenticated backend response received. method=\(method, privacy: .public) path=\(path, privacy: .public) status=\(http.statusCode)"
                )
            }
            clearOfflineStatusAfterRead()
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

    private func apiTimestamp(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
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

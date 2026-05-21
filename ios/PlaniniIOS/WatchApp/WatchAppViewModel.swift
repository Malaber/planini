import Foundation
import PlaniniCore
import os.log
import SwiftUI

private let watchAppLog = Logger(
    subsystem: "de.malaber.planini.watch",
    category: "view-model"
)

@MainActor
final class WatchAppViewModel: ObservableObject {
    @Published private(set) var state: SharedAppState
    @Published private(set) var categories: [GroceryCategorySummary] = []
    @Published private(set) var categoryOrder: [ListCategoryOrderEntry] = []
    @Published private(set) var selectedListID: UUID?
    @Published var draftItemName = ""
    @Published var errorMessage: String?
    @Published private(set) var isWorking = false
    @Published private(set) var isCompanionAppInstalled = false
    @Published private(set) var isPhoneReachable = false
    @Published private var listActionHistories: [UUID: WatchListActionHistory] = [:]

    private let store: SharedAppStateStore
    private let backendClient: WatchBackendClient
    private let connectivityBridge: WatchConnectivityBridge
    private let liveUpdates: WatchListLiveUpdateClient

    init(
        store: SharedAppStateStore = WatchSharedContainer.stateStore,
        backendClient: WatchBackendClient = WatchBackendClient(),
        connectivityBridge: WatchConnectivityBridge = WatchConnectivityBridge(),
        liveUpdates: WatchListLiveUpdateClient = WatchListLiveUpdateClient()
    ) {
        let initialState = store.load()
        self.store = store
        self.backendClient = backendClient
        self.connectivityBridge = connectivityBridge
        self.liveUpdates = liveUpdates
        state = initialState
        categories = initialState.categories
        categoryOrder = initialState.categoryOrder
        selectedListID = initialState.favoriteListID
        self.connectivityBridge.onStateUpdate = { [weak self] updatedState in
            self?.applySyncedState(updatedState)
        }
        self.connectivityBridge.onReachabilityChange = { [weak self] in
            self?.refreshConnectivityStatus()
        }
        self.liveUpdates.onListChanged = { [weak self] listID in
            Task { @MainActor in
                await self?.handleLiveListChanged(listID)
            }
        }
        refreshConnectivityStatus()
    }

    var displayedLists: [GroceryListSummary] {
        let favoriteID = state.favoriteListID
        return state.lists.sorted { left, right in
            if left.id == favoriteID, right.id != favoriteID {
                return true
            }
            if left.id != favoriteID, right.id == favoriteID {
                return false
            }
            if left.householdName != right.householdName {
                return left.householdName.localizedCaseInsensitiveCompare(right.householdName) == .orderedAscending
            }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }

    func isFavorite(_ list: GroceryListSummary) -> Bool {
        list.id == state.favoriteListID
    }

    func items(for list: GroceryListSummary) -> [GroceryItemRecord] {
        guard selectedListID == list.id else { return [] }
        return state.items.sorted { left, right in
            if left.checked != right.checked {
                return left.checked == false
            }
            return left.sortOrder < right.sortOrder
        }
    }

    func sections(for list: GroceryListSummary) -> [GroceryItemSection] {
        guard selectedListID == list.id else { return [] }
        return GroceryItemSectionBuilder.build(
            items: state.items,
            categories: categories,
            categoryOrder: categoryOrder
        )
    }

    func categoryColorHex(for item: GroceryItemRecord) -> String? {
        guard let categoryID = item.categoryID else { return nil }
        return categories.first(where: { $0.id == categoryID })?.colorHex
    }

    var availableCategories: [GroceryCategorySummary] {
        categories.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var needsPhoneSetup: Bool {
        state.hasAuthenticatedSession == false
    }

    var setupButtonTitle: String {
        isPhoneReachable ? "Sync from iPhone" : "Open and unlock iPhone app"
    }

    var versionBuildText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "0"
        let build = info["CFBundleVersion"] as? String ?? "0"
        return "Version \(version) (\(build))"
    }

    func performInitialLoad() async {
        await Task.yield()
        connectivityBridge.requestLatestState()
        refreshConnectivityStatus()
        await refresh()
    }

    func onAppear() {
        connectivityBridge.requestLatestState()
        refreshConnectivityStatus()
    }

    func refresh() async {
        watchAppLog.debug("Manual watch refresh started.")
        await syncLatestState()
        await refreshSelectedList()
    }

    func showList(_ list: GroceryListSummary) async {
        if selectedListID != list.id {
            selectedListID = list.id
            if state.items.first?.listID != list.id {
                state.items = []
            }
            categories = list.id == state.favoriteListID ? state.categories : []
            categoryOrder = list.id == state.favoriteListID ? state.categoryOrder : []
        }
        await refreshSelectedList()
    }

    func startLiveUpdates(for list: GroceryListSummary) {
        liveUpdates.connect(listID: list.id, using: state)
    }

    func stopLiveUpdates(for list: GroceryListSummary) {
        liveUpdates.disconnect(listID: list.id)
    }

    func addDraftItem(to list: GroceryListSummary) async {
        let name = draftItemName
        draftItemName = ""
        guard name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        await runListMutation(for: list.id) { [self] in
            let result = try await self.backendClient.addItemResult(named: name, to: list.id, using: self.state)
            return (result.snapshot, .added(item: result.item))
        }
    }

    func toggle(_ item: GroceryItemRecord, in list: GroceryListSummary) async {
        await runListMutation(for: list.id) { [self] in
            let before = self.state.items.first { $0.id == item.id } ?? item
            let result = try await self.backendClient.toggleResult(before, in: list.id, using: self.state)
            return (result.snapshot, .toggled(before: before, after: result.item))
        }
    }

    func saveEdit(
        item: GroceryItemRecord,
        note: String,
        categoryID: UUID?,
        in list: GroceryListSummary
    ) async -> Bool {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }

        do {
            await syncLatestState()
            let before = state.items.first { $0.id == item.id } ?? item
            let result = try await backendClient.saveEditResult(
                item: item,
                note: note,
                categoryID: categoryID,
                in: list.id,
                using: state
            )
            applySnapshot(result.snapshot)
            record(.edited(before: before, after: result.item), for: list.id)
            watchAppLog.debug("Watch item edit completed successfully.")
            return true
        } catch {
            if let backendError = error as? WatchBackendClientError, backendError == .unauthorized {
                clearAuthenticatedSession()
            }
            watchAppLog.error("Watch item edit failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            return false
        }
    }

    func canUndoListAction(for list: GroceryListSummary) -> Bool {
        actionHistory(for: list.id).canUndo && isWorking == false
    }

    func canRedoListAction(for list: GroceryListSummary) -> Bool {
        actionHistory(for: list.id).canRedo && isWorking == false
    }

    func undoListActionTitle(for list: GroceryListSummary) -> String {
        actionHistory(for: list.id).undoTitle ?? "Undo"
    }

    func redoListActionTitle(for list: GroceryListSummary) -> String {
        actionHistory(for: list.id).redoTitle ?? "Redo"
    }

    func undoLastListAction(in list: GroceryListSummary) async {
        guard let action = popUndoAction(for: list.id) else { return }
        await runHistoryAction(
            for: list.id,
            action: action,
            restore: restoreUndoAction,
            complete: completeUndoAction
        ) {
            try await self.applyUndo(action, in: list.id)
        }
    }

    func redoLastListAction(in list: GroceryListSummary) async {
        guard let action = popRedoAction(for: list.id) else { return }
        await runHistoryAction(
            for: list.id,
            action: action,
            restore: restoreRedoAction,
            complete: completeRedoAction
        ) {
            try await self.applyRedo(action, in: list.id)
        }
    }

    private func runListMutation(
        for listID: UUID,
        _ operation: @escaping () async throws -> (WatchListSnapshot, WatchListAction)
    ) async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }

        do {
            await syncLatestState()
            let (snapshot, action) = try await operation()
            applySnapshot(snapshot)
            record(action, for: listID)
            watchAppLog.debug("Watch list mutation completed successfully.")
        } catch {
            if let backendError = error as? WatchBackendClientError, backendError == .unauthorized {
                clearAuthenticatedSession()
            }
            watchAppLog.error("Watch list mutation failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    private func runHistoryAction(
        for listID: UUID,
        action: WatchListAction,
        restore: (UUID, WatchListAction) -> Void,
        complete: (UUID, WatchListAction) -> Void,
        operation: () async throws -> WatchListAction
    ) async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }

        do {
            await syncLatestState()
            let completedAction = try await operation()
            complete(listID, completedAction)
            watchAppLog.debug("Watch history action completed successfully.")
        } catch {
            restore(listID, action)
            if let backendError = error as? WatchBackendClientError, backendError == .unauthorized {
                clearAuthenticatedSession()
            }
            watchAppLog.error("Watch history action failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    private func applyUndo(_ action: WatchListAction, in listID: UUID) async throws -> WatchListAction {
        switch action {
        case let .added(item):
            let snapshot = try await backendClient.deleteItem(item, in: listID, using: state)
            applySnapshot(snapshot)
            return action
        case let .toggled(before, after):
            let result = try await backendClient.setChecked(before.checked, for: after, in: listID, using: state)
            applySnapshot(result.snapshot)
            return .toggled(before: before, after: after)
        case let .edited(before, after):
            let result = try await backendClient.saveItem(before, in: listID, using: state)
            applySnapshot(result.snapshot)
            return .edited(before: before, after: after)
        }
    }

    private func applyRedo(_ action: WatchListAction, in listID: UUID) async throws -> WatchListAction {
        switch action {
        case let .added(item):
            let result = try await backendClient.recreateItem(item, in: listID, using: state)
            applySnapshot(result.snapshot)
            return .added(item: result.item)
        case let .toggled(before, after):
            let result = try await backendClient.setChecked(after.checked, for: before, in: listID, using: state)
            applySnapshot(result.snapshot)
            return .toggled(before: before, after: after)
        case let .edited(before, after):
            let result = try await backendClient.saveItem(after, in: listID, using: state)
            applySnapshot(result.snapshot)
            return .edited(before: before, after: result.item)
        }
    }

    private func actionHistory(for listID: UUID) -> WatchListActionHistory {
        listActionHistories[listID] ?? WatchListActionHistory()
    }

    private func updateActionHistory(for listID: UUID, _ update: (inout WatchListActionHistory) -> Void) {
        var history = actionHistory(for: listID)
        update(&history)
        listActionHistories[listID] = history
    }

    private func record(_ action: WatchListAction, for listID: UUID) {
        updateActionHistory(for: listID) { $0.record(action) }
    }

    private func popUndoAction(for listID: UUID) -> WatchListAction? {
        var poppedAction: WatchListAction?
        updateActionHistory(for: listID) { poppedAction = $0.popUndo() }
        return poppedAction
    }

    private func restoreUndoAction(for listID: UUID, action: WatchListAction) {
        updateActionHistory(for: listID) { $0.restoreUndo(action) }
    }

    private func completeUndoAction(for listID: UUID, action: WatchListAction) {
        updateActionHistory(for: listID) { $0.completeUndo(action) }
    }

    private func popRedoAction(for listID: UUID) -> WatchListAction? {
        var poppedAction: WatchListAction?
        updateActionHistory(for: listID) { poppedAction = $0.popRedo() }
        return poppedAction
    }

    private func restoreRedoAction(for listID: UUID, action: WatchListAction) {
        updateActionHistory(for: listID) { $0.restoreRedo(action) }
    }

    private func completeRedoAction(for listID: UUID, action: WatchListAction) {
        updateActionHistory(for: listID) { $0.completeRedo(action) }
    }

    private func syncLatestState() async {
        refreshConnectivityStatus()
        guard let updatedState = await connectivityBridge.requestLatestStateAsync() else {
            watchAppLog.error(
                "No shared state returned from iPhone. companionInstalled=\(self.isCompanionAppInstalled) reachable=\(self.isPhoneReachable)"
            )
            return
        }
        watchAppLog.debug(
            "Synced shared state from iPhone. lists=\(updatedState.lists.count) auth=\(updatedState.authToken?.isEmpty == false) favorite=\(updatedState.favoriteListID?.uuidString ?? "nil", privacy: .public)"
        )
        applySyncedState(updatedState)
        refreshConnectivityStatus()
    }

    private func clearAuthenticatedSession() {
        var updatedState = state
        updatedState.authToken = nil
        updatedState.items = []
        updatedState.categories = []
        updatedState.categoryOrder = []
        state = updatedState
        categories = []
        categoryOrder = []
        store.save(updatedState)
        liveUpdates.disconnect()
    }

    private func refreshSelectedList() async {
        guard
            needsPhoneSetup == false,
            let selectedListID
        else {
            return
        }

        errorMessage = nil
        isWorking = true
        defer { isWorking = false }

        do {
            await syncLatestState()
            let snapshot = try await backendClient.refreshList(for: selectedListID, using: state)
            applySnapshot(snapshot)
            watchAppLog.debug("Watch list refresh completed successfully.")
        } catch {
            if let backendError = error as? WatchBackendClientError, backendError == .unauthorized {
                clearAuthenticatedSession()
            }
            watchAppLog.error("Watch list refresh failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    private func applySyncedState(_ updatedState: SharedAppState) {
        state = updatedState
        if selectedListID == nil || displayedLists.contains(where: { $0.id == selectedListID }) == false {
            selectedListID = updatedState.favoriteListID ?? updatedState.lists.first?.id
        }
        if selectedListID == updatedState.favoriteListID {
            categories = updatedState.categories
            categoryOrder = updatedState.categoryOrder
        }
        store.save(updatedState)
        if let selectedListID {
            liveUpdates.connect(listID: selectedListID, using: updatedState)
        } else {
            liveUpdates.disconnect()
        }
    }

    private func refreshConnectivityStatus() {
        isCompanionAppInstalled = connectivityBridge.isCompanionAppInstalled
        isPhoneReachable = connectivityBridge.isReachable
    }

    private func handleLiveListChanged(_ listID: UUID) async {
        guard selectedListID == listID, needsPhoneSetup == false else { return }
        watchAppLog.debug("Received live list update for selected list.")
        await refreshListItemsSilently(for: listID)
    }

    private func refreshListItemsSilently(for listID: UUID) async {
        do {
            let snapshot = try await backendClient.refreshList(for: listID, using: state)
            state = snapshot.state
            categories = snapshot.categories
            categoryOrder = snapshot.categoryOrder
            store.save(snapshot.state)
        } catch {
            if let backendError = error as? WatchBackendClientError, backendError == .unauthorized {
                clearAuthenticatedSession()
            }
            watchAppLog.error(
                "Silent live refresh failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func applySnapshot(_ snapshot: WatchListSnapshot) {
        state = snapshot.state
        categories = snapshot.categories
        categoryOrder = snapshot.categoryOrder
        store.save(snapshot.state)
    }
}

final class WatchListLiveUpdateClient {
    var onListChanged: ((UUID) -> Void)?

    private var webSocketTask: URLSessionWebSocketTask?
    private var reconnectTask: Task<Void, Never>?
    private var currentListID: UUID?
    private var backendURL: URL?
    private var authToken: String?

    func connect(listID: UUID, using state: SharedAppState) {
        guard
            let backendURL = state.backendURL,
            let authToken = state.authToken,
            authToken.isEmpty == false
        else {
            disconnect()
            return
        }

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

    func disconnect(listID: UUID? = nil) {
        if let listID, currentListID != listID {
            return
        }

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

        watchAppLog.debug(
            "Connecting live updates socket for list \(currentListID.uuidString, privacy: .public)."
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
                watchAppLog.error(
                    "Live updates socket failed: \(error.localizedDescription, privacy: .public)"
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
        ]
        guard liveUpdateTypes.contains(type) else { return }

        watchAppLog.debug(
            "Received live updates event \(type, privacy: .public) for list \(listID.uuidString, privacy: .public)."
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

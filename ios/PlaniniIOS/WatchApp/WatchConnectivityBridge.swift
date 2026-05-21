import Foundation
import PlaniniCore
import os.log
#if canImport(WatchConnectivity)
import WatchConnectivity

private let watchConnectivityLog = Logger(
    subsystem: "de.malaber.planini.watch",
    category: "connectivity"
)

final class WatchConnectivityBridge: NSObject {
    var onStateUpdate: ((SharedAppState) -> Void)?
    var onReachabilityChange: (() -> Void)?

    private let session: WCSession?
    private let store: SharedAppStateStore
    private let decoder = JSONDecoder()
    private var activationState: WCSessionActivationState
    private var activationWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        session: WCSession? = WCSession.isSupported() ? WCSession.default : nil,
        store: SharedAppStateStore = WatchSharedContainer.stateStore
    ) {
        self.session = session
        self.store = store
        self.activationState = session?.activationState ?? .notActivated
        super.init()
        self.session?.delegate = self
        self.session?.activate()
    }

    var isCompanionAppInstalled: Bool {
        session?.isCompanionAppInstalled ?? false
    }

    var isReachable: Bool {
        session?.isReachable ?? false
    }

    func requestLatestState() {
        Task {
            _ = await requestLatestStateAsync()
        }
    }

    func requestLatestStateAsync() async -> SharedAppState? {
        await waitForActivationIfNeeded()

        if let session, session.isReachable {
            watchConnectivityLog.debug("Requesting latest state from iPhone via sendMessage.")
            if let state = await requestStateViaMessage(session) {
                return state
            }
        }

        if
            let session,
            let state = decodedState(from: session.receivedApplicationContext)
        {
            watchConnectivityLog.debug(
                "Using cached application context. lists=\(state.lists.count) auth=\(state.authToken?.isEmpty == false) favorite=\(state.favoriteListID?.uuidString ?? "nil", privacy: .public)"
            )
            apply(state)
            return state
        }

        if let fallbackState = storedStateFallback() {
            watchConnectivityLog.debug(
                "Using stored shared state fallback. lists=\(fallbackState.lists.count) auth=\(fallbackState.authToken?.isEmpty == false) favorite=\(fallbackState.favoriteListID?.uuidString ?? "nil", privacy: .public)"
            )
            apply(fallbackState)
            return fallbackState
        }

        guard let session else {
            watchConnectivityLog.error("WCSession unavailable on watch.")
            return nil
        }
        guard session.isReachable else {
            watchConnectivityLog.error(
                "WCSession not reachable. companionInstalled=\(session.isCompanionAppInstalled)"
            )
            return nil
        }
        watchConnectivityLog.error("No shared state available after reachable sync attempt.")
        return nil
    }

    private func requestStateViaMessage(_ session: WCSession) async -> SharedAppState? {
        return await withCheckedContinuation { continuation in
            session.sendMessage(
                ["command": "syncState"],
                replyHandler: { [weak self] payload in
                    watchConnectivityLog.debug("Received syncState reply from iPhone.")
                    let state = self?.handle(payload)
                    continuation.resume(returning: state ?? self?.storedStateFallback())
                },
                errorHandler: { error in
                    watchConnectivityLog.error(
                        "syncState request failed: \(error.localizedDescription, privacy: .public)"
                    )
                    continuation.resume(returning: self.storedStateFallback())
                }
            )
        }
    }

    @discardableResult
    private func handle(_ payload: [String: Any]) -> SharedAppState? {
        guard let state = decodedState(from: payload) else { return nil }
        apply(state)
        return state
    }

    private func decodedState(from payload: [String: Any]) -> SharedAppState? {
        guard
            let data = payload[PlaniniSharedConstants.watchContextPayloadKey] as? Data,
            let state = try? decoder.decode(SharedAppState.self, from: data)
        else {
            watchConnectivityLog.error(
                "Failed to decode shared state. payloadKeys=\(payload.keys.sorted().joined(separator: ","), privacy: .public)"
            )
            return nil
        }

        return state
    }

    private func apply(_ state: SharedAppState) {
        watchConnectivityLog.debug(
            "Applying shared state. lists=\(state.lists.count) auth=\(state.authToken?.isEmpty == false) favorite=\(state.favoriteListID?.uuidString ?? "nil", privacy: .public)"
        )
        store.save(state)
        DispatchQueue.main.async { [weak self] in
            self?.onStateUpdate?(state)
        }
    }

    private func storedStateFallback() -> SharedAppState? {
        let state = store.load()
        guard state.hasAuthenticatedSession || state.lists.isEmpty == false else {
            return nil
        }
        return state
    }

    private func waitForActivationIfNeeded() async {
        guard let session else { return }
        activationState = session.activationState
        guard activationState != .activated else { return }

        watchConnectivityLog.debug(
            "Waiting for WCSession activation. state=\(self.activationState.rawValue)"
        )

        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                await withCheckedContinuation { continuation in
                    self?.activationWaiters.append(continuation)
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
            await group.next()
            group.cancelAll()
        }
    }

    private func finishActivationWaiters() {
        let waiters = activationWaiters
        activationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

extension WatchConnectivityBridge: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        self.activationState = activationState
        watchConnectivityLog.debug(
            "WCSession activation completed. state=\(activationState.rawValue) error=\(error?.localizedDescription ?? "none", privacy: .public)"
        )
        finishActivationWaiters()
        DispatchQueue.main.async { [weak self] in
            self?.onReachabilityChange?()
        }
        if activationState == .activated {
            requestLatestState()
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        watchConnectivityLog.debug("WCSession reachability changed. reachable=\(session.isReachable)")
        DispatchQueue.main.async { [weak self] in
            self?.onReachabilityChange?()
        }
    }

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        watchConnectivityLog.debug("Received application context from iPhone.")
        handle(applicationContext)
    }
}
#else
final class WatchConnectivityBridge {
    var onStateUpdate: ((SharedAppState) -> Void)?
    var onReachabilityChange: (() -> Void)?

    func requestLatestState() {}

    func requestLatestStateAsync() async -> SharedAppState? { nil }

    var isCompanionAppInstalled: Bool { false }

    var isReachable: Bool { false }
}
#endif

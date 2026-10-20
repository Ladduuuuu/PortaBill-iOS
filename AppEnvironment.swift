import SwiftUI

enum AppTab: Hashable {
    case areas, queue, signOut
}

enum Route: Hashable {
    case accounts(AreaAssignment)
    case reading(accountGid: String, category: MeterCategory?)
}

struct AppError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor @Observable
final class AppEnvironment {
    @ObservationIgnored let store: DataStore
    @ObservationIgnored let api: any ApiService
    let network: NetworkMonitor
    let sync: SyncService

    var session: Session?
    var isRestoring = true
    var selectedTab: AppTab = .areas
    var areasPath: [Route] = []
    var pendingCount = 0

    init() {
        let store = DataStore()
        let network = NetworkMonitor()
        let api: any ApiService = AppConfig.useMockApi ? MockApiService() : LiveApiService()
        self.store = store
        self.api = api
        self.network = network
        self.sync = SyncService(api: api, store: store, network: network)
    }

    // MARK: Lifecycle

    func bootstrap() async {
        guard isRestoring else { return }

        if let saved = await store.session() {
            let queued = await store.queuedReadings().count
            if let expiry = saved.expireDate, expiry < Date(), queued == 0 {
                await store.clearAll()
            } else {
                session = saved
            }
        }
        await refreshPendingCount()
        isRestoring = false

        sync.onChange = { [weak self] in
            Task { await self?.refreshPendingCount() }
        }
        network.onBecameOnline = { [weak self] in
            Task {
                guard let self else { return }
                await self.sync.syncPendingReadings()
                await self.refreshPendingCount()
            }
        }
        sync.startBackgroundSync()
        if session != nil, network.isOnline {
            Task { await sync.syncPendingReadings() }
        }
    }

    func refreshPendingCount() async {
        pendingCount = await store.queuedReadings().count
    }

    // MARK: Auth

    func login(username: String, password: String) async throws {
        let response = try await api.login(username: username, password: password)
        guard response.success, !response.staffKey.isEmpty else {
            throw AppError(message: "Invalid username or password")
        }
        let newSession = Session(username: username,
                                 staffName: response.staffName,
                                 staffKey: response.staffKey,
                                 expireDate: response.expireDate)
        await store.saveSession(newSession)
        areasPath = []
        selectedTab = .areas
        session = newSession
        sync.startBackgroundSync()
        await refreshPendingCount()
    }

    func signOut() async {
        await store.clearAll()
        areasPath = []
        selectedTab = .areas
        pendingCount = 0
        session = nil
    }
}

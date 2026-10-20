import Foundation
import Observation

@MainActor @Observable
final class SyncService {
    struct Summary {
        var attempted = 0
        var synced = 0
        var rejected = 0
        var networkFailed = false
        var alreadyRunning = false
        var remaining: Int { max(0, attempted - synced - rejected) }
    }

    private(set) var isSyncing = false
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private let api: any ApiService
    @ObservationIgnored private let store: DataStore
    @ObservationIgnored private let network: NetworkMonitor
    @ObservationIgnored private var timer: Task<Void, Never>?

    init(api: any ApiService, store: DataStore, network: NetworkMonitor) {
        self.api = api
        self.store = store
        self.network = network
    }

    /// Uploads every queued reading that has not been rejected. Safe to call repeatedly.
    @discardableResult
    func syncPendingReadings() async -> Summary {
        if isSyncing { return Summary(alreadyRunning: true) }
        isSyncing = true
        defer {
            isSyncing = false
            onChange?()
        }

        guard let session = await store.session() else { return Summary() }
        let pending = await store.pendingReadings()
        var summary = Summary()
        summary.attempted = pending.count

        for item in pending {
            let request = makeRequest(for: item, staffKey: session.staffKey)
            let result = await api.postSaveNewReading(request)

            if result.isSuccess {
                await store.markSynced(item.id)
                summary.synced += 1
            } else if result.isRejected {
                let message = result.message.isEmpty
                    ? "Reading rejected by the server. Please check the value and try again."
                    : result.message
                await store.markRejected(item.id, code: result.statusCode, message: message)
                summary.rejected += 1
            } else {
                await store.markAttempt(item.id)
                if result.noResponse {
                    // Connectivity is down; no point hammering the rest of the queue.
                    summary.networkFailed = true
                    break
                }
            }
        }
        return summary
    }

    func startBackgroundSync() {
        stopBackgroundSync()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(AppConfig.backgroundSyncInterval * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                if self.network.isOnline { await self.syncPendingReadings() }
            }
        }
    }

    func stopBackgroundSync() {
        timer?.cancel()
        timer = nil
    }

    private func makeRequest(for item: QueuedReading, staffKey: String) -> NewReadingRequest {
        let bytes = ImageStore.load(item.imageFile)
        return NewReadingRequest(staffKey: staffKey,
                                 gid: item.accountGid,
                                 accountNo: item.accountNo,
                                 newReading: item.newReading.readingText(maxDecimals: max(item.category.maxDecimals, 0)),
                                 brId: item.brId,
                                 comment: "",
                                 fileBytesBase64: bytes?.base64EncodedString(),
                                 fileName: bytes == nil ? nil : "reading_photo.jpg",
                                 quickComment: item.quickComment,
                                 enType: item.category.serverType,
                                 appId: AppConfig.appId)
    }
}

import Foundation

// MARK: - Photo files

/// Photos live on disk (not inside the JSON stores) so the data files stay small.
enum ImageStore {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PortaBill/Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    static func save(_ data: Data) throws -> String {
        let name = UUID().uuidString + ".jpg"
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        return name
    }

    static func load(_ name: String?) -> Data? {
        guard let name else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(name))
    }

    static func delete(_ name: String?) {
        guard let name else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

// MARK: - Data store

/// Offline-first store. Everything is kept in memory and persisted as JSON in Application Support.
actor DataStore {
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var loaded = false

    private var currentSession: Session?
    private var areasByDay: [String: [AreaAssignment]] = [:]
    private var accounts: [AccountMeter] = []
    private var history: [BillHistoryEntry] = []
    private var queue: [QueuedReading] = []

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PortaBill", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        directory = base
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        encoder = enc
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        decoder = dec
    }

    nonisolated static func dayKey(_ date: Date) -> String {
        DateFormatter.make("yyyy-MM-dd").string(from: date)
    }

    // MARK: Persistence plumbing

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        currentSession = read("session.json", as: Session.self)
        areasByDay = read("areas.json", as: [String: [AreaAssignment]].self) ?? [:]
        accounts = read("accounts.json", as: [AccountMeter].self) ?? []
        history = read("history.json", as: [BillHistoryEntry].self) ?? []
        queue = read("queue.json", as: [QueuedReading].self) ?? []
    }

    private func read<T: Decodable>(_ name: String, as type: T.Type) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    // MARK: Session

    func session() -> Session? {
        ensureLoaded()
        return currentSession
    }

    func saveSession(_ session: Session) {
        ensureLoaded()
        currentSession = session
        write(session, to: "session.json")
    }

    /// Removes everything (used on sign-out).
    func clearAll() {
        ensureLoaded()
        currentSession = nil
        areasByDay = [:]
        accounts = []
        history = []
        queue = []
        for name in ["session.json", "areas.json", "accounts.json", "history.json", "queue.json"] {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
        ImageStore.deleteAll()
    }

    // MARK: Areas

    func areas(for day: Date) -> [AreaAssignment] {
        ensureLoaded()
        return (areasByDay[Self.dayKey(day)] ?? []).sorted { $0.orderNumber < $1.orderNumber }
    }

    func saveAreas(_ areas: [AreaAssignment], for day: Date) {
        ensureLoaded()
        areasByDay[Self.dayKey(day)] = areas
        write(areasByDay, to: "areas.json")
    }

    func clearAreas(for day: Date) {
        ensureLoaded()
        areasByDay[Self.dayKey(day)] = nil
        write(areasByDay, to: "areas.json")
    }

    // MARK: Accounts

    func accounts(areaId: Int) -> [AccountMeter] {
        ensureLoaded()
        return accounts.filter { $0.areaId == areaId }.sorted { $0.rowNumber < $1.rowNumber }
    }

    func account(gid: String) -> AccountMeter? {
        ensureLoaded()
        return accounts.first { $0.gid == gid }
    }

    /// Replaces an area's accounts with a fresh server copy. Readings that were entered on this
    /// device but not yet synced are carried over so a refresh never makes a reader redo work.
    func replaceAccounts(_ fresh: [AccountMeter], areaId: Int) {
        ensureLoaded()
        let existing = Dictionary(uniqueKeysWithValues: accounts.filter { $0.areaId == areaId }.map { ($0.gid, $0) })
        var merged = fresh
        for i in merged.indices {
            guard let old = existing[merged[i].gid] else { continue }
            for category in merged[i].categories {
                guard let oldReading = old.reading(for: category), oldReading.isCompleted, !oldReading.isSynced else { continue }
                merged[i].update(category) { $0 = oldReading }
            }
            if !old.quickComment.isEmpty && merged[i].quickComment.isEmpty { merged[i].quickComment = old.quickComment }
        }
        accounts.removeAll { $0.areaId == areaId }
        accounts.append(contentsOf: merged)
        write(accounts, to: "accounts.json")
    }

    func updateAccount(_ account: AccountMeter) {
        ensureLoaded()
        guard let i = accounts.firstIndex(where: { $0.gid == account.gid }) else { return }
        accounts[i] = account
        write(accounts, to: "accounts.json")
    }

    func clearAccounts(areaId: Int) {
        ensureLoaded()
        accounts.removeAll { $0.areaId == areaId }
        write(accounts, to: "accounts.json")
    }

    // MARK: Bill history

    func billHistory(accountNo: String, category: MeterCategory) -> [BillHistoryEntry] {
        ensureLoaded()
        return history
            .filter { $0.accountNo == accountNo && $0.category == category }
            .sorted { ($0.billYear, $0.billNo) > ($1.billYear, $1.billNo) }
    }

    func saveBillHistory(_ entries: [BillHistoryEntry], accountNo: String, category: MeterCategory) {
        ensureLoaded()
        history.removeAll { $0.accountNo == accountNo && $0.category == category }
        history.append(contentsOf: entries)
        write(history, to: "history.json")
    }

    // MARK: Queue

    func queuedReadings() -> [QueuedReading] {
        ensureLoaded()
        return queue.sorted { $0.createdDate > $1.createdDate }
    }

    func pendingReadings() -> [QueuedReading] {
        ensureLoaded()
        return queue.filter { !$0.isRejected }.sorted { $0.createdDate < $1.createdDate }
    }

    /// A new reading for an account/category replaces any older queued (or rejected) one.
    func saveQueued(_ reading: QueuedReading) {
        ensureLoaded()
        let stale = queue.filter { $0.accountGid == reading.accountGid && $0.category == reading.category && $0.id != reading.id }
        stale.forEach { ImageStore.delete($0.imageFile) }
        queue.removeAll { $0.accountGid == reading.accountGid && $0.category == reading.category && $0.id != reading.id }
        if let i = queue.firstIndex(where: { $0.id == reading.id }) {
            queue[i] = reading
        } else {
            queue.append(reading)
        }
        write(queue, to: "queue.json")
    }

    func markAttempt(_ id: UUID) {
        ensureLoaded()
        guard let i = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[i].attemptCount += 1
        write(queue, to: "queue.json")
    }

    func markRejected(_ id: UUID, code: Int, message: String) {
        ensureLoaded()
        guard let i = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[i].isRejected = true
        queue[i].rejectionCode = code
        queue[i].rejectionMessage = message
        queue[i].rejectedAt = Date()
        write(queue, to: "queue.json")

        // Let the reader enter it again.
        let item = queue[i]
        if let a = accounts.firstIndex(where: { $0.gid == item.accountGid }) {
            accounts[a].update(item.category) { $0.isCompleted = false; $0.isSynced = false }
            write(accounts, to: "accounts.json")
        }
    }

    /// Server accepted the reading: drop it from the queue and flag the account as synced.
    func markSynced(_ id: UUID) {
        ensureLoaded()
        guard let i = queue.firstIndex(where: { $0.id == id }) else { return }
        let item = queue.remove(at: i)
        ImageStore.delete(item.imageFile)
        write(queue, to: "queue.json")
        if let a = accounts.firstIndex(where: { $0.gid == item.accountGid }) {
            accounts[a].update(item.category) { $0.isSynced = true; $0.imageFile = nil }
            write(accounts, to: "accounts.json")
        }
    }

    func deleteQueued(_ id: UUID) {
        ensureLoaded()
        if let item = queue.first(where: { $0.id == id }) { ImageStore.delete(item.imageFile) }
        queue.removeAll { $0.id == id }
        write(queue, to: "queue.json")
    }
}

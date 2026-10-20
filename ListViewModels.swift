import SwiftUI

// MARK: - Login

@MainActor @Observable
final class LoginViewModel {
    var username = ""
    var password = ""
    var isBusy = false
    var errorMessage = ""
    var isPasswordHidden = true

    var canLogin: Bool { !isBusy }

    func login(env: AppEnvironment) async {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty, !password.isEmpty else {
            errorMessage = "Username and password are required"
            return
        }
        isBusy = true
        errorMessage = ""
        defer { isBusy = false }
        do {
            try await env.login(username: user, password: password)
        } catch let error as AppError {
            errorMessage = error.message
        } catch {
            errorMessage = "Login failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Assigned areas

struct DayItem: Identifiable, Hashable {
    let date: Date
    var id: Date { date }
    var isToday: Bool { Calendar.current.isDateInToday(date) }
    var day: String { DateFormatter.make("d").string(from: date) }
    var weekday: String { DateFormatter.make("EEE").string(from: date) }
}

@MainActor @Observable
final class AreasViewModel {
    @ObservationIgnored private let env: AppEnvironment

    var days: [DayItem] = []
    var selectedDate = Calendar.current.startOfDay(for: Date())
    var areas: [AreaAssignment] = []
    var isLoading = false
    var errorMessage = ""

    init(env: AppEnvironment) {
        self.env = env
        let today = Calendar.current.startOfDay(for: Date())
        // A strip of recent days plus a few ahead.
        days = (-10...3).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }.map { DayItem(date: $0) }
    }

    // MARK: Derived

    var staffName: String { env.session?.staffName ?? "" }
    var firstName: String { env.session?.firstName ?? "" }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
        return firstName.isEmpty ? part : "\(part), \(firstName)"
    }

    var monthLabel: String { DateFormatter.make("MMMM yyyy").string(from: selectedDate) }
    var isTodaySelected: Bool { Calendar.current.isDateInToday(selectedDate) }
    var areaCount: Int { areas.count }
    var accountsTotal: Int { areas.reduce(0) { $0 + $1.accountCount } }
    var accountsCompleted: Int { areas.reduce(0) { $0 + $1.completedCount } }
    var accountsRemaining: Int { max(0, accountsTotal - accountsCompleted) }
    var overallProgress: Double { accountsTotal > 0 ? Double(accountsCompleted) / Double(accountsTotal) : 0 }
    var overallPercentText: String { "\(Int((overallProgress * 100).rounded()))%" }
    var completedSummary: String { "\(accountsCompleted) of \(accountsTotal) accounts read" }

    // MARK: Actions

    func load() async {
        isLoading = true
        errorMessage = ""
        defer { isLoading = false }

        let local = await env.store.areas(for: selectedDate)
        if local.isEmpty {
            if env.network.isOnline {
                await fetchFromServer()
                return
            }
            areas = []
            errorMessage = isTodaySelected
                ? "No internet connection available."
                : "Connect to the internet to load areas for another date."
            return
        }
        areas = await withLocalProgress(local)
    }

    func select(_ day: DayItem) async {
        selectedDate = day.date
        await load()
    }

    func goToToday() async {
        selectedDate = Calendar.current.startOfDay(for: Date())
        await load()
    }

    /// Re-reads progress from local readings (used when coming back from a reading screen).
    func reloadProgress() async {
        guard !areas.isEmpty else { return }
        areas = await withLocalProgress(areas)
    }

    func refreshFromServer() async {
        guard env.network.isOnline else {
            errorMessage = "No internet connection available"
            return
        }
        isLoading = true
        defer { isLoading = false }
        await env.store.clearAreas(for: selectedDate)
        await fetchFromServer()
    }

    private func fetchFromServer() async {
        guard let key = env.session?.staffKey else { return }
        do {
            let fetched = try await env.api.assignedAreas(staffKey: key, date: selectedDate)
            await env.store.saveAreas(fetched, for: selectedDate)
            areas = await withLocalProgress(fetched)
            errorMessage = ""
        } catch {
            errorMessage = "Error loading areas: \(error.localizedDescription)"
        }
    }

    private func withLocalProgress(_ areas: [AreaAssignment]) async -> [AreaAssignment] {
        var result = areas
        for i in result.indices {
            let accounts = await env.store.accounts(areaId: result[i].areaId)
            guard !accounts.isEmpty else { continue }
            result[i].accountCount = accounts.count
            result[i].completedCount = accounts.filter(\.isFullyCompleted).count
        }
        return result
    }
}

// MARK: - Accounts in an area

@MainActor @Observable
final class AccountsViewModel {
    @ObservationIgnored private let env: AppEnvironment
    let area: AreaAssignment

    var accounts: [AccountMeter] = []
    var query = ""
    var isLoading = false
    var errorMessage = ""

    init(env: AppEnvironment, area: AreaAssignment) {
        self.env = env
        self.area = area
    }

    var filtered: [AccountMeter] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return accounts }
        return accounts.filter {
            $0.accountNo.lowercased().contains(q) || $0.meterNo.lowercased().contains(q) || $0.premisesName.lowercased().contains(q)
        }
    }

    var totalAccounts: Int { accounts.count }
    var completedAccounts: Int { accounts.filter(\.isFullyCompleted).count }
    var completionProgress: Double { totalAccounts > 0 ? Double(completedAccounts) / Double(totalAccounts) : 0 }
    var completionPercentText: String { "\(Int((completionProgress * 100).rounded()))%" }

    func load() async {
        let local = await env.store.accounts(areaId: area.areaId)
        if !local.isEmpty {
            accounts = local
            errorMessage = ""
            return
        }
        guard env.network.isOnline else {
            errorMessage = "No internet connection available"
            return
        }
        await fetchFromServer()
    }

    /// Cheap local re-read, e.g. after saving a reading.
    func reloadLocal() async {
        let local = await env.store.accounts(areaId: area.areaId)
        if !local.isEmpty { accounts = local }
    }

    func refreshFromServer() async {
        guard env.network.isOnline else {
            errorMessage = "No internet connection available"
            return
        }
        await fetchFromServer()
    }

    private func fetchFromServer() async {
        guard !area.gid.isEmpty else { errorMessage = "Area GUID is missing. Cannot fetch accounts."; return }
        guard area.brId > 0 else { errorMessage = "Branch ID is missing. Cannot fetch accounts."; return }
        guard let key = env.session?.staffKey else { return }

        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await env.api.areaAccounts(staffKey: key, brId: area.brId, areaId: area.areaId)
            await env.store.replaceAccounts(fetched, areaId: area.areaId)
            accounts = await env.store.accounts(areaId: area.areaId)
            errorMessage = accounts.isEmpty ? "No accounts found for this area" : ""
        } catch {
            errorMessage = "Error refreshing accounts: \(error.localizedDescription)"
        }
    }
}

// MARK: - Queue

@MainActor @Observable
final class QueueViewModel {
    @ObservationIgnored private let env: AppEnvironment

    var readings: [QueuedReading] = []
    var isSyncing = false
    var errorMessage = ""

    init(env: AppEnvironment) { self.env = env }

    var pendingCount: Int { readings.filter { !$0.isRejected }.count }
    var rejectedCount: Int { readings.filter(\.isRejected).count }
    var hasItems: Bool { !readings.isEmpty }

    var pendingCountText: String {
        pendingCount == 1 ? "1 reading waiting to sync" : "\(pendingCount) readings waiting to sync"
    }

    var rejectedCountText: String {
        rejectedCount == 1
            ? "1 reading was rejected — re-enter it to send again"
            : "\(rejectedCount) readings were rejected — re-enter them to send again"
    }

    func load() async {
        readings = await env.store.queuedReadings()
        await env.refreshPendingCount()
    }

    func delete(_ reading: QueuedReading) async {
        await env.store.deleteQueued(reading.id)
        await load()
    }

    /// Returns a message for the UI to show, or nil if nothing needs saying.
    func submitAll() async -> Notice? {
        guard env.network.isOnline else {
            return Notice(title: "No Internet",
                          message: "No internet connection. Readings stay safely queued until you're back online.")
        }
        if readings.isEmpty {
            return Notice(title: "No Pending Data", message: "There are no readings in the queue to synchronize.")
        }
        if pendingCount == 0 {
            return Notice(title: "Nothing to Send",
                          message: "Every queued reading was rejected by the server. Open each account and enter a corrected reading.")
        }

        isSyncing = true
        defer { isSyncing = false }
        let summary = await env.sync.syncPendingReadings()
        await load()

        if summary.alreadyRunning { return nil }
        if summary.synced == 0 && summary.rejected > 0 {
            return Notice(title: "Readings Rejected",
                          message: "The server rejected \(summary.rejected) reading(s). Open each account and enter a corrected reading.")
        }
        if summary.synced == 0 {
            return Notice(title: "Sync Failed",
                          message: "Unable to synchronize any readings. This could be due to server connectivity issues. The app will continue to attempt synchronization automatically.")
        }
        if summary.remaining == 0 && summary.rejected == 0 {
            return Notice(title: "Sync Complete", message: "All readings have been synchronized successfully.")
        }
        let left = summary.remaining + summary.rejected
        return Notice(title: "Partial Sync",
                      message: "Synchronized \(summary.synced) readings. \(left) readings remain in queue and will be automatically synchronized when possible.")
    }
}

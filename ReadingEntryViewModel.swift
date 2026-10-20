import SwiftUI

struct ContactEntry: Identifiable {
    let id = UUID()
    let title: String
    let name: String
    let number: String
}

@MainActor @Observable
final class ReadingEntryViewModel {
    enum MarginAlert { case none, above, below }
    enum SaveCheck {
        case invalid(String)
        case needsConfirmation(String)
        case ready
    }

    @ObservationIgnored private let env: AppEnvironment
    let accountGid: String
    @ObservationIgnored private let requestedCategory: MeterCategory?

    // Account state
    var account: AccountMeter?
    var category: MeterCategory = .electricity
    var loadError = ""

    // Input + calculation
    var newReadingText = ""
    var errorMessage = ""
    var isValidReading = false
    var totalUnits = 0.0
    var days = 0
    var avgPerDay = 0.0
    var marginAlert: MarginAlert = .none
    var history: [BillHistoryEntry] = []

    // Photo
    var previewImage: UIImage?
    var isProcessingImage = false
    var isFlashlightOn = false

    // Saving / UI
    var isSaving = false
    var goToNextAccount = true
    var notice: Notice?
    var quickCommentDraft = ""

    @ObservationIgnored private var imageData: Data?

    init(env: AppEnvironment, accountGid: String, requestedCategory: MeterCategory?) {
        self.env = env
        self.accountGid = accountGid
        self.requestedCategory = requestedCategory
    }

    // MARK: Derived

    var currentReading: CategoryReading? { account?.reading(for: category) }
    var hasMultipleCategories: Bool { account?.hasMultipleCategories ?? false }
    var xFactorText: String { (currentReading?.xFactor ?? 1).readingText(maxDecimals: 3) }
    var previousReadingText: String { (currentReading?.previousReading ?? 0).readingText(maxDecimals: max(category.maxDecimals, 3)) }
    var previousReadingDateText: String {
        guard let date = currentReading?.previousReadingDate else { return "—" }
        return DateFormatter.make("dd MMM yyyy").string(from: date)
    }
    var totalUnitsText: String { "Total \(totalUnits.readingText(maxDecimals: 2)) \(category.unit)" }
    var avgUnitsText: String { "Avg \(avgPerDay.readingText(maxDecimals: 2)) \(category.unit)/day" }
    var hasSelectedImage: Bool { previewImage != nil }

    var marginText: String? {
        switch marginAlert {
        case .none: return nil
        case .above: return "Above Margin"
        case .below: return "Below Margin"
        }
    }

    var saveButtonText: String {
        guard let account else { return "Save" }
        let base = account.hasMultipleCategories ? "Save \(category.displayName)" : "Save"
        let otherPending = account.readings.contains { $0.category != category && !$0.isCompleted }
        if otherPending { return base + " & Next Reading" }
        return goToNextAccount ? base + " & Next Account" : base
    }

    var contacts: [ContactEntry] {
        guard let a = account else { return [] }
        return [
            ContactEntry(title: "Owner", name: a.ownerName, number: a.ownerContact),
            ContactEntry(title: "Consumer", name: a.consumerName, number: a.consumerContact),
            ContactEntry(title: "SMS Contact", name: a.smsName, number: a.smsNumber)
        ].filter { !$0.number.isEmpty }
    }

    // MARK: Loading

    func load() async {
        guard let loaded = await env.store.account(gid: accountGid) else {
            loadError = "Account not found"
            return
        }
        account = loaded
        let start = requestedCategory.flatMap { loaded.categories.contains($0) ? $0 : nil }
            ?? loaded.firstPendingCategory
            ?? loaded.categories.first
            ?? .electricity
        await select(start)
    }

    func select(_ newCategory: MeterCategory) async {
        category = newCategory
        errorMessage = ""
        previewImage = nil
        imageData = nil
        history = []
        marginAlert = .none

        // Re-opening a finished reading pre-fills it so it can be corrected.
        if let existing = account?.reading(for: newCategory), existing.isCompleted, let value = existing.newReading {
            newReadingText = value.readingText(maxDecimals: newCategory.maxDecimals)
        } else {
            newReadingText = ""
        }
        recalculate()
        await loadHistory()
        recalculate()
    }

    private func loadHistory() async {
        guard let account else { return }
        let cat = category
        var entries = await env.store.billHistory(accountNo: account.accountNo, category: cat)
        if entries.isEmpty, env.network.isOnline {
            if let fetched = try? await env.api.billHistory(accountNo: account.accountNo, category: cat, count: 6), !fetched.isEmpty {
                await env.store.saveBillHistory(fetched, accountNo: account.accountNo, category: cat)
                entries = await env.store.billHistory(accountNo: account.accountNo, category: cat)
            }
        }
        if cat == category { history = entries }
    }

    // MARK: Input handling

    func readingTextChanged() {
        let cleaned = sanitize(newReadingText)
        if cleaned != newReadingText {
            newReadingText = cleaned
            return
        }
        recalculate()
    }

    private func sanitize(_ text: String) -> String {
        var out = ""
        var seenDot = false
        var decimals = 0
        for ch in text {
            if ch.isASCII && ch.isNumber {
                if seenDot {
                    if decimals >= category.maxDecimals { continue }
                    decimals += 1
                }
                out.append(ch)
            } else if (ch == "." || ch == ",") && category.allowsDecimals && !seenDot {
                seenDot = true
                out.append(".")
            }
        }
        return out
    }

    private func recalculate() {
        errorMessage = ""
        marginAlert = .none
        totalUnits = 0
        avgPerDay = 0
        days = 0
        isValidReading = false

        let trimmed = newReadingText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard let value = Double(trimmed), value >= 0, let cr = currentReading else {
            errorMessage = "Please enter a valid reading"
            return
        }
        if value < cr.previousReading {
            errorMessage = "New reading is smaller than previous \(category.displayName.lowercased()) reading!"
            return
        }

        isValidReading = true
        let factor = category.usesXFactor ? cr.xFactor : 1
        totalUnits = (value - cr.previousReading) * factor

        let calendar = Calendar.current
        if let prev = cr.previousReadingDate {
            let diff = calendar.dateComponents([.day], from: calendar.startOfDay(for: prev), to: calendar.startOfDay(for: Date())).day ?? 1
            days = max(1, diff)
        } else {
            days = max(1, cr.previousDays)
        }
        avgPerDay = totalUnits / Double(days)
        marginAlert = computeMarginAlert(for: cr)
    }

    /// Compares today's per-day consumption with the account's usual daily average.
    private func computeMarginAlert(for cr: CategoryReading) -> MarginAlert {
        guard category.usesMarginAlert else { return .none }
        let recent = history.prefix(6).map(\.avgCons).filter { $0 > 0 }
        let baseline: Double
        if !recent.isEmpty {
            baseline = recent.reduce(0, +) / Double(recent.count)
        } else if cr.previousConsumption > 0, cr.previousDays > 0 {
            baseline = cr.previousConsumption / Double(cr.previousDays)
        } else {
            return .none
        }
        guard baseline > 0 else { return .none }
        let deviation = (avgPerDay - baseline) / baseline * 100
        if deviation > AppConfig.consumptionMarginPercent { return .above }
        if deviation < -AppConfig.consumptionMarginPercent { return .below }
        return .none
    }

    // MARK: Saving

    func validateForSave() -> SaveCheck {
        recalculate()
        guard isValidReading else {
            return .invalid(errorMessage.isEmpty ? "Please enter a valid reading" : errorMessage)
        }
        if let text = marginText {
            return .needsConfirmation("\(text)\nDo you want to proceed with saving?")
        }
        return .ready
    }

    func commitSave() async {
        guard var account, let value = Double(newReadingText), !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        var savedFile: String?
        if let data = imageData {
            savedFile = try? ImageStore.save(data)
        }

        let queued = QueuedReading(areaGid: "",
                                   accountGid: account.gid,
                                   brId: account.brId,
                                   accountNo: account.accountNo,
                                   meterNo: account.meterNo,
                                   category: category,
                                   newReading: value,
                                   quickComment: account.quickComment,
                                   imageFile: savedFile)
        await env.store.saveQueued(queued)

        let cat = category
        account.update(cat) {
            $0.newReading = value
            $0.newReadingDate = Date()
            $0.imageFile = savedFile
            $0.isCompleted = true
            $0.isSynced = false
        }
        await env.store.updateAccount(account)
        self.account = account
        await env.refreshPendingCount()

        // Try to send straight away; the queue keeps it safe if that fails.
        if env.network.isOnline {
            Task { await env.sync.syncPendingReadings() }
        }

        await navigateAfterSave(from: account)
    }

    private func navigateAfterSave(from account: AccountMeter) async {
        if let next = account.nextPendingCategory(after: category), next != category {
            await select(next)
            return
        }
        guard goToNextAccount, let nextAccount = await findNextAccount(after: account) else {
            if !env.areasPath.isEmpty { env.areasPath.removeLast() }
            return
        }
        let route = Route.reading(accountGid: nextAccount.gid, category: nextAccount.firstPendingCategory)
        if env.areasPath.isEmpty {
            env.areasPath.append(route)
        } else {
            env.areasPath[env.areasPath.count - 1] = route
        }
    }

    private func findNextAccount(after current: AccountMeter) async -> AccountMeter? {
        let all = await env.store.accounts(areaId: current.areaId)
        guard let index = all.firstIndex(where: { $0.gid == current.gid }) else { return nil }
        let after = all[(index + 1)...].first { !$0.isFullyCompleted }
        let before = all[..<index].first { !$0.isFullyCompleted }
        return after ?? before
    }

    // MARK: Quick comment

    func beginEditingComment() { quickCommentDraft = account?.quickComment ?? "" }

    func saveComment() async {
        guard var account else { return }
        account.quickComment = quickCommentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        await env.store.updateAccount(account)
        self.account = account
    }

    // MARK: Photos

    func handlePicked(_ image: UIImage, saveToLibrary: Bool) async {
        isProcessingImage = true
        defer { isProcessingImage = false }
        guard let data = await ImageProcessor.optimized(image) else {
            notice = Notice(title: "Error", message: "Error selecting image: the photo could not be processed.")
            return
        }
        imageData = data
        previewImage = UIImage(data: data)
        if saveToLibrary, let account {
            await ImageProcessor.saveToPhotoLibrary(data, accountNo: account.accountNo)
        }
    }

    func removeImage() {
        imageData = nil
        previewImage = nil
    }

    func toggleFlashlight() {
        guard Flashlight.isAvailable else {
            notice = Notice(title: "Not Supported", message: "Flashlight is not supported on this device.")
            return
        }
        let target = !isFlashlightOn
        if Flashlight.set(target) {
            isFlashlightOn = target
        } else {
            notice = Notice(title: "Error", message: "Error toggling flashlight.")
        }
    }

    func turnOffFlashlight() {
        if isFlashlightOn {
            Flashlight.set(false)
            isFlashlightOn = false
        }
    }

    // MARK: Contacts

    func contact(via scheme: String, number: String) {
        let cleaned = number.filter { $0.isNumber || $0 == "+" }
        guard !cleaned.isEmpty, let url = URL(string: "\(scheme):\(cleaned)") else { return }
        UIApplication.shared.open(url) { [weak self] ok in
            guard !ok else { return }
            Task { @MainActor in
                self?.notice = Notice(title: "Not Supported", message: "This action is not supported on this device.")
            }
        }
    }
}

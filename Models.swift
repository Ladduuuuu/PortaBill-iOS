import Foundation
import SwiftUI

// MARK: - Meter categories

enum MeterCategory: Int, Codable, CaseIterable, Identifiable, Hashable {
    case electricity = 0
    case water = 1
    case netMeter = 2

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .electricity: return "Electricity"
        case .water: return "Water"
        case .netMeter: return "Net Meter"
        }
    }

    var shortName: String {
        switch self {
        case .electricity: return "Elec"
        case .water: return "Water"
        case .netMeter: return "Net"
        }
    }

    var unit: String {
        switch self {
        case .electricity: return "kWh"
        case .water: return "m³"
        case .netMeter: return "kWh (export)"
        }
    }

    var symbol: String {
        switch self {
        case .electricity: return "bolt.fill"
        case .water: return "drop.fill"
        case .netMeter: return "sun.max.fill"
        }
    }

    var color: Color {
        switch self {
        case .electricity: return Color(hex: 0xF59E0B)
        case .water: return Color(hex: 0x0EA5E9)
        case .netMeter: return Color(hex: 0x10B981)
        }
    }

    var tint: Color {
        switch self {
        case .electricity: return Color(hex: 0xFEF3E2)
        case .water: return Color(hex: 0xE5F6FE)
        case .netMeter: return Color(hex: 0xE7F8F1)
        }
    }

    // NOTE: the next four flags are inferred, see README ("Things to verify").
    var usesXFactor: Bool { true }
    var usesMarginAlert: Bool { self != .netMeter }
    var allowsDecimals: Bool { self == .water }
    var maxDecimals: Int { self == .water ? 3 : 0 }

    /// Value sent as `en_Type` when submitting a reading (verify against your backend).
    var serverType: Int { rawValue }

    var photoHint: String { "Photo of the \(displayName.lowercased()) meter" }
}

// MARK: - Per-category reading state on an account

struct CategoryReading: Codable, Hashable {
    var category: MeterCategory
    var xFactor: Double = 1
    var previousReading: Double = 0
    var previousReadingDate: Date?
    var previousConsumption: Double = 0
    var previousDays: Int = 0
    var newReading: Double?
    var newReadingDate: Date?
    var imageFile: String?
    var isCompleted = false
    var isSynced = false
}

// MARK: - Account / meter

struct AccountMeter: Codable, Identifiable, Hashable {
    var gid: String
    var areaId: Int
    var brId: Int
    var rowNumber: Int
    var premisesName: String
    var accountNo: String
    var meterNo: String
    var tariffCategory: String
    var meterPhase: String
    var visitingOrderNo: String
    var ownerName: String = ""
    var ownerContact: String = ""
    var consumerName: String = ""
    var consumerContact: String = ""
    var smsName: String = ""
    var smsNumber: String = ""
    var onHold: Bool = false
    var alertMessage: String = ""
    var newBillRef: String = ""
    var quickComment: String = ""
    var readings: [CategoryReading]

    var id: String { gid }
    var categories: [MeterCategory] { readings.map(\.category) }
    var hasMultipleCategories: Bool { readings.count > 1 }

    func reading(for category: MeterCategory) -> CategoryReading? {
        readings.first { $0.category == category }
    }

    mutating func update(_ category: MeterCategory, _ change: (inout CategoryReading) -> Void) {
        guard let i = readings.firstIndex(where: { $0.category == category }) else { return }
        change(&readings[i])
    }

    var isFullyCompleted: Bool { !readings.isEmpty && readings.allSatisfy(\.isCompleted) }
    var isFullySynced: Bool { !readings.isEmpty && readings.allSatisfy(\.isSynced) }
    var completedCategoryCount: Int { readings.filter(\.isCompleted).count }
    var completionText: String { "\(completedCategoryCount) of \(readings.count) read" }
    var firstPendingCategory: MeterCategory? { readings.first { !$0.isCompleted }?.category }

    func nextPendingCategory(after category: MeterCategory) -> MeterCategory? {
        guard let i = readings.firstIndex(where: { $0.category == category }) else { return firstPendingCategory }
        let later = readings[(i + 1)...].first { !$0.isCompleted }
        let earlier = readings[..<i].first { !$0.isCompleted }
        return (later ?? earlier)?.category
    }
}

// MARK: - Area assignment

struct AreaAssignment: Codable, Identifiable, Hashable {
    var gid: String
    var brId: Int
    var areaId: Int
    var orderNumber: Int
    var areaName: String
    var accountCount: Int
    var completedCount: Int

    var id: String { "\(gid)-\(areaId)" }
    var remaining: Int { max(0, accountCount - completedCount) }
    var progress: Double { accountCount > 0 ? Double(completedCount) / Double(accountCount) : 0 }
    var isComplete: Bool { accountCount > 0 && completedCount >= accountCount }
    var isNotStarted: Bool { completedCount == 0 }
    var isInProgress: Bool { !isNotStarted && !isComplete }
    var statusText: String { isComplete ? "Completed" : (isInProgress ? "In progress" : "Not started") }
    var statusColor: Color { isComplete ? Theme.success : (isInProgress ? Theme.primary : Theme.muted) }
    var statusTint: Color { isComplete ? Theme.successTint : (isInProgress ? Theme.primaryTint : Theme.field) }
}

// MARK: - Bill history

struct BillHistoryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var accountNo: String
    var category: MeterCategory
    var billYear: Int
    var billNo: Int
    var billRef: String
    var avgCons: Double
    var invoiceTotal: Double
    var consumption: Double
    var totalDays: Int
    var previousReading: Double
    var meterReading: Double
}

// MARK: - Offline queue

struct QueuedReading: Codable, Identifiable, Hashable {
    var id = UUID()
    var areaGid: String
    var accountGid: String
    var brId: Int
    var accountNo: String
    var meterNo: String
    var category: MeterCategory
    var newReading: Double
    var quickComment: String
    var imageFile: String?
    var createdDate = Date()
    var isRejected = false
    var rejectionCode: Int?
    var rejectionMessage: String?
    var rejectedAt: Date?
    var attemptCount = 0

    var hasFile: Bool { imageFile != nil }
    var statusText: String { isRejected ? "Needs correction" : "Waiting to sync" }
    var readingText: String { newReading.readingText(maxDecimals: category.maxDecimals) + " " + category.unit }
}

// MARK: - Session

struct Session: Codable, Equatable {
    var username: String
    var staffName: String
    var staffKey: String
    var expireDate: Date?

    var firstName: String {
        staffName.split(separator: " ").first.map(String.init) ?? staffName
    }
}

// MARK: - Network DTOs

struct LoginResponse {
    var success: Bool
    var staffName: String
    var staffKey: String
    var expireDate: Date?
}

struct NewReadingRequest: Encodable {
    var staffKey: String
    var gid: String
    var accountNo: String
    var newReading: String
    var brId: Int
    var comment: String
    var fileBytesBase64: String?
    var fileName: String?
    var quickComment: String
    var enType: Int
    var appId: String

    enum CodingKeys: String, CodingKey {
        case staffKey = "StaffKey"
        case gid
        case accountNo = "AccountNo"
        case newReading = "NewReading"
        case brId = "brID"
        case comment = "Comment"
        case fileBytesBase64 = "FilBytes"
        case fileName = "FilName"
        case quickComment = "QuickComment"
        case enType = "en_Type"
        case appId = "app_ID"
    }
}

struct SaveReadingResult {
    var statusCode: Int
    var message: String
    var httpStatus: Int
    var noResponse: Bool

    var isSuccess: Bool { !noResponse && statusCode == AppConfig.successCode }
    var isRejected: Bool { !noResponse && AppConfig.rejectedCodes.contains(statusCode) }
    var isRetryable: Bool { !isSuccess && !isRejected }

    static func ok() -> SaveReadingResult {
        SaveReadingResult(statusCode: AppConfig.successCode, message: "", httpStatus: 200, noResponse: false)
    }
    static func rejected(_ message: String, code: Int = 423) -> SaveReadingResult {
        SaveReadingResult(statusCode: code, message: message, httpStatus: 200, noResponse: false)
    }
    static func networkFailure(_ message: String) -> SaveReadingResult {
        SaveReadingResult(statusCode: 0, message: message, httpStatus: 0, noResponse: true)
    }
}

// MARK: - Formatting helpers

extension Double {
    func readingText(maxDecimals: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = maxDecimals
        return f.string(from: NSNumber(value: self)) ?? String(self)
    }
}

extension DateFormatter {
    static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }
}

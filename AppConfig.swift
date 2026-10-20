import Foundation

/// Central place for everything you need to configure before shipping.
enum AppConfig {
    /// `true` = fully offline demo data (no server needed). Set to `false` to use the real backend.
    static let useMockApi = true

    /// Base URL of the readings API, without trailing slash, e.g. "https://your-host/api/PBread".
    static let apiBaseURL = ""

    /// Application ID the backend expects in `app_ID` on reading submissions.
    static let appId = ""

    static let organizationName = "State Electric Company Limited"
    static let productSubtitle = "Field meter reading"

    /// Consumption (per day) deviating more than this % from the account's usual average raises a margin alert.
    static let consumptionMarginPercent = 35.0

    /// Server status codes.
    static let successCode = 200
    static let rejectedCodes: Set<Int> = [423, 306]

    /// How often queued readings are retried while the app is open.
    static let backgroundSyncInterval: TimeInterval = 60

    static var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "v\(v) (\(b))"
    }
}

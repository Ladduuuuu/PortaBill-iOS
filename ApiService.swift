import Foundation

protocol ApiService: Sendable {
    func login(username: String, password: String) async throws -> LoginResponse
    func assignedAreas(staffKey: String, date: Date) async throws -> [AreaAssignment]
    func areaAccounts(staffKey: String, brId: Int, areaId: Int) async throws -> [AccountMeter]
    func billHistory(accountNo: String, category: MeterCategory, count: Int) async throws -> [BillHistoryEntry]
    func postSaveNewReading(_ request: NewReadingRequest) async -> SaveReadingResult
}

enum ApiError: LocalizedError {
    case notConfigured
    case http(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "The API base URL is not configured (see AppConfig.swift)."
        case .http(let code): return "Server returned HTTP \(code)."
        case .invalidResponse: return "The server response could not be read."
        }
    }
}

// MARK: - Live implementation

/// Talks to the real backend. Endpoint paths and field names were recovered from the Android app;
/// the exact JSON shapes should be checked against your server (see README).
final class LiveApiService: ApiService, @unchecked Sendable {
    private let baseURL: String
    private let session: URLSession

    init(baseURL: String = AppConfig.apiBaseURL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    // MARK: Plumbing

    private func makeURL(_ path: String, query: [(String, String)] = []) throws -> URL {
        guard !baseURL.isEmpty, var components = URLComponents(string: baseURL + path) else { throw ApiError.notConfigured }
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) } }
        guard let url = components.url else { throw ApiError.notConfigured }
        return url
    }

    private func getJSON(_ path: String, query: [(String, String)]) async throws -> Any {
        var request = URLRequest(url: try makeURL(path, query: query))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try JSONSerialization.jsonObject(with: data)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw ApiError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw ApiError.http(http.statusCode) }
    }

    private func objects(_ json: Any) -> [[String: Any]] {
        if let list = json as? [[String: Any]] { return list }
        if let dict = json as? [String: Any] {
            for key in ["data", "Data", "result", "Result", "items", "Items"] {
                if let list = dict[key] as? [[String: Any]] { return list }
            }
        }
        return []
    }

    // MARK: ApiService

    func login(username: String, password: String) async throws -> LoginResponse {
        var request = URLRequest(url: try makeURL("/LoginValidation"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["Username": username, "Password": password])
        let (data, response) = try await session.data(for: request)
        try validate(response)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ApiError.invalidResponse }
        let reader = JSONReader(obj)
        return LoginResponse(success: reader.bool("Success"),
                             staffName: reader.string("StaffName"),
                             staffKey: reader.string("StaffSecretKey"),
                             expireDate: reader.date("ExpireDate"))
    }

    func assignedAreas(staffKey: String, date: Date) async throws -> [AreaAssignment] {
        let json = try await getJSON("/GetStaffAssignedAreaForToday", query: [
            ("StaffKey", staffKey),
            ("schedDate", DateFormatter.make("yyyy-MM-dd").string(from: date))
        ])
        return objects(json).enumerated().map { index, o in
            let r = JSONReader(o)
            return AreaAssignment(gid: r.string("Gid"),
                                  brId: r.int("brID"),
                                  areaId: r.int("AreaId"),
                                  orderNumber: r.int("OrderNumber", default: index + 1),
                                  areaName: r.string("AreaName"),
                                  accountCount: r.int("NoOfAccounts"),
                                  completedCount: r.int("NoOfAccountsCompleted"))
        }
    }

    func areaAccounts(staffKey: String, brId: Int, areaId: Int) async throws -> [AccountMeter] {
        let json = try await getJSON("/GetStaffAssignedAreaAccounts", query: [
            ("StaffKey", staffKey),
            ("brID", String(brId)),
            ("rangeId", String(areaId))
        ])
        return objects(json).enumerated().map { index, o in
            Self.account(from: JSONReader(o), fallbackRow: index + 1, areaId: areaId, brId: brId)
        }
    }

    func billHistory(accountNo: String, category: MeterCategory, count: Int) async throws -> [BillHistoryEntry] {
        let json = try await getJSON("/GetACBillHist", query: [
            ("dbM", DateFormatter.make("yyyyMM").string(from: Date())),
            ("acNo", accountNo),
            ("nrecs", String(count)),
            ("fmode", String(category.serverType))
        ])
        return objects(json).map { o in
            let r = JSONReader(o)
            return BillHistoryEntry(accountNo: accountNo,
                                    category: category,
                                    billYear: r.int("bill_year"),
                                    billNo: r.int("bill_no"),
                                    billRef: r.string("billref"),
                                    avgCons: r.double("avg_cons"),
                                    invoiceTotal: r.double("invoice_total"),
                                    consumption: r.double("consumption"),
                                    totalDays: r.int("tot_days"),
                                    previousReading: r.double("pre_reading"),
                                    meterReading: r.double("meter_reading"))
        }
    }

    func postSaveNewReading(_ request: NewReadingRequest) async -> SaveReadingResult {
        do {
            var urlRequest = URLRequest(url: try makeURL("/PostSaveNewReading"))
            urlRequest.httpMethod = "POST"
            urlRequest.timeoutInterval = 60
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
            urlRequest.httpBody = try JSONEncoder().encode(request)

            let (data, response) = try await session.data(for: urlRequest)
            let http = (response as? HTTPURLResponse)?.statusCode ?? 0
            var code = http
            var message = ""
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let r = JSONReader(obj)
                let c = r.int("StatusCode", default: -1)
                if c >= 0 { code = c }
                message = r.string("Message")
            }
            return SaveReadingResult(statusCode: code, message: message, httpStatus: http, noResponse: false)
        } catch {
            return .networkFailure(error.localizedDescription)
        }
    }

    // MARK: Mapping

    private static func account(from r: JSONReader, fallbackRow: Int, areaId: Int, brId: Int) -> AccountMeter {
        let hasWater = r.bool("HasWater")
        let hasNet = r.bool("HasNetMeter")
        let hasElectricity = r.has("HasElectricity") ? r.bool("HasElectricity") : true

        var readings: [CategoryReading] = []
        if hasElectricity || (!hasWater && !hasNet) {
            readings.append(CategoryReading(category: .electricity,
                                            xFactor: r.double("Xfactor", default: 1),
                                            previousReading: r.double("PreviousReading"),
                                            previousReadingDate: r.date("PrevousRedingDate"),
                                            previousConsumption: r.double("PreviousCons"),
                                            previousDays: r.int("PreviousDays")))
        }
        if hasWater {
            readings.append(CategoryReading(category: .water,
                                            xFactor: r.double("WaterXfactor", default: 1),
                                            previousReading: r.double("PreviousWaterReading"),
                                            previousReadingDate: r.date("PrevousWaterRedingDate"),
                                            previousConsumption: r.double("PreviousWaterCons"),
                                            previousDays: r.int("PreviousWaterDays")))
        }
        if hasNet {
            readings.append(CategoryReading(category: .netMeter,
                                            xFactor: r.double("NetXfactor", default: 1),
                                            previousReading: r.double("PreviousNetReading"),
                                            previousReadingDate: r.date("PrevousNetRedingDate"),
                                            previousConsumption: r.double("PreviousNetCons"),
                                            previousDays: r.int("PreviousNetDays")))
        }

        return AccountMeter(gid: r.string("ent_gid"),
                            areaId: areaId,
                            brId: brId,
                            rowNumber: r.int("RowNumber", default: fallbackRow),
                            premisesName: r.string("PremisesName"),
                            accountNo: r.string("AccountNo"),
                            meterNo: r.string("MeterNo"),
                            tariffCategory: r.string("TariffCat"),
                            meterPhase: r.string("MeterPhase"),
                            visitingOrderNo: r.string("VisintingOrderNo"),
                            ownerName: r.string("OwnerName"),
                            ownerContact: r.string("OwnerContact"),
                            consumerName: r.string("ConsumerName"),
                            consumerContact: r.string("ConsumerContact"),
                            smsName: r.string("SMSName"),
                            smsNumber: r.string("SmsNo"),
                            onHold: r.bool("OnHold"),
                            alertMessage: r.string("AlertMsg"),
                            quickComment: r.string("QuickComment"),
                            readings: readings)
    }
}

// MARK: - Lenient JSON reading

/// Backends like this one often mix strings, numbers and 0/1 flags. This reader is forgiving about all of it.
struct JSONReader {
    let object: [String: Any]
    init(_ object: [String: Any]) { self.object = object }

    private func value(_ key: String) -> Any? {
        if let v = object[key], !(v is NSNull) { return v }
        // Case-insensitive fallback.
        let lower = key.lowercased()
        for (k, v) in object where k.lowercased() == lower && !(v is NSNull) { return v }
        return nil
    }

    func has(_ key: String) -> Bool { value(key) != nil }

    func string(_ key: String) -> String {
        guard let v = value(key) else { return "" }
        if let s = v as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }

    func double(_ key: String, default fallback: Double = 0) -> Double {
        guard let v = value(key) else { return fallback }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String, let d = Double(s.trimmingCharacters(in: .whitespaces)) { return d }
        return fallback
    }

    func int(_ key: String, default fallback: Int = 0) -> Int {
        guard let v = value(key) else { return fallback }
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String, let i = Int(s.trimmingCharacters(in: .whitespaces)) { return i }
        return fallback
    }

    func bool(_ key: String) -> Bool {
        guard let v = value(key) else { return false }
        if let n = v as? NSNumber { return n.boolValue }
        if let s = v as? String { return ["true", "yes", "y", "1"].contains(s.lowercased()) }
        return false
    }

    func date(_ key: String) -> Date? {
        let s = string(key)
        guard !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "dd/MM/yyyy", "dd-MMM-yyyy"] {
            if let d = DateFormatter.make(format).date(from: s) { return d }
        }
        return nil
    }
}

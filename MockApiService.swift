import Foundation

/// Deterministic demo backend so the whole app can be tried without a server.
/// Any non-empty username works; use the password "wrong" to see a failed login.
/// A new reading of exactly 0 is rejected by the "server" so you can see the "Needs correction" flow.
struct MockApiService: ApiService {

    // MARK: Seeded random numbers (same data every launch)

    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    private static let premises = ["Sunrise Villa", "Coral House", "Palm Court", "Blue Lagoon", "Green Gate", "Harbour View",
                                   "Star Residence", "Lotus Lodge", "Ocean Breeze", "Moonlight Manor", "Sandy Nook", "Rose Cottage"]
    private static let streets = ["Orchid Magu", "Boduthakurufaanu Magu", "Majeedhee Magu", "Sosun Magu", "Kaneeru Goalhi", "Fareedhee Magu"]
    private static let people = ["Ahmed Naseem", "Fathimath Shifa", "Mohamed Hassan", "Aishath Zahira", "Ibrahim Rasheed", "Mariyam Nuha"]
    private static let tariffs = ["Domestic", "Domestic", "Commercial", "Domestic", "Industrial"]
    private static let alerts = ["", "", "", "", "", "Check for leaks", "Dog on premises", "Meter box locked – call owner"]

    // MARK: ApiService

    func login(username: String, password: String) async throws -> LoginResponse {
        try await Task.sleep(nanoseconds: 600_000_000)
        guard !username.isEmpty, password != "wrong" else {
            return LoginResponse(success: false, staffName: "", staffKey: "", expireDate: nil)
        }
        return LoginResponse(success: true,
                             staffName: "Demo Reader",
                             staffKey: "demo-staff-key",
                             expireDate: Calendar.current.date(byAdding: .day, value: 30, to: Date()))
    }

    func assignedAreas(staffKey: String, date: Date) async throws -> [AreaAssignment] {
        try await Task.sleep(nanoseconds: 400_000_000)
        let day = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
        return [
            AreaAssignment(gid: "demo-area-\(day)-1", brId: 1, areaId: 1000 + (day % 50) * 2,
                           orderNumber: 1, areaName: "Area \(12 + day % 5) (Range: 1149-1386)",
                           accountCount: 14, completedCount: 0),
            AreaAssignment(gid: "demo-area-\(day)-2", brId: 1, areaId: 1001 + (day % 50) * 2,
                           orderNumber: 2, areaName: "Area \(13 + day % 5) (Range: 1400-1550)",
                           accountCount: 11, completedCount: 0)
        ]
    }

    func areaAccounts(staffKey: String, brId: Int, areaId: Int) async throws -> [AccountMeter] {
        try await Task.sleep(nanoseconds: 500_000_000)
        let count = areaId % 2 == 0 ? 14 : 11
        var rng = SeededGenerator(state: UInt64(areaId) &* 7919)
        let now = Date()

        return (1...count).map { row in
            let hasWater = Int.random(in: 0..<4, using: &rng) == 0
            let hasNet = Int.random(in: 0..<7, using: &rng) == 0
            let daysAgo = Int.random(in: 27...34, using: &rng)
            let prevDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)

            let elecPrev = Double(Int.random(in: 4_000...48_000, using: &rng))
            let elecCons = Double(Int.random(in: 120...620, using: &rng))
            var readings = [CategoryReading(category: .electricity,
                                            xFactor: [1, 1, 1, 10, 40].randomElement(using: &rng) ?? 1,
                                            previousReading: elecPrev,
                                            previousReadingDate: prevDate,
                                            previousConsumption: elecCons,
                                            previousDays: daysAgo)]
            if hasWater {
                readings.append(CategoryReading(category: .water, xFactor: 1,
                                                previousReading: Double(Int.random(in: 100...900, using: &rng)) + 0.25,
                                                previousReadingDate: prevDate,
                                                previousConsumption: Double(Int.random(in: 8...30, using: &rng)),
                                                previousDays: daysAgo))
            }
            if hasNet {
                readings.append(CategoryReading(category: .netMeter, xFactor: 1,
                                                previousReading: Double(Int.random(in: 200...5_000, using: &rng)),
                                                previousReadingDate: prevDate,
                                                previousConsumption: Double(Int.random(in: 20...140, using: &rng)),
                                                previousDays: daysAgo))
            }

            let name = Self.premises[(row + areaId) % Self.premises.count]
            let street = Self.streets[(row * 3 + areaId) % Self.streets.count]
            let owner = Self.people[(row + 1) % Self.people.count]
            let consumer = Self.people[(row + 3) % Self.people.count]

            return AccountMeter(gid: "demo-acc-\(areaId)-\(row)",
                                areaId: areaId, brId: brId, rowNumber: row,
                                premisesName: "\(name), \(street)",
                                accountNo: String(2_000_000 + areaId * 100 + row),
                                meterNo: String(70_000_000 + areaId * 31 + row * 7),
                                tariffCategory: Self.tariffs[row % Self.tariffs.count],
                                meterPhase: row % 5 == 0 ? "Three" : "Single",
                                visitingOrderNo: String(row),
                                ownerName: owner, ownerContact: "7\(String(format: "%06d", 100_000 + row * 137))",
                                consumerName: consumer, consumerContact: "9\(String(format: "%06d", 200_000 + row * 91))",
                                smsName: consumer, smsNumber: "9\(String(format: "%06d", 200_000 + row * 91))",
                                alertMessage: Self.alerts[(row + areaId) % Self.alerts.count],
                                readings: readings)
        }
    }

    func billHistory(accountNo: String, category: MeterCategory, count: Int) async throws -> [BillHistoryEntry] {
        try await Task.sleep(nanoseconds: 250_000_000)
        let seed = accountNo.unicodeScalars.reduce(UInt64(17)) { $0 &* 31 &+ UInt64($1.value) }
        var rng = SeededGenerator(state: seed &+ UInt64(category.rawValue))
        let base: Double = category == .water ? 18 : 380
        var reading: Double = category == .water ? 300 : 20_000
        let calendar = Calendar.current
        let now = Date()

        var entries: [BillHistoryEntry] = []
        for i in 0..<max(1, count) {
            let monthsBack = count - i
            let date = calendar.date(byAdding: .month, value: -monthsBack, to: now) ?? now
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            let days = Int.random(in: 28...33, using: &rng)
            let consumption = (base * Double.random(in: 0.7...1.3, using: &rng)).rounded()
            let previous = reading
            reading += consumption
            entries.append(BillHistoryEntry(accountNo: accountNo, category: category,
                                            billYear: year, billNo: month,
                                            billRef: "\(year)/\(String(format: "%02d", month))",
                                            avgCons: consumption / Double(days),
                                            invoiceTotal: (consumption * (category == .water ? 14 : 3.2) * 100).rounded() / 100,
                                            consumption: consumption, totalDays: days,
                                            previousReading: previous, meterReading: reading))
        }
        return entries
    }

    func postSaveNewReading(_ request: NewReadingRequest) async -> SaveReadingResult {
        try? await Task.sleep(nanoseconds: 700_000_000)
        if Double(request.newReading) == 0 {
            return .rejected("Reading rejected by the server. Please check the value and try again.")
        }
        return .ok()
    }
}

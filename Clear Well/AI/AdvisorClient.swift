import Foundation

/// Talks to the small ClearWell server (in the `server` folder), which calls Claude.
/// The Claude API key lives only on that server — never inside this app.
struct AdvisorClient {
    var settings: AppSettings

    enum AdvisorError: LocalizedError {
        case notConfigured
        case server(String)
        case unreadable

        var errorDescription: String? {
            switch self {
            case .notConfigured: "The ClearWell server address isn't set yet. Add it in Settings → AI server."
            case .server(let message): message
            case .unreadable: "The server sent back something ClearWell couldn't read."
            }
        }
    }

    // MARK: - Explain results

    private struct ExplainRequest: Encodable {
        struct Household: Encodable {
            var infantOrPregnantAtHome: Bool
            var wellAge: String
            var county: String
        }
        struct Result: Encodable {
            var contaminant: String
            var name: String
            var measured: String
            var status: String
            var statusMeaning: String
            var officialLimit: String
            var mostAtRisk: String
            var trend: String?
            var approvedNextStep: String
        }
        var household: Household
        var results: [Result]
    }

    private struct ExplainResponse: Decodable {
        struct Item: Decodable {
            var contaminant: String
            var explanation: String
            var nextStep: String
        }
        var explanations: [Item]
    }

    func explain(_ test: WaterTest, allTests: [WaterTest], profile: HouseholdProfile) async throws -> [Contaminant: Explanation] {
        let results = test.readings.map { reading in
            let limit = reading.contaminant.limit
            let status = OfficialLimits.status(for: reading.contaminant, value: reading.value, infantOrPregnantAtHome: profile.infantOrPregnant)
            let trend = TrendAnalysis.trend(for: reading.contaminant, tests: allTests.filter { $0.date <= test.date })
            return ExplainRequest.Result(
                contaminant: reading.contaminant.rawValue,
                name: limit.name,
                measured: reading.formatted,
                status: "\(status)",
                statusMeaning: status.title,
                officialLimit: limit.limitLabel,
                mostAtRisk: limit.mostAtRisk,
                trend: (trend?.points.count ?? 0) >= 2 ? trend?.summary : nil,
                approvedNextStep: limit.nextSteps[status] ?? "")
        }
        let body = ExplainRequest(
            household: .init(
                infantOrPregnantAtHome: profile.infantOrPregnant,
                wellAge: profile.wellAge.label,
                county: profile.county.fullName),
            results: results)

        let response: ExplainResponse = try await post("api/explain", body: body, timeout: 60)

        var explanations: [Contaminant: Explanation] = [:]
        for item in response.explanations {
            guard let contaminant = Contaminant(rawValue: item.contaminant),
                  test.value(for: contaminant) != nil else { continue }
            explanations[contaminant] = Explanation(text: item.explanation, nextStep: item.nextStep, origin: .ai)
        }
        return explanations
    }

    // MARK: - Scan a lab report

    struct ScannedReading: Decodable, Hashable {
        var contaminant: String
        var nameOnReport: String
        var value: Double?
        var unit: String?
        var present: Bool?
        var nitrateBasis: UnitConversion.NitrateBasis?
        var belowDetectionLimit: Bool?
    }

    struct ScanResult: Decodable {
        var testDate: String?
        var labName: String?
        var readings: [ScannedReading]
    }

    private struct ScanRequest: Encodable {
        var imageBase64: String
        var mediaType: String
    }

    func scan(jpegData: Data) async throws -> ScanResult {
        try await post("api/scan", body: ScanRequest(imageBase64: jpegData.base64EncodedString(), mediaType: "image/jpeg"), timeout: 120)
    }

    // MARK: - Health check

    struct Health: Decodable {
        var ok: Bool
        var aiConfigured: Bool
    }

    func health() async throws -> Health {
        try await send(makeRequest("api/health", timeout: 10))
    }

    // MARK: - HTTP

    private struct ServerError: Decodable {
        var error: String
    }

    private func makeRequest(_ path: String, timeout: TimeInterval) throws -> URLRequest {
        let base = settings.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, let baseURL = URL(string: base.hasSuffix("/") ? base : base + "/") else {
            throw AdvisorError.notConfigured
        }
        var request = URLRequest(url: baseURL.appending(path: path))
        request.timeoutInterval = timeout
        if !settings.appToken.isEmpty {
            request.setValue(settings.appToken, forHTTPHeaderField: "X-ClearWell-Token")
        }
        return request
    }

    private func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body, timeout: TimeInterval) async throws -> Response {
        var request = try makeRequest(path, timeout: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request)
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(ServerError.self, from: data))?.error
            throw AdvisorError.server(message ?? "The ClearWell server returned an error (\(status)).")
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw AdvisorError.unreadable
        }
    }
}

import Foundation
import Observation

// ─────────────────────────────────────────────────────────────────────────────
//  LOCAL WATER DASHBOARD
//
//  Live updates come from public services, fetched directly by the app:
//    • U.S. Drought Monitor (drought by county)
//    • National Weather Service (flood alerts and the rain forecast)
//  The explanations are fixed text chosen by the data — not written by AI —
//  so every update says what is happening, why it matters, and what to do.
//  Only the county (or county-seat location) is sent to these services.
// ─────────────────────────────────────────────────────────────────────────────

struct LocalUpdate: Identifiable, Hashable {
    enum Topic: String {
        case drought, floods, rain, groundwater, lakes, waterQuality, projects

        var icon: String {
            switch self {
            case .drought: "sun.max.fill"
            case .floods: "water.waves"
            case .rain: "cloud.rain.fill"
            case .groundwater: "drop.circle.fill"
            case .lakes: "fish.fill"
            case .waterQuality: "testtube.2"
            case .projects: "leaf.fill"
            }
        }
    }

    var id: String { topic.rawValue }
    var topic: Topic
    var title: String
    /// Short status for live updates, e.g. "Moderate drought".
    var status: String?
    var whatsHappening: String
    var whyItMatters: String
    var whatYouCanDo: String
    var sources: [SourceLink]
    /// When the source data was published (live updates only).
    var asOf: Date?
    var isLive: Bool
    /// Draws attention to updates that need action (drought or flood alerts).
    var needsAttention = false
}

/// Drought coverage from the U.S. Drought Monitor. Percentages are cumulative:
/// `d1` is the share of the county in moderate drought *or worse*.
struct DroughtSummary: Equatable {
    var county: String
    var mapDate: Date
    var d0: Double
    var d1: Double
    var d2: Double
    var d3: Double
    var d4: Double

    var inDrought: Bool { d1 >= 1 }

    /// The most serious category covering at least a tenth of the county.
    var worstCategory: String {
        if d4 >= 10 { return "Exceptional drought" }
        if d3 >= 10 { return "Extreme drought" }
        if d2 >= 10 { return "Severe drought" }
        if d1 >= 10 { return "Moderate drought" }
        if d0 >= 10 { return "Abnormally dry" }
        return "No drought"
    }
}

enum LocalWaterContent {
    static let droughtMonitor = SourceLink(title: "U.S. Drought Monitor", url: URL(string: "https://droughtmonitor.unl.edu")!)
    static let dnrDrought = SourceLink(title: "Minnesota DNR: Drought", url: URL(string: "https://www.dnr.state.mn.us/climate/drought/index.html")!)
    static let mdhFlooding = SourceLink(title: "MDH: Natural disasters and private wells", url: URL(string: "https://www.health.state.mn.us/communities/environment/water/wells/natural/index.html")!)
    static let nwsTwinCities = SourceLink(title: "National Weather Service – Twin Cities", url: URL(string: "https://www.weather.gov/mpx/")!)
    static let wellIndex = SourceLink(title: "MDH: Minnesota Well Index", url: URL(string: "https://www.health.state.mn.us/communities/environment/water/mwi/index.html")!)
    static let groundwaterMonitoring = SourceLink(title: "DNR: Cooperative Groundwater Monitoring", url: URL(string: "https://www.dnr.state.mn.us/waters/cgm/program.html")!)
    static let surfaceWaterData = SourceLink(title: "MPCA: Surface water data", url: URL(string: "https://www.pca.state.mn.us/eda-surface-water-data")!)
    static let townshipTesting = SourceLink(title: "MDA: Township Testing Program", url: URL(string: "https://www.mda.state.mn.us/township-testing-program")!)
    static let oneWatershed = SourceLink(title: "BWSR: One Watershed, One Plan", url: URL(string: "https://bwsr.state.mn.us/one-watershed-one-plan")!)
    static let findSWCD = SourceLink(title: "Find your Soil & Water Conservation District", url: URL(string: "https://www.maswcd.org/")!)
    static let umnLawn = SourceLink(title: "UMN Extension: Water-saving strategies for lawns", url: URL(string: "https://extension.umn.edu/lawn-care/water-saving-strategies-home-lawns")!)

    static func drought(_ summary: DroughtSummary) -> LocalUpdate {
        let name = summary.county
        let happening: String
        let why: String
        let todo: String
        if summary.inDrought {
            let severe = summary.d2 >= 1 ? " About \(Int(summary.d2.rounded()))% is in severe drought or worse." : ""
            happening = "About \(Int(summary.d1.rounded()))% of \(name) is in moderate drought or worse.\(severe)"
            why = "Drought lowers lakes, streams and groundwater. Shallow wells can run low, and heavy lawn watering across a community adds to the strain."
            todo = "Cut back outdoor watering — about 1 inch every 10 to 14 days is enough for established lawns during drought (UMN Extension). Fix leaks, and follow any local watering restrictions."
        } else if summary.d0 >= 1 {
            happening = "Parts of \(name) are abnormally dry — drier than normal, but not in drought."
            why = "Dry spells can be the start of drought and can lower shallow groundwater."
            todo = "Water lawns in the morning, skip watering when rain is in the forecast, and watch for drought updates."
        } else {
            happening = "The U.S. Drought Monitor shows no drought or dryness in \(name) this week."
            why = "Normal rain and snow refill the groundwater that private and city wells draw from."
            todo = "Keep using water wisely. Drought can develop quickly in summer, so check back."
        }
        return LocalUpdate(
            topic: .drought, title: "Drought", status: summary.worstCategory,
            whatsHappening: happening, whyItMatters: why, whatYouCanDo: todo,
            sources: [droughtMonitor, dnrDrought, umnLawn], asOf: summary.mapDate, isLive: true,
            needsAttention: summary.inDrought)
    }

    static func floodAlerts(_ alerts: [(event: String, headline: String)], county: String) -> LocalUpdate {
        if alerts.isEmpty {
            return LocalUpdate(
                topic: .floods, title: "Flood alerts", status: "None right now",
                whatsHappening: "There are no flood watches, warnings or advisories for \(county) right now.",
                whyItMatters: "Floodwater can carry bacteria and chemicals into wells, lakes and streams.",
                whatYouCanDo: "If flooding is ever forecast, keep your well cap sealed and know where to find MDH's flooded-well guidance.",
                sources: [nwsTwinCities, mdhFlooding], asOf: .now, isLive: true)
        }
        let lines = alerts.map { "\($0.event): \($0.headline)" }.joined(separator: "\n")
        return LocalUpdate(
            topic: .floods, title: "Flood alerts", status: alerts.count == 1 ? alerts[0].event : "\(alerts.count) active alerts",
            whatsHappening: lines,
            whyItMatters: "Floodwater can carry bacteria and chemicals into wells, lakes and streams.",
            whatYouCanDo: "Stay out of floodwater. If floodwater reaches your well, don't drink the water until the well is disinfected and tested — follow MDH's flooded-well steps.",
            sources: [nwsTwinCities, mdhFlooding], asOf: .now, isLive: true, needsAttention: true)
    }

    static func rain(maxChance: Int, periods: [(name: String, forecast: String)], forecastURL: URL) -> LocalUpdate {
        let preview = periods.prefix(2).map { "\($0.name): \($0.forecast)" }.joined(separator: ". ")
        return LocalUpdate(
            topic: .rain, title: "Rain outlook", status: "Up to \(maxChance)% chance in the next 2 days",
            whatsHappening: preview.isEmpty ? "Forecast from the National Weather Service." : preview + ".",
            whyItMatters: "Rain recharges soil and groundwater. Heavy rain also washes fertilizer, leaves and litter from streets into lakes and streams.",
            whatYouCanDo: maxChance >= 50
                ? "Rain is likely — skip watering the lawn, and sweep grass clippings and leaves off driveways and streets before it falls."
                : "Little rain is expected. If you water, do it in the morning to lose less to evaporation.",
            sources: [SourceLink(title: "National Weather Service forecast", url: forecastURL)], asOf: .now, isLive: true)
    }

    /// Background updates from official programs, always shown.
    static func reference(county: County) -> [LocalUpdate] {
        let place = county == .other ? "Minnesota" : county.fullName
        return [
            LocalUpdate(
                topic: .groundwater, title: "Groundwater and private wells",
                whatsHappening: "Most homes in \(place) get their water from groundwater. The DNR measures groundwater levels in observation wells, and MDH keeps construction records for private wells in the Minnesota Well Index.",
                whyItMatters: "Groundwater drops in dry years and when many people pump heavily, and deep aquifers can take years to recover.",
                whatYouCanDo: "Look up your well's depth and record in the Minnesota Well Index, and check groundwater-level trends near you from the DNR.",
                sources: [wellIndex, groundwaterMonitoring], isLive: false),
            LocalUpdate(
                topic: .lakes, title: "Lakes and streams",
                whatsHappening: "The MPCA and volunteer monitors test lakes and streams across Minnesota, with records going back decades.",
                whyItMatters: "A lake's health shows how everything upstream — farms, lawns, roads and storm drains — affects shared water.",
                whatYouCanDo: "Search a nearby lake or river in MPCA's surface water data, or volunteer with the Citizen Lake or Stream Monitoring Program.",
                sources: [surfaceWaterData], isLive: false),
            LocalUpdate(
                topic: .waterQuality, title: "Nitrate in nearby wells",
                whatsHappening: "The Minnesota Department of Agriculture has tested private wells for nitrate township by township in areas where groundwater is vulnerable.",
                whyItMatters: "These results show whether nitrate is a concern near you, even if your own well hasn't been tested yet.",
                whatYouCanDo: "Check whether your township was tested, and test your own well for nitrate every other year.",
                sources: [townshipTesting], isLive: false),
            LocalUpdate(
                topic: .projects, title: "Local water-protection projects",
                whatsHappening: "Watersheds across Minnesota have local plans for protecting water, and Soil and Water Conservation Districts run projects such as wetland restoration, buffer strips and well sealing.",
                whyItMatters: "These projects protect the water your whole community shares — and many need volunteers and local input.",
                whatYouCanDo: "Find your Soil and Water Conservation District to see current projects and events, and look up your watershed's plan.",
                sources: [findSWCD, oneWatershed], isLive: false),
        ]
    }
}

/// Fetches live local conditions. Results are kept in memory while the app is open.
@Observable
final class LocalWaterStore {
    enum State: Equatable {
        case idle, loading, loaded, failed(String)
    }

    private(set) var liveUpdates: [LocalUpdate] = []
    private(set) var drought: DroughtSummary?
    private(set) var state = State.idle
    private(set) var loadedCounty: County?
    private(set) var lastRefresh: Date?

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Refreshes if the county changed or the data is more than an hour old.
    func refreshIfNeeded(county: County) async {
        if loadedCounty == county, let lastRefresh, Date.now.timeIntervalSince(lastRefresh) < 3600, state == .loaded { return }
        await refresh(county: county)
    }

    func refresh(county: County) async {
        guard let fips = county.fips, let seat = county.seatCoordinate else {
            liveUpdates = []
            drought = nil
            loadedCounty = county
            state = .loaded
            return
        }
        state = .loading
        async let droughtResult = try? fetchDrought(fips: fips)
        async let alertsResult = try? fetchFloodAlerts(fips: fips)
        async let rainResult = try? fetchRain(latitude: seat.latitude, longitude: seat.longitude)
        let (droughtSummary, alerts, rain) = await (droughtResult, alertsResult, rainResult)

        var updates: [LocalUpdate] = []
        if let droughtSummary { updates.append(LocalWaterContent.drought(droughtSummary)) }
        if let alerts { updates.append(LocalWaterContent.floodAlerts(alerts, county: county.fullName)) }
        if let rain { updates.append(rain) }

        drought = droughtSummary
        liveUpdates = updates
        loadedCounty = county
        lastRefresh = .now
        state = updates.isEmpty ? .failed("Live updates couldn't be loaded. Check your internet connection and try again.") : .loaded
    }

    // MARK: - U.S. Drought Monitor

    private struct DroughtRow: Decodable {
        var mapDate: String
        var county: String
        var d0: Double
        var d1: Double
        var d2: Double
        var d3: Double
        var d4: Double
    }

    private func fetchDrought(fips: String) async throws -> DroughtSummary? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "M/d/yyyy"
        let end = Date.now
        let start = Calendar.current.date(byAdding: .day, value: -21, to: end) ?? end
        var components = URLComponents(string: "https://usdmdataservices.unl.edu/api/CountyStatistics/GetDroughtSeverityStatisticsByAreaPercent")!
        components.queryItems = [
            URLQueryItem(name: "aoi", value: fips),
            URLQueryItem(name: "startdate", value: formatter.string(from: start)),
            URLQueryItem(name: "enddate", value: formatter.string(from: end)),
            URLQueryItem(name: "statisticsType", value: "1"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let (data, _) = try await session.data(for: request)
        let rows = try JSONDecoder().decode([DroughtRow].self, from: data)

        let dateParser = DateFormatter()
        dateParser.locale = Locale(identifier: "en_US_POSIX")
        dateParser.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        guard let newest = rows.max(by: { $0.mapDate < $1.mapDate }),
              let mapDate = dateParser.date(from: newest.mapDate) else { return nil }
        return DroughtSummary(county: newest.county, mapDate: mapDate, d0: newest.d0, d1: newest.d1, d2: newest.d2, d3: newest.d3, d4: newest.d4)
    }

    // MARK: - National Weather Service

    private func nwsRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        // NWS asks every app to identify itself.
        request.setValue("ClearWell (Congressional App Challenge student app)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        return request
    }

    private struct AlertCollection: Decodable {
        struct Feature: Decodable {
            struct Properties: Decodable {
                var event: String
                var headline: String?
            }
            var properties: Properties
        }
        var features: [Feature]
    }

    private func fetchFloodAlerts(fips: String) async throws -> [(event: String, headline: String)] {
        // NWS county zones look like "MNC171" (state + "C" + county code).
        let zone = "MNC" + fips.suffix(3)
        let (data, _) = try await session.data(for: nwsRequest(URL(string: "https://api.weather.gov/alerts/active?zone=\(zone)")!))
        let collection = try JSONDecoder().decode(AlertCollection.self, from: data)
        return collection.features
            .map(\.properties)
            .filter { $0.event.localizedCaseInsensitiveContains("flood") }
            .map { (event: $0.event, headline: $0.headline ?? $0.event) }
    }

    private struct PointResponse: Decodable {
        struct Properties: Decodable { var forecast: String }
        var properties: Properties
    }

    private struct ForecastResponse: Decodable {
        struct Properties: Decodable {
            struct Period: Decodable {
                struct Chance: Decodable { var value: Double? }
                var name: String
                var shortForecast: String
                var probabilityOfPrecipitation: Chance?
            }
            var periods: [Period]
        }
        var properties: Properties
    }

    private func fetchRain(latitude: Double, longitude: Double) async throws -> LocalUpdate? {
        let point = String(format: "%.4f,%.4f", latitude, longitude)
        let (pointData, _) = try await session.data(for: nwsRequest(URL(string: "https://api.weather.gov/points/\(point)")!))
        guard let forecastURL = URL(string: try JSONDecoder().decode(PointResponse.self, from: pointData).properties.forecast) else { return nil }
        let (data, _) = try await session.data(for: nwsRequest(forecastURL))
        let periods = Array(try JSONDecoder().decode(ForecastResponse.self, from: data).properties.periods.prefix(4))
        guard !periods.isEmpty else { return nil }
        let maxChance = Int(periods.compactMap { $0.probabilityOfPrecipitation?.value }.max() ?? 0)
        let page = URL(string: "https://forecast.weather.gov/MapClick.php?lat=\(latitude)&lon=\(longitude)")!
        return LocalWaterContent.rain(maxChance: maxChance, periods: periods.map { ($0.name, $0.shortForecast) }, forecastURL: page)
    }
}

import Foundation

// ─────────────────────────────────────────────────────────────────────────────
//  GET HELP NEARBY  (CAC build plan, Step 10)
//
//  ⚠️ ANURAG: add each county's environmental health / water contact to
//  `countyContacts` below (name, phone, website, street address). Only add
//  details you have confirmed on the county's official website.
//  The MDH statewide contacts were checked on the MDH website in Oct 2026.
// ─────────────────────────────────────────────────────────────────────────────

struct LocalResource: Identifiable, Hashable {
    enum Kind {
        case state, county, labSearch
    }

    var name: String
    var detail: String
    var kind: Kind
    var phone: String?
    var email: String?
    var website: URL?
    /// Street address for directions in Maps.
    var address: String?
    /// A Maps search, such as "water testing laboratory near Buffalo, MN".
    var mapsSearch: String?

    var id: String { name }

    var phoneURL: URL? {
        guard let phone else { return nil }
        let digits = phone.filter(\.isNumber)
        return URL(string: "tel:\(digits)")
    }

    var mapsURL: URL? {
        var components = URLComponents(string: "https://maps.apple.com/")!
        if let address {
            components.queryItems = [URLQueryItem(name: "daddr", value: address)]
        } else if let mapsSearch {
            components.queryItems = [URLQueryItem(name: "q", value: mapsSearch)]
        } else {
            return nil
        }
        return components.url
    }
}

enum LocalResources {
    static let statewide: [LocalResource] = [
        LocalResource(
            name: "MDH Well Management Section",
            detail: "Minnesota Department of Health experts on private wells, testing and water treatment.",
            kind: .state,
            phone: "651-201-4600",
            email: "health.wells@state.mn.us",
            website: URL(string: "https://www.health.state.mn.us/communities/environment/water/wells/index.html")),
        LocalResource(
            name: "MDH toll-free well line",
            detail: "Same MDH well team, toll-free from anywhere in Minnesota.",
            kind: .state,
            phone: "800-383-9808"),
        LocalResource(
            name: "Find an MDH-accredited lab",
            detail: "Search the state's list of labs certified to test private well water.",
            kind: .labSearch,
            website: URL(string: "https://eldo.web.health.state.mn.us/public/accreditedlabs/labsearch.seam")),
        LocalResource(
            name: "Map of labs that test well water",
            detail: "MDH map of accredited labs that accept samples from private well owners.",
            kind: .labSearch,
            website: URL(string: "https://www.health.state.mn.us/communities/environment/water/docs/wells/waterquality/labmap.pdf")),
    ]

    /// County environmental health contacts — filled in by the research lead.
    static let countyContacts: [County: [LocalResource]] = [:]

    /// Resources for one county: its own contacts first, then a nearby-lab search.
    static func resources(for county: County) -> [LocalResource] {
        var list = countyContacts[county] ?? []
        if let seat = county.countySeat {
            list.append(LocalResource(
                name: "Water testing labs near \(seat)",
                detail: "Open Maps to find labs and well contractors near the \(county.fullName) seat.",
                kind: .county,
                mapsSearch: "water testing laboratory near \(seat), MN"))
        }
        return list
    }
}

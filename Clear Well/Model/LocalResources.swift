import Foundation

// ─────────────────────────────────────────────────────────────────────────────
//  GET HELP NEARBY  (CAC build plan, Step 10)
//
//  Every phone number and address below was checked in Oct 2026 against the
//  county's official website or MDH's accredited-lab list (July 2026).
//  Re-check them before the demo, and again each year.
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

    // MARK: - County contacts
    // Sources (checked Oct 2026):
    //  • County offices: each county's official website (linked in `website`).
    //  • Labs: MDH "Accredited Labs in Minnesota Accepting Drinking Water Samples
    //    from Private Well Users" (July 2026). Listing is not an endorsement.

    private static func lab(_ name: String, phone: String, address: String, detail: String = "MDH-accredited lab that tests private well water.") -> LocalResource {
        LocalResource(name: name, detail: detail, kind: .labSearch, phone: phone, address: address)
    }

    private static let waterLaboratories = lab("Water Laboratories, Inc.", phone: "763-441-7509", address: "333 Main Street NW, Elk River, MN 55330")
    private static let trautLab = lab("Traut Water Analysis Lab", phone: "320-251-5090", address: "32640 County Road 133, St. Joseph, MN 56374")
    private static let engelLab = lab("Engel Water Testing, Inc.", phone: "952-955-1800", address: "9300 County Road 15, Minnetrista, MN 55359")
    private static let twinCityWaterClinic = lab("Twin City Water Clinic, Inc.", phone: "952-935-3556", address: "617 13th Avenue S, Hopkins, MN 55343")

    /// County well-water contacts, nearest first.
    static let countyContacts: [County: [LocalResource]] = [
        .carver: [
            LocalResource(
                name: "Carver County Water Management",
                detail: "Free well test kits at the Government Center in Chaska or the Extension office in Cologne. Questions: Tim Sundby.",
                kind: .county,
                phone: "952-361-1816",
                email: "tsundby@carvercountymn.gov",
                website: URL(string: "https://www.carvercountymn.gov/departments/public-services/planning-water-management/water-management/get-involved/private-well-testing"),
                address: "600 East 4th Street, Chaska, MN 55318"),
            engelLab,
        ],
        .wright: [
            LocalResource(
                name: "Wright County Water Lab",
                detail: "Accredited coliform bacteria and nitrate tests for Wright County residents ($30 each, $60 for both). Buy a kit at Health & Human Services, Mon–Fri 8–4:30; return samples Monday or Tuesday.",
                kind: .county,
                website: URL(string: "https://www.wrightcountymn.gov/299/Environmental-Health"),
                address: "3650 Braddock Avenue NE, Suite 2100, Buffalo, MN 55313"),
            waterLaboratories,
        ],
        .sherburne: [
            waterLaboratories,
            LocalResource(
                name: "Sherburne County Water & Wells",
                detail: "County guidance on keeping a private well safe.",
                kind: .county,
                website: URL(string: "https://www.co.sherburne.mn.us/355/Water-Wells")),
        ],
        .stearns: [trautLab],
        .benton: [
            lab("Traut Water Analysis Lab", phone: "320-251-5090", address: "32640 County Road 133, St. Joseph, MN 56374",
                detail: "Nearest MDH-accredited lab, in neighboring Stearns County."),
        ],
        .anoka: [
            LocalResource(
                name: "Anoka County Environmental Services",
                detail: "Well water test kits for county residents. Drop off bacteria and nitrate samples Monday 8:30–4 or Tuesday 8:30–11:30.",
                kind: .county,
                phone: "763-324-4260",
                email: "environmental.health@anokacountymn.gov",
                website: URL(string: "https://www.anokacountymn.gov/2010/Well-Water-Testing"),
                address: "2100 3rd Avenue N, Suite 600, Anoka, MN 55303"),
            lab("Instrumental Research, Inc.", phone: "763-571-3698", address: "7800 Main Street NE, Fridley, MN 55432"),
        ],
        .hennepin: [
            twinCityWaterClinic,
            engelLab,
            lab("Pace Analytical Services – Minneapolis", phone: "612-607-1700", address: "1700 Elm Street SE, Suite 200, Minneapolis, MN 55414"),
        ],
    ]

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

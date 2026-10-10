import Foundation

// ─────────────────────────────────────────────────────────────────────────────
//  OFFICIAL LIMITS TABLE  (CAC build plan, Step 2)
//
//  This table is the ONLY thing that decides green / amber / red.
//  The AI never changes a color — it only explains what the color means.
//
//  ⚠️ ANURAG: verify every number below against the linked official page
//  before the demo, then set `verifiedOn` to the date you checked.
//  Already confirmed on the MDH website (Oct 2026):
//    • Nitrate: EPA limit 10 mg/L; MDH says above 3 mg/L suggests human-made
//      sources; bottle-fed babies under 6 months are most at risk.
//    • Manganese: MDH safe level 100 µg/L for infants drinking tap water or
//      formula, 300 µg/L for everyone else.
//    • MDH testing schedule: coliform every year, nitrate every other year,
//      arsenic and lead at least once.
//    • Carver County's well-testing page (citing MDH): arsenic "as close to 0
//      as possible", lead has "no known safe level", manganese "at least once
//      before a baby drinks the water". So any detected arsenic or lead is amber.
//  Still a judgment call for the team:
//    • Lead red line uses the EPA action level of 15 µg/L. EPA's newer rule
//      lowers it to 10 µg/L in Nov 2027 — decide which to show.
//    • Fluoride retest timing (MDH gives no schedule; we use "at least once").
// ─────────────────────────────────────────────────────────────────────────────

/// How often MDH recommends testing for a contaminant.
enum RetestInterval: Equatable {
    case everyYears(Int)
    case atLeastOnce

    var description: String {
        switch self {
        case .everyYears(1): "Test every year"
        case .everyYears(2): "Test every other year"
        case .everyYears(let n): "Test every \(n) years"
        case .atLeastOnce: "Test at least once"
        }
    }
}

/// Whether a lab reports a number (mg/L, µg/L) or just present / absent.
enum MeasurementKind: Equatable {
    case amount
    case presence
}

struct SourceLink: Hashable {
    let title: String
    let url: URL
}

/// One row of the official limits table.
struct OfficialLimit {
    let contaminant: Contaminant
    let name: String
    /// Plain-language "what is it and where does it come from".
    let plainDescription: String
    let kind: MeasurementKind
    /// Unit we store and show values in. Lab values are converted to this.
    let unit: String
    /// At or above this value → amber.
    let amberAt: Double?
    /// At or above this value → red.
    let redAt: Double?
    /// Stricter red line used when an infant or pregnant person lives in the home.
    let redAtWithInfant: Double?
    /// Short label of the official limit, e.g. "EPA limit: 10 mg/L".
    let limitLabel: String
    let mostAtRisk: String
    /// True if babies / pregnant people are the most sensitive group.
    let infantsMostAtRisk: Bool
    let whyItMatters: String
    let nextSteps: [WaterStatus: String]
    let retest: RetestInterval
    let sources: [SourceLink]

    /// The red line that applies to this household.
    func redLine(infantOrPregnantAtHome: Bool) -> Double? {
        if infantOrPregnantAtHome, let stricter = redAtWithInfant { return stricter }
        return redAt
    }
}

enum OfficialLimits {
    /// Date the research lead last checked every number against the sources. `nil` = not yet verified.
    static let verifiedOn: String? = nil

    /// Returns green, amber, or red using ONLY this table.
    ///
    /// - For amounts: at or above the red line → red; at or above the amber line → amber; otherwise green.
    /// - For presence tests (coliform bacteria): pass 1 for present, 0 for absent. Present → red.
    static func status(for contaminant: Contaminant, value: Double, infantOrPregnantAtHome: Bool = false) -> WaterStatus {
        let limit = limit(for: contaminant)
        guard value.isFinite, value >= 0 else { return .amber } // unreadable value: ask the user to check it

        switch limit.kind {
        case .presence:
            return value >= 1 ? .red : .green
        case .amount:
            if let red = limit.redLine(infantOrPregnantAtHome: infantOrPregnantAtHome), value >= red { return .red }
            if let amber = limit.amberAt, value >= amber { return .amber }
            return .green
        }
    }

    static func limit(for contaminant: Contaminant) -> OfficialLimit {
        guard let row = table.first(where: { $0.contaminant == contaminant }) else {
            preconditionFailure("Missing official limit for \(contaminant)")
        }
        return row
    }

    // MARK: - Sources

    private static let epaPrimary = SourceLink(
        title: "EPA National Primary Drinking Water Regulations",
        url: URL(string: "https://www.epa.gov/ground-water-and-drinking-water/national-primary-drinking-water-regulations")!)
    private static let epaSecondary = SourceLink(
        title: "EPA Secondary Drinking Water Standards",
        url: URL(string: "https://www.epa.gov/sdwa/secondary-drinking-water-standards-guidance-nuisance-chemicals")!)
    private static let mdhTesting = SourceLink(
        title: "MDH: Well Water Testing",
        url: URL(string: "https://www.health.state.mn.us/communities/environment/water/wells/waterquality/test.html")!)

    private static func mdh(_ title: String, _ path: String) -> SourceLink {
        SourceLink(title: title, url: URL(string: "https://www.health.state.mn.us/communities/environment/water/\(path)")!)
    }

    // MARK: - The table

    static let table: [OfficialLimit] = [
        OfficialLimit(
            contaminant: .nitrate,
            name: "Nitrate",
            plainDescription: "Comes from fertilizer, manure and septic systems.",
            kind: .amount,
            unit: "mg/L",
            amberAt: 3,          // MDH: above 3 mg/L suggests human-made sources are reaching the well
            redAt: 10,           // EPA limit (measured as nitrogen)
            redAtWithInfant: nil,
            limitLabel: "EPA limit: 10 mg/L",
            mostAtRisk: "Babies under 6 months (especially bottle-fed) and pregnant people",
            infantsMostAtRisk: true,
            whyItMatters: "High nitrate can keep a baby's blood from carrying oxygen properly, sometimes called \"blue baby syndrome.\" Levels above 3 mg/L suggest fertilizer, manure or septic waste is reaching your well, and the level could rise over time.",
            nextSteps: [
                .red: "Use bottled water for drinking and for mixing baby formula. Do not boil the water — boiling makes nitrate more concentrated. Call MDH or a licensed well contractor to inspect your well.",
                .amber: "Retest within a year to see whether nitrate is rising, and look for nearby sources such as septic systems, manure or fertilized fields.",
                .green: "No action needed. MDH recommends testing for nitrate every other year.",
            ],
            retest: .everyYears(2),
            sources: [epaPrimary, mdh("MDH: Nitrate in Well Water", "wells/waterquality/nitrate.html")]),

        OfficialLimit(
            contaminant: .arsenic,
            name: "Arsenic",
            plainDescription: "A natural element found in Minnesota rock and soil.",
            kind: .amount,
            unit: "µg/L",
            amberAt: 1,          // no known safe level — any detection is amber (verify)
            redAt: 10,           // EPA limit
            redAtWithInfant: nil,
            limitLabel: "EPA limit: 10 µg/L",
            mostAtRisk: "Everyone who drinks the water for many years, including children",
            infantsMostAtRisk: false,
            whyItMatters: "Drinking water with arsenic over many years raises the risk of some cancers and other health problems. Arsenic has no taste, color or smell, so testing is the only way to know.",
            nextSteps: [
                .red: "Use bottled water for drinking and cooking. Ask MDH or a certified lab about treatment, such as a reverse osmosis system.",
                .amber: "There is no known completely safe level of arsenic. Talk with MDH about whether treatment makes sense for your home.",
                .green: "No action needed. MDH recommends testing for arsenic at least once.",
            ],
            retest: .atLeastOnce,
            sources: [epaPrimary, mdh("MDH: Arsenic in Well Water", "wells/waterquality/arsenic.html")]),

        OfficialLimit(
            contaminant: .lead,
            name: "Lead",
            plainDescription: "Usually comes from old pipes, solder or well parts — not from the ground.",
            kind: .amount,
            unit: "µg/L",
            amberAt: 1,          // no known safe level — any detection is amber (verify)
            redAt: 15,           // EPA action level (verify: drops to 10 µg/L in Nov 2027)
            redAtWithInfant: nil,
            limitLabel: "EPA action level: 15 µg/L",
            mostAtRisk: "Babies, young children and pregnant people",
            infantsMostAtRisk: true,
            whyItMatters: "Lead can harm how a child's brain develops, even at low levels. There is no known safe level of lead in drinking water.",
            nextSteps: [
                .red: "Use bottled water, or a filter certified to remove lead, for drinking, cooking and baby formula. Contact MDH for next steps.",
                .amber: "Run the cold tap for a few minutes before drinking, never use hot tap water for cooking or formula, and consider a filter certified to remove lead.",
                .green: "No action needed. MDH recommends testing for lead at least once.",
            ],
            retest: .atLeastOnce,
            sources: [epaPrimary, mdh("MDH: Lead in Drinking Water", "contaminants/lead.html")]),

        OfficialLimit(
            contaminant: .manganese,
            name: "Manganese",
            plainDescription: "A natural mineral common in Minnesota groundwater.",
            kind: .amount,
            unit: "µg/L",
            amberAt: 50,         // EPA secondary standard (taste, staining)
            redAt: 300,          // MDH safe level for everyone over 1 year
            redAtWithInfant: 100, // MDH safe level for infants drinking tap water or formula
            limitLabel: "MDH guidance: 100 µg/L for infants, 300 µg/L for everyone else",
            mostAtRisk: "Babies under 1 year, especially those drinking formula made with tap water",
            infantsMostAtRisk: true,
            whyItMatters: "Too much manganese can affect learning and behavior, and babies are the most sensitive. Above 50 µg/L it can also stain sinks and laundry and give water a metallic taste.",
            nextSteps: [
                .red: "Use bottled water for babies and for mixing formula. Ask MDH about treatment options that lower manganese.",
                .amber: "Your water is within the health guidance, but you may notice staining or taste. Retest before a baby drinks the water.",
                .green: "No action needed. Test again before a baby starts drinking the water.",
            ],
            retest: .atLeastOnce,
            sources: [mdh("MDH: Manganese in Drinking Water", "contaminants/manganese.html"), epaSecondary]),

        OfficialLimit(
            contaminant: .fluoride,
            name: "Fluoride",
            plainDescription: "Occurs naturally in some groundwater.",
            kind: .amount,
            unit: "mg/L",
            amberAt: 2,          // EPA secondary standard (tooth spotting in children)
            redAt: 4,            // EPA limit
            redAtWithInfant: nil,
            limitLabel: "EPA limit: 4 mg/L",
            mostAtRisk: "Children under 9 (tooth spotting); everyone at high levels over many years",
            infantsMostAtRisk: false,
            whyItMatters: "Some fluoride protects teeth, but above 2 mg/L it can cause white spots on children's teeth. Above 4 mg/L, many years of drinking it can cause painful bone problems.",
            nextSteps: [
                .red: "Use another water source for drinking, especially for children. Ask MDH or a certified lab about treatment.",
                .amber: "Talk with your dentist about your children's fluoride, and consider bottled water for young kids.",
                .green: "No action needed.",
            ],
            retest: .atLeastOnce,
            sources: [epaPrimary, epaSecondary]),

        OfficialLimit(
            contaminant: .coliform,
            name: "Coliform bacteria",
            plainDescription: "A warning sign that surface water or waste may be getting into your well.",
            kind: .presence,
            unit: "",
            amberAt: nil,
            redAt: 1,            // present = red
            redAtWithInfant: nil,
            limitLabel: "Standard: none present",
            mostAtRisk: "Everyone, especially babies, older adults and people with weakened immune systems",
            infantsMostAtRisk: false,
            whyItMatters: "Coliform bacteria are usually harmless themselves, but finding them means germs that cause stomach illness could also get into your water.",
            nextSteps: [
                .red: "Use bottled water, or boil water for at least 1 minute before drinking, until the well is disinfected and a new test shows no bacteria. Contact MDH or a licensed well contractor.",
                .amber: "Retest to confirm the result.",
                .green: "No action needed. MDH recommends testing for bacteria every year, and after flooding or any change in taste, smell or color.",
            ],
            retest: .everyYears(1),
            sources: [epaPrimary, mdh("MDH: Bacteria in Well Water", "wells/waterquality/bacteria.html")]),
    ]

    /// MDH's general testing page, used on the About screen.
    static let generalSources: [SourceLink] = [mdhTesting, epaPrimary, epaSecondary]
}

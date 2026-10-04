import Foundation

/// Converts lab-report units into the unit used by the limits table.
/// Done in code (not by the AI) so the numbers are always exact.
enum UnitConversion {
    /// How a lab reported nitrate. Most Minnesota labs report "nitrate as nitrogen" (NO3-N).
    enum NitrateBasis: String, Codable {
        case asNitrogen = "as_nitrogen"
        case asNitrate = "as_nitrate"
        case unknown
    }

    /// Nitrate measured as the nitrate ion (NO3) × 0.2259 = nitrate as nitrogen (NO3-N).
    static let nitrateIonToNitrogen = 0.2259

    /// Returns the value in the table's unit, or `nil` if the unit is not understood.
    static func normalize(_ value: Double, unit rawUnit: String, for contaminant: Contaminant, nitrateBasis: NitrateBasis = .unknown) -> Double? {
        let unit = rawUnit
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "μ", with: "µ") // Greek mu → micro sign

        let inMilligrams: Double
        switch unit {
        case "mg/l", "ppm", "milligramsperliter":
            inMilligrams = value
        case "µg/l", "ug/l", "ppb", "microgramsperliter", "mcg/l":
            inMilligrams = value / 1000
        default:
            return nil
        }

        var converted = inMilligrams
        if contaminant == .nitrate, nitrateBasis == .asNitrate {
            converted *= nitrateIonToNitrogen
        }

        switch contaminant.limit.unit {
        case "mg/L": return converted
        case "µg/L": return converted * 1000
        default: return nil
        }
    }
}

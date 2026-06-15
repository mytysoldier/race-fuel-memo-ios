import Foundation

enum DistanceOption: Double, CaseIterable, Codable, Identifiable {
    case fiveKilometers = 5.0
    case tenKilometers = 10.0
    case thirtyKilometers = 30.0
    case halfMarathon = 21.0975
    case fullMarathon = 42.195

    var id: Double {
        rawValue
    }

    var distanceKm: Double {
        rawValue
    }

    var label: String {
        switch self {
        case .fiveKilometers:
            return "5km"
        case .tenKilometers:
            return "10km"
        case .thirtyKilometers:
            return "30km"
        case .halfMarathon:
            return "ハーフ"
        case .fullMarathon:
            return "フル"
        }
    }
}

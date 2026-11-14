import Foundation
import CoreGraphics

struct GridCoord: Hashable, Codable {
    let x: Int
    let z: Int
}

enum CityMapType: String, CaseIterable, Identifiable, Codable {
    case malang
    case surabaya
    case jakarta

    var id: String { rawValue }

    var title: String {
        switch self {
        case .malang: return "Malang Raya"
        case .surabaya: return "Kota Surabaya"
        case .jakarta: return "DKI Jakarta"
        }
    }

    var subtitle: String {
        switch self {
        case .malang: return "Lembah Sejuk & Sungai Brantas"
        case .surabaya: return "Pesisir Selat Madura & Kali Mas"
        case .jakarta: return "Teluk Jakarta & Sungai Ciliwung"
        }
    }
}

enum PlayMode: String, CaseIterable, Identifiable, Codable {
    case real
    case sandbox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .real: return "Mode Real (APBD)"
        case .sandbox: return "Mode Sandbox"
        }
    }

    var subtitle: String {
        switch self {
        case .real: return "Modal awal Rp 150 Miliar + pajak kota"
        case .sandbox: return "Anggaran tak terbatas, bebas bangun"
        }
    }
}

enum BuildCategory: String, CaseIterable, Identifiable {
    case roads
    case zones
    case bulldoze

    var id: String { rawValue }

    var title: String {
        switch self {
        case .roads: return "Jalan"
        case .zones: return "Area / Zona"
        case .bulldoze: return "Hapus"
        }
    }

    var icon: String {
        switch self {
        case .roads: return "road.lanes"
        case .zones: return "square.grid.2x2.fill"
        case .bulldoze: return "trash.fill"
        }
    }
}

enum RoadKind: String, CaseIterable, Identifiable, Codable {
    case fourLane
    case twoLane
    case oneWay
    case sidewalkTree

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fourLane: return "Jalan 4 Lajur"
        case .twoLane: return "Jalan 2 Lajur"
        case .oneWay: return "Jalan 1 Arah"
        case .sidewalkTree: return "Trotoar & Pohon"
        }
    }

    var costIDR: Int64 {
        switch self {
        case .fourLane: return 400_000_000
        case .twoLane: return 200_000_000
        case .oneWay: return 150_000_000
        case .sidewalkTree: return 100_000_000
        }
    }

    var isDriveable: Bool {
        self != .sidewalkTree
    }
}

enum ZoneKind: String, CaseIterable, Identifiable, Codable {
    case residential
    case commercial
    case industrial
    case park

    var id: String { rawValue }

    var title: String {
        switch self {
        case .residential: return "Area Hunian"
        case .commercial: return "Area Komersial"
        case .industrial: return "Area Industri"
        case .park: return "Taman Kota"
        }
    }

    var costIDR: Int64 {
        switch self {
        case .residential: return 250_000_000
        case .commercial: return 350_000_000
        case .industrial: return 450_000_000
        case .park: return 300_000_000
        }
    }

    var populationGain: Int {
        switch self {
        case .residential: return 30
        case .commercial: return 5
        case .industrial: return 0
        case .park: return 0
        }
    }

    var monthlyTaxIDR: Int64 {
        switch self {
        case .residential: return 15_000_000
        case .commercial: return 45_000_000
        case .industrial: return 65_000_000
        case .park: return -10_000_000
        }
    }
}

struct RoadTile: Identifiable, Codable {
    var id: String { "\(coord.x)_\(coord.z)" }
    let coord: GridCoord
    var kind: RoadKind
}

struct ZoneTile: Identifiable, Codable {
    var id: String { "\(coord.x)_\(coord.z)" }
    let coord: GridCoord
    var kind: ZoneKind
    var level: Int
}

struct CitySaveSnapshot: Codable {
    let mapType: CityMapType
    let playMode: PlayMode
    let budgetIDR: Int64
    let roads: [RoadTile]
    let zones: [ZoneTile]
}

enum IDRFormat {
    static func string(_ value: Int64) -> String {
        if value >= 1_000_000_000_000 {
            return "Tak Terbatas"
        }
        let absVal = abs(value)
        let sign = value < 0 ? "-" : ""
        if absVal >= 1_000_000_000 {
            return String(format: "%@Rp %.1f M", sign, Double(absVal) / 1_000_000_000.0)
        } else if absVal >= 1_000_000 {
            return String(format: "%@Rp %lld Jt", sign, absVal / 1_000_000)
        } else {
            return "\(sign)Rp \(absVal)"
        }
    }
}

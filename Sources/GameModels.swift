import Foundation
import CoreGraphics

struct GridCoord: Hashable, Codable {
    let x: Int
    let z: Int
}

enum CityMapType: String, CaseIterable, Identifiable, Codable {
    case malang, surabaya, jakarta
    var id: String { rawValue }
    var title: String {
        switch self {
        case .malang: return "Malang Raya (Pegunungan)"
        case .surabaya: return "Kota Surabaya (Pesisir)"
        case .jakarta: return "DKI Jakarta (Metropolitan)"
        }
    }
}

enum PlayMode: String, CaseIterable, Identifiable, Codable {
    case real, sandbox
    var id: String { rawValue }
    var title: String { self == .real ? "Mode Real (APBD & Pajak)" : "Mode Sandbox (Tanpa Batas)" }
}

enum BuildCategory: String, CaseIterable, Identifiable {
    case roads, zones, facilities, gebrakans
    var id: String { rawValue }
    var title: String {
        switch self {
        case .roads: return "Jalan & Alun-Alun"
        case .zones: return "Zona Hunian/Kom"
        case .facilities: return "Fasilitas Publik"
        case .gebrakans: return "Menu Gebrakan"
        }
    }
    var icon: String {
        switch self {
        case .roads: return "road.lanes"
        case .zones: return "square.grid.2x2.fill"
        case .facilities: return "building.2.fill"
        case .gebrakans: return "bolt.fill"
        }
    }
}

enum RoadKind: String, CaseIterable, Identifiable, Codable {
    case fourLane, twoLane, roundabout, sidewalkTree
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fourLane: return "Jalan 4 Lajur"
        case .twoLane: return "Jalan 2 Lajur"
        case .roundabout: return "Bundaran Alun-Alun"
        case .sidewalkTree: return "Trotoar & Pohon"
        }
    }
    var costIDR: Int64 {
        switch self {
        case .fourLane: return 400_000_000
        case .twoLane: return 200_000_000
        case .roundabout: return 1_200_000_000
        case .sidewalkTree: return 100_000_000
        }
    }
    var isDriveable: Bool { self != .sidewalkTree }
}

enum ZoneKind: String, CaseIterable, Identifiable, Codable {
    case residential, commercial, industrial, park
    var id: String { rawValue }
    var title: String {
        switch self {
        case .residential: return "Area Hunian (Rumah)"
        case .commercial: return "Area Komersial (Ruko/Mini market)"
        case .industrial: return "Area Industri"
        case .park: return "Taman Hijau"
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
    var basePopulation: Int {
        switch self {
        case .residential: return 5 // Logis: 1 kapling rumah dihuni 5 jiwa
        case .commercial: return 2
        case .industrial: return 0
        case .park: return 0
        }
    }
    var monthlyTaxIDR: Int64 {
        switch self {
        case .residential: return 15_000_000
        case .commercial: return 50_000_000
        case .industrial: return 80_000_000
        case .park: return -10_000_000
        }
    }
}

enum FacilityKind: String, CaseIterable, Identifiable, Codable {
    case balaiKota, sdNegeri, smpUnggulan, smaKandungan, universitas, rsud, polda, pemadam
    var id: String { rawValue }
    var title: String {
        switch self {
        case .balaiKota: return "Balai Kota (Town Hall)"
        case .sdNegeri: return "SD Negeri Nusantara"
        case .smpUnggulan: return "SMP Unggulan"
        case .smaKandungan: return "SMA / SMK Nusantara"
        case .universitas: return "Universitas Kampus Utama"
        case .rsud: return "Rumah Sakit (RSUD)"
        case .polda: return "Kantor Polisi"
        case .pemadam: return "Pos Pemadam Kebakaran"
        }
    }
    var costIDR: Int64 {
        switch self {
        case .balaiKota: return 10_000_000_000
        case .sdNegeri: return 1_500_000_000
        case .smpUnggulan: return 2_500_000_000
        case .smaKandungan: return 4_000_000_000
        case .universitas: return 25_000_000_000
        case .rsud: return 8_000_000_000
        case .polda: return 3_000_000_000
        case .pemadam: return 2_000_000_000
        }
    }
}

enum GebrakanKind: String, CaseIterable, Identifiable {
    case jumatBersih, digitalUmkm, subsidiTrans, beasiswa
    var id: String { rawValue }
    var title: String {
        switch self {
        case .jumatBersih: return "Gebrakan Jumat Bersih (+10% Bahagia)"
        case .digitalUmkm: return "Digitalisasi UMKM (+25% Pajak Toko)"
        case .subsidiTrans: return "Subsidi Transportasi Publik"
        case .beasiswa: return "Program Beasiswa Kampus Utama"
        }
    }
    var costIDR: Int64 {
        switch self {
        case .jumatBersih: return 5_000_000_000
        case .digitalUmkm: return 12_000_000_000
        case .subsidiTrans: return 8_000_000_000
        case .beasiswa: return 15_000_000_000
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

struct FacilityTile: Identifiable, Codable {
    var id: String { "\(coord.x)_\(coord.z)" }
    let coord: GridCoord
    var kind: FacilityKind
}

struct CitySaveSnapshot: Codable {
    let mapType: CityMapType
    let playMode: PlayMode
    let budgetIDR: Int64
    let roads: [RoadTile]
    let zones: [ZoneTile]
    let facilities: [FacilityTile]
}

enum IDRFormat {
    static func string(_ value: Int64) -> String {
        let absVal = abs(value)
        let sign = value < 0 ? "-" : ""
        if absVal >= 1_000_000_000 {
            return String(format: "%@Rp %.1f M", sign, Double(absVal) / 1_000_000_000.0)
        } else {
            return String(format: "%@Rp %lld Jt", sign, absVal / 1_000_000)
        }
    }
}

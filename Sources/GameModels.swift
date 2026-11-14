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
        case .malang: return "Malang Raya"
        case .surabaya: return "Kota Surabaya"
        case .jakarta: return "DKI Jakarta"
        }
    }
    var subtitle: String {
        switch self {
        case .malang: return "Pegunungan Arjuno & Sungai Brantas"
        case .surabaya: return "Pesisir Selat Madura & Kali Mas"
        case .jakarta: return "Teluk Utara & Sungai Ciliwung"
        }
    }
}

enum PlayMode: String, CaseIterable, Identifiable, Codable {
    case real, sandbox
    var id: String { rawValue }
    var title: String { self == .real ? "Mode Real (APBD)" : "Mode Sandbox" }
    var subtitle: String { self == .real ? "Modal Rp 150 M + Pajak Riil" : "Dana Tak Terbatas" }
}

enum BuildCategory: String, CaseIterable, Identifiable {
    case roads, zones, facilities, gebrakans, bulldoze
    var id: String { rawValue }
    var title: String {
        switch self {
        case .roads: return "Jalan & Alun-Alun"
        case .zones: return "Zona Kota"
        case .facilities: return "Sekolah & Publik"
        case .gebrakans: return "Menu Gebrakan"
        case .bulldoze: return "Hapus"
        }
    }
    var icon: String {
        switch self {
        case .roads: return "road.lanes"
        case .zones: return "square.grid.2x2.fill"
        case .facilities: return "building.2.fill"
        case .gebrakans: return "bolt.fill"
        case .bulldoze: return "trash.fill"
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
        case .residential: return "Hunian (5 Jiwa/Rumah)"
        case .commercial: return "Komersial & Ruko"
        case .industrial: return "Kawasan Industri"
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
    var basePopulation: Int {
        switch self {
        case .residential: return 5
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
    case balaiKota, sdNegeri, smpUnggulan, smaKejuruan, universitas, rsud, kantorPolisi, pemadam
    var id: String { rawValue }
    var title: String {
        switch self {
        case .balaiKota: return "Balai Kota"
        case .sdNegeri: return "SD Negeri"
        case .smpUnggulan: return "SMP Unggulan"
        case .smaKejuruan: return "SMA / SMK"
        case .universitas: return "Universitas"
        case .rsud: return "RSUD (Kesehatan)"
        case .kantorPolisi: return "Kantor Polisi"
        case .pemadam: return "Pemadam Kebakaran"
        }
    }
    var costIDR: Int64 {
        switch self {
        case .balaiKota: return 8_000_000_000
        case .sdNegeri: return 1_200_000_000
        case .smpUnggulan: return 2_000_000_000
        case .smaKejuruan: return 3_200_000_000
        case .universitas: return 18_000_000_000
        case .rsud: return 6_000_000_000
        case .kantorPolisi: return 2_500_000_000
        case .pemadam: return 2_000_000_000
        }
    }
    var educationScore: Int {
        switch self {
        case .sdNegeri: return 15
        case .smpUnggulan: return 20
        case .smaKejuruan: return 25
        case .universitas: return 40
        default: return 0
        }
    }
}

enum GebrakanKind: String, CaseIterable, Identifiable, Codable {
    case jumatBersih, digitalUmkm, subsidiTrans, beasiswaKampus
    var id: String { rawValue }
    var title: String {
        switch self {
        case .jumatBersih: return "Jumat Bersih (+10% Bahagia)"
        case .digitalUmkm: return "Digitalisasi UMKM (+25% Pajak)"
        case .subsidiTrans: return "Subsidi Transportasi (-Macet)"
        case .beasiswaKampus: return "Beasiswa Nusantara (+Riset)"
        }
    }
    var costIDR: Int64 {
        switch self {
        case .jumatBersih: return 3_000_000_000
        case .digitalUmkm: return 8_000_000_000
        case .subsidiTrans: return 6_000_000_000
        case .beasiswaKampus: return 10_000_000_000
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
    let activeGebrakans: [GebrakanKind]
}

enum IDRFormat {
    static func string(_ value: Int64) -> String {
        if value >= 1_000_000_000_000 { return "Tak Terbatas" }
        let absVal = abs(value)
        let sign = value < 0 ? "-" : ""
        if absVal >= 1_000_000_000 {
            return String(format: "%@Rp %.1f M", sign, Double(absVal) / 1_000_000_000.0)
        } else {
            return String(format: "%@Rp %lld Jt", sign, absVal / 1_000_000)
        }
    }
}

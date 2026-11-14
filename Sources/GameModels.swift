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
        case .malang: return "Lembah Pegunungan Arjuno-Kawi & Sungai Brantas"
        case .surabaya: return "Dataran Pesisir Selat Madura & Kali Mas"
        case .jakarta: return "Metropolitan Teluk Utara & Sungai Ciliwung"
        }
    }
    var difficultyLabel: String {
        switch self {
        case .malang: return "Kontur Berbukit • Sejuk"
        case .surabaya: return "Pesisir Luas • Pelabuhan"
        case .jakarta: return "Padat Metropolitan • Sungai"
        }
    }
}

enum PlayMode: String, CaseIterable, Identifiable, Codable {
    case real, sandbox
    var id: String { rawValue }
    var title: String { self == .real ? "Mode Real (APBD)" : "Mode Sandbox" }
    var subtitle: String {
        self == .real
            ? "Modal awal Rp 150 Miliar, pajak warga riil, listrik-air & tantangan lalu lintas"
            : "Anggaran APBD tak terbatas untuk bebas merancang tata kota impian"
    }
}

enum CameraMode: String, CaseIterable, Identifiable {
    case drone, followVehicle, streetView
    var id: String { rawValue }
    var title: String {
        switch self {
        case .drone: return "Drone 360°"
        case .followVehicle: return "Ikuti Kendaraan"
        case .streetView: return "Street View"
        }
    }
    var icon: String {
        switch self {
        case .drone: return "viewfinder"
        case .followVehicle: return "car.fill"
        case .streetView: return "figure.walk"
        }
    }
}

enum DataLensMode: String, CaseIterable, Identifiable {
    case normal, traffic, coverage
    var id: String { rawValue }
    var title: String {
        switch self {
        case .normal: return "Normal"
        case .traffic: return "Lensa Macet"
        case .coverage: return "Lensa Layanan"
        }
    }
}

enum BuildCategory: String, CaseIterable, Identifiable {
    case roads, zones, facilities, utilities, gebrakans, bulldoze
    var id: String { rawValue }
    var title: String {
        switch self {
        case .roads: return "Jalan & Alun-Alun"
        case .zones: return "Zona Kota"
        case .facilities: return "Sekolah & Publik"
        case .utilities: return "Listrik & Air"
        case .gebrakans: return "Menu Gebrakan"
        case .bulldoze: return "Hapus"
        }
    }
    var icon: String {
        switch self {
        case .roads: return "road.lanes"
        case .zones: return "square.grid.2x2.fill"
        case .facilities: return "building.2.fill"
        case .utilities: return "bolt.circle.fill"
        case .gebrakans: return "sparkles"
        case .bulldoze: return "trash.fill"
        }
    }
}

enum RoadKind: String, CaseIterable, Identifiable, Codable {
    case fourLane, twoLane, oneWay, elasticCurve, roundabout, sidewalkTree
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fourLane: return "Jalan 4 Lajur"
        case .twoLane: return "Jalan 2 Lajur"
        case .oneWay: return "Jalan 1 Arah"
        case .elasticCurve: return "Jalan Elastis (Kurva)"
        case .roundabout: return "Bundaran Alun-Alun"
        case .sidewalkTree: return "Trotoar & Pohon"
        }
    }
    var costIDR: Int64 {
        switch self {
        case .fourLane: return 400_000_000
        case .twoLane: return 200_000_000
        case .oneWay: return 150_000_000
        case .elasticCurve: return 320_000_000
        case .roundabout: return 1_200_000_000
        case .sidewalkTree: return 100_000_000
        }
    }
    var isDriveable: Bool { self != .sidewalkTree }
}

enum ZoneKind: String, CaseIterable, Identifiable, Codable {
    case residentialSingle, residentialMulti, commercial, industrial, park
    var id: String { rawValue }
    var title: String {
        switch self {
        case .residentialSingle: return "Rumah Tapak (Maks 5)"
        case .residentialMulti: return "Rumah Tingkat (Maks 14)"
        case .commercial: return "Komersial & Ruko"
        case .industrial: return "Kawasan Industri"
        case .park: return "Taman Kota"
        }
    }
    var costIDR: Int64 {
        switch self {
        case .residentialSingle: return 240_000_000
        case .residentialMulti: return 480_000_000
        case .commercial: return 360_000_000
        case .industrial: return 460_000_000
        case .park: return 300_000_000
        }
    }
    var maxCapacity: Int {
        switch self {
        case .residentialSingle: return 5
        case .residentialMulti: return 14
        case .commercial: return 4
        case .industrial: return 0
        case .park: return 0
        }
    }
    var jobSlots: Int {
        switch self {
        case .commercial: return 12
        case .industrial: return 24
        default: return 0
        }
    }
    var powerNeed: Int {
        switch self {
        case .residentialSingle: return 2
        case .residentialMulti: return 5
        case .commercial: return 6
        case .industrial: return 12
        case .park: return 1
        }
    }
    var waterNeed: Int {
        switch self {
        case .residentialSingle: return 2
        case .residentialMulti: return 5
        case .commercial: return 4
        case .industrial: return 10
        case .park: return 2
        }
    }
    var monthlyTaxIDR: Int64 {
        switch self {
        case .residentialSingle: return 14_000_000
        case .residentialMulti: return 32_000_000
        case .commercial: return 55_000_000
        case .industrial: return 85_000_000
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

enum UtilityKind: String, CaseIterable, Identifiable, Codable {
    case garduListrik, menaraPDAM
    var id: String { rawValue }
    var title: String {
        self == .garduListrik ? "Gardu Induk Listrik (+60 MW)" : "Instalasi Air PDAM (+60 m³)"
    }
    var costIDR: Int64 {
        self == .garduListrik ? 3_500_000_000 : 2_800_000_000
    }
}

enum GebrakanKind: String, CaseIterable, Identifiable, Codable {
    case jumatBersih, digitalUmkm, subsidiAngkot, beasiswaKampus
    var id: String { rawValue }
    var title: String {
        switch self {
        case .jumatBersih: return "Jumat Bersih (+10% Bahagia)"
        case .digitalUmkm: return "Digitalisasi UMKM (+25% Pajak)"
        case .subsidiAngkot: return "Subsidi Angkot & Bus (-Macet)"
        case .beasiswaKampus: return "Beasiswa Kampus (+Riset)"
        }
    }
    var costIDR: Int64 {
        switch self {
        case .jumatBersih: return 3_000_000_000
        case .digitalUmkm: return 8_000_000_000
        case .subsidiAngkot: return 6_000_000_000
        case .beasiswaKampus: return 10_000_000_000
        }
    }
}

struct RoadTile: Identifiable, Codable {
    var id: String { "\(coord.x)_\(coord.z)" }
    let coord: GridCoord
    var kind: RoadKind
    var curveYaw: Float = 0.0
}

struct ZoneTile: Identifiable, Codable {
    var id: String { "\(coord.x)_\(coord.z)" }
    let coord: GridCoord
    var kind: ZoneKind
    var residents: Int
    var maxResidents: Int
    var hasPower: Bool = true
    var hasWater: Bool = true
}

struct FacilityTile: Identifiable, Codable {
    var id: String { "\(coord.x)_\(coord.z)" }
    let coord: GridCoord
    var kind: FacilityKind
}

struct UtilityTile: Identifiable, Codable {
    var id: String { "\(coord.x)_\(coord.z)" }
    let coord: GridCoord
    var kind: UtilityKind
}

enum UndoAction {
    case placedRoad(GridCoord, Int64)
    case placedZone(GridCoord, Int64)
    case placedFacility(GridCoord, Int64)
    case placedUtility(GridCoord, Int64)
}

struct InspectCardData {
    let title: String
    let subtitle: String
    let details: [String]
}

struct CitySaveSnapshot: Codable {
    let slotIndex: Int
    let savedAtText: String
    let mapType: CityMapType
    let playMode: PlayMode
    let budgetIDR: Int64
    let population: Int
    let roads: [RoadTile]
    let zones: [ZoneTile]
    let facilities: [FacilityTile]
    let utilities: [UtilityTile]
    let activeGebrakans: [GebrakanKind]
}

struct GameSettings: Codable {
    var hdShadows: Bool = true
    var atmosphericFog: Bool = true
    var bgmVolume: Float = 0.42
    var sfxVolume: Float = 0.65
    var cameraSensitivity: Float = 1.0
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

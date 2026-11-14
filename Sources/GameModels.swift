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
        case .malang: return "Kontur Pegunungan • Sejuk"
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
            ? "Modal awal Rp 150 Miliar, sistem kuas zona otomatis tumbuh Lv 1–5, pajak & utilitas riil"
            : "Anggaran APBD tak terbatas untuk bebas merancang tata kota impian"
    }
}

enum TouchToolMode: String, CaseIterable, Identifiable {
    case buildBrush, panCamera
    var id: String { rawValue }
    var title: String { self == .buildBrush ? "Kuas / Tarik" : "Geser Kamera" }
    var icon: String { self == .buildBrush ? "paintbrush.pointed.fill" : "hand.draw.fill" }
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
    case normal, landValue, utilities, traffic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .normal: return "Normal"
        case .landValue: return "Level & Nilai Tanah"
        case .utilities: return "Listrik & Air"
        case .traffic: return "Lensa Macet"
        }
    }
}

enum BuildCategory: String, CaseIterable, Identifiable {
    case roads, zoning, facilities, utilities, gebrakans, bulldoze
    var id: String { rawValue }
    var title: String {
        switch self {
        case .roads: return "Tarik Jalan"
        case .zoning: return "Kuas Zona"
        case .facilities: return "Sekolah & Publik"
        case .utilities: return "Listrik & Air"
        case .gebrakans: return "Menu Gebrakan"
        case .bulldoze: return "Hapus"
        }
    }
    var icon: String {
        switch self {
        case .roads: return "road.lanes"
        case .zoning: return "paintbrush.fill"
        case .facilities: return "building.2.fill"
        case .utilities: return "bolt.circle.fill"
        case .gebrakans: return "sparkles"
        case .bulldoze: return "trash.fill"
        }
    }
}

enum RoadKind: String, CaseIterable, Identifiable, Codable {
    case twoLane, fourLane, oneWay, elasticCurve, roundabout, sidewalkTree
    var id: String { rawValue }
    var title: String {
        switch self {
        case .twoLane: return "Jalan 2 Lajur"
        case .fourLane: return "Jalan Arteri 4 Lajur"
        case .oneWay: return "Jalan 1 Arah"
        case .elasticCurve: return "Jalan Elastis (Kurva)"
        case .roundabout: return "Bundaran Alun-Alun"
        case .sidewalkTree: return "Trotoar & Pohon"
        }
    }
    var costIDR: Int64 {
        switch self {
        case .twoLane: return 180_000_000
        case .fourLane: return 380_000_000
        case .oneWay: return 140_000_000
        case .elasticCurve: return 300_000_000
        case .roundabout: return 1_200_000_000
        case .sidewalkTree: return 90_000_000
        }
    }
    var isDriveable: Bool { self != .sidewalkTree }
}

// Sistem Kuas Zona ala Cities: Skylines (Tanpa tombol rumah manual!)
enum ZoneBrushKind: String, CaseIterable, Identifiable, Codable {
    case residentialLow, residentialHigh, commercial, industrialOffice, parkGreen, clearZone
    var id: String { rawValue }
    var title: String {
        switch self {
        case .residentialLow: return "Hunian Rendah (Rumah)"
        case .residentialHigh: return "Hunian Padat (Tingkat/Apt)"
        case .commercial: return "Komersial & Ruko"
        case .industrialOffice: return "Industri & Kantor"
        case .parkGreen: return "Taman & RTH"
        case .clearZone: return "Hapus Cat Zona"
        }
    }
    var costIDR: Int64 {
        switch self {
        case .residentialLow: return 80_000_000
        case .residentialHigh: return 160_000_000
        case .commercial: return 120_000_000
        case .industrialOffice: return 150_000_000
        case .parkGreen: return 260_000_000
        case .clearZone: return 0
        }
    }
    func capacity(forLevel level: Int) -> Int {
        switch self {
        case .residentialLow:
            // Lv 1: 2-3 jiwa, Lv 3 (rumah 2 tingkat): 4-6 jiwa, Lv 5: 7 jiwa
            return 2 + level
        case .residentialHigh:
            // Lv 1: 8 jiwa, Lv 3: 16 jiwa, Lv 5 (apartemen tinggi): 26 jiwa
            return 4 + level * 4
        case .commercial:
            return 2 + level
        case .industrialOffice, .parkGreen, .clearZone:
            return 0
        }
    }
    func jobSlots(forLevel level: Int) -> Int {
        switch self {
        case .commercial: return 6 + level * 3
        case .industrialOffice: return 10 + level * 5
        default: return 0
        }
    }
    var powerNeed: Int {
        switch self {
        case .residentialLow: return 2
        case .residentialHigh: return 5
        case .commercial: return 5
        case .industrialOffice: return 10
        case .parkGreen: return 1
        case .clearZone: return 0
        }
    }
    var waterNeed: Int {
        switch self {
        case .residentialLow: return 2
        case .residentialHigh: return 5
        case .commercial: return 4
        case .industrialOffice: return 8
        case .parkGreen: return 2
        case .clearZone: return 0
        }
    }
    func monthlyTaxIDR(level: Int) -> Int64 {
        let mult = Int64(max(1, level))
        switch self {
        case .residentialLow: return 12_000_000 * mult
        case .residentialHigh: return 26_000_000 * mult
        case .commercial: return 42_000_000 * mult
        case .industrialOffice: return 65_000_000 * mult
        case .parkGreen: return -8_000_000
        case .clearZone: return 0
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
        self == .garduListrik ? "Gardu Induk Listrik (+80 MW)" : "Instalasi Air PDAM (+80 m³)"
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

struct ZonedPlot: Identifiable, Codable {
    var id: String { "\(coord.x)_\(coord.z)" }
    let coord: GridCoord
    var kind: ZoneBrushKind
    var buildingLevel: Int // 0 = Konstruksi Scaffolding, 1..5 = Tumbuh & Naik Tingkat Otomatis
    var residents: Int
    var maxResidents: Int
    var hasPower: Bool = true
    var hasWater: Bool = true
    var isAbandoned: Bool = false
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
    case placedBatchRoads([GridCoord], Int64)
    case placedBatchZones([GridCoord], Int64)
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
    let plots: [ZonedPlot]
    let facilities: [FacilityTile]
    let utilities: [UtilityTile]
    let activeGebrakans: [GebrakanKind]
}

struct GameSettings: Codable {
    var hdShadows: Bool = true
    var atmosphericFog: Bool = true
    var hdrBloom: Bool = true
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

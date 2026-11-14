import Foundation
import CoreGraphics

struct GridCoord: Hashable, Codable {
    let x: Int
    let z: Int
}

enum TimeOfDayPhase: Int, CaseIterable, Codable {
    case day = 0
    case sunset = 1
    case night = 2

    var title: String {
        switch self {
        case .day: return "Siang Cerah"
        case .sunset: return "Senja Golden Hour"
        case .night: return "Malam City Lights"
        }
    }

    var icon: String {
        switch self {
        case .day: return "sun.max.fill"
        case .sunset: return "sunset.fill"
        case .night: return "moon.stars.fill"
        }
    }

    var isLitTime: Bool { self == .sunset || self == .night }
}

enum CityWeather: String, CaseIterable, Codable {
    case cerahBerawan
    case anginSepoi
    case hujanTropis
    case kabutPegunungan

    var title: String {
        switch self {
        case .cerahBerawan: return "Cerah Berawan • 28°C"
        case .anginSepoi: return "Berangin Sejuk • 25°C"
        case .hujanTropis: return "Hujan Tropis • 23°C"
        case .kabutPegunungan: return "Kabut Lembah • 21°C"
        }
    }

    var windSummary: String {
        switch self {
        case .cerahBerawan: return "Angin Tenggara 11 km/j, jarak pandang 14 km, ideal untuk konstruksi."
        case .anginSepoi: return "Angin Lembah 24 km/j menggoyangkan pepohonan & menerbangkan daun gugur."
        case .hujanTropis: return "Curah hujan sedang, kelembapan 88%, pasokan air sungai meningkat."
        case .kabutPegunungan: return "Kabut tipis turun dari lereng pegunungan, jarak pandang 6 km."
        }
    }
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
            ? "Modal awal Rp 150 Miliar, kuas zona otomatis tumbuh Lv 1–5, AI Perizinan & pajak riil"
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
        case .roads: return "Jalan"
        case .zoning: return "Zona"
        case .facilities: return "Publik"
        case .utilities: return "Utilitas"
        case .gebrakans: return "Gebrakan"
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
        case .fourLane: return "Arteri 4 Lajur (Lebar)"
        case .oneWay: return "Jalan 1 Arah"
        case .elasticCurve: return "Jalan Elastis"
        case .roundabout: return "Bundaran Alun-Alun"
        case .sidewalkTree: return "Trotoar & Pohon"
        }
    }
    var costIDR: Int64 {
        switch self {
        case .twoLane: return 180_000_000
        case .fourLane: return 420_000_000
        case .oneWay: return 140_000_000
        case .elasticCurve: return 300_000_000
        case .roundabout: return 1_200_000_000
        case .sidewalkTree: return 90_000_000
        }
    }
    var isDriveable: Bool { self != .sidewalkTree }
}

enum ZoneBrushKind: String, CaseIterable, Identifiable, Codable {
    case residentialLow, residentialHigh, commercial, industrialOffice, parkGreen, clearZone
    var id: String { rawValue }
    var title: String {
        switch self {
        case .residentialLow: return "Hunian Rendah"
        case .residentialHigh: return "Hunian Padat"
        case .commercial: return "Komersial & Ruko"
        case .industrialOffice: return "Industri & Kantor"
        case .parkGreen: return "Taman & RTH"
        case .clearZone: return "Hapus Zona"
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
        case .residentialLow: return 2 + level
        case .residentialHigh: return 4 + level * 4
        case .commercial: return 2 + level
        case .industrialOffice, .parkGreen, .clearZone: return 0
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
        case .rsud: return "RSUD"
        case .kantorPolisi: return "Kantor Polisi"
        case .pemadam: return "Pemadam"
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
        self == .garduListrik ? "Gardu Listrik (+80 MW)" : "Menara PDAM (+80 m³)"
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
        case .subsidiAngkot: return "Subsidi Angkot (-Macet)"
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

struct CustomAIGebrakan: Identifiable, Codable {
    let id: UUID
    let title: String
    let userPrompt: String
    let aiReasoning: String
    let costIDR: Int64
    let happinessDelta: Int
    let taxMultiplierBonus: Double
    let educationDelta: Int
}

struct FranchisePermitRequest: Identifiable, Codable {
    let id: UUID
    let brandName: String
    let companyName: String
    let branchTitle: String
    let licenseFeeIDR: Int64
    let happinessBonus: Int
    let zoneKind: ZoneBrushKind
    let brandSkin: Int // 1 = Indomaret, 2 = Alfamart, 0 = Modern Commercial
    var resolved: Bool = false
    var approved: Bool = false
}

struct AIChatMessage: Identifiable {
    let id = UUID()
    let isFromUser: Bool
    let senderName: String
    let text: String
    let timestamp: String
    var permit: FranchisePermitRequest? = nil
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
    var buildingLevel: Int
    var residents: Int
    var maxResidents: Int
    var hasPower: Bool = true
    var hasWater: Bool = true
    var isAbandoned: Bool = false
    var forcedBrandSkin: Int = 0 // 0 = auto, 1 = Indomaret, 2 = Alfamart
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
    let customGebrakans: [CustomAIGebrakan]
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

import Foundation

// MARK: - 1. Alur Layar & Navigasi Utama

enum GameScreenState: Equatable {
    case bootLoading
    case studioLogo
    case mainMenu
    case modeSelection
    case mapSelection
    case inGame
}

// MARK: - 2. Mode Permainan & Tingkat Kesulitan (APBD)

enum GameMode: String, Codable, CaseIterable, Identifiable {
    case sandbox = "Sandbox Mode"
    case real = "Real Mode"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .sandbox:
            return "Anggaran APBD tak terbatas (Unlimited). Bebas bereksperimen membangun kota impian dan menguji gebrakan walikota."
        case .real:
            return "Kelola APBD nyata, pajak daerah, perizinan swasta, serta tuntutan warga secara realistis."
        }
    }
}

enum RealDifficulty: String, Codable, CaseIterable, Identifiable {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"

    var id: String { rawValue }

    var startingBudgetIDR: Int64 {
        switch self {
        case .easy: return 5_000_000_000    // Rp 5 Miliar
        case .medium: return 2_500_000_000  // Rp 2,5 Miliar
        case .hard: return 1_200_000_000    // Rp 1,2 Miliar
        }
    }

    var protestSensitivity: Double {
        switch self {
        case .easy: return 0.75
        case .medium: return 1.0
        case .hard: return 1.35
        }
    }

    var description: String {
        switch self {
        case .easy: return "Modal awal Rp 5 Miliar • Toleransi warga tinggi • Cocok untuk merintis kota pertama."
        case .medium: return "Modal awal Rp 2,5 Miliar • Dinamika ekonomi & protes warga seimbang."
        case .hard: return "Modal awal Rp 1,2 Miliar • Warga sangat kritis • Manajemen APBD & listrik/air wajib presisi."
        }
    }
}

// MARK: - 3. Peta Topografi Nusantara

enum NusantaraCityMap: String, Codable, CaseIterable, Identifiable {
    case malang = "malang"
    case surabaya = "surabaya"
    case jakarta = "jakarta"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .malang: return "Kota Malang & Gunung Arjuno"
        case .surabaya: return "Kota Surabaya & Selat Madura"
        case .jakarta: return "DKI Jakarta & Teluk Utara"
        }
    }

    var subtitle: String {
        switch self {
        case .malang:
            return "Cekungan dataran tinggi sejuk yang dikelilingi lereng Gunung Arjuno, Gunung Kawi, dan aliran Sungai Brantas."
        case .surabaya:
            return "Dataran rendah pesisir strategis di tepi Selat Madura dan Sungai Kali Mas dengan karakter kota metropolitan."
        case .jakarta:
            return "Lanskap pesisir Teluk Jakarta yang dibelah Sungai Ciliwung menuju perbukitan landai di sisi selatan."
        }
    }

    var heightmapResourceName: String { "\(rawValue)_heightmap" }

    var elevationScale: Float {
        switch self {
        case .malang: return 42.0
        case .surabaya: return 18.0
        case .jakarta: return 22.0
        }
    }

    var defaultTreeSpecies: TreeSpecies {
        switch self {
        case .malang: return .pinusMalang
        case .surabaya: return .trembesiSurabaya
        case .jakarta: return .tabebuyaSurabaya
        }
    }

    var availableTrees: [TreeSpecies] {
        switch self {
        case .malang:
            return [.pinusMalang, .trembesiSurabaya, .tabebuyaSurabaya]
        case .surabaya:
            return [.trembesiSurabaya, .tabebuyaSurabaya, .pinusMalang]
        case .jakarta:
            return [.tabebuyaSurabaya, .trembesiSurabaya, .pinusMalang]
        }
    }

    var iconicLandmarkCoord: GridCoord {
        switch self {
        case .malang: return GridCoord(x: 33, z: 9)    // Lereng Gunung Arjuno
        case .surabaya: return GridCoord(x: 33, z: 32) // Tepi Sungai Kali Mas
        case .jakarta: return GridCoord(x: 32, z: 36)  // Koridor Ciliwung
        }
    }

    var iconicLandmarkName: String {
        switch self {
        case .malang: return "Lereng Gunung Arjuno"
        case .surabaya: return "Tepi Sungai Kali Mas"
        case .jakarta: return "Koridor Sungai Ciliwung"
        }
    }
}

// MARK: - 4. Jenis Pepohonan Spesifik Wilayah (Dapat Ditanam di Trotoar)

enum TreeSpecies: String, Codable, CaseIterable, Identifiable {
    case pinusMalang = "tree_pinus_malang"
    case trembesiSurabaya = "tree_trembesi_surabaya"
    case tabebuyaSurabaya = "tree_tabebuya_surabaya"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pinusMalang: return "Pohon Pinus Pegunungan (Khas Malang)"
        case .trembesiSurabaya: return "Pohon Trembesi Peneduh (Khas Surabaya)"
        case .tabebuyaSurabaya: return "Pohon Tabebuya Berbunga"
        }
    }

    var shortName: String {
        switch self {
        case .pinusMalang: return "Pinus Malang"
        case .trembesiSurabaya: return "Trembesi"
        case .tabebuyaSurabaya: return "Tabebuya"
        }
    }

    var foliageTextureName: String {
        switch self {
        case .pinusMalang: return "foliage_pinus_albedo"
        case .trembesiSurabaya: return "foliage_trembesi_albedo"
        case .tabebuyaSurabaya: return "foliage_tabebuya_albedo"
        }
    }

    var buildCostIDR: Int64 { 2_500_000 }
    var greeneryScore: Double { 2.5 }
}

// MARK: - 5. Sistem Jalan Khas Indonesia

enum RoadType: String, Codable, CaseIterable, Identifiable {
    case oneWayTwoLane = "one_way_2_lane"
    case twoWayFourLane = "two_way_4_lane"
    case sidewalk = "sidewalk"
    case bikeLane = "bike_lane"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .oneWayTwoLane: return "Jalan 1 Arah (2 Jalur)"
        case .twoWayFourLane: return "Jalan 2 Arah (4 Jalur)"
        case .sidewalk: return "Jalan Trotoar Pejalan Kaki"
        case .bikeLane: return "Jalur Khusus Pesepeda"
        }
    }

    var shortLabel: String {
        switch self {
        case .oneWayTwoLane: return "1 Arah 2 Jalur"
        case .twoWayFourLane: return "2 Arah 4 Jalur"
        case .sidewalk: return "Trotoar"
        case .bikeLane: return "Jalur Sepeda"
        }
    }

    var albedoTextureName: String {
        switch self {
        case .oneWayTwoLane: return "road_1way_2lane_albedo"
        case .twoWayFourLane: return "road_2way_4lane_albedo"
        case .sidewalk: return "sidewalk_paving_albedo"
        case .bikeLane: return "bikelane_albedo"
        }
    }

    var buildCostIDR: Int64 {
        switch self {
        case .oneWayTwoLane: return 15_000_000
        case .twoWayFourLane: return 32_000_000
        case .sidewalk: return 8_000_000
        case .bikeLane: return 10_000_000
        }
    }

    var maintenancePerMonthIDR: Int64 {
        switch self {
        case .oneWayTwoLane: return 600_000
        case .twoWayFourLane: return 1_400_000
        case .sidewalk: return 250_000
        case .bikeLane: return 300_000
        }
    }

    var trafficCapacity: Int {
        switch self {
        case .oneWayTwoLane: return 120
        case .twoWayFourLane: return 320
        case .sidewalk: return 80
        case .bikeLane: return 90
        }
    }

    var allowsMotorVehicles: Bool {
        self == .oneWayTwoLane || self == .twoWayFourLane
    }

    var allowsSidewalkTreePlanting: Bool {
        true // Trotoar mandiri maupun bahu trotoar di tepi jalan mendukung penanaman pohon
    }
}

// MARK: - 6. Zonasi, Fasilitas Publik, Pendidikan (SD-Univ) & Landmark

enum BuildToolCategory: String, CaseIterable, Identifiable {
    case roads = "Jalan"
    case zones = "Zonasi"
    case utilities = "Utilitas"
    case education = "Pendidikan"
    case trees = "Pohon"
    case bulldoze = "Hapus"

    var id: String { rawValue }

    var systemIcon: String {
        switch self {
        case .roads: return "road.lanes"
        case .zones: return "building.2.fill"
        case .utilities: return "bolt.fill"
        case .education: return "graduationcap.fill"
        case .trees: return "tree.fill"
        case .bulldoze: return "trash.fill"
        }
    }
}

enum StructureType: String, Codable, CaseIterable, Identifiable {
    // Zonasi Permukiman & Komersial
    case residentialHouse = "residential_house"
    case commercialShop = "commercial_shop"
    case commercialHighRise = "commercial_highrise"
    case indomaretRetail = "indomaret_retail"

    // Utilitas & Pemerintahan
    case cityHall = "city_hall"
    case powerPlantPLN = "power_plant_pln"
    case waterPlantPDAM = "water_plant_pdam"
    case cityPark = "city_park"

    // Jenjang Pendidikan Lengkap (SD, SMP, SMA, Universitas)
    case eduSD = "edu_sd"
    case eduSMP = "edu_smp"
    case eduSMA = "edu_sma"
    case eduUniversitas = "edu_universitas"

    // Proyek Khusus Hasil Gebrakan Walikota
    case kampungWarnaWarni = "kampung_warnawarni"
    case arjunoBasecamp = "arjuno_basecamp"
    case nightCulinaryWalk = "night_culinary_walk"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .residentialHouse: return "Area Permukiman Warga"
        case .commercialShop: return "Area Komersial & Ruko"
        case .commercialHighRise: return "Gedung Komersial Bertingkat"
        case .indomaretRetail: return "Gerai Ritel Indomaret"
        case .cityHall: return "Kantor Walikota & Balai Kota"
        case .powerPlantPLN: return "Gardu & Pembangkit Listrik"
        case .waterPlantPDAM: return "Instalasi Air Bersih (PDAM)"
        case .cityPark: return "Taman Kota & Ruang Terbuka"
        case .eduSD: return "Sekolah Dasar (SD)"
        case .eduSMP: return "Sekolah Menengah Pertama (SMP)"
        case .eduSMA: return "Sekolah Menengah Atas (SMA)"
        case .eduUniversitas: return "Universitas & Kampus Riset"
        case .kampungWarnaWarni: return "Wisata Kampung Warna-Warni"
        case .arjunoBasecamp: return "Basecamp & Jalur Pendakian Arjuno"
        case .nightCulinaryWalk: return "Wisata Kuliner & Lampu Malam"
        }
    }

    var objModelName: String {
        switch self {
        case .residentialHouse: return "building_house"
        case .commercialShop: return "building_house"
        case .commercialHighRise: return "building_highrise"
        case .indomaretRetail: return "building_indomaret"
        case .cityHall: return "edu_universitas"
        case .powerPlantPLN: return "building_highrise"
        case .waterPlantPDAM: return "edu_smp"
        case .cityPark: return "landmark_arjuno_basecamp"
        case .eduSD: return "edu_sd"
        case .eduSMP: return "edu_smp"
        case .eduSMA: return "edu_sma"
        case .eduUniversitas: return "edu_universitas"
        case .kampungWarnaWarni: return "building_kampung_warnawarni"
        case .arjunoBasecamp: return "landmark_arjuno_basecamp"
        case .nightCulinaryWalk: return "building_kampung_warnawarni"
        }
    }

    var albedoTextureName: String {
        switch self {
        case .indomaretRetail: return "indomaret_facade_albedo"
        case .kampungWarnaWarni, .nightCulinaryWalk: return "kampung_warnawarni_albedo"
        case .cityPark: return "grass_nusantara_albedo"
        default: return "building_facade_day"
        }
    }

    var buildCostIDR: Int64 {
        switch self {
        case .residentialHouse: return 45_000_000
        case .commercialShop: return 75_000_000
        case .commercialHighRise: return 350_000_000
        case .indomaretRetail: return 90_000_000
        case .cityHall: return 250_000_000
        case .powerPlantPLN: return 220_000_000
        case .waterPlantPDAM: return 180_000_000
        case .cityPark: return 60_000_000
        case .eduSD: return 110_000_000
        case .eduSMP: return 145_000_000
        case .eduSMA: return 185_000_000
        case .eduUniversitas: return 420_000_000
        case .kampungWarnaWarni: return 190_000_000
        case .arjunoBasecamp: return 240_000_000
        case .nightCulinaryWalk: return 175_000_000
        }
    }

    var monthlyTaxOrMaintenanceIDR: Int64 {
        switch self {
        case .residentialHouse: return 8_500_000
        case .commercialShop: return 18_000_000
        case .commercialHighRise: return 55_000_000
        case .indomaretRetail: return 22_000_000
        case .cityHall: return -15_000_000
        case .powerPlantPLN: return -18_000_000
        case .waterPlantPDAM: return -14_000_000
        case .cityPark: return -5_000_000
        case .eduSD: return -7_000_000
        case .eduSMP: return -9_000_000
        case .eduSMA: return -11_000_000
        case .eduUniversitas: return -20_000_000
        case .kampungWarnaWarni: return 34_000_000
        case .arjunoBasecamp: return 38_000_000
        case .nightCulinaryWalk: return 31_000_000
        }
    }

    /// Nilai positif = menyuplai listrik (MW), nilai negatif = mengonsumsi listrik (MW)
    var powerDeltaMW: Int {
        switch self {
        case .powerPlantPLN: return 120
        case .residentialHouse: return -8
        case .commercialShop: return -12
        case .commercialHighRise: return -35
        case .indomaretRetail: return -10
        case .cityHall: return -15
        case .waterPlantPDAM: return -14
        case .eduSD, .eduSMP, .eduSMA: return -8
        case .eduUniversitas: return -22
        case .kampungWarnaWarni, .arjunoBasecamp, .nightCulinaryWalk: return -10
        case .cityPark: return -2
        }
    }

    /// Nilai positif = menyuplai air bersih (ML), nilai negatif = mengonsumsi air (ML)
    var waterDeltaML: Int {
        switch self {
        case .waterPlantPDAM: return 140
        case .residentialHouse: return -10
        case .commercialShop: return -10
        case .commercialHighRise: return -28
        case .indomaretRetail: return -6
        case .cityHall: return -10
        case .powerPlantPLN: return -12
        case .eduSD, .eduSMP, .eduSMA: return -7
        case .eduUniversitas: return -18
        case .kampungWarnaWarni, .arjunoBasecamp, .nightCulinaryWalk: return -9
        case .cityPark: return -5
        }
    }

    var populationCapacity: Int {
        self == .residentialHouse ? 180 : 0
    }

    var jobsProvided: Int {
        switch self {
        case .commercialShop: return 45
        case .commercialHighRise: return 220
        case .indomaretRetail: return 24
        case .cityHall: return 60
        case .powerPlantPLN, .waterPlantPDAM: return 40
        case .eduSD: return 25
        case .eduSMP: return 35
        case .eduSMA: return 45
        case .eduUniversitas: return 140
        case .kampungWarnaWarni, .arjunoBasecamp, .nightCulinaryWalk: return 85
        default: return 0
        }
    }

    var educationBonus: Double {
        switch self {
        case .eduSD: return 12.0
        case .eduSMP: return 16.0
        case .eduSMA: return 20.0
        case .eduUniversitas: return 32.0
        default: return 0.0
        }
    }

    var tourismBonus: Double {
        switch self {
        case .kampungWarnaWarni: return 28.0
        case .arjunoBasecamp: return 35.0
        case .nightCulinaryWalk: return 25.0
        case .cityPark: return 8.0
        default: return 0.0
        }
    }

    var isManuallyBuildable: Bool {
        switch self {
        case .indomaretRetail, .kampungWarnaWarni, .arjunoBasecamp, .nightCulinaryWalk:
            return false // Dibangun lewat Perizinan AI Agent atau Gebrakan Walikota
        default:
            return true
        }
    }
}

// MARK: - 7. Koordinat Grid & Objek Terpasang di Peta

struct GridCoord: Codable, Hashable, Equatable {
    var x: Int
    var z: Int
}

struct PlacedRoad: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var coord: GridCoord
    var roadType: RoadType
    var hasStreetLights: Bool = true
    var plantedTree: TreeSpecies? = nil
}

struct PlacedStructure: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var coord: GridCoord
    var structureType: StructureType
    var rotationY: Float = 0.0
    var hasPower: Bool = true
    var hasWater: Bool = true
    var satisfaction: Double = 85.0
    var customTitle: String? = nil
}

// MARK: - 8. NPC Berpikir & Sistem Demonstrasi Warga

struct CitizenThought: Identifiable, Equatable {
    var id: UUID = UUID()
    var citizenName: String
    var role: String // Pejalan Kaki, Pemotor, Pesepeda, Pelajar, Pedagang
    var thoughtText: String
    var moodPositive: Bool
    var coord: GridCoord
}

struct CitizenProtest: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var issueTitle: String
    var demandMessage: String
    var location: GridCoord
    var crowdCount: Int
    var severity: Double // 0.0 - 1.0
    var resolved: Bool = false
}

// MARK: - 9. Pengaturan Grafik & Pencahayaan Malam

enum GraphicsQualityPreset: String, Codable, CaseIterable, Identifiable {
    case medium = "Medium (60 FPS)"
    case high = "High Detail"
    case ultraRealism = "Ultra Realism (100MB+ HD)"

    var id: String { rawValue }
}

struct GraphicsSettings: Codable, Equatable {
    var qualityPreset: GraphicsQualityPreset = .ultraRealism
    var enableWindAndFallingLeaves: Bool = true
    var enableCozyNightLights: Bool = true
    var enableDynamicShadows: Bool = true
    var trafficDensity: Double = 0.85
    var soundVolume: Double = 0.80
    var lockNightCozyMode: Bool = false
}

// MARK: - 10. Statistik Kota Ala TheoTown + Cities Skylines

struct CityStatistics: Codable, Equatable {
    var population: Int = 0
    var budgetIDR: Int64 = 2_500_000_000
    var monthlyIncomeIDR: Int64 = 0
    var monthlyExpenseIDR: Int64 = 0
    var happinessPercent: Double = 82.0
    var powerSupplyMW: Int = 0
    var powerDemandMW: Int = 0
    var waterSupplyML: Int = 0
    var waterDemandML: Int = 0
    var educationIndex: Double = 40.0
    var tourismRating: Double = 15.0
    var greeneryIndex: Double = 50.0
    var timeOfDayHours: Double = 17.5 // Mulai menjelang senja menuju suasana malam cozy
    var dayCount: Int = 1

    var formattedTimeString: String {
        let hour = Int(timeOfDayHours) % 24
        let minute = Int((timeOfDayHours - Double(Int(timeOfDayHours))) * 60.0)
        return String(format: "%02d:%02d WIB", hour, minute)
    }

    var isNightTime: Bool {
        timeOfDayHours >= 18.2 || timeOfDayHours <= 5.5
    }
}

// MARK: - 11. Model Sistem Dual-AI (AI Gebrakan Walikota & AI Agent)

enum GebrakanStatus: String, Codable {
    case planned = "Siap Dieksekusi"
    case executing = "Dalam Pengerjaan"
    case completed = "Beroperasi Penuh"
}

struct GebrakanBlueprintStep: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var stepNumber: Int
    var title: String
    var technicalDetail: String
    var targetCoord: GridCoord
    var structureToBuild: StructureType?
    var roadToBuild: RoadType?
    var treeToPlant: TreeSpecies?
    var estimatedCostIDR: Int64
    var isCompleted: Bool = false
}

struct GebrakanPlan: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var mayorIdeaPrompt: String
    var projectTitle: String
    var aiSpatialAnalysis: String
    var selectedZoneName: String
    var centerCoord: GridCoord
    var totalBudgetIDR: Int64
    var expectedTourismGain: Double
    var expectedHappinessGain: Double
    var steps: [GebrakanBlueprintStep]
    var status: GebrakanStatus = .planned
}

struct PermitRequest: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var applicantName: String
    var structureType: StructureType
    var proposedCoord: GridCoord
    var investmentFeeIDR: Int64
    var taxRevenuePerMonthIDR: Int64
    var jobsCreated: Int
    var aiAgentPros: String
    var aiAgentCons: String
    var aiRecommendation: String
    var isApproved: Bool? = nil
}

enum AlertSeverity: String, Codable {
    case info = "Saran AI Agent"
    case warning = "Peringatan Kota"
    case critical = "Krisis & Demo Warga"
}

struct AIAgentAlert: Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var diagnosis: String
    var suggestedAction: String
    var severity: AlertSeverity
    var targetCoord: GridCoord? = nil
    var quickFixStructure: StructureType? = nil
}

// MARK: - 12. Struktur Penyimpanan Game (Save / Load)

struct CitySaveData: Codable, Identifiable {
    var id: UUID = UUID()
    var saveTitle: String
    var savedAt: Date = Date()
    var gameMode: GameMode
    var difficulty: RealDifficulty
    var cityMap: NusantaraCityMap
    var stats: CityStatistics
    var roads: [PlacedRoad]
    var structures: [PlacedStructure]
    var protests: [CitizenProtest]
    var gebrakanHistory: [GebrakanPlan]
    var permitRequests: [PermitRequest]
}

// MARK: - 13. Helper Format Mata Uang Rupiah

enum IDRFormatter {
    static func format(_ amount: Int64) -> String {
        let absVal = abs(amount)
        let sign = amount < 0 ? "-" : ""
        if absVal >= 1_000_000_000 {
            let val = Double(absVal) / 1_000_000_000.0
            return String(format: "%@Rp %.2f M", sign, val)
        } else if absVal >= 1_000_000 {
            let val = Double(absVal) / 1_000_000.0
            return String(format: "%@Rp %.1f Jt", sign, val)
        } else {
            return "\(sign)Rp \(absVal)"
        }
    }
}

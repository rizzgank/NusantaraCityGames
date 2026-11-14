import Foundation

// MARK: - Mesin Utama Dual-AI & Simulasi Kesadaran Warga Nusantara

final class NusantaraAISystem {

    static let shared = NusantaraAISystem()

    private let gridSize = 64

    private let indonesianFirstNames = [
        "Budi", "Siti", "Rizky", "Ayu", "Dimas", "Nadia", "Fajar", "Putri",
        "Hendra", "Dewi", "Agus", "Rina", "Bagas", "Tari", "Eko", "Wulan",
        "Galih", "Intan", "Yusuf", "Fitri", "Arif", "Ratna", "Ilham", "Lestari"
    ]

    private let indonesianLastNames = [
        "Santoso", "Pratama", "Wijaya", "Kusuma", "Saputra", "Hidayat",
        "Nugroho", "Ramadhan", "Setiawan", "Permata", "Laksana", "Utami"
    ]

    private init() {}

    // =========================================================================
    // 1. AI GEBRAKAN WALIKOTA (PERENCANA PROYEK BEBAS & BLUEPRINT OTOMATIS)
    // =========================================================================

    func generateGebrakanPlan(
        prompt: String,
        cityMap: NusantaraCityMap,
        roads: [PlacedRoad],
        structures: [PlacedStructure],
        stats: CityStatistics
    ) -> GebrakanPlan {
        let cleanedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = cleanedPrompt.lowercased()

        let isMountainTrail = lower.contains("gunung") || lower.contains("arjuno") ||
            lower.contains("pendakian") || lower.contains("hiking") || lower.contains("basecamp") ||
            lower.contains("alam") || lower.contains("bukit")

        let isColorfulVillage = lower.contains("warna") || lower.contains("kampung") ||
            lower.contains("jodipan") || lower.contains("mural") || lower.contains("seni") ||
            lower.contains("sungai") || lower.contains("heritage")

        let isNightCulinary = lower.contains("malam") || lower.contains("kuliner") ||
            lower.contains("cafe") || lower.contains("kopi") || lower.contains("lampu") ||
            lower.contains("wisata") || lower.contains("alun") || lower.contains("taman")

        let isEducationHub = lower.contains("kampus") || lower.contains("universitas") ||
            lower.contains("pendidikan") || lower.contains("sekolah") || lower.contains("riset") ||
            lower.contains("teknologi")

        let occupied = buildOccupiedSet(roads: roads, structures: structures)

        let preferredOrigin: GridCoord
        let zoneName: String

        if isMountainTrail {
            preferredOrigin = cityMap.iconicLandmarkCoord
            zoneName = cityMap == .malang
                ? "Zona Kaki & Lereng Gunung Arjuno (Sektor Utara)"
                : "Zona Perbukitan & Ekowisata \(cityMap.iconicLandmarkName)"
        } else if isColorfulVillage {
            preferredOrigin = GridCoord(x: 31, z: 28)
            zoneName = cityMap == .malang
                ? "Bantaran Sungai Brantas & Permukiman Terasering"
                : "Koridor Tepian Sungai & Permukiman Kreatif \(cityMap.displayName)"
        } else if isNightCulinary {
            preferredOrigin = findClusterCenter(structures: structures, fallback: GridCoord(x: 32, z: 32))
            zoneName = "Kawasan Pusat Kota & Koridor Lampu Malam \(cityMap.displayName)"
        } else if isEducationHub {
            preferredOrigin = GridCoord(x: 24, z: 26)
            zoneName = "Kawasan Terpadu Pendidikan & Inovasi Daerah"
        } else {
            preferredOrigin = findClusterCenter(structures: structures, fallback: GridCoord(x: 30, z: 30))
            zoneName = "Zona Pengembangan Strategis \(cityMap.displayName)"
        }

        let center = findNearestFreeCoord(near: preferredOrigin, occupied: occupied, radius: 14)
        var reserved = occupied
        reserved.insert(center)

        let p1 = findNearestFreeCoord(near: GridCoord(x: center.x, z: min(gridSize - 3, center.z + 1)), occupied: reserved, radius: 8)
        reserved.insert(p1)
        let p2 = findNearestFreeCoord(near: GridCoord(x: min(gridSize - 3, center.x + 1), z: center.z), occupied: reserved, radius: 8)
        reserved.insert(p2)
        let p3 = findNearestFreeCoord(near: GridCoord(x: max(2, center.x - 1), z: center.z), occupied: reserved, radius: 8)
        reserved.insert(p3)
        let p4 = findNearestFreeCoord(near: GridCoord(x: center.x, z: max(2, center.z - 1)), occupied: reserved, radius: 8)
        reserved.insert(p4)

        let treeSpecies = cityMap.defaultTreeSpecies
        let projectTitle: String
        let spatialAnalysis: String
        var steps: [GebrakanBlueprintStep] = []
        let tourismGain: Double
        let happinessGain: Double

        if isMountainTrail {
            projectTitle = cityMap == .malang
                ? "Gebrakan Wisata Pendakian Gunung Arjuno"
                : "Gebrakan Jalur Pendakian & Ekowisata \(cityMap.iconicLandmarkName)"

            spatialAnalysis = """
            AI Spatial Scanner memetakan elevasi kontur \(zoneName) di koordinat (\(center.x), \(center.z)). \
            Kemiringan lereng dinilai aman untuk akses kendaraan menuju kaki gunung sebelum masuk jalur jalan kaki. \
            Sistem menyusun 4 tahapan konstruksi mulai dari pembukaan akses trotoar/jalan, pembangunan Basecamp resmi, \
            penghijauan \(treeSpecies.shortName), hingga pembukaan jalur pendakian untuk wisatawan.
            """

            steps = [
                GebrakanBlueprintStep(
                    stepNumber: 1,
                    title: "Pembukaan Akses Jalan Menuju Kaki Gunung",
                    technicalDetail: "Membangun ruas Jalan 1 Arah 2 Jalur sebagai jalur logistik menuju titik awal pendakian.",
                    targetCoord: p1,
                    structureToBuild: nil,
                    roadToBuild: .oneWayTwoLane,
                    treeToPlant: nil,
                    estimatedCostIDR: RoadType.oneWayTwoLane.buildCostIDR
                ),
                GebrakanBlueprintStep(
                    stepNumber: 2,
                    title: "Pembangunan Basecamp & Pos Registrasi Pendaki",
                    technicalDetail: "Mendirikan gedung Basecamp utama lengkap dengan gerbang pendakian, pos SAR, dan area istirahat.",
                    targetCoord: center,
                    structureToBuild: .arjunoBasecamp,
                    roadToBuild: nil,
                    treeToPlant: nil,
                    estimatedCostIDR: StructureType.arjunoBasecamp.buildCostIDR
                ),
                GebrakanBlueprintStep(
                    stepNumber: 3,
                    title: "Penataan Jalur Trotoar Pendakian & Penghijauan",
                    technicalDetail: "Memasang jalur pejalan kaki berbatu dan menanam \(treeSpecies.shortName) di sepanjang jalur.",
                    targetCoord: p2,
                    structureToBuild: nil,
                    roadToBuild: .sidewalk,
                    treeToPlant: treeSpecies,
                    estimatedCostIDR: RoadType.sidewalk.buildCostIDR + treeSpecies.buildCostIDR
                ),
                GebrakanBlueprintStep(
                    stepNumber: 4,
                    title: "Pos Taman Konservasi & Pembukaan Wisata Resmi",
                    technicalDetail: "Menambahkan zona konservasi alam di lereng atas agar wisata pendakian siap dibuka untuk umum.",
                    targetCoord: p3,
                    structureToBuild: .cityPark,
                    roadToBuild: nil,
                    treeToPlant: nil,
                    estimatedCostIDR: StructureType.cityPark.buildCostIDR
                )
            ]
            tourismGain = 38.0
            happinessGain = 14.0

        } else if isColorfulVillage {
            projectTitle = "Gebrakan Wisata Kampung Warna-Warni Nusantara"
            spatialAnalysis = """
            AI Spatial Scanner mendeteksi kontur tepian sungai di \(zoneName) (koordinat \(center.x), \(center.z)) \
            sangat ideal untuk transformasi kawasan tematik. Pola fasad rumah bertingkat berwarna cerah dipadukan \
            dengan jalur trotoar pejalan kaki, jalur sepeda, dan pohon peneduh agar menarik wisatawan lokal maupun mancanegara.
            """

            steps = [
                GebrakanBlueprintStep(
                    stepNumber: 1,
                    title: "Revitalisasi Trotoar Wisata & Peneduh Jalan",
                    technicalDetail: "Membangun jalan trotoar paving dan menanam \(treeSpecies.shortName) di tepi kawasan.",
                    targetCoord: p1,
                    structureToBuild: nil,
                    roadToBuild: .sidewalk,
                    treeToPlant: treeSpecies,
                    estimatedCostIDR: RoadType.sidewalk.buildCostIDR + treeSpecies.buildCostIDR
                ),
                GebrakanBlueprintStep(
                    stepNumber: 2,
                    title: "Konstruksi Blok Inti Kampung Warna-Warni",
                    technicalDetail: "Membangun deretan hunian ikonik berornamen warna-warni cerah menghadap tepi sungai.",
                    targetCoord: center,
                    structureToBuild: .kampungWarnaWarni,
                    roadToBuild: nil,
                    treeToPlant: nil,
                    estimatedCostIDR: StructureType.kampungWarnaWarni.buildCostIDR
                ),
                GebrakanBlueprintStep(
                    stepNumber: 3,
                    title: "Jalur Khusus Pesepeda & Spot Foto Wisata",
                    technicalDetail: "Menghubungkan kawasan dengan jalur pesepeda ramah lingkungan untuk mendongkrak kunjungan.",
                    targetCoord: p2,
                    structureToBuild: nil,
                    roadToBuild: .bikeLane,
                    treeToPlant: .tabebuyaSurabaya,
                    estimatedCostIDR: RoadType.bikeLane.buildCostIDR + TreeSpecies.tabebuyaSurabaya.buildCostIDR
                ),
                GebrakanBlueprintStep(
                    stepNumber: 4,
                    title: "Pusat UMKM & Kuliner Pendukung Wisata",
                    technicalDetail: "Menyediakan sentra ruko UMKM warga lokal untuk menjual suvenir dan kuliner khas daerah.",
                    targetCoord: p3,
                    structureToBuild: .commercialShop,
                    roadToBuild: nil,
                    treeToPlant: nil,
                    estimatedCostIDR: StructureType.commercialShop.buildCostIDR
                )
            ]
            tourismGain = 34.0
            happinessGain = 16.0

        } else if isEducationHub {
            projectTitle = "Gebrakan Kawasan Terpadu Pendidikan & Riset Kota"
            spatialAnalysis = """
            AI Spatial Scanner mengevaluasi tingkat pendidikan kota saat ini (\(Int(stats.educationIndex))%) dan memilih \
            \(zoneName) di koordinat (\(center.x), \(center.z)) karena jauh dari kebisingan industri serta mudah diakses \
            jalur sepeda dan trotoar pelajar.
            """

            steps = [
                GebrakanBlueprintStep(
                    stepNumber: 1,
                    title: "Akses Jalan Utama 2 Arah & Jalur Sepeda Pelajar",
                    technicalDetail: "Menyiapkan akses transportasi aman bagi pelajar dan mahasiswa menuju kawasan kampus.",
                    targetCoord: p1,
                    structureToBuild: nil,
                    roadToBuild: .twoWayFourLane,
                    treeToPlant: treeSpecies,
                    estimatedCostIDR: RoadType.twoWayFourLane.buildCostIDR + treeSpecies.buildCostIDR
                ),
                GebrakanBlueprintStep(
                    stepNumber: 2,
                    title: "Pembangunan Gedung Universitas & Pusat Riset",
                    technicalDetail: "Mendirikan kampus perguruan tinggi utama untuk mencetak SDM unggul dan meningkatkan ekonomi kota.",
                    targetCoord: center,
                    structureToBuild: .eduUniversitas,
                    roadToBuild: nil,
                    treeToPlant: nil,
                    estimatedCostIDR: StructureType.eduUniversitas.buildCostIDR
                ),
                GebrakanBlueprintStep(
                    stepNumber: 3,
                    title: "Taman Literasi & Ruang Terbuka Hijau Kampus",
                    technicalDetail: "Membangun taman kota asri dengan pepohonan rindang untuk ruang diskusi mahasiswa.",
                    targetCoord: p2,
                    structureToBuild: .cityPark,
                    roadToBuild: nil,
                    treeToPlant: nil,
                    estimatedCostIDR: StructureType.cityPark.buildCostIDR
                )
            ]
            tourismGain = 15.0
            happinessGain = 18.0

        } else {
            projectTitle = cleanedPrompt.isEmpty
                ? "Gebrakan Penataan Kawasan Strategis"
                : "Gebrakan: \(cleanedPrompt.prefix(44))"

            spatialAnalysis = """
            AI Strategic Planner menganalisis gagasan Walikota ("\(cleanedPrompt)") terhadap tata ruang \(cityMap.displayName). \
            Ditemukan lahan potensial di \(zoneName) pada koordinat (\(center.x), \(center.z)) yang terhubung dengan \
            jaringan mobilitas kota. Sistem merancang infrastruktur akses, kawasan tematik bercahaya malam (cozy night lights), \
            serta penghijauan trotoar agar gagasan ini berdampak langsung pada kebahagiaan warga dan pendapatan daerah.
            """

            steps = [
                GebrakanBlueprintStep(
                    stepNumber: 1,
                    title: "Infrastruktur Jalan Utama & Penghijauan Trotoar",
                    technicalDetail: "Membuka akses Jalan 2 Arah 4 Jalur dengan deretan pohon \(treeSpecies.shortName) di tepi trotoar.",
                    targetCoord: p1,
                    structureToBuild: nil,
                    roadToBuild: .twoWayFourLane,
                    treeToPlant: treeSpecies,
                    estimatedCostIDR: RoadType.twoWayFourLane.buildCostIDR + treeSpecies.buildCostIDR
                ),
                GebrakanBlueprintStep(
                    stepNumber: 2,
                    title: "Pembangunan Zona Ikonik: \(cleanedPrompt.prefix(28))",
                    technicalDetail: "Mewujudkan pusat aktivitas tematik yang dirancang khusus dengan pencahayaan malam hangat.",
                    targetCoord: center,
                    structureToBuild: .nightCulinaryWalk,
                    roadToBuild: nil,
                    treeToPlant: nil,
                    estimatedCostIDR: StructureType.nightCulinaryWalk.buildCostIDR
                ),
                GebrakanBlueprintStep(
                    stepNumber: 3,
                    title: "Jalur Pejalan Kaki & Ruang Publik Terbuka",
                    technicalDetail: "Melengkapi kawasan dengan trotoar nyaman dan taman kota agar warga betah beraktivitas.",
                    targetCoord: p2,
                    structureToBuild: .cityPark,
                    roadToBuild: nil,
                    treeToPlant: nil,
                    estimatedCostIDR: StructureType.cityPark.buildCostIDR
                ),
                GebrakanBlueprintStep(
                    stepNumber: 4,
                    title: "Konektivitas Jalur Sepeda & Koridor UMKM",
                    technicalDetail: "Menambahkan jalur sepeda ramah lingkungan untuk menggerakkan roda ekonomi sekitar proyek.",
                    targetCoord: p4,
                    structureToBuild: nil,
                    roadToBuild: .bikeLane,
                    treeToPlant: .tabebuyaSurabaya,
                    estimatedCostIDR: RoadType.bikeLane.buildCostIDR + TreeSpecies.tabebuyaSurabaya.buildCostIDR
                )
            ]
            tourismGain = 26.0
            happinessGain = 15.0
        }

        let totalCost = steps.reduce(0) { $0 + $1.estimatedCostIDR }

        return GebrakanPlan(
            mayorIdeaPrompt: cleanedPrompt,
            projectTitle: projectTitle,
            aiSpatialAnalysis: spatialAnalysis,
            selectedZoneName: zoneName,
            centerCoord: center,
            totalBudgetIDR: totalCost,
            expectedTourismGain: tourismGain,
            expectedHappinessGain: happinessGain,
            steps: steps,
            status: .planned
        )
    }

    // =========================================================================
    // 2. AI AGENT (ASISTEN HARIAN WALIKOTA & KURATOR PERIZINAN INVESTASI)
    // =========================================================================

    func evaluateCityDiagnostics(
        cityMap: NusantaraCityMap,
        gameMode: GameMode,
        stats: CityStatistics,
        roads: [PlacedRoad],
        structures: [PlacedStructure],
        protests: [CitizenProtest]
    ) -> [AIAgentAlert] {
        var alerts: [AIAgentAlert] = []

        if let activeProtest = protests.first(where: { !$0.resolved }) {
            alerts.append(AIAgentAlert(
                title: "Aksi Demo Warga di Koordinat (\(activeProtest.location.x), \(activeProtest.location.z))",
                diagnosis: "Sebanyak \(activeProtest.crowdCount) warga turun ke jalan menyuarakan: \"\(activeProtest.demandMessage)\"",
                suggestedAction: "Segera penuhi kebutuhan infrastruktur yang dituntut warga sebelum tingkat kebahagiaan kota anjlok.",
                severity: .critical,
                targetCoord: activeProtest.location,
                quickFixStructure: activeProtest.issueTitle.contains("Listrik") ? .powerPlantPLN :
                    (activeProtest.issueTitle.contains("Air") ? .waterPlantPDAM : .cityPark)
            ))
        }

        if stats.powerDemandMW > stats.powerSupplyMW {
            let deficit = stats.powerDemandMW - stats.powerSupplyMW
            alerts.append(AIAgentAlert(
                title: "Defisit Pasokan Listrik (-\(deficit) MW)",
                diagnosis: "Konsumsi listrik kota (\(stats.powerDemandMW) MW) melebihi kapasitas pembangkit (\(stats.powerSupplyMW) MW). Rumah warga mulai padam.",
                suggestedAction: "Bangun Gardu & Pembangkit Listrik baru agar warga tidak menggelar aksi demo pemadaman.",
                severity: .critical,
                targetCoord: structures.first?.coord,
                quickFixStructure: .powerPlantPLN
            ))
        }

        if stats.waterDemandML > stats.waterSupplyML {
            let deficit = stats.waterDemandML - stats.waterSupplyML
            alerts.append(AIAgentAlert(
                title: "Krisis Distribusi Air Bersih (-\(deficit) ML)",
                diagnosis: "Kebutuhan air bersih warga (\(stats.waterDemandML) ML) belum tercukupi pasokan PDAM (\(stats.waterSupplyML) ML).",
                suggestedAction: "Tambahkan unit Instalasi Air Bersih (PDAM) di dekat kawasan permukiman.",
                severity: .critical,
                targetCoord: structures.first?.coord,
                quickFixStructure: .waterPlantPDAM
            ))
        }

        if roads.isEmpty && structures.isEmpty {
            alerts.append(AIAgentAlert(
                title: "Selamat Bertugas, Pak/Bu Walikota \(cityMap.displayName)!",
                diagnosis: "Kota ini masih berupa lahan alam murni (0% pembangunan). Warga menunggu pembangunan infrastruktur pertama.",
                suggestedAction: "Mulai dengan membangun Jalan 2 Arah 4 Jalur, Pembangkit Listrik, Air Bersih, dan Area Permukiman.",
                severity: .info,
                targetCoord: GridCoord(x: 32, z: 32),
                quickFixStructure: nil
            ))
        }

        if stats.population >= 180 {
            let hasSD = structures.contains { $0.structureType == .eduSD }
            let hasSMP = structures.contains { $0.structureType == .eduSMP }
            let hasSMA = structures.contains { $0.structureType == .eduSMA }
            let hasUniv = structures.contains { $0.structureType == .eduUniversitas }

            if !hasSD {
                alerts.append(AIAgentAlert(
                    title: "Kebutuhan Sekolah Dasar (SD)",
                    diagnosis: "Populasi anak usia sekolah mulai tumbuh di permukiman, namun belum tersedia gedung SD.",
                    suggestedAction: "Bangun Sekolah Dasar (SD) dari menu Pendidikan untuk meningkatkan indeks SDM kota.",
                    severity: .warning,
                    targetCoord: nil,
                    quickFixStructure: .eduSD
                ))
            } else if !hasSMP && stats.population >= 360 {
                alerts.append(AIAgentAlert(
                    title: "Kebutuhan Sekolah Menengah Pertama (SMP)",
                    diagnosis: "Lulusan SD membutuhkan fasilitas SMP agar kualitas pendidikan warga terus berlanjut.",
                    suggestedAction: "Bangun gedung SMP di dekat koridor permukiman.",
                    severity: .warning,
                    targetCoord: nil,
                    quickFixStructure: .eduSMP
                ))
            } else if !hasSMA && stats.population >= 540 {
                alerts.append(AIAgentAlert(
                    title: "Kebutuhan Sekolah Menengah Atas (SMA)",
                    diagnosis: "Warga remaja membutuhkan fasilitas SMA untuk mempersiapkan tenaga kerja terampil.",
                    suggestedAction: "Bangun gedung SMA dari menu Pendidikan.",
                    severity: .info,
                    targetCoord: nil,
                    quickFixStructure: .eduSMA
                ))
            } else if !hasUniv && stats.population >= 720 {
                alerts.append(AIAgentAlert(
                    title: "Peluang Pendirian Universitas Kota",
                    diagnosis: "Kota sudah cukup matang untuk memiliki Universitas guna mendorong riset dan pajak sektor modern.",
                    suggestedAction: "Bangun Universitas atau gunakan menu Gebrakan Walikota untuk kawasan pendidikan terpadu.",
                    severity: .info,
                    targetCoord: nil,
                    quickFixStructure: .eduUniversitas
                ))
            }
        }

        let unplantedRoads = roads.filter { $0.plantedTree == nil }.count
        if roads.count >= 4 && unplantedRoads > roads.count / 2 {
            alerts.append(AIAgentAlert(
                title: "Trotoar Masih Gersang",
                diagnosis: "Sebagian besar jalan dan trotoar belum ditanami pepohonan peneduh (\(cityMap.defaultTreeSpecies.shortName)).",
                suggestedAction: "Pilih menu Pohon lalu ketuk ruas jalan/trotoar untuk menanam pohon dan mengurangi polusi.",
                severity: .info,
                targetCoord: roads.first(where: { $0.plantedTree == nil })?.coord,
                quickFixStructure: nil
            ))
        }

        if gameMode == .real && stats.budgetIDR < 150_000_000 {
            alerts.append(AIAgentAlert(
                title: "Peringatan Kas APBD Menipis",
                diagnosis: "Saldo APBD tersisa \(IDRFormatter.format(stats.budgetIDR)). Pembangunan besar berisiko gagal.",
                suggestedAction: "Setujui izin investasi swasta (seperti Indomaret/gedung komersial) atau tambah area komersial untuk menaikkan pajak.",
                severity: .warning,
                targetCoord: nil,
                quickFixStructure: nil
            ))
        }

        if alerts.isEmpty {
            alerts.append(AIAgentAlert(
                title: "Kondisi Kota Terkendali & Kondusif",
                diagnosis: "Suplai listrik, air bersih, dan lalu lintas berjalan stabil. Warga menikmati suasana kota.",
                suggestedAction: "Anda dapat merancang proyek ikonik baru lewat menu Gebrakan Walikota kapan saja.",
                severity: .info,
                targetCoord: nil,
                quickFixStructure: nil
            ))
        }

        return alerts
    }

    func generateIncomingPermitRequest(
        cityMap: NusantaraCityMap,
        roads: [PlacedRoad],
        structures: [PlacedStructure],
        existingPermits: [PermitRequest]
    ) -> PermitRequest? {
        guard !roads.isEmpty else { return nil }
        let pendingCount = existingPermits.filter { $0.isApproved == nil }.count
        guard pendingCount < 3 else { return nil }

        let occupied = buildOccupiedSet(roads: roads, structures: structures)
        let anchor = roads.randomElement()?.coord ?? GridCoord(x: 32, z: 32)
        let site = findNearestFreeCoord(near: anchor, occupied: occupied, radius: 6)

        let roll = Int.random(in: 0...2)
        if roll == 0 {
            return PermitRequest(
                applicantName: "PT Indomarco Prismatama (Indomaret)",
                structureType: .indomaretRetail,
                proposedCoord: site,
                investmentFeeIDR: 120_000_000,
                taxRevenuePerMonthIDR: 22_000_000,
                jobsCreated: 24,
                aiAgentPros: "Menambah pemasukan retribusi izin Rp 120 Jt, pajak bulanan Rp 22 Jt, dan mempermudah akses kebutuhan harian warga sekitar.",
                aiAgentCons: "Berpotensi meningkatkan persaingan dengan warung kelontong/UMKM lokal serta menambah parkir motor di bahu jalan.",
                aiRecommendation: "Disarankan SETUJUI jika akses jalan sekitar sudah memiliki trotoar atau 2 jalur memadai."
            )
        } else if roll == 1 {
            return PermitRequest(
                applicantName: "PT Nusantara Properti Jaya (Menara Komersial)",
                structureType: .commercialHighRise,
                proposedCoord: site,
                investmentFeeIDR: 450_000_000,
                taxRevenuePerMonthIDR: 55_000_000,
                jobsCreated: 220,
                aiAgentPros: "Suntikan investasi besar untuk kas daerah, menciptakan 220 lapangan kerja baru, dan mempercantik skyline malam kota.",
                aiAgentCons: "Mengonsumsi daya listrik 35 MW dan air 28 ML serta berpotensi memicu kemacetan jika tidak terhubung Jalan 2 Arah 4 Jalur.",
                aiRecommendation: "Pastikan cadangan listrik & air bersih kota mencukupi sebelum menandatangani IMB gedung tinggi ini."
            )
        } else {
            return PermitRequest(
                applicantName: "PT Indomarco Prismatama (Indomaret Point & Cafe)",
                structureType: .indomaretRetail,
                proposedCoord: site,
                investmentFeeIDR: 145_000_000,
                taxRevenuePerMonthIDR: 25_000_000,
                jobsCreated: 28,
                aiAgentPros: "Konsep ritel modern dengan area duduk malam yang menghidupkan suasana cozy kota serta menyumbang pajak daerah.",
                aiAgentCons: "Membutuhkan pasokan listrik stabil 10 MW dan pengelolaan sampah kawasan komersial.",
                aiRecommendation: "Layak disetujui untuk mempercepat pertumbuhan sektor komersial di \(cityMap.displayName)."
            )
        }
    }

    // =========================================================================
    // 3. SIMULASI PEMIKIRAN NPC & AKSI DEMONSTRASI WARGA
    // =========================================================================

    func generateLiveCitizenThoughts(
        cityMap: NusantaraCityMap,
        stats: CityStatistics,
        roads: [PlacedRoad],
        structures: [PlacedStructure]
    ) -> [CitizenThought] {
        guard !structures.isEmpty || !roads.isEmpty else { return [] }

        var thoughts: [CitizenThought] = []
        let sampleCount = min(6, max(2, (structures.count + roads.count) / 3))

        let hasPowerShortage = stats.powerDemandMW > stats.powerSupplyMW
        let hasWaterShortage = stats.waterDemandML > stats.waterSupplyML
        let hasBikeLane = roads.contains { $0.roadType == .bikeLane }
        let plantedCount = roads.filter { $0.plantedTree != nil }.count
        let hasEducation = structures.contains {
            $0.structureType == .eduSD || $0.structureType == .eduSMP ||
            $0.structureType == .eduSMA || $0.structureType == .eduUniversitas
        }

        let roles = ["Pejalan Kaki", "Pemotor", "Pesepeda", "Pelajar", "Pedagang UMKM"]

        for _ in 0..<sampleCount {
            let fullName = "\(indonesianFirstNames.randomElement() ?? "Budi") \(indonesianLastNames.randomElement() ?? "Santoso")"
            let role = roles.randomElement() ?? "Pejalan Kaki"
            let coord = structures.randomElement()?.coord ?? roads.randomElement()?.coord ?? GridCoord(x: 32, z: 32)

            if hasPowerShortage {
                thoughts.append(CitizenThought(
                    citizenName: fullName,
                    role: role,
                    thoughtText: "Listriknya mana ini Pak Wali?! Rumah dan warung mati lampu terus!",
                    moodPositive: false,
                    coord: coord
                ))
            } else if hasWaterShortage {
                thoughts.append(CitizenThought(
                    citizenName: fullName,
                    role: role,
                    thoughtText: "Air PDAM mampet sejak pagi, tolong segera bangun instalasi air bersih!",
                    moodPositive: false,
                    coord: coord
                ))
            } else if role == "Pesepeda" && !hasBikeLane {
                thoughts.append(CitizenThought(
                    citizenName: fullName,
                    role: role,
                    thoughtText: "Agak ngeri gowes bareng motor, semoga Walikota bikin jalur khusus pesepeda.",
                    moodPositive: false,
                    coord: coord
                ))
            } else if role == "Pelajar" && !hasEducation {
                thoughts.append(CitizenThought(
                    citizenName: fullName,
                    role: role,
                    thoughtText: "Kami butuh sekolah (SD/SMP/SMA) yang dekat dari permukiman warga.",
                    moodPositive: false,
                    coord: coord
                ))
            } else if stats.isNightTime {
                thoughts.append(CitizenThought(
                    citizenName: fullName,
                    role: role,
                    thoughtText: "Adem banget suasana malam \(cityMap.displayName), lampu jalan dan kota kelihatan cozy!",
                    moodPositive: true,
                    coord: coord
                ))
            } else if plantedCount > 0 {
                thoughts.append(CitizenThought(
                    citizenName: fullName,
                    role: role,
                    thoughtText: "Trotoarnya teduh banyak pohon \(cityMap.defaultTreeSpecies.shortName), daun gugurnya estetik!",
                    moodPositive: true,
                    coord: coord
                ))
            } else {
                thoughts.append(CitizenThought(
                    citizenName: fullName,
                    role: role,
                    thoughtText: "Kota mulai berkembang pesat, semoga makin banyak ruang terbuka hijau.",
                    moodPositive: true,
                    coord: coord
                ))
            }
        }

        return thoughts
    }

    func evaluateCitizenProtests(
        stats: CityStatistics,
        difficulty: RealDifficulty,
        structures: [PlacedStructure],
        existingProtests: [CitizenProtest]
    ) -> [CitizenProtest] {
        var updated = existingProtests

        for idx in updated.indices {
            if updated[idx].issueTitle.contains("Listrik") && stats.powerSupplyMW >= stats.powerDemandMW {
                updated[idx].resolved = true
            }
            if updated[idx].issueTitle.contains("Air") && stats.waterSupplyML >= stats.waterDemandML {
                updated[idx].resolved = true
            }
            if updated[idx].issueTitle.contains("Fasilitas") && stats.happinessPercent >= 70.0 {
                updated[idx].resolved = true
            }
        }

        let activeProtests = updated.filter { !$0.resolved }
        guard activeProtests.count < 3, let rallyCoord = structures.first?.coord else {
            return updated.filter { !$0.resolved }
        }

        if stats.powerDemandMW > stats.powerSupplyMW &&
            !activeProtests.contains(where: { $0.issueTitle.contains("Listrik") }) {
            let crowd = Int(Double(max(45, stats.population / 3)) * difficulty.protestSensitivity)
            updated.append(CitizenProtest(
                issueTitle: "Demo Krisis Listrik Kota",
                demandMessage: "Listriknya mana Pak Wali?! Warga menuntut pembangunan Pembangkit Listrik segera!",
                location: rallyCoord,
                crowdCount: crowd,
                severity: 0.90
            ))
        }

        if stats.waterDemandML > stats.waterSupplyML &&
            !activeProtests.contains(where: { $0.issueTitle.contains("Air") }) {
            let crowd = Int(Double(max(40, stats.population / 4)) * difficulty.protestSensitivity)
            updated.append(CitizenProtest(
                issueTitle: "Demo Krisis Air Bersih PDAM",
                demandMessage: "Warga kesulitan air bersih! Segera bangun Instalasi PDAM baru!",
                location: rallyCoord,
                crowdCount: crowd,
                severity: 0.85
            ))
        }

        if stats.population >= 180 && stats.happinessPercent < 48.0 &&
            !activeProtests.contains(where: { $0.issueTitle.contains("Fasilitas") }) {
            updated.append(CitizenProtest(
                issueTitle: "Demo Tuntutan Fasilitas & Taman Kota",
                demandMessage: "Warga butuh taman kota, penghijauan trotoar, dan fasilitas pendidikan!",
                location: rallyCoord,
                crowdCount: 65,
                severity: 0.70
            ))
        }

        return updated.filter { !$0.resolved }
    }

    // =========================================================================
    // 4. HELPER PENCARIAN SPASIAL GRID PETA
    // =========================================================================

    private func buildOccupiedSet(roads: [PlacedRoad], structures: [PlacedStructure]) -> Set<GridCoord> {
        var set = Set<GridCoord>()
        for r in roads { set.insert(r.coord) }
        for s in structures { set.insert(s.coord) }
        return set
    }

    private func findClusterCenter(structures: [PlacedStructure], fallback: GridCoord) -> GridCoord {
        guard !structures.isEmpty else { return fallback }
        let sumX = structures.reduce(0) { $0 + $1.coord.x }
        let sumZ = structures.reduce(0) { $0 + $1.coord.z }
        return GridCoord(x: sumX / structures.count, z: sumZ / structures.count)
    }

    func findNearestFreeCoord(near origin: GridCoord, occupied: Set<GridCoord>, radius: Int) -> GridCoord {
        if !occupied.contains(origin) && isValidCoord(origin) {
            return origin
        }
        for r in 1...radius {
            for dx in -r...r {
                for dz in -r...r {
                    let candidate = GridCoord(x: origin.x + dx, z: origin.z + dz)
                    if isValidCoord(candidate) && !occupied.contains(candidate) {
                        return candidate
                    }
                }
            }
        }
        return GridCoord(x: max(2, min(gridSize - 3, origin.x)), z: max(2, min(gridSize - 3, origin.z)))
    }

    private func isValidCoord(_ c: GridCoord) -> Bool {
        c.x >= 2 && c.x < gridSize - 2 && c.z >= 2 && c.z < gridSize - 2
    }
}

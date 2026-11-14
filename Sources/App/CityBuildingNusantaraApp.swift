import SwiftUI
import Combine

// MARK: - Titik Masuk Utama Aplikasi iOS

@main
struct CityBuildingNusantaraApp: App {
    @StateObject private var viewModel = GameSessionViewModel()

    var body: some Scene {
        WindowGroup {
            RootGameContainerView(viewModel: viewModel)
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - ViewModel Pusat Pengendali Simulasi, 3D Engine & Dual-AI

@MainActor
final class GameSessionViewModel: ObservableObject {

    // Navigasi Layar & Konfigurasi Permainan
    @Published var screenState: GameScreenState = .bootLoading
    @Published var selectedMode: GameMode = .real
    @Published var selectedDifficulty: RealDifficulty = .medium
    @Published var selectedMap: NusantaraCityMap = .malang

    // Pengaturan Grafik & Audio
    @Published var settings: GraphicsSettings = GraphicsSettings()

    // Statistik & Dunia Kota Aktif
    @Published var stats: CityStatistics = CityStatistics()
    @Published var roads: [PlacedRoad] = []
    @Published var structures: [PlacedStructure] = []
    @Published var protests: [CitizenProtest] = []
    @Published var citizenThoughts: [CitizenThought] = []

    // State Sistem Dual-AI
    @Published var draftGebrakanPlan: GebrakanPlan? = nil
    @Published var gebrakanHistory: [GebrakanPlan] = []
    @Published var permitRequests: [PermitRequest] = []
    @Published var aiAlerts: [AIAgentAlert] = []

    // Alat Pembangunan Aktif di Toolbar
    @Published var selectedCategory: BuildToolCategory = .roads
    @Published var selectedRoadType: RoadType = .twoWayFourLane
    @Published var selectedStructureType: StructureType = .residentialHouse
    @Published var selectedTreeSpecies: TreeSpecies = .pinusMalang

    // Notifikasi Singkat & Daftar Save Game
    @Published var statusToastMessage: String? = nil
    @Published var savedGames: [CitySaveData] = []

    // Engine 3D SceneKit
    let engineController = City3DEngineController()

    private var simulationTimer: Timer?
    private var tickCounter: Int = 0
    private let savesStorageKey = "com.rizzigames.citybuildingnusantara.saves.v1"
    private let settingsStorageKey = "com.rizzigames.citybuildingnusantara.settings.v1"

    init() {
        loadPersistedSettings()
        loadAllSavedGames()
        setupEngineCallbacks()
    }

    // =========================================================================
    // 1. ALUR INTRO, LOGO RG, MAIN MENU & MULAI KOTA BARU
    // =========================================================================

    func completeBootLoading() {
        screenState = .studioLogo
    }

    func completeStudioLogo() {
        engineController.loadMap(.malang, isShowcaseMenu: true)
        screenState = .mainMenu
    }

    func startNewCitySession() {
        stopSimulationLoop()

        roads.removeAll()
        structures.removeAll()
        protests.removeAll()
        citizenThoughts.removeAll()
        draftGebrakanPlan = nil
        gebrakanHistory.removeAll()
        permitRequests.removeAll()
        aiAlerts.removeAll()
        tickCounter = 0

        selectedTreeSpecies = selectedMap.defaultTreeSpecies
        selectedCategory = .roads
        selectedRoadType = .twoWayFourLane

        var initialStats = CityStatistics()
        initialStats.budgetIDR = selectedMode == .sandbox
            ? 999_999_999_999
            : selectedDifficulty.startingBudgetIDR
        initialStats.timeOfDayHours = 16.8 // Sore cerah menjelang senja & malam cozy
        initialStats.dayCount = 1
        stats = initialStats

        engineController.loadMap(selectedMap, isShowcaseMenu: false)
        recalculateCityMetrics()
        refreshDualAIState(allowNewPermit: false)
        syncEngineWorld()

        screenState = .inGame
        showToast("Selamat datang Walikota di \(selectedMap.displayName)!")
        startSimulationLoop()
    }

    func returnToMainMenu() {
        stopSimulationLoop()
        engineController.loadMap(.malang, isShowcaseMenu: true)
        screenState = .mainMenu
    }

    // =========================================================================
    // 2. INTERAKSI PEMBANGUNAN DI PETA 3D (JALAN, ZONA, SEKOLAH, POHON TROTOAR)
    // =========================================================================

    private func setupEngineCallbacks() {
        engineController.onGridTapped = { [weak self] coord in
            self?.handleGridTap(at: coord)
        }
    }

    func handleGridTap(at coord: GridCoord) {
        guard screenState == .inGame else { return }

        switch selectedCategory {
        case .roads:
            buildRoad(at: coord, type: selectedRoadType)

        case .zones, .utilities, .education:
            buildStructure(at: coord, type: selectedStructureType)

        case .trees:
            plantTreeOnSidewalk(at: coord, species: selectedTreeSpecies)

        case .bulldoze:
            bulldozeTile(at: coord)
        }
    }

    private func buildRoad(at coord: GridCoord, type: RoadType) {
        if structures.contains(where: { $0.coord == coord }) {
            showToast("Lahan sudah terisi bangunan. Hapus dulu jika ingin membangun jalan.")
            return
        }

        if let existingIndex = roads.firstIndex(where: { $0.coord == coord }) {
            if roads[existingIndex].roadType == type {
                showToast("\(type.shortLabel) sudah terpasang di titik ini.")
                return
            }
            guard chargeBudget(type.buildCostIDR) else { return }
            roads[existingIndex].roadType = type
        } else {
            guard chargeBudget(type.buildCostIDR) else { return }
            let newRoad = PlacedRoad(
                coord: coord,
                roadType: type,
                hasStreetLights: true,
                plantedTree: nil
            )
            roads.append(newRoad)
        }

        engineController.playBuildSFX(volume: settings.soundVolume)
        recalculateCityMetrics()
        refreshDualAIState(allowNewPermit: false)
        syncEngineWorld()
        showToast("\(type.displayName) selesai dibangun.")
    }

    private func buildStructure(at coord: GridCoord, type: StructureType) {
        if roads.contains(where: { $0.coord == coord }) ||
            structures.contains(where: { $0.coord == coord }) {
            showToast("Titik ini sudah terisi. Pilih lahan kosong di sebelahnya.")
            return
        }

        guard chargeBudget(type.buildCostIDR) else { return }

        let newStructure = PlacedStructure(
            coord: coord,
            structureType: type,
            rotationY: 0.0,
            hasPower: true,
            hasWater: true,
            satisfaction: 88.0
        )
        structures.append(newStructure)

        engineController.playBuildSFX(volume: settings.soundVolume)
        recalculateCityMetrics()
        refreshDualAIState(allowNewPermit: false)
        syncEngineWorld()
        showToast("\(type.displayName) berhasil didirikan.")
    }

    private func plantTreeOnSidewalk(at coord: GridCoord, species: TreeSpecies) {
        // Cari ruas jalan/trotoar di titik sentuh atau 1 petak di sekitarnya
        let targetIndex = roads.firstIndex(where: { $0.coord == coord }) ??
            roads.firstIndex(where: { abs($0.coord.x - coord.x) <= 1 && abs($0.coord.z - coord.z) <= 1 })

        guard let idx = targetIndex else {
            showToast("Ketuk pada ruas Jalan atau Trotoar untuk menanam pohon peneduh.")
            return
        }

        guard chargeBudget(species.buildCostIDR) else { return }

        roads[idx].plantedTree = species
        engineController.playBuildSFX(volume: settings.soundVolume)
        recalculateCityMetrics()
        syncEngineWorld()
        showToast("\(species.shortName) berhasil ditanam di trotoar!")
    }

    private func bulldozeTile(at coord: GridCoord) {
        if let sIdx = structures.firstIndex(where: { $0.coord == coord }) {
            let removedName = structures[sIdx].structureType.displayName
            structures.remove(at: sIdx)
            engineController.playBuildSFX(volume: settings.soundVolume)
            recalculateCityMetrics()
            refreshDualAIState(allowNewPermit: false)
            syncEngineWorld()
            showToast("\(removedName) dibongkar.")
            return
        }

        if let rIdx = roads.firstIndex(where: { $0.coord == coord }) {
            let removedName = roads[rIdx].roadType.shortLabel
            roads.remove(at: rIdx)
            engineController.playBuildSFX(volume: settings.soundVolume)
            recalculateCityMetrics()
            refreshDualAIState(allowNewPermit: false)
            syncEngineWorld()
            showToast("\(removedName) dibongkar.")
            return
        }

        showToast("Tidak ada bangunan atau jalan di titik tersebut.")
    }

    private func chargeBudget(_ cost: Int64) -> Bool {
        if selectedMode == .sandbox {
            return true
        }
        if stats.budgetIDR < cost {
            showToast("Anggaran APBD tidak cukup! Butuh \(IDRFormatter.format(cost)).")
            return false
        }
        stats.budgetIDR -= cost
        return true
    }

    // =========================================================================
    // 3. EKSEKUSI DUAL-AI (AI GEBRAKAN WALIKOTA & AI AGENT PERIZINAN)
    // =========================================================================

    func generateGebrakanDraft(ideaPrompt: String) {
        let plan = NusantaraAISystem.shared.generateGebrakanPlan(
            prompt: ideaPrompt,
            cityMap: selectedMap,
            roads: roads,
            structures: structures,
            stats: stats
        )
        draftGebrakanPlan = plan
    }

    func executeGebrakanPlan(_ plan: GebrakanPlan) {
        guard chargeBudget(plan.totalBudgetIDR) else { return }

        var executedPlan = plan
        executedPlan.status = .executing

        for i in executedPlan.steps.indices {
            let step = executedPlan.steps[i]
            let coord = step.targetCoord

            if let roadType = step.roadToBuild {
                structures.removeAll { $0.coord == coord }
                if let rIdx = roads.firstIndex(where: { $0.coord == coord }) {
                    roads[rIdx].roadType = roadType
                    if let tree = step.treeToPlant {
                        roads[rIdx].plantedTree = tree
                    }
                } else {
                    roads.append(PlacedRoad(
                        coord: coord,
                        roadType: roadType,
                        hasStreetLights: true,
                        plantedTree: step.treeToPlant
                    ))
                }
            } else if let structureType = step.structureToBuild {
                roads.removeAll { $0.coord == coord }
                structures.removeAll { $0.coord == coord }
                structures.append(PlacedStructure(
                    coord: coord,
                    structureType: structureType,
                    rotationY: 0.0,
                    hasPower: true,
                    hasWater: true,
                    satisfaction: 95.0,
                    customTitle: plan.projectTitle
                ))
            } else if let tree = step.treeToPlant {
                if let rIdx = roads.firstIndex(where: { $0.coord == coord }) {
                    roads[rIdx].plantedTree = tree
                } else {
                    roads.append(PlacedRoad(
                        coord: coord,
                        roadType: .sidewalk,
                        hasStreetLights: true,
                        plantedTree: tree
                    ))
                }
            }

            executedPlan.steps[i].isCompleted = true
        }

        executedPlan.status = .completed
        gebrakanHistory.insert(executedPlan, at: 0)
        draftGebrakanPlan = nil

        engineController.playBuildSFX(volume: settings.soundVolume)
        recalculateCityMetrics()
        refreshDualAIState(allowNewPermit: false)
        syncEngineWorld()
        engineController.focusCamera(on: executedPlan.centerCoord)
        showToast("Gebrakan \"\(executedPlan.projectTitle)\" selesai dibangun!")
    }

    func decidePermit(_ permit: PermitRequest, approved: Bool) {
        guard let idx = permitRequests.firstIndex(where: { $0.id == permit.id }) else { return }
        permitRequests[idx].isApproved = approved

        if approved {
            var occupied = Set<GridCoord>()
            roads.forEach { occupied.insert($0.coord) }
            structures.forEach { occupied.insert($0.coord) }

            let finalCoord = NusantaraAISystem.shared.findNearestFreeCoord(
                near: permit.proposedCoord,
                occupied: occupied,
                radius: 8
            )

            structures.append(PlacedStructure(
                coord: finalCoord,
                structureType: permit.structureType,
                rotationY: 0.0,
                hasPower: true,
                hasWater: true,
                satisfaction: 86.0,
                customTitle: permit.applicantName
            ))

            if selectedMode == .real {
                stats.budgetIDR += permit.investmentFeeIDR
            }

            engineController.playBuildSFX(volume: settings.soundVolume)
            recalculateCityMetrics()
            refreshDualAIState(allowNewPermit: false)
            syncEngineWorld()
            engineController.focusCamera(on: finalCoord)
            showToast("Izin \(permit.applicantName) disetujui! +\(IDRFormatter.format(permit.investmentFeeIDR))")
        } else {
            showToast("Pengajuan izin \(permit.applicantName) ditolak.")
        }
    }

    func triggerQuickFix(from alert: AIAgentAlert) {
        guard let fixStructure = alert.quickFixStructure else { return }
        switch fixStructure {
        case .powerPlantPLN, .waterPlantPDAM:
            selectedCategory = .utilities
            selectedStructureType = fixStructure
        case .eduSD, .eduSMP, .eduSMA, .eduUniversitas:
            selectedCategory = .education
            selectedStructureType = fixStructure
        default:
            selectedCategory = .zones
            selectedStructureType = fixStructure
        }

        if let coord = alert.targetCoord {
            engineController.focusCamera(on: coord)
        }
        showToast("Alat pilih: \(fixStructure.displayName). Ketuk lahan kosong di peta!")
    }

    // =========================================================================
    // 4. LOOP SIMULASI REAL-TIME (SIANG-MALAM, EKONOMI, WARGA & DEMO)
    // =========================================================================

    private func startSimulationLoop() {
        stopSimulationLoop()
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.simulationTick()
            }
        }
    }

    private func stopSimulationLoop() {
        simulationTimer?.invalidate()
        simulationTimer = nil
    }

    private func simulationTick() {
        guard screenState == .inGame else { return }
        tickCounter += 1

        // Progres waktu kota (1 tick = 15 menit virtual)
        stats.timeOfDayHours += 0.25
        if stats.timeOfDayHours >= 24.0 {
            stats.timeOfDayHours -= 24.0
            stats.dayCount += 1

            // Siklus anggaran bulanan/harian di Real Mode
            if selectedMode == .real {
                let netCashflow = stats.monthlyIncomeIDR - stats.monthlyExpenseIDR
                stats.budgetIDR += netCashflow
            }
        }

        recalculateCityMetrics()

        // Evaluasi demonstrasi warga, pikiran NPC, dan pengajuan izin swasta
        protests = NusantaraAISystem.shared.evaluateCitizenProtests(
            stats: stats,
            difficulty: selectedDifficulty,
            structures: structures,
            existingProtests: protests
        )

        if tickCounter % 2 == 0 {
            citizenThoughts = NusantaraAISystem.shared.generateLiveCitizenThoughts(
                cityMap: selectedMap,
                stats: stats,
                roads: roads,
                structures: structures
            )
        }

        let shouldSpawnPermit = (tickCounter % 5 == 0) && !roads.isEmpty
        refreshDualAIState(allowNewPermit: shouldSpawnPermit)
        syncEngineWorld()
    }

    private func recalculateCityMetrics() {
        var totalPop = 0
        var totalPowerSupply = 0
        var totalPowerDemand = 0
        var totalWaterSupply = 0
        var totalWaterDemand = 0
        var totalIncome: Int64 = 0
        var totalExpense: Int64 = 0
        var eduBonus = 25.0
        var tourBonus = 10.0

        for s in structures {
            totalPop += s.structureType.populationCapacity
            eduBonus += s.structureType.educationBonus
            tourBonus += s.structureType.tourismBonus

            let pDelta = s.structureType.powerDeltaMW
            if pDelta >= 0 { totalPowerSupply += pDelta } else { totalPowerDemand += abs(pDelta) }

            let wDelta = s.structureType.waterDeltaML
            if wDelta >= 0 { totalWaterSupply += wDelta } else { totalWaterDemand += abs(wDelta) }

            let cashflow = s.structureType.monthlyTaxOrMaintenanceIDR
            if cashflow >= 0 { totalIncome += cashflow } else { totalExpense += abs(cashflow) }
        }

        var plantedTrees = 0
        for r in roads {
            totalExpense += r.roadType.maintenancePerMonthIDR
            if r.plantedTree != nil {
                plantedTrees += 1
            }
        }

        // Update status suplai listrik & air pada setiap gedung
        let powerOK = totalPowerSupply >= totalPowerDemand
        let waterOK = totalWaterSupply >= totalWaterDemand
        for idx in structures.indices {
            structures[idx].hasPower = powerOK
            structures[idx].hasWater = waterOK
        }

        let greenery = roads.isEmpty ? 55.0 : min(100.0, 35.0 + (Double(plantedTrees) / Double(roads.count)) * 65.0)
        var happiness = 72.0 + (greenery - 50.0) * 0.25 + (eduBonus - 25.0) * 0.2 + (tourBonus - 10.0) * 0.15
        if !powerOK { happiness -= 28.0 }
        if !waterOK { happiness -= 24.0 }
        happiness -= Double(protests.filter { !$0.resolved }.count) * 8.0

        stats.population = totalPop
        stats.powerSupplyMW = totalPowerSupply
        stats.powerDemandMW = totalPowerDemand
        stats.waterSupplyML = totalWaterSupply
        stats.waterDemandML = totalWaterDemand
        stats.monthlyIncomeIDR = totalIncome
        stats.monthlyExpenseIDR = totalExpense
        stats.educationIndex = min(100.0, eduBonus)
        stats.tourismRating = min(100.0, tourBonus)
        stats.greeneryIndex = greenery
        stats.happinessPercent = max(10.0, min(100.0, happiness))
    }

    private func refreshDualAIState(allowNewPermit: Bool) {
        aiAlerts = NusantaraAISystem.shared.evaluateCityDiagnostics(
            cityMap: selectedMap,
            gameMode: selectedMode,
            stats: stats,
            roads: roads,
            structures: structures,
            protests: protests
        )

        if allowNewPermit,
           let incoming = NusantaraAISystem.shared.generateIncomingPermitRequest(
               cityMap: selectedMap,
               roads: roads,
               structures: structures,
               existingPermits: permitRequests
           ) {
            permitRequests.insert(incoming, at: 0)
            showToast("AI Agent: Pengajuan izin baru dari \(incoming.applicantName)!")
        }
    }

    private func syncEngineWorld() {
        engineController.syncWorld(
            roads: roads,
            structures: structures,
            protests: protests,
            stats: stats,
            settings: settings
        )
    }

    // =========================================================================
    // 5. KONTROL KAMERA, PENGATURAN GRAFIK & SAVE / LOAD GAME
    // =========================================================================

    func focusOnCoord(_ coord: GridCoord) {
        engineController.focusCamera(on: coord)
    }

    func toggleCozyNightMode() {
        settings.lockNightCozyMode.toggle()
        if !settings.lockNightCozyMode {
            stats.timeOfDayHours = stats.isNightTime ? 10.0 : 20.5
        }
        applyGraphicsSettings()
        showToast((settings.lockNightCozyMode || stats.isNightTime)
            ? "Mode Malam Cozy City Lights Aktif"
            : "Mode Siang Cerah Aktif")
    }

    func applyGraphicsSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsStorageKey)
        }
        syncEngineWorld()
    }

    private func loadPersistedSettings() {
        if let data = UserDefaults.standard.data(forKey: settingsStorageKey),
           let decoded = try? JSONDecoder().decode(GraphicsSettings.self, from: data) {
            settings = decoded
        }
    }

    func saveCurrentGame(customName: String?) {
        let title = customName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? customName!
            : "\(selectedMap.displayName) - Hari ke-\(stats.dayCount)"

        let snapshot = CitySaveData(
            saveTitle: title,
            savedAt: Date(),
            gameMode: selectedMode,
            difficulty: selectedDifficulty,
            cityMap: selectedMap,
            stats: stats,
            roads: roads,
            structures: structures,
            protests: protests,
            gebrakanHistory: gebrakanHistory,
            permitRequests: permitRequests
        )

        savedGames.insert(snapshot, at: 0)
        persistSavedGames()
        showToast("Kota berhasil disimpan: \(title)")
    }

    func loadSavedGame(_ save: CitySaveData) {
        stopSimulationLoop()

        selectedMode = save.gameMode
        selectedDifficulty = save.difficulty
        selectedMap = save.cityMap
        stats = save.stats
        roads = save.roads
        structures = save.structures
        protests = save.protests
        gebrakanHistory = save.gebrakanHistory
        permitRequests = save.permitRequests
        selectedTreeSpecies = save.cityMap.defaultTreeSpecies

        engineController.loadMap(save.cityMap, isShowcaseMenu: false)
        recalculateCityMetrics()
        refreshDualAIState(allowNewPermit: false)
        syncEngineWorld()

        screenState = .inGame
        startSimulationLoop()
        showToast("Memuat kota: \(save.saveTitle)")
    }

    func deleteSavedGame(_ save: CitySaveData) {
        savedGames.removeAll { $0.id == save.id }
        persistSavedGames()
    }

    private func persistSavedGames() {
        if let data = try? JSONEncoder().encode(savedGames) {
            UserDefaults.standard.set(data, forKey: savesStorageKey)
        }
    }

    private func loadAllSavedGames() {
        if let data = UserDefaults.standard.data(forKey: savesStorageKey),
           let decoded = try? JSONDecoder().decode([CitySaveData].self, from: data) {
            savedGames = decoded
        }
    }

    private func showToast(_ message: String) {
        statusToastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in
            if self?.statusToastMessage == message {
                self?.statusToastMessage = nil
            }
        }
    }
}

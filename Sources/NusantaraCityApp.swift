import UIKit
import SwiftUI
import Combine

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ app: UIApplication, didFinishLaunchingWithOptions opts: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let win = UIWindow(frame: UIScreen.main.bounds)
        win.rootViewController = UIHostingController(rootView: RootGameView().preferredColorScheme(.dark))
        win.makeKeyAndVisible()
        self.window = win
        return true
    }
    func application(_ app: UIApplication, supportedInterfaceOrientationsFor win: UIWindow?) -> UIInterfaceOrientationMask { .landscape }
}

enum AppScreen {
    case splashTitle
    case splashStudio
    case mainMenu
    case selectMode
    case selectMap
    case saveSlots
    case settingsMenu
    case inGame
}

@MainActor
final class GameViewModel: ObservableObject {
    @Published var screen: AppScreen = .splashTitle
    @Published var selectedMap: CityMapType = .malang
    @Published var selectedMode: PlayMode = .real

    @Published var budgetIDR: Int64 = 150_000_000_000
    @Published var population: Int = 0
    @Published var educationIndex: Int = 0
    @Published var happiness: Int = 85
    @Published var powerSupply: Int = 0
    @Published var powerDemand: Int = 0
    @Published var waterSupply: Int = 0
    @Published var waterDemand: Int = 0

    @Published var rDemand: Double = 0.80
    @Published var cDemand: Double = 0.50
    @Published var iDemand: Double = 0.45

    @Published var isNight: Bool = false
    @Published var isMuted: Bool = false
    @Published var hideHUDForPhoto: Bool = false
    @Published var touchToolMode: TouchToolMode = .buildBrush
    @Published var cameraMode: CameraMode = .drone
    @Published var lensMode: DataLensMode = .normal

    @Published var activeCategory: BuildCategory = .roads
    @Published var selRoad: RoadKind = .twoLane
    @Published var selZoneBrush: ZoneBrushKind = .residentialLow
    @Published var selFacility: FacilityKind = .balaiKota
    @Published var selUtility: UtilityKind = .garduListrik

    @Published var roads: [GridCoord: RoadTile] = [:]
    @Published var plots: [GridCoord: ZonedPlot] = [:]
    @Published var facilities: [GridCoord: FacilityTile] = [:]
    @Published var utilities: [GridCoord: UtilityTile] = [:]
    @Published var activeGebrakans: Set<GebrakanKind> = []

    @Published var settings = GameSettings()
    @Published var inspectCard: InspectCardData? = nil
    @Published var dragCostPreview: String? = nil
    @Published var aiAgentMessage: String = "Tarik garis jalan di tanah, lalu sapukan Kuas Zona (Hijau/Biru/Kuning) di pinggir jalan!"
    @Published var accidentCoord: GridCoord? = nil
    @Published var toast: String? = nil

    private var dragStartCoord: GridCoord? = nil
    private var dragCurrentCoords: [GridCoord] = []
    private var undoStack: [UndoAction] = []
    let engine = City3DEngine()
    private var simTimer: Timer?

    init() {
        engine.onTileTapped = { [weak self] coord in
            Task { @MainActor [weak self] in self?.handleSingleTap(coord) }
        }
        engine.onDragBegan = { [weak self] coord in
            Task { @MainActor [weak self] in self?.handleDragBegan(coord) }
        }
        engine.onDragMoved = { [weak self] coord in
            Task { @MainActor [weak self] in self?.handleDragMoved(coord) }
        }
        engine.onDragEnded = { [weak self] coord in
            Task { @MainActor [weak self] in self?.handleDragEnded(coord) }
        }
        startSplashSequence()
    }

    func startSplashSequence() {
        screen = .splashTitle
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.screen == .splashTitle else { return }
            self.screen = .splashStudio
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.screen == .splashStudio else { return }
                self.enterMainMenu()
            }
        }
    }

    func enterMainMenu() {
        simTimer?.invalidate()
        simTimer = nil
        inspectCard = nil
        hideHUDForPhoto = false
        engine.loadMap(.malang, showcaseDemo: true)
        screen = .mainMenu
    }

    func startCity() {
        roads.removeAll(); plots.removeAll(); facilities.removeAll(); utilities.removeAll()
        activeGebrakans.removeAll(); undoStack.removeAll()
        accidentCoord = nil; inspectCard = nil; hideHUDForPhoto = false
        population = 0; educationIndex = 0; happiness = 85
        budgetIDR = selectedMode == .sandbox ? 999_999_999_999_999 : 150_000_000_000

        engine.loadMap(selectedMap, showcaseDemo: false)
        engine.applyAtmosphere(shadows: settings.hdShadows, fog: settings.atmosphericFog, bloom: settings.hdrBloom)
        engine.cameraSensitivity = settings.cameraSensitivity
        screen = .inGame
        aiAgentMessage = "1) Tarik jalan raya di tanah  2) Sapukan Kuas Zona di tepi jalan  3) Rumah otomatis tumbuh & naik Lv 1→5!"
        startSimulationLoop()
    }

    // MARK: - Save & Load Multi-Slot

    func slotSnapshot(_ slot: Int) -> CitySaveSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: "nusantara.v4.slot.\(slot)") else { return nil }
        return try? JSONDecoder().decode(CitySaveSnapshot.self, from: data)
    }

    func saveToSlot(_ slot: Int) {
        let fmt = DateFormatter()
        fmt.dateFormat = "dd MMM HH:mm"
        let snap = CitySaveSnapshot(
            slotIndex: slot,
            savedAtText: fmt.string(from: Date()),
            mapType: selectedMap,
            playMode: selectedMode,
            budgetIDR: budgetIDR,
            population: population,
            roads: Array(roads.values),
            plots: Array(plots.values),
            facilities: Array(facilities.values),
            utilities: Array(utilities.values),
            activeGebrakans: Array(activeGebrakans)
        )
        if let encoded = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(encoded, forKey: "nusantara.v4.slot.\(slot)")
            showToast("Kota tersimpan di Slot \(slot)!")
        }
    }

    func loadFromSlot(_ slot: Int) {
        guard let snap = slotSnapshot(slot) else {
            showToast("Slot \(slot) masih kosong.")
            return
        }
        selectedMap = snap.mapType
        selectedMode = snap.playMode
        budgetIDR = snap.budgetIDR
        roads = Dictionary(uniqueKeysWithValues: snap.roads.map { ($0.coord, $0) })
        plots = Dictionary(uniqueKeysWithValues: snap.plots.map { ($0.coord, $0) })
        facilities = Dictionary(uniqueKeysWithValues: snap.facilities.map { ($0.coord, $0) })
        utilities = Dictionary(uniqueKeysWithValues: snap.utilities.map { ($0.coord, $0) })
        activeGebrakans = Set(snap.activeGebrakans)
        undoStack.removeAll()

        engine.loadMap(selectedMap, showcaseDemo: false)
        syncEngine()
        recalcStats()
        screen = .inGame
        startSimulationLoop()
        showToast("Kota \(selectedMap.title) dari Slot \(slot) dimuat!")
    }

    // MARK: - Tarik Jalan Geser Jari (Drag-to-Build) & Kuas Zona Otomatis

    private func computeRoadPath(from a: GridCoord, to b: GridCoord) -> [GridCoord] {
        var result: [GridCoord] = [a]
        var cx = a.x
        var cz = a.z
        while cx != b.x {
            cx += (b.x > cx) ? 1 : -1
            result.append(GridCoord(x: cx, z: cz))
        }
        while cz != b.z {
            cz += (b.z > cz) ? 1 : -1
            result.append(GridCoord(x: cx, z: cz))
        }
        return result
    }

    private func isNearRoad(_ c: GridCoord) -> Bool {
        for dz in -3...3 {
            for dx in -3...3 {
                if abs(dx) + abs(dz) <= 3 {
                    if let r = roads[GridCoord(x: c.x + dx, z: c.z + dz)], r.kind.isDriveable {
                        return true
                    }
                }
            }
        }
        return false
    }

    func handleDragBegan(_ coord: GridCoord) {
        guard screen == .inGame else { return }
        dragStartCoord = coord
        dragCurrentCoords = [coord]
        updatePreviewOverlay()
    }

    func handleDragMoved(_ coord: GridCoord) {
        guard screen == .inGame, let start = dragStartCoord else { return }
        if activeCategory == .roads {
            dragCurrentCoords = computeRoadPath(from: start, to: coord)
        } else if activeCategory == .zoning {
            if !dragCurrentCoords.contains(coord) {
                dragCurrentCoords.append(coord)
            }
        } else {
            dragCurrentCoords = [coord]
        }
        updatePreviewOverlay()
    }

    func handleDragEnded(_ coord: GridCoord) {
        guard screen == .inGame else { return }
        let targets = dragCurrentCoords.isEmpty ? [coord] : dragCurrentCoords
        dragStartCoord = nil
        dragCurrentCoords = []
        dragCostPreview = nil
        engine.updateDragPreview(coords: [], isValid: true, tint: .cyan)

        if activeCategory == .roads {
            commitBatchRoads(targets)
        } else if activeCategory == .zoning {
            commitBatchZones(targets)
        } else {
            handleSingleTap(coord)
        }
    }

    private func updatePreviewOverlay() {
        guard !dragCurrentCoords.isEmpty else { return }
        if activeCategory == .roads {
            let validCoords = dragCurrentCoords.filter { plots[$0] == nil && facilities[$0] == nil && utilities[$0] == nil }
            let totalCost = Int64(validCoords.count) * selRoad.costIDR
            dragCostPreview = "\(validCoords.count) Petak Jalan • \(selectedMode == .sandbox ? "Gratis" : IDRFormat.string(totalCost))"
            engine.updateDragPreview(coords: dragCurrentCoords, isValid: validCoords.count == dragCurrentCoords.count, tint: .cyan)
        } else if activeCategory == .zoning {
            let validCoords = dragCurrentCoords.filter { roads[$0] == nil && facilities[$0] == nil && utilities[$0] == nil && isNearRoad($0) }
            let totalCost = Int64(validCoords.count) * selZoneBrush.costIDR
            dragCostPreview = "\(selZoneBrush.title) (\(validCoords.count) Petak) • \(selectedMode == .sandbox ? "Gratis" : IDRFormat.string(totalCost))"
            let tint: UIColor = selZoneBrush == .commercial ? .systemBlue : (selZoneBrush == .industrialOffice ? .systemYellow : .systemGreen)
            engine.updateDragPreview(coords: dragCurrentCoords, isValid: !validCoords.isEmpty, tint: tint)
        }
    }

    private func commitBatchRoads(_ coords: [GridCoord]) {
        let valid = coords.filter { plots[$0] == nil && facilities[$0] == nil && utilities[$0] == nil && roads[$0] == nil }
        guard !valid.isEmpty else {
            showToast("Lahan sudah terisi bangunan.")
            return
        }
        let totalCost = Int64(valid.count) * selRoad.costIDR
        guard spend(totalCost) else { return }

        for (idx, c) in valid.enumerated() {
            let yaw: Float = selRoad == .elasticCurve ? Float(idx % 4) * 0.25 : 0.0
            roads[c] = RoadTile(coord: c, kind: selRoad, curveYaw: yaw)
            if accidentCoord == c {
                accidentCoord = nil
                engine.showAccidentMarker(at: nil)
            }
        }
        undoStack.append(.placedBatchRoads(valid, totalCost))
        syncEngine()
        NusantaraAssetBank.shared.playBuildSFX()
        recalcStats()
    }

    private func commitBatchZones(_ coords: [GridCoord]) {
        if selZoneBrush == .clearZone {
            var cleared = 0
            for c in coords {
                if plots.removeValue(forKey: c) != nil { cleared += 1 }
            }
            if cleared > 0 {
                syncEngine()
                recalcStats()
                showToast("Cat zona dihapus dari \(cleared) petak.")
            }
            return
        }

        let valid = coords.filter { roads[$0] == nil && facilities[$0] == nil && utilities[$0] == nil && plots[$0] == nil && isNearRoad($0) }
        guard !valid.isEmpty else {
            showToast("Sapukan Kuas Zona pada petak biru di tepi jalan!")
            return
        }
        let totalCost = Int64(valid.count) * selZoneBrush.costIDR
        guard spend(totalCost) else { return }

        for c in valid {
            let startLv = selZoneBrush == .parkGreen ? 1 : 0 // 0 = Mulai dengan Scaffolding Konstruksi!
            let cap = selZoneBrush.capacity(forLevel: max(1, startLv))
            plots[c] = ZonedPlot(coord: c, kind: selZoneBrush, buildingLevel: startLv, residents: 0, maxResidents: cap)
        }
        undoStack.append(.placedBatchZones(valid, totalCost))
        syncEngine()
        NusantaraAssetBank.shared.playBuildSFX()
        recalcStats()
    }

    func handleSingleTap(_ coord: GridCoord) {
        guard screen == .inGame else { return }

        // Tap-to-Inspect bangunan yang sudah berdiri
        if activeCategory != .bulldoze {
            if let p = plots[coord] {
                let stageText = p.buildingLevel == 0 ? "Sedang Konstruksi (Scaffolding)" : "Level \(p.buildingLevel) / 5"
                inspectCard = InspectCardData(
                    title: p.kind.title,
                    subtitle: "\(stageText) • Koordinat (\(coord.x), \(coord.z))",
                    details: [
                        "Penghuni Riil: \(p.residents) / \(p.maxResidents) Jiwa",
                        "Arsitektur: \(p.buildingLevel >= 3 ? "Bangunan Bertingkat / Modern" : "Bangunan Dasar")",
                        "Listrik: \(p.hasPower ? "Menyala" : "Byarpet (Kurang Daya)")",
                        "Air Bersih PDAM: \(p.hasWater ? "Tersedia" : "Kering")",
                        "Pajak Bulanan: \(IDRFormat.string(p.kind.monthlyTaxIDR(level: p.buildingLevel)))"
                    ]
                )
                return
            } else if let f = facilities[coord] {
                inspectCard = InspectCardData(
                    title: f.kind.title,
                    subtitle: "Fasilitas Publik & Pendidikan",
                    details: [
                        "Status: Beroperasi Penuh",
                        "Indeks Pendidikan: +\(f.kind.educationScore)%",
                        "Mendorong Rumah Sekitar Naik Level 3–5"
                    ]
                )
                return
            }
        }

        inspectCard = nil

        switch activeCategory {
        case .roads:
            commitBatchRoads([coord])

        case .zoning:
            commitBatchZones([coord])

        case .facilities:
            guard roads[coord] == nil && plots[coord] == nil && facilities[coord] == nil && utilities[coord] == nil else {
                showToast("Pilih lahan kosong untuk \(selFacility.title).")
                return
            }
            guard spend(selFacility.costIDR) else { return }
            facilities[coord] = FacilityTile(coord: coord, kind: selFacility)
            undoStack.append(.placedFacility(coord, selFacility.costIDR))
            aiAgentMessage = "\(selFacility.title) beroperasi! Rumah warga sekitar kini bisa berkembang ke Level 3–5."

        case .utilities:
            guard roads[coord] == nil && plots[coord] == nil && facilities[coord] == nil && utilities[coord] == nil else {
                showToast("Pilih lahan kosong untuk \(selUtility.title).")
                return
            }
            guard spend(selUtility.costIDR) else { return }
            utilities[coord] = UtilityTile(coord: coord, kind: selUtility)
            undoStack.append(.placedUtility(coord, selUtility.costIDR))
            aiAgentMessage = "\(selUtility.title) aktif menyuplai jaringan utilitas kota!"

        case .gebrakans:
            showToast("Pilih kartu Gebrakan di dock bawah untuk mengaktifkannya.")
            return

        case .bulldoze:
            let removed = (roads.removeValue(forKey: coord) != nil) ||
                          (plots.removeValue(forKey: coord) != nil) ||
                          (facilities.removeValue(forKey: coord) != nil) ||
                          (utilities.removeValue(forKey: coord) != nil)
            if removed {
                if accidentCoord == coord {
                    accidentCoord = nil
                    engine.showAccidentMarker(at: nil)
                }
                showToast("Objek dibongkar.")
            }
        }

        syncEngine()
        NusantaraAssetBank.shared.playBuildSFX()
        recalcStats()
    }

    func selectCategory(_ cat: BuildCategory) {
        activeCategory = cat
        touchToolMode = .buildBrush
        syncEngine()
    }

    private func syncEngine() {
        engine.syncWorld(
            roads: roads,
            plots: plots,
            facilities: facilities,
            utilities: utilities,
            showZonableGrid: activeCategory == .zoning
        )
    }

    func undoLastBuild() {
        guard let last = undoStack.popLast() else {
            showToast("Tidak ada aksi untuk dibatalkan.")
            return
        }
        switch last {
        case .placedBatchRoads(let cs, let cost):
            cs.forEach { roads.removeValue(forKey: $0) }
            if selectedMode == .real { budgetIDR += cost }
        case .placedBatchZones(let cs, let cost):
            cs.forEach { plots.removeValue(forKey: $0) }
            if selectedMode == .real { budgetIDR += cost }
        case .placedFacility(let c, let cost):
            facilities.removeValue(forKey: c)
            if selectedMode == .real { budgetIDR += cost }
        case .placedUtility(let c, let cost):
            utilities.removeValue(forKey: c)
            if selectedMode == .real { budgetIDR += cost }
        }
        syncEngine()
        recalcStats()
        showToast("Pembangunan terakhir dibatalkan (APBD dikembalikan).")
    }

    func triggerGebrakan(_ g: GebrakanKind) {
        if activeGebrakans.contains(g) {
            showToast("Kebijakan ini sudah aktif!")
            return
        }
        guard spend(g.costIDR) else { return }
        activeGebrakans.insert(g)
        recalcStats()
        aiAgentMessage = "Gebrakan '\(g.title)' resmi diberlakukan ke seluruh kota!"
        showToast("Gebrakan Aktif: \(g.title)")
    }

    private func spend(_ cost: Int64) -> Bool {
        if selectedMode == .sandbox { return true }
        if budgetIDR < cost {
            showToast("APBD tidak cukup! Butuh \(IDRFormat.string(cost))")
            return false
        }
        budgetIDR -= cost
        return true
    }

    // MARK: - Simulasi Cities: Skylines (Konstruksi Scaffolding, Naik Level 1->5 Otomatis & Populasi Organik)

    private func recalcStats() {
        let pSup = utilities.values.filter { $0.kind == .garduListrik }.count * 80
        let wSup = utilities.values.filter { $0.kind == .menaraPDAM }.count * 80
        var pDem = 0
        var wDem = 0
        var pop = 0
        var jobs = 0
        var parkBonus = 0

        for key in plots.keys {
            guard var p = plots[key] else { continue }
            pDem += p.kind.powerNeed
            wDem += p.kind.waterNeed
            p.hasPower = selectedMode == .sandbox || pSup >= pDem
            p.hasWater = selectedMode == .sandbox || wSup >= wDem
            plots[key] = p
            pop += p.residents
            jobs += p.kind.jobSlots(forLevel: max(1, p.buildingLevel))
            if p.kind == .parkGreen { parkBonus += 3 }
        }

        powerSupply = pSup; powerDemand = pDem
        waterSupply = wSup; waterDemand = wDem
        population = pop

        var edu = 0
        for f in facilities.values { edu += f.kind.educationScore }
        if activeGebrakans.contains(.beasiswaKampus) { edu += 20 }
        educationIndex = min(100, edu)

        let gebBonus = activeGebrakans.contains(.jumatBersih) ? 10 : 0
        let accidentPenalty = accidentCoord != nil ? 12 : 0
        let utilityPenalty = (pDem > pSup || wDem > wSup) && selectedMode == .real ? 10 : 0
        happiness = min(100, max(20, 82 + parkBonus + gebBonus - accidentPenalty - utilityPenalty))

        rDemand = jobs >= pop ? 0.85 : 0.45
        cDemand = pop > jobs ? 0.82 : 0.35
        iDemand = pop > (jobs / 2) ? 0.78 : 0.30
    }

    private func startSimulationLoop() {
        simTimer?.invalidate()
        simTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.screen == .inGame else { return }

                var visualChanged = false
                let maxAllowedLevel = min(5, 1 + (self.educationIndex / 22) + (self.happiness >= 85 ? 1 : 0))

                for key in self.plots.keys {
                    guard var p = self.plots[key], p.kind != .parkGreen else { continue }
                    let connected = self.isNearRoad(p.coord)

                    if connected && p.hasPower && p.hasWater {
                        p.isAbandoned = false
                        if p.buildingLevel == 0 {
                            // Selesai tahap konstruksi scaffolding -> Jadi Bangunan Level 1!
                            p.buildingLevel = 1
                            p.maxResidents = p.kind.capacity(forLevel: 1)
                            visualChanged = true
                        } else if p.residents < p.maxResidents {
                            // Warga pindah masuk secara bertahap
                            p.residents = min(p.maxResidents, p.residents + Int.random(in: 1...2))
                        } else if p.residents >= p.maxResidents && p.buildingLevel < maxAllowedLevel {
                            // Bangunan penuh & layanan bagus -> Warga renovasi naik tingkat (Level 1 -> 5)!
                            p.buildingLevel += 1
                            p.maxResidents = p.kind.capacity(forLevel: p.buildingLevel)
                            visualChanged = true
                        }
                    } else {
                        // Tanpa jalan / listrik / air -> Penghuni keluar & gedung terbengkalai
                        if p.residents > 0 {
                            p.residents = max(0, p.residents - 1)
                        } else if p.buildingLevel > 0 && !p.isAbandoned {
                            p.isAbandoned = true
                            visualChanged = true
                        }
                    }
                    self.plots[key] = p
                }

                // Pajak riil sesuai okupansi & level bangunan
                if self.selectedMode == .real {
                    let mult: Double = self.activeGebrakans.contains(.digitalUmkm) ? 1.25 : 1.0
                    let tax = self.plots.values.reduce(Int64(0)) { acc, p in
                        guard p.buildingLevel > 0 && !p.isAbandoned else { return acc }
                        let ratio = p.maxResidents > 0 ? Double(p.residents) / Double(p.maxResidents) : 1.0
                        return acc + Int64(Double(p.kind.monthlyTaxIDR(level: p.buildingLevel)) * ratio * mult)
                    }
                    self.budgetIDR += tax
                }

                // Insiden kecelakaan lalu lintas & respon darurat
                let hasEmergency = self.facilities.values.contains { $0.kind == .kantorPolisi || $0.kind == .rsud }
                if self.accidentCoord == nil, self.roads.count >= 7, !hasEmergency, let r = self.roads.values.randomElement() {
                    self.accidentCoord = r.coord
                    self.engine.showAccidentMarker(at: r.coord)
                    self.aiAgentMessage = "DARURAT! Kecelakaan lalu lintas di (\(r.coord.x), \(r.coord.z)). Bangun RSUD / Kantor Polisi!"
                } else if self.accidentCoord != nil && hasEmergency {
                    self.accidentCoord = nil
                    self.engine.showAccidentMarker(at: nil)
                    self.aiAgentMessage = "Ambulans RSUD & Polisi mengevakuasi kecelakaan lalu lintas!"
                } else if self.powerDemand > self.powerSupply && self.selectedMode == .real {
                    self.aiAgentMessage = "Byarpet! Daya listrik kurang (\(self.powerSupply)/\(self.powerDemand) MW). Bangun Gardu Induk!"
                }

                if visualChanged {
                    self.syncEngine()
                }
                self.recalcStats()
            }
        }
    }

    func toggleNight() {
        isNight = engine.toggleNightMode()
        syncEngine()
    }

    func switchCameraMode(_ mode: CameraMode) {
        cameraMode = mode
        if mode == .followVehicle {
            engine.cycleFollowedVehicle()
        } else {
            engine.setCameraMode(mode)
        }
    }

    func cycleLensMode() {
        let all = DataLensMode.allCases
        if let idx = all.firstIndex(of: lensMode) {
            lensMode = all[(idx + 1) % all.count]
            engine.setLensMode(lensMode)
            showToast("Info View: \(lensMode.title)")
        }
    }

    private func showToast(_ msg: String) {
        toast = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            if self?.toast == msg { self?.toast = nil }
        }
    }
}

// MARK: - Antarmuka Pengguna (Splash, Menu Utama 4 Tombol, Alur Bertingkat, HUD Skylines)

struct RootGameView: View {
    @StateObject private var vm = GameViewModel()

    var body: some View {
        ZStack {
            if vm.screen == .splashTitle || vm.screen == .splashStudio {
                Color(red: 0.04, green: 0.06, blue: 0.12).ignoresSafeArea()
            } else {
                SceneKitViewport(engine: vm.engine, interactive: vm.screen == .inGame, touchToolMode: vm.touchToolMode)
                    .ignoresSafeArea()
            }

            switch vm.screen {
            case .splashTitle:
                splashTitleView
            case .splashStudio:
                splashStudioView
            case .mainMenu:
                mainMenuView
            case .selectMode:
                selectModeView
            case .selectMap:
                selectMapView
            case .saveSlots:
                saveSlotsView
            case .settingsMenu:
                settingsView
            case .inGame:
                inGameHUD
            }
        }
    }

    private var splashTitleView: some View {
        VStack(spacing: 12) {
            Text("NUSANTARA URBAN SIMULATION")
                .font(.caption.bold())
                .tracking(3)
                .foregroundColor(.cyan)
            Text("City Building : Nusantara Project")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundColor(.white)
            Text("Ketuk layar untuk melewati")
                .font(.caption2)
                .foregroundColor(.gray)
                .padding(.top, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { vm.enterMainMenu() }
    }

    private var splashStudioView: some View {
        VStack(spacing: 14) {
            Text("RG")
                .font(.system(size: 58, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 26)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                )
            Text("RIZZI GAMES")
                .font(.title2.bold())
                .tracking(5)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { vm.enterMainMenu() }
    }

    private var mainMenuView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("RIZZI GAMES (RG)")
                    .font(.caption.bold())
                    .tracking(2)
                    .foregroundColor(.cyan)
                Text("City Building :\nNusantara Project")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)

                Spacer()

                menuButton(title: "START", icon: "play.fill", primary: true) { vm.screen = .selectMode }
                menuButton(title: "SAVE GAME", icon: "folder.fill", primary: false) { vm.screen = .saveSlots }
                menuButton(title: "SETTINGS", icon: "gearshape.fill", primary: false) { vm.screen = .settingsMenu }
                menuButton(title: "EXIT", icon: "power", primary: false) { exit(0) }
            }
            .padding(24)
            .frame(width: 310)
            .background(.ultraThinMaterial)
            .cornerRadius(22)
            .padding(.leading, 28)
            .padding(.vertical, 20)

            Spacer()
        }
    }

    private func menuButton(title: String, icon: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .foregroundColor(primary ? .black : .white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(primary ? Color.cyan : Color.white.opacity(0.14))
                .cornerRadius(12)
        }
    }

    private var selectModeView: some View {
        VStack(spacing: 18) {
            Text("TAHAP 1 : PILIH MODE PERMAINAN")
                .font(.headline.bold())
                .tracking(2)
                .foregroundColor(.cyan)

            HStack(spacing: 16) {
                ForEach(PlayMode.allCases) { mode in
                    Button { vm.selectedMode = mode } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(mode.title).font(.title3.bold())
                            Text(mode.subtitle).font(.caption).multilineTextAlignment(.leading)
                        }
                        .foregroundColor(.white)
                        .padding(18)
                        .frame(width: 265, height: 135, alignment: .topLeading)
                        .background(vm.selectedMode == mode ? Color.cyan.opacity(0.35) : Color.black.opacity(0.55))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(vm.selectedMode == mode ? Color.cyan : Color.white.opacity(0.2), lineWidth: 2))
                        .cornerRadius(16)
                    }
                }
            }

            HStack(spacing: 14) {
                Button("Kembali") { vm.screen = .mainMenu }
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Color.white.opacity(0.16)).cornerRadius(10)

                Button("Lanjut Pilih Map →") { vm.screen = .selectMap }
                    .font(.subheadline.bold())
                    .foregroundColor(.black)
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(Color.cyan).cornerRadius(10)
            }
            .foregroundColor(.white)
        }
        .padding(28)
        .background(.ultraThinMaterial)
        .cornerRadius(24)
    }

    private var selectMapView: some View {
        VStack(spacing: 18) {
            Text("TAHAP 2 : PILIH WILAYAH MAP NUSANTARA")
                .font(.headline.bold())
                .tracking(2)
                .foregroundColor(.cyan)

            HStack(spacing: 14) {
                ForEach(CityMapType.allCases) { m in
                    Button { vm.selectedMap = m } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(m.title).font(.headline.bold())
                            Text(m.difficultyLabel).font(.caption2.bold()).foregroundColor(.cyan)
                            Text(m.subtitle).font(.caption).multilineTextAlignment(.leading)
                        }
                        .foregroundColor(.white)
                        .padding(16)
                        .frame(width: 215, height: 145, alignment: .topLeading)
                        .background(vm.selectedMap == m ? Color.green.opacity(0.35) : Color.black.opacity(0.55))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(vm.selectedMap == m ? Color.green : Color.white.opacity(0.2), lineWidth: 2))
                        .cornerRadius(16)
                    }
                }
            }

            HStack(spacing: 14) {
                Button("← Mode") { vm.screen = .selectMode }
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Color.white.opacity(0.16)).cornerRadius(10)

                Button("MULAI BANGUN KOTA") { vm.startCity() }
                    .font(.subheadline.bold())
                    .foregroundColor(.black)
                    .padding(.horizontal, 26).padding(.vertical, 10)
                    .background(Color.green).cornerRadius(10)
            }
            .foregroundColor(.white)
        }
        .padding(28)
        .background(.ultraThinMaterial)
        .cornerRadius(24)
    }

    private var saveSlotsView: some View {
        VStack(spacing: 16) {
            Text("SAVE GAME SLOTS")
                .font(.headline.bold())
                .foregroundColor(.cyan)

            HStack(spacing: 14) {
                ForEach(1...3, id: \.self) { slot in
                    let snap = vm.slotSnapshot(slot)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Slot \(slot)").font(.headline.bold())
                        if let snap {
                            Text(snap.mapType.title).font(.subheadline).foregroundColor(.cyan)
                            Text("Warga: \(snap.population) Jiwa").font(.caption)
                            Text("APBD: \(IDRFormat.string(snap.budgetIDR))").font(.caption2)
                            Text(snap.savedAtText).font(.caption2).foregroundColor(.gray)
                            Spacer()
                            Button("Muat Kota") { vm.loadFromSlot(slot) }
                                .font(.caption.bold())
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(Color.cyan)
                                .cornerRadius(8)
                        } else {
                            Text("Kosong").font(.caption).foregroundColor(.gray)
                            Spacer()
                        }
                    }
                    .foregroundColor(.white)
                    .padding(14)
                    .frame(width: 195, height: 165, alignment: .topLeading)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(14)
                }
            }

            Button("Tutup") { vm.screen = .mainMenu }
                .foregroundColor(.white)
                .padding(.horizontal, 24).padding(.vertical, 9)
                .background(Color.white.opacity(0.16)).cornerRadius(10)
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .cornerRadius(22)
    }

    private var settingsView: some View {
        VStack(spacing: 14) {
            Text("PENGATURAN GRAFIS HD & AUDIO")
                .font(.headline.bold())
                .foregroundColor(.cyan)

            Toggle("Bayangan Dinamis HD", isOn: $vm.settings.hdShadows)
            Toggle("Kabut Pegunungan & Atmosfer", isOn: $vm.settings.atmosphericFog)
            Toggle("HDR Bloom City Lights Malam", isOn: $vm.settings.hdrBloom)

            HStack {
                Text("Volume Musik").font(.caption)
                Slider(value: $vm.settings.bgmVolume, in: 0...1)
            }
            HStack {
                Text("Sensitivitas Kamera").font(.caption)
                Slider(value: $vm.settings.cameraSensitivity, in: 0.4...2.0)
            }

            Button("Simpan & Kembali") {
                NusantaraAssetBank.shared.bgmVolume = vm.settings.bgmVolume
                vm.engine.cameraSensitivity = vm.settings.cameraSensitivity
                vm.engine.applyAtmosphere(shadows: vm.settings.hdShadows, fog: vm.settings.atmosphericFog, bloom: vm.settings.hdrBloom)
                vm.screen = .mainMenu
            }
            .font(.subheadline.bold())
            .foregroundColor(.black)
            .padding(.horizontal, 24).padding(.vertical, 10)
            .background(Color.cyan).cornerRadius(10)
        }
        .foregroundColor(.white)
        .padding(24)
        .frame(width: 430)
        .background(.ultraThinMaterial)
        .cornerRadius(22)
    }

    private var inGameHUD: some View {
        ZStack {
            if vm.hideHUDForPhoto {
                VStack {
                    HStack {
                        Spacer()
                        Button { vm.hideHUDForPhoto = false } label: {
                            Label("Tampilkan HUD", systemImage: "eye.fill")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .padding(10)
                                .background(.ultraThinMaterial)
                                .cornerRadius(10)
                        }
                    }
                    .padding()
                    Spacer()
                }
            } else {
                VStack(spacing: 6) {
                    // Bar Atas
                    HStack(spacing: 7) {
                        Button { vm.enterMainMenu() } label: {
                            Image(systemName: "house.fill").padding(8).background(.ultraThinMaterial).cornerRadius(9)
                        }
                        rciDemandMeter
                        statBadge(title: "APBD", val: IDRFormat.string(vm.budgetIDR), col: .green)
                        statBadge(title: "Penduduk", val: "\(vm.population) Jiwa", col: .cyan)
                        statBadge(title: "Listrik", val: "\(vm.powerSupply)/\(vm.powerDemand)", col: vm.powerSupply >= vm.powerDemand ? .yellow : .red)
                        statBadge(title: "Air", val: "\(vm.waterSupply)/\(vm.waterDemand)", col: vm.waterSupply >= vm.waterDemand ? .blue : .red)
                        statBadge(title: "Bahagia", val: "\(vm.happiness)%", col: .orange)

                        Spacer()

                        Button {
                            vm.touchToolMode = (vm.touchToolMode == .buildBrush) ? .panCamera : .buildBrush
                        } label: {
                            Label(vm.touchToolMode.title, systemImage: vm.touchToolMode.icon)
                                .font(.caption2.bold())
                                .padding(.horizontal, 9)
                                .padding(.vertical, 7)
                                .background(vm.touchToolMode == .buildBrush ? Color.cyan.opacity(0.45) : Color.orange.opacity(0.55))
                                .cornerRadius(9)
                        }

                        Button { vm.cycleLensMode() } label: {
                            Image(systemName: "eye.trianglebadge.exclamationmark")
                                .padding(8).background(.ultraThinMaterial).cornerRadius(9)
                        }
                        Button { vm.toggleNight() } label: {
                            Image(systemName: vm.isNight ? "moon.stars.fill" : "sun.max.fill")
                                .foregroundColor(vm.isNight ? .yellow : .orange)
                                .padding(8).background(.ultraThinMaterial).cornerRadius(9)
                        }
                        Button { vm.hideHUDForPhoto = true } label: {
                            Image(systemName: "camera.fill").padding(8).background(.ultraThinMaterial).cornerRadius(9)
                        }
                        Button { vm.saveToSlot(1) } label: {
                            Image(systemName: "square.and.arrow.down.fill").padding(8).background(.ultraThinMaterial).cornerRadius(9)
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    // AI Agent "Nusa" Bar
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles").foregroundColor(.cyan)
                        Text("AI Nusa: \(vm.aiAgentMessage)")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.68))
                    .cornerRadius(9)
                    .padding(.horizontal, 12)

                    if let preview = vm.dragCostPreview {
                        Text(preview)
                            .font(.caption.bold())
                            .foregroundColor(.black)
                            .padding(.horizontal, 14).padding(.vertical, 5)
                            .background(Color.cyan)
                            .cornerRadius(12)
                    } else if let t = vm.toast {
                        Text(t)
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Color.blue.opacity(0.88))
                            .cornerRadius(12)
                    }

                    // Tengah: Kartu Inspeksi Warga/Bangunan & Kontrol Kamera
                    HStack(alignment: .top) {
                        if let card = vm.inspectCard {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(card.title).font(.subheadline.bold()).foregroundColor(.cyan)
                                    Spacer()
                                    Button { vm.inspectCard = nil } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                                    }
                                }
                                Text(card.subtitle).font(.caption2).foregroundColor(.gray)
                                ForEach(card.details, id: \.self) { line in
                                    Text("• \(line)").font(.caption2).foregroundColor(.white)
                                }
                            }
                            .padding(12)
                            .frame(width: 255)
                            .background(.ultraThinMaterial)
                            .cornerRadius(14)
                            .padding(.leading, 12)
                        }

                        Spacer()

                        VStack(spacing: 6) {
                            ForEach(CameraMode.allCases) { cm in
                                Button { vm.switchCameraMode(cm) } label: {
                                    Image(systemName: cm.icon)
                                        .frame(width: 34, height: 34)
                                        .background(vm.cameraMode == cm ? Color.cyan.opacity(0.45) : Color.black.opacity(0.45))
                                        .cornerRadius(8)
                                }
                            }
                            Button { vm.engine.zoomCamera(scaleFactor: 1.25) } label: {
                                Image(systemName: "plus.magnifyingglass").frame(width: 34, height: 34).background(.ultraThinMaterial).cornerRadius(8)
                            }
                            Button { vm.engine.zoomCamera(scaleFactor: 0.8) } label: {
                                Image(systemName: "minus.magnifyingglass").frame(width: 34, height: 34).background(.ultraThinMaterial).cornerRadius(8)
                            }
                            Button { vm.undoLastBuild() } label: {
                                Image(systemName: "arrow.uturn.backward").frame(width: 34, height: 34).background(Color.orange.opacity(0.65)).cornerRadius(8)
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.trailing, 12)
                    }

                    Spacer()

                    // Dock Pembangunan Bawah (Tarik Jalan & Kuas Zona Skylines)
                    VStack(spacing: 6) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                if vm.activeCategory == .roads {
                                    ForEach(RoadKind.allCases) { k in
                                        subItemButton(title: k.title, price: k.costIDR, selected: vm.selRoad == k, badgeColor: .cyan) { vm.selRoad = k }
                                    }
                                } else if vm.activeCategory == .zoning {
                                    ForEach(ZoneBrushKind.allCases) { z in
                                        let zCol: Color = z == .commercial ? .blue : (z == .industrialOffice ? .yellow : (z == .clearZone ? .red : .green))
                                        subItemButton(title: z.title, price: z.costIDR, selected: vm.selZoneBrush == z, badgeColor: zCol) { vm.selZoneBrush = z }
                                    }
                                } else if vm.activeCategory == .facilities {
                                    ForEach(FacilityKind.allCases) { k in
                                        subItemButton(title: k.title, price: k.costIDR, selected: vm.selFacility == k, badgeColor: .cyan) { vm.selFacility = k }
                                    }
                                } else if vm.activeCategory == .utilities {
                                    ForEach(UtilityKind.allCases) { u in
                                        subItemButton(title: u.title, price: u.costIDR, selected: vm.selUtility == u, badgeColor: .yellow) { vm.selUtility = u }
                                    }
                                } else if vm.activeCategory == .gebrakans {
                                    ForEach(GebrakanKind.allCases) { g in
                                        subItemButton(
                                            title: vm.activeGebrakans.contains(g) ? "✓ \(g.title)" : g.title,
                                            price: g.costIDR,
                                            selected: vm.activeGebrakans.contains(g),
                                            badgeColor: .purple
                                        ) { vm.triggerGebrakan(g) }
                                    }
                                }
                            }
                            .padding(.horizontal, 6)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(BuildCategory.allCases) { cat in
                                    Button { vm.selectCategory(cat) } label: {
                                        Label(cat.title, systemImage: cat.icon)
                                            .font(.caption.bold())
                                            .padding(.horizontal, 11)
                                            .padding(.vertical, 7)
                                            .background(vm.activeCategory == cat ? Color.blue : Color.white.opacity(0.14))
                                            .cornerRadius(9)
                                    }
                                }
                            }
                        }
                    }
                    .foregroundColor(.white)
                    .padding(9)
                    .background(.ultraThinMaterial)
                    .cornerRadius(15)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private var rciDemandMeter: some View {
        HStack(alignment: .bottom, spacing: 3) {
            demandBar(height: vm.rDemand, color: .green)
            demandBar(height: vm.cDemand, color: .blue)
            demandBar(height: vm.iDemand, color: .yellow)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }

    private func demandBar(height: Double, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 5, height: max(5, CGFloat(height) * 20))
    }

    private func subItemButton(title: String, price: Int64, selected: Bool, badgeColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title).font(.caption.bold())
                Text(vm.selectedMode == .sandbox || price == 0 ? "Gratis" : IDRFormat.string(price))
                    .font(.caption2)
                    .foregroundColor(badgeColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(selected ? badgeColor.opacity(0.32) : Color.black.opacity(0.65))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? badgeColor : Color.clear, lineWidth: 1.5))
            .cornerRadius(8)
        }
    }

    private func statBadge(title: String, val: String, col: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundColor(.gray)
            Text(val).font(.caption.bold()).foregroundColor(col)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}

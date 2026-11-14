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

    @Published var rDemand: Double = 0.75
    @Published var cDemand: Double = 0.50
    @Published var iDemand: Double = 0.45

    @Published var isNight: Bool = false
    @Published var isMuted: Bool = false
    @Published var hideHUDForPhoto: Bool = false
    @Published var cameraMode: CameraMode = .drone
    @Published var lensMode: DataLensMode = .normal

    @Published var activeCategory: BuildCategory = .roads
    @Published var selRoad: RoadKind = .fourLane
    @Published var selZone: ZoneKind = .residentialSingle
    @Published var selFacility: FacilityKind = .balaiKota
    @Published var selUtility: UtilityKind = .garduListrik

    @Published var roads: [GridCoord: RoadTile] = [:]
    @Published var zones: [GridCoord: ZoneTile] = [:]
    @Published var facilities: [GridCoord: FacilityTile] = [:]
    @Published var utilities: [GridCoord: UtilityTile] = [:]
    @Published var activeGebrakans: Set<GebrakanKind> = []

    @Published var settings = GameSettings()
    @Published var inspectCard: InspectCardData? = nil
    @Published var aiAgentMessage: String = "Halo Pak Wali! Bangun jalan raya, gardu listrik & perumahan agar warga mulai pindah masuk."
    @Published var accidentCoord: GridCoord? = nil
    @Published var toast: String? = nil

    private var undoStack: [UndoAction] = []
    private var elasticCurveCount: Int = 0
    let engine = City3DEngine()
    private var simTimer: Timer?

    init() {
        engine.onTileTapped = { [weak self] coord in
            Task { @MainActor [weak self] in
                self?.handleTap(coord)
            }
        }
        startSplashSequence()
    }

    func startSplashSequence() {
        screen = .splashTitle
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self, self.screen == .splashTitle else { return }
            self.screen = .splashStudio
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
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
        roads.removeAll(); zones.removeAll(); facilities.removeAll(); utilities.removeAll()
        activeGebrakans.removeAll(); undoStack.removeAll()
        accidentCoord = nil; inspectCard = nil; hideHUDForPhoto = false
        population = 0; educationIndex = 0; happiness = 85
        budgetIDR = selectedMode == .sandbox ? 999_999_999_999_999 : 150_000_000_000

        engine.loadMap(selectedMap, showcaseDemo: false)
        engine.applyAtmosphere(shadows: settings.hdShadows, fog: settings.atmosphericFog)
        engine.cameraSensitivity = settings.cameraSensitivity
        screen = .inGame
        aiAgentMessage = "Selamat datang di \(selectedMap.title)! Rumah baru mulai dari 0 jiwa & terisi bertahap jika ada jalan, listrik & air."
        startSimulationLoop()
    }

    // MARK: - Save & Load Multi-Slot

    func slotSnapshot(_ slot: Int) -> CitySaveSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: "nusantara.slot.\(slot)") else { return nil }
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
            zones: Array(zones.values),
            facilities: Array(facilities.values),
            utilities: Array(utilities.values),
            activeGebrakans: Array(activeGebrakans)
        )
        if let encoded = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(encoded, forKey: "nusantara.slot.\(slot)")
            showToast("Tersimpan di Slot \(slot)!")
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
        zones = Dictionary(uniqueKeysWithValues: snap.zones.map { ($0.coord, $0) })
        facilities = Dictionary(uniqueKeysWithValues: snap.facilities.map { ($0.coord, $0) })
        utilities = Dictionary(uniqueKeysWithValues: snap.utilities.map { ($0.coord, $0) })
        activeGebrakans = Set(snap.activeGebrakans)
        undoStack.removeAll()

        engine.loadMap(selectedMap, showcaseDemo: false)
        engine.syncWorld(roads: roads, zones: zones, facilities: facilities, utilities: utilities)
        recalcStats()
        screen = .inGame
        startSimulationLoop()
        showToast("Kota \(selectedMap.title) dari Slot \(slot) dimuat!")
    }

    // MARK: - Interaksi Tanah & Pembangunan

    func handleTap(_ coord: GridCoord) {
        guard screen == .inGame else { return }

        // Jika mengetuk bangunan/rumah yang sudah ada saat tidak menghapus, tampilkan kartu inspeksi!
        if activeCategory != .bulldoze {
            if let z = zones[coord] {
                inspectCard = InspectCardData(
                    title: z.kind.title,
                    subtitle: "Koordinat (\(coord.x), \(coord.z))",
                    details: [
                        "Penghuni Riil: \(z.residents) / \(z.maxResidents) Jiwa",
                        "Listrik: \(z.hasPower ? "Menyala" : "Byarpet (Kurang Daya)")",
                        "Air Bersih PDAM: \(z.hasWater ? "Tersedia" : "Kering")",
                        "Pajak Bulanan: \(IDRFormat.string(z.kind.monthlyTaxIDR))"
                    ]
                )
                return
            } else if let f = facilities[coord] {
                inspectCard = InspectCardData(
                    title: f.kind.title,
                    subtitle: "Fasilitas Publik Kota",
                    details: [
                        "Status: Beroperasi Penuh",
                        "Kontribusi Pendidikan: +\(f.kind.educationScore)%",
                        "Radius Layanan: Aktif"
                    ]
                )
                return
            }
        }

        inspectCard = nil

        switch activeCategory {
        case .roads:
            guard zones[coord] == nil && facilities[coord] == nil && utilities[coord] == nil else {
                showToast("Petak terisi bangunan.")
                return
            }
            guard spend(selRoad.costIDR) else { return }
            var yaw: Float = 0.0
            if selRoad == .elasticCurve {
                elasticCurveCount += 1
                yaw = Float(elasticCurveCount % 6) * 0.26
            }
            roads[coord] = RoadTile(coord: coord, kind: selRoad, curveYaw: yaw)
            undoStack.append(.placedRoad(coord, selRoad.costIDR))
            if accidentCoord == coord {
                accidentCoord = nil
                engine.showAccidentMarker(at: nil)
            }

        case .zones:
            guard roads[coord] == nil && zones[coord] == nil && facilities[coord] == nil && utilities[coord] == nil else {
                showToast("Pilih lahan kosong!")
                return
            }
            guard spend(selZone.costIDR) else { return }
            let cap = selZone.maxCapacity > 0 ? Int.random(in: max(2, selZone.maxCapacity - 2)...selZone.maxCapacity) : 0
            // Mulai dari 0 penghuni agar tumbuh secara logis & bertahap!
            zones[coord] = ZoneTile(coord: coord, kind: selZone, residents: 0, maxResidents: cap)
            undoStack.append(.placedZone(coord, selZone.costIDR))

        case .facilities:
            guard roads[coord] == nil && zones[coord] == nil && facilities[coord] == nil && utilities[coord] == nil else {
                showToast("Pilih lahan kosong untuk \(selFacility.title).")
                return
            }
            guard spend(selFacility.costIDR) else { return }
            facilities[coord] = FacilityTile(coord: coord, kind: selFacility)
            undoStack.append(.placedFacility(coord, selFacility.costIDR))
            aiAgentMessage = "\(selFacility.title) selesai dibangun dan mulai melayani masyarakat."

        case .utilities:
            guard roads[coord] == nil && zones[coord] == nil && facilities[coord] == nil && utilities[coord] == nil else {
                showToast("Pilih lahan kosong untuk \(selUtility.title).")
                return
            }
            guard spend(selUtility.costIDR) else { return }
            utilities[coord] = UtilityTile(coord: coord, kind: selUtility)
            undoStack.append(.placedUtility(coord, selUtility.costIDR))
            aiAgentMessage = "\(selUtility.title) aktif menyuplai jaringan kota!"

        case .gebrakans:
            showToast("Pilih kartu Gebrakan di panel bawah untuk mengaktifkannya.")
            return

        case .bulldoze:
            let removed = (roads.removeValue(forKey: coord) != nil) ||
                          (zones.removeValue(forKey: coord) != nil) ||
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

        engine.syncWorld(roads: roads, zones: zones, facilities: facilities, utilities: utilities)
        NusantaraAssetBank.shared.playBuildSFX()
        recalcStats()
    }

    func undoLastBuild() {
        guard let last = undoStack.popLast() else {
            showToast("Tidak ada aksi untuk dibatalkan.")
            return
        }
        switch last {
        case .placedRoad(let c, let cost):
            roads.removeValue(forKey: c)
            if selectedMode == .real { budgetIDR += cost }
        case .placedZone(let c, let cost):
            zones.removeValue(forKey: c)
            if selectedMode == .real { budgetIDR += cost }
        case .placedFacility(let c, let cost):
            facilities.removeValue(forKey: c)
            if selectedMode == .real { budgetIDR += cost }
        case .placedUtility(let c, let cost):
            utilities.removeValue(forKey: c)
            if selectedMode == .real { budgetIDR += cost }
        }
        engine.syncWorld(roads: roads, zones: zones, facilities: facilities, utilities: utilities)
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

    // MARK: - Simulasi Populasi Organik, Utilitas Listrik-Air & Kecelakaan

    private func recalcStats() {
        let pSup = utilities.values.filter { $0.kind == .garduListrik }.count * 60
        let wSup = utilities.values.filter { $0.kind == .menaraPDAM }.count * 60
        var pDem = 0
        var wDem = 0
        var pop = 0
        var jobs = 0
        var parkBonus = 0

        for key in zones.keys {
            guard var z = zones[key] else { continue }
            pDem += z.kind.powerNeed
            wDem += z.kind.waterNeed
            z.hasPower = selectedMode == .sandbox || pSup >= pDem
            z.hasWater = selectedMode == .sandbox || wSup >= wDem
            zones[key] = z
            pop += z.residents
            jobs += z.kind.jobSlots
            if z.kind == .park { parkBonus += 3 }
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

        // Update indikator permintaan RCI
        rDemand = jobs > pop ? 0.85 : 0.45
        cDemand = pop > jobs ? 0.80 : 0.35
        iDemand = pop > (jobs / 2) ? 0.75 : 0.30
    }

    private func startSimulationLoop() {
        simTimer?.invalidate()
        simTimer = Timer.scheduledTimer(withTimeInterval: 5.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.screen == .inGame else { return }

                // 1. Pertumbuhan populasi organik bertahap (tidak instan & tergantung jalan, listrik, air)
                var changed = false
                for key in self.zones.keys {
                    guard var z = self.zones[key], z.maxResidents > 0 else { continue }
                    let hasRoad = self.roads[GridCoord(x: z.coord.x + 1, z: z.coord.z)] != nil ||
                                  self.roads[GridCoord(x: z.coord.x - 1, z: z.coord.z)] != nil ||
                                  self.roads[GridCoord(x: z.coord.x, z: z.coord.z + 1)] != nil ||
                                  self.roads[GridCoord(x: z.coord.x, z: z.coord.z - 1)] != nil

                    if hasRoad && z.hasPower && z.hasWater && z.residents < z.maxResidents {
                        z.residents = min(z.maxResidents, z.residents + Int.random(in: 1...2))
                        self.zones[key] = z
                        changed = true
                    } else if (!hasRoad || !z.hasPower || !z.hasWater) && z.residents > 0 {
                        z.residents = max(0, z.residents - 1)
                        self.zones[key] = z
                        changed = true
                    }
                }

                // 2. Pajak riil dari warga yang sudah menghuni bangunan
                if self.selectedMode == .real {
                    let mult: Double = self.activeGebrakans.contains(.digitalUmkm) ? 1.25 : 1.0
                    let tax = self.zones.values.reduce(Int64(0)) { acc, z in
                        let occupancyRatio = z.maxResidents > 0 ? Double(z.residents) / Double(z.maxResidents) : 1.0
                        return acc + Int64(Double(z.kind.monthlyTaxIDR) * occupancyRatio * mult)
                    }
                    self.budgetIDR += tax
                }

                // 3. Kejadian kecelakaan lalu lintas & respon RSUD/Polisi
                let hasEmergencyService = self.facilities.values.contains { $0.kind == .kantorPolisi || $0.kind == .rsud }
                if self.accidentCoord == nil, self.roads.count >= 6, !hasEmergencyService, let r = self.roads.values.randomElement() {
                    self.accidentCoord = r.coord
                    self.engine.showAccidentMarker(at: r.coord)
                    self.aiAgentMessage = "DARURAT! Kecelakaan lalu lintas di (\(r.coord.x), \(r.coord.z)). Bangun RSUD / Kantor Polisi!"
                } else if self.accidentCoord != nil && hasEmergencyService {
                    self.accidentCoord = nil
                    self.engine.showAccidentMarker(at: nil)
                    self.aiAgentMessage = "Ambulans RSUD & Polisi berhasil mengevakuasi kecelakaan lalu lintas!"
                } else if self.powerDemand > self.powerSupply && self.selectedMode == .real {
                    self.aiAgentMessage = "Peringatan Byarpet! Daya listrik kurang (\(self.powerSupply)/\(self.powerDemand) MW). Bangun Gardu Induk!"
                }

                if changed {
                    self.engine.syncWorld(roads: self.roads, zones: self.zones, facilities: self.facilities, utilities: self.utilities)
                }
                self.recalcStats()
            }
        }
    }

    func toggleNight() {
        isNight = engine.toggleNightMode()
        engine.syncWorld(roads: roads, zones: zones, facilities: facilities, utilities: utilities)
    }

    func toggleMute() {
        isMuted.toggle()
        NusantaraAssetBank.shared.isMuted = isMuted
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
            showToast("Mode Lensa: \(lensMode.title)")
        }
    }

    private func showToast(_ msg: String) {
        toast = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            if self?.toast == msg { self?.toast = nil }
        }
    }
}

// MARK: - Antarmuka Pengguna (Splash, Menu Utama 4 Tombol, Alur Bertingkat, HUD HD)

struct RootGameView: View {
    @StateObject private var vm = GameViewModel()

    var body: some View {
        ZStack {
            if vm.screen == .splashTitle || vm.screen == .splashStudio {
                Color(red: 0.04, green: 0.06, blue: 0.12).ignoresSafeArea()
            } else {
                SceneKitViewport(engine: vm.engine, interactive: vm.screen == .inGame)
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

    // 1. Animasi Judul Awal
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

    // 2. Animasi Logo RG — RIZZI GAMES
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

    // 3. Menu Utama (Start, Save Game, Settings, Exit)
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

                menuButton(title: "START", icon: "play.fill", primary: true) {
                    vm.screen = .selectMode
                }
                menuButton(title: "SAVE GAME", icon: "folder.fill", primary: false) {
                    vm.screen = .saveSlots
                }
                menuButton(title: "SETTINGS", icon: "gearshape.fill", primary: false) {
                    vm.screen = .settingsMenu
                }
                menuButton(title: "EXIT", icon: "power", primary: false) {
                    exit(0)
                }
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

    // 4. Tahap 1 Setelah Start: Pilih Mode Permainan
    private var selectModeView: some View {
        VStack(spacing: 18) {
            Text("TAHAP 1 : PILIH MODE PERMAINAN")
                .font(.headline.bold())
                .tracking(2)
                .foregroundColor(.cyan)

            HStack(spacing: 16) {
                ForEach(PlayMode.allCases) { mode in
                    Button {
                        vm.selectedMode = mode
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(mode.title)
                                .font(.title3.bold())
                            Text(mode.subtitle)
                                .font(.caption)
                                .multilineTextAlignment(.leading)
                        }
                        .foregroundColor(.white)
                        .padding(18)
                        .frame(width: 260, height: 135, alignment: .topLeading)
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

    // 5. Tahap 2 Setelah Start: Pilih Map Nusantara
    private var selectMapView: some View {
        VStack(spacing: 18) {
            Text("TAHAP 2 : PILIH WILAYAH MAP NUSANTARA")
                .font(.headline.bold())
                .tracking(2)
                .foregroundColor(.cyan)

            HStack(spacing: 14) {
                ForEach(CityMapType.allCases) { m in
                    Button {
                        vm.selectedMap = m
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(m.title)
                                .font(.headline.bold())
                            Text(m.difficultyLabel)
                                .font(.caption2.bold())
                                .foregroundColor(.cyan)
                            Text(m.subtitle)
                                .font(.caption)
                                .multilineTextAlignment(.leading)
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

    // 6. Save Game Slots
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

    // 7. Settings Menu
    private var settingsView: some View {
        VStack(spacing: 14) {
            Text("PENGATURAN GRAFIS & AUDIO")
                .font(.headline.bold())
                .foregroundColor(.cyan)

            Toggle("Bayangan Dinamis HD", isOn: $vm.settings.hdShadows)
            Toggle("Kabut Pegunungan & Atmosfer", isOn: $vm.settings.atmosphericFog)

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
                vm.engine.applyAtmosphere(shadows: vm.settings.hdShadows, fog: vm.settings.atmosphericFog)
                vm.screen = .mainMenu
            }
            .font(.subheadline.bold())
            .foregroundColor(.black)
            .padding(.horizontal, 24).padding(.vertical, 10)
            .background(Color.cyan).cornerRadius(10)
        }
        .foregroundColor(.white)
        .padding(24)
        .frame(width: 420)
        .background(.ultraThinMaterial)
        .cornerRadius(22)
    }

    // 8. HUD Utama Dalam Game
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

                    if let t = vm.toast {
                        Text(t)
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Color.blue.opacity(0.88))
                            .cornerRadius(12)
                    }

                    // Tengah: Kartu Inspeksi Warga/Bangunan (kiri) & Kontrol Kamera (kanan)
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
                            .frame(width: 245)
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

                    // Dock Pembangunan Bawah
                    VStack(spacing: 6) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                if vm.activeCategory == .roads {
                                    ForEach(RoadKind.allCases) { k in
                                        subItemButton(title: k.title, price: k.costIDR, selected: vm.selRoad == k) { vm.selRoad = k }
                                    }
                                } else if vm.activeCategory == .zones {
                                    ForEach(ZoneKind.allCases) { k in
                                        subItemButton(title: k.title, price: k.costIDR, selected: vm.selZone == k) { vm.selZone = k }
                                    }
                                } else if vm.activeCategory == .facilities {
                                    ForEach(FacilityKind.allCases) { k in
                                        subItemButton(title: k.title, price: k.costIDR, selected: vm.selFacility == k) { vm.selFacility = k }
                                    }
                                } else if vm.activeCategory == .utilities {
                                    ForEach(UtilityKind.allCases) { u in
                                        subItemButton(title: u.title, price: u.costIDR, selected: vm.selUtility == u) { vm.selUtility = u }
                                    }
                                } else if vm.activeCategory == .gebrakans {
                                    ForEach(GebrakanKind.allCases) { g in
                                        subItemButton(
                                            title: vm.activeGebrakans.contains(g) ? "✓ \(g.title)" : g.title,
                                            price: g.costIDR,
                                            selected: vm.activeGebrakans.contains(g)
                                        ) { vm.triggerGebrakan(g) }
                                    }
                                }
                            }
                            .padding(.horizontal, 6)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(BuildCategory.allCases) { cat in
                                    Button { vm.activeCategory = cat } label: {
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

    private func subItemButton(title: String, price: Int64, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title).font(.caption.bold())
                Text(vm.selectedMode == .sandbox ? "Gratis" : IDRFormat.string(price))
                    .font(.caption2)
                    .foregroundColor(.cyan)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(selected ? Color.cyan.opacity(0.35) : Color.black.opacity(0.65))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.cyan : Color.clear, lineWidth: 1.5))
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

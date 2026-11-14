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

enum AppScreen { case mainMenu, inGame }

@MainActor
final class GameViewModel: ObservableObject {
    @Published var screen: AppScreen = .mainMenu
    @Published var selectedMap: CityMapType = .malang
    @Published var selectedMode: PlayMode = .real

    @Published var budgetIDR: Int64 = 150_000_000_000
    @Published var population: Int = 0
    @Published var educationIndex: Int = 0
    @Published var happiness: Int = 85
    @Published var isNight: Bool = false
    @Published var isMuted: Bool = false

    @Published var activeCategory: BuildCategory = .roads
    @Published var selRoad: RoadKind = .fourLane
    @Published var selZone: ZoneKind = .residential
    @Published var selFacility: FacilityKind = .balaiKota

    @Published var roads: [GridCoord: RoadTile] = [:]
    @Published var zones: [GridCoord: ZoneTile] = [:]
    @Published var facilities: [GridCoord: FacilityTile] = [:]
    @Published var activeGebrakans: Set<GebrakanKind> = []

    @Published var aiAgentMessage: String = "Halo Pak Wali! Bangun jalan raya & Balai Kota dulu agar warga mulai berdatangan."
    @Published var accidentCoord: GridCoord? = nil
    @Published var toast: String? = nil

    let engine = City3DEngine()
    private let saveKey = "com.nusantara.citybuilding.save.v22"
    private var simTimer: Timer?

    init() {
        engine.onTileTapped = { [weak self] coord in self?.handleTap(coord) }
    }

    var hasSave: Bool { UserDefaults.standard.data(forKey: saveKey) != nil }

    func startCity() {
        roads.removeAll(); zones.removeAll(); facilities.removeAll(); activeGebrakans.removeAll()
        accidentCoord = nil
        population = 0; educationIndex = 0; happiness = 85
        budgetIDR = selectedMode == .sandbox ? 999_999_999_999_999 : 150_000_000_000
        engine.loadMap(selectedMap, showcaseDemo: false)
        engine.showAccidentMarker(at: nil)
        screen = .inGame
        aiAgentMessage = "Selamat datang di \(selectedMap.title)! 1 rumah menampung 5 jiwa secara realistis."
        startSimulationLoop()
    }

    func saveCity() {
        let snap = CitySaveSnapshot(
            mapType: selectedMap,
            playMode: selectedMode,
            budgetIDR: budgetIDR,
            roads: Array(roads.values),
            zones: Array(zones.values),
            facilities: Array(facilities.values),
            activeGebrakans: Array(activeGebrakans)
        )
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: saveKey)
            showToast("Kota berhasil disimpan!")
        }
    }

    func loadCity() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let snap = try? JSONDecoder().decode(CitySaveSnapshot.self, from: data) else { return }
        selectedMap = snap.mapType
        selectedMode = snap.playMode
        budgetIDR = snap.budgetIDR
        roads = Dictionary(uniqueKeysWithValues: snap.roads.map { ($0.coord, $0) })
        zones = Dictionary(uniqueKeysWithValues: snap.zones.map { ($0.coord, $0) })
        facilities = Dictionary(uniqueKeysWithValues: snap.facilities.map { ($0.coord, $0) })
        activeGebrakans = Set(snap.activeGebrakans)

        engine.loadMap(selectedMap, showcaseDemo: false)
        engine.syncWorld(roads: roads, zones: zones, facilities: facilities)
        recalcStats()
        screen = .inGame
        startSimulationLoop()
        showToast("Kota \(selectedMap.title) dimuat!")
    }

    func handleTap(_ coord: GridCoord) {
        guard screen == .inGame else { return }
        switch activeCategory {
        case .roads:
            guard zones[coord] == nil && facilities[coord] == nil else {
                showToast("Petak terisi bangunan. Hapus dulu jika ingin bangun jalan.")
                return
            }
            guard spend(selRoad.costIDR) else { return }
            roads[coord] = RoadTile(coord: coord, kind: selRoad)
            if accidentCoord == coord {
                accidentCoord = nil
                engine.showAccidentMarker(at: nil)
            }

        case .zones:
            guard roads[coord] == nil && zones[coord] == nil && facilities[coord] == nil else {
                showToast("Pilih petak tanah kosong!")
                return
            }
            guard spend(selZone.costIDR) else { return }
            zones[coord] = ZoneTile(coord: coord, kind: selZone, level: 1)

        case .facilities:
            guard roads[coord] == nil && zones[coord] == nil && facilities[coord] == nil else {
                showToast("Pilih lahan kosong untuk membangun \(selFacility.title).")
                return
            }
            guard spend(selFacility.costIDR) else { return }
            facilities[coord] = FacilityTile(coord: coord, kind: selFacility)
            aiAgentMessage = "Mantap! \(selFacility.title) resmi beroperasi melayani warga."

        case .gebrakans:
            showToast("Pilih kartu Gebrakan di panel bawah untuk mengaktifkannya.")
            return

        case .bulldoze:
            let removed = (roads.removeValue(forKey: coord) != nil) ||
                          (zones.removeValue(forKey: coord) != nil) ||
                          (facilities.removeValue(forKey: coord) != nil)
            if removed {
                if accidentCoord == coord {
                    accidentCoord = nil
                    engine.showAccidentMarker(at: nil)
                }
                showToast("Objek dibongkar.")
            }
        }

        engine.syncWorld(roads: roads, zones: zones, facilities: facilities)
        NusantaraAssetBank.shared.playBuildSFX()
        recalcStats()
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

    private func recalcStats() {
        var pop = 0
        var parkBonus = 0
        for z in zones.values {
            pop += z.kind.basePopulation
            if z.kind == .park { parkBonus += 3 }
        }
        var edu = 0
        for f in facilities.values { edu += f.kind.educationScore }
        if activeGebrakans.contains(.beasiswaKampus) { edu += 20 }

        population = pop
        educationIndex = min(100, edu)
        let gebBonus = activeGebrakans.contains(.jumatBersih) ? 10 : 0
        let accidentPenalty = accidentCoord != nil ? 12 : 0
        happiness = min(100, max(25, 80 + parkBonus + gebBonus - accidentPenalty))
    }

    private func startSimulationLoop() {
        simTimer?.invalidate()
        simTimer = Timer.scheduledTimer(withTimeInterval: 7.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.screen == .inGame else { return }
                if self.selectedMode == .real {
                    let mult: Double = self.activeGebrakans.contains(.digitalUmkm) ? 1.25 : 1.0
                    let tax = self.zones.values.reduce(Int64(0)) { $0 + Int64(Double($1.kind.monthlyTaxIDR) * mult) }
                    self.budgetIDR += tax
                }
                let hasPoliceOrHospital = self.facilities.values.contains { $0.kind == .kantorPolisi || $0.kind == .rsud }
                if self.accidentCoord == nil, self.roads.count >= 6, !hasPoliceOrHospital, let roadTile = self.roads.values.randomElement() {
                    self.accidentCoord = roadTile.coord
                    self.engine.showAccidentMarker(at: roadTile.coord)
                    self.aiAgentMessage = "DARURAT! Kecelakaan lalu lintas di (\(roadTile.coord.x), \(roadTile.coord.z)). Bangun Kantor Polisi / RSUD!"
                    self.recalcStats()
                } else if self.accidentCoord != nil && hasPoliceOrHospital {
                    self.accidentCoord = nil
                    self.engine.showAccidentMarker(at: nil)
                    self.aiAgentMessage = "Armada Polisi & Ambulans RSUD berhasil menangani kecelakaan lalu lintas!"
                    self.recalcStats()
                }
            }
        }
    }

    func toggleNight() {
        isNight = engine.toggleNightMode()
        engine.syncWorld(roads: roads, zones: zones, facilities: facilities)
    }

    func toggleMute() {
        isMuted.toggle()
        NusantaraAssetBank.shared.isMuted = isMuted
    }

    private func showToast(_ msg: String) {
        toast = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            if self?.toast == msg { self?.toast = nil }
        }
    }
}

struct RootGameView: View {
    @StateObject private var vm = GameViewModel()

    var body: some View {
        ZStack {
            SceneKitViewport(engine: vm.engine, interactive: vm.screen == .inGame)
                .ignoresSafeArea()

            if vm.screen == .mainMenu {
                mainMenuOverlay
            } else {
                inGameHUD
            }
        }
    }

    private var mainMenuOverlay: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("RIZZI GAMES (RG)")
                    .font(.caption.bold())
                    .tracking(2)
                    .foregroundColor(.cyan)
                Text("City Building :\nNusantara Project")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Button { vm.startCity() } label: {
                    Label("MULAI BANGUN KOTA", systemImage: "play.fill")
                        .font(.headline.bold())
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.cyan)
                        .cornerRadius(12)
                }
                if vm.hasSave {
                    Button { vm.loadCity() } label: {
                        Label("LANJUTKAN SIMPANAN", systemImage: "folder.fill")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color.white.opacity(0.16))
                            .cornerRadius(12)
                    }
                }
            }
            .padding(22)
            .frame(width: 310)
            .background(.ultraThinMaterial)
            .cornerRadius(20)

            VStack(alignment: .leading, spacing: 14) {
                Text("Pilih Wilayah Peta Nusantara")
                    .font(.headline)
                    .foregroundColor(.white)
                HStack(spacing: 10) {
                    ForEach(CityMapType.allCases) { m in
                        Button { vm.selectedMap = m } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(m.title).font(.subheadline.bold())
                                Text(m.subtitle).font(.caption2).lineLimit(2)
                            }
                            .foregroundColor(.white)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(vm.selectedMap == m ? Color.cyan.opacity(0.35) : Color.white.opacity(0.08))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(vm.selectedMap == m ? Color.cyan : Color.clear, lineWidth: 2))
                            .cornerRadius(10)
                        }
                    }
                }

                Text("Mode Permainan")
                    .font(.headline)
                    .foregroundColor(.white)
                HStack(spacing: 10) {
                    ForEach(PlayMode.allCases) { mode in
                        Button { vm.selectedMode = mode } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mode.title).font(.subheadline.bold())
                                Text(mode.subtitle).font(.caption2)
                            }
                            .foregroundColor(.white)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(vm.selectedMode == mode ? Color.green.opacity(0.35) : Color.white.opacity(0.08))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(vm.selectedMode == mode ? Color.green : Color.clear, lineWidth: 2))
                            .cornerRadius(10)
                        }
                    }
                }
            }
            .padding(22)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
        }
        .padding(24)
    }

    private var inGameHUD: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button { vm.screen = .mainMenu } label: {
                    Image(systemName: "house.fill").padding(9).background(.ultraThinMaterial).cornerRadius(10)
                }
                statBadge(title: "APBD", val: IDRFormat.string(vm.budgetIDR), col: .green)
                statBadge(title: "Penduduk", val: "\(vm.population) Jiwa", col: .cyan)
                statBadge(title: "Pendidikan", val: "\(vm.educationIndex)%", col: .blue)
                statBadge(title: "Bahagia", val: "\(vm.happiness)%", col: .yellow)
                Spacer()
                Button { vm.toggleNight() } label: {
                    Image(systemName: vm.isNight ? "moon.stars.fill" : "sun.max.fill")
                        .foregroundColor(vm.isNight ? .yellow : .orange)
                        .padding(9).background(.ultraThinMaterial).cornerRadius(10)
                }
                Button { vm.toggleMute() } label: {
                    Image(systemName: vm.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .padding(9).background(.ultraThinMaterial).cornerRadius(10)
                }
                Button { vm.saveCity() } label: {
                    Image(systemName: "square.and.arrow.down.fill")
                        .padding(9).background(.ultraThinMaterial).cornerRadius(10)
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.top, 8)

            // AI Agent Asisten Walikota Bar
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(.cyan)
                Text("AI Nusa: \(vm.aiAgentMessage)")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.65))
            .cornerRadius(10)
            .padding(.horizontal, 14)

            if let t = vm.toast {
                Text(t)
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.85))
                    .cornerRadius(14)
            }

            Spacer()

            HStack {
                Spacer()
                VStack(spacing: 6) {
                    Button { vm.engine.zoomCamera(scaleFactor: 1.25) } label: {
                        Image(systemName: "plus.magnifyingglass").frame(width: 36, height: 36).background(.ultraThinMaterial).cornerRadius(9)
                    }
                    Button { vm.engine.zoomCamera(scaleFactor: 0.8) } label: {
                        Image(systemName: "minus.magnifyingglass").frame(width: 36, height: 36).background(.ultraThinMaterial).cornerRadius(9)
                    }
                    Button { vm.engine.rotateCamera(deltaYaw: 0.45) } label: {
                        Image(systemName: "arrow.triangle.2.circlepath").frame(width: 36, height: 36).background(.ultraThinMaterial).cornerRadius(9)
                    }
                }
                .foregroundColor(.white)
                .padding(.trailing, 14)
            }

            // Dock Bawah Lengkap dengan Sub-Item
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

                HStack(spacing: 8) {
                    ForEach(BuildCategory.allCases) { cat in
                        Button { vm.activeCategory = cat } label: {
                            Label(cat.title, systemImage: cat.icon)
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(vm.activeCategory == cat ? Color.blue : Color.white.opacity(0.14))
                                .cornerRadius(10)
                        }
                    }
                }
            }
            .foregroundColor(.white)
            .padding(10)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private func subItemButton(title: String, price: Int64, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title).font(.caption.bold())
                Text(vm.selectedMode == .sandbox ? "Gratis" : IDRFormat.string(price))
                    .font(.caption2)
                    .foregroundColor(.cyan)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(selected ? Color.cyan.opacity(0.35) : Color.black.opacity(0.65))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Color.cyan : Color.clear, lineWidth: 1.5))
            .cornerRadius(9)
        }
    }

    private func statBadge(title: String, val: String, col: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundColor(.gray)
            Text(val).font(.caption.bold()).foregroundColor(col)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}

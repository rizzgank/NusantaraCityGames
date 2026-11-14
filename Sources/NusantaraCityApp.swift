import UIKit
import SwiftUI
import Combine

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let root = RootGameView()
            .preferredColorScheme(.dark)
        window.rootViewController = UIHostingController(rootView: root)
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return .landscape
    }
}

enum AppScreen {
    case splashTitle
    case splashStudio
    case mainMenu
    case inGame
}

@MainActor
final class GameViewModel: ObservableObject {
    @Published var screen: AppScreen = .splashTitle
    @Published var selectedMap: CityMapType = .malang
    @Published var selectedMode: PlayMode = .real

    @Published var budgetIDR: Int64 = 150_000_000_000
    @Published var population: Int = 0
    @Published var happiness: Int = 85
    @Published var isNight: Bool = false

    @Published var selectedCategory: BuildCategory = .roads
    @Published var selectedRoadKind: RoadKind = .fourLane
    @Published var selectedZoneKind: ZoneKind = .residential

    @Published var roads: [GridCoord: RoadTile] = [:]
    @Published var zones: [GridCoord: ZoneTile] = [:]
    @Published var toastText: String? = nil

    let engine = City3DEngine()
    private let saveKey = "com.nusantara.citybuilding.autosave.v1"
    private var economyTimer: Timer?

    init() {
        engine.onTileTapped = { [weak self] coord in
            self?.handleTileTap(coord)
        }
        startSplashSequence()
    }

    func startSplashSequence() {
        screen = .splashTitle
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self, self.screen == .splashTitle else { return }
            self.screen = .splashStudio
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                guard let self, self.screen == .splashStudio else { return }
                self.enterMainMenu()
            }
        }
    }

    func skipSplash() {
        enterMainMenu()
    }

    func enterMainMenu() {
        economyTimer?.invalidate()
        economyTimer = nil
        engine.loadMap(.malang, showcaseDemo: true)
        screen = .mainMenu
    }

    func startNewCity() {
        roads.removeAll()
        zones.removeAll()
        budgetIDR = selectedMode == .sandbox ? 999_999_999_999_999 : 150_000_000_000
        population = 0
        happiness = 85

        engine.loadMap(selectedMap, showcaseDemo: false)
        screen = .inGame
        startEconomyLoop()
        showToast("Selamat datang di \(selectedMap.title)! Pilih Jalan atau Area lalu ketuk tanah.")
    }

    var hasSavedGame: Bool {
        UserDefaults.standard.data(forKey: saveKey) != nil
    }

    func saveCity() {
        let snapshot = CitySaveSnapshot(
            mapType: selectedMap,
            playMode: selectedMode,
            budgetIDR: budgetIDR,
            roads: Array(roads.values),
            zones: Array(zones.values)
        )
        if let encoded = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
            showToast("Kota berhasil disimpan!")
        }
    }

    func loadSavedCity() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let snap = try? JSONDecoder().decode(CitySaveSnapshot.self, from: data) else {
            showToast("Belum ada data tersimpan.")
            return
        }
        selectedMap = snap.mapType
        selectedMode = snap.playMode
        budgetIDR = snap.budgetIDR

        roads.removeAll()
        for r in snap.roads { roads[r.coord] = r }

        zones.removeAll()
        for z in snap.zones { zones[z.coord] = z }

        engine.loadMap(selectedMap, showcaseDemo: false)
        engine.syncWorld(roads: roads, zones: zones)
        recalculateStats()
        screen = .inGame
        startEconomyLoop()
        showToast("Kota \(selectedMap.title) berhasil dimuat!")
    }

    func handleTileTap(_ coord: GridCoord) {
        guard screen == .inGame else { return }

        switch selectedCategory {
        case .roads:
            if zones[coord] != nil {
                showToast("Petak terisi area. Hapus dulu dengan Buldoser.")
                return
            }
            guard spendBudget(selectedRoadKind.costIDR) else { return }
            roads[coord] = RoadTile(coord: coord, kind: selectedRoadKind)
            engine.syncWorld(roads: roads, zones: zones)
            NusantaraAssetBank.shared.playBuildSFX()
            recalculateStats()

        case .zones:
            if roads[coord] != nil || zones[coord] != nil {
                showToast("Petak sudah terisi. Pilih lahan kosong.")
                return
            }
            guard spendBudget(selectedZoneKind.costIDR) else { return }
            zones[coord] = ZoneTile(coord: coord, kind: selectedZoneKind, level: 1)
            engine.syncWorld(roads: roads, zones: zones)
            NusantaraAssetBank.shared.playBuildSFX()
            recalculateStats()

        case .bulldoze:
            if roads.removeValue(forKey: coord) != nil || zones.removeValue(forKey: coord) != nil {
                engine.syncWorld(roads: roads, zones: zones)
                recalculateStats()
                showToast("Objek dibongkar.")
            }
        }
    }

    private func spendBudget(_ cost: Int64) -> Bool {
        if selectedMode == .sandbox { return true }
        if budgetIDR < cost {
            showToast("Dana APBD kurang! Butuh \(IDRFormat.string(cost))")
            return false
        }
        budgetIDR -= cost
        return true
    }

    private func recalculateStats() {
        var pop = 0
        var parkBonus = 0
        for z in zones.values {
            pop += z.kind.populationGain
            if z.kind == .park { parkBonus += 3 }
        }
        population = pop
        happiness = min(100, max(40, 80 + parkBonus))
    }

    private func startEconomyLoop() {
        economyTimer?.invalidate()
        economyTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.screen == .inGame, self.selectedMode == .real else { return }
                let netTax = self.zones.values.reduce(Int64(0)) { $0 + $1.kind.monthlyTaxIDR }
                self.budgetIDR += netTax
            }
        }
    }

    func toggleNight() {
        isNight = engine.toggleNightMode()
        engine.syncWorld(roads: roads, zones: zones)
    }

    private func showToast(_ text: String) {
        toastText = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            if self?.toastText == text {
                self?.toastText = nil
            }
        }
    }
}

struct RootGameView: View {
    @StateObject private var vm = GameViewModel()

    var body: some View {
        ZStack {
            if vm.screen == .mainMenu || vm.screen == .inGame {
                SceneKitViewport(engine: vm.engine, interactive: vm.screen == .inGame)
                    .ignoresSafeArea()
            } else {
                Color(red: 0.04, green: 0.06, blue: 0.11)
                    .ignoresSafeArea()
            }

            switch vm.screen {
            case .splashTitle:
                splashTitleView
            case .splashStudio:
                splashStudioView
            case .mainMenu:
                mainMenuOverlay
            case .inGame:
                inGameHUD
            }
        }
    }

    private var splashTitleView: some View {
        VStack(spacing: 10) {
            Text("NUSANTARA URBAN SIMULATION")
                .font(.caption.bold())
                .tracking(3)
                .foregroundColor(.cyan)
            Text("City Building : Nusantara Project")
                .font(.largeTitle.bold())
                .foregroundColor(.white)
            Text("Ketuk layar untuk melewati")
                .font(.footnote)
                .foregroundColor(.gray)
                .padding(.top, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { vm.skipSplash() }
    }

    private var splashStudioView: some View {
        VStack(spacing: 12) {
            Text("RG")
                .font(.system(size: 54, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                )
            Text("RIZZI GAMES")
                .font(.title3.bold())
                .tracking(4)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { vm.skipSplash() }
    }

    private var mainMenuOverlay: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("RIZZI GAMES PRESENTS")
                    .font(.caption.bold())
                    .tracking(2)
                    .foregroundColor(.cyan)

                Text("City Building :\nNusantara Project")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)

                Spacer()

                Button {
                    vm.startNewCity()
                } label: {
                    Label("MULAI BANGUN KOTA", systemImage: "play.fill")
                        .font(.headline.bold())
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.cyan)
                        .cornerRadius(12)
                }

                if vm.hasSavedGame {
                    Button {
                        vm.loadSavedCity()
                    } label: {
                        Label("LANJUTKAN KOTA TERSIMPAN", systemImage: "folder.fill")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.16))
                            .cornerRadius(12)
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: 320)
            .background(.ultraThinMaterial)
            .cornerRadius(20)

            VStack(alignment: .leading, spacing: 14) {
                Text("Pilih Wilayah Peta")
                    .font(.headline)
                    .foregroundColor(.white)

                HStack(spacing: 10) {
                    ForEach(CityMapType.allCases) { map in
                        Button {
                            vm.selectedMap = map
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(map.title)
                                    .font(.subheadline.bold())
                                Text(map.subtitle)
                                    .font(.caption2)
                                    .lineLimit(2)
                            }
                            .foregroundColor(.white)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(vm.selectedMap == map ? Color.cyan.opacity(0.35) : Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(vm.selectedMap == map ? Color.cyan : Color.clear, lineWidth: 2)
                            )
                            .cornerRadius(10)
                        }
                    }
                }

                Text("Pilih Mode Permainan")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.top, 4)

                HStack(spacing: 10) {
                    ForEach(PlayMode.allCases) { mode in
                        Button {
                            vm.selectedMode = mode
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mode.title)
                                    .font(.subheadline.bold())
                                Text(mode.subtitle)
                                    .font(.caption2)
                            }
                            .foregroundColor(.white)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(vm.selectedMode == mode ? Color.green.opacity(0.35) : Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(vm.selectedMode == mode ? Color.green : Color.clear, lineWidth: 2)
                            )
                            .cornerRadius(10)
                        }
                    }
                }
            }
            .padding(22)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    private var inGameHUD: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    vm.enterMainMenu()
                } label: {
                    Image(systemName: "house.fill")
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .cornerRadius(10)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.selectedMap.title)
                        .font(.subheadline.bold())
                    Text(vm.selectedMode.title)
                        .font(.caption2)
                        .foregroundColor(.cyan)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .cornerRadius(10)

                statBadge(title: "APBD", value: IDRFormat.string(vm.budgetIDR), color: .green)
                statBadge(title: "Warga", value: "\(vm.population)", color: .cyan)
                statBadge(title: "Bahagia", value: "\(vm.happiness)%", color: .yellow)

                Spacer()

                Button {
                    vm.toggleNight()
                } label: {
                    Image(systemName: vm.isNight ? "moon.stars.fill" : "sun.max.fill")
                        .foregroundColor(vm.isNight ? .yellow : .orange)
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .cornerRadius(10)
                }

                Button {
                    vm.saveCity()
                } label: {
                    Label("Simpan", systemImage: "square.and.arrow.down.fill")
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .cornerRadius(10)
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.top, 10)

            if let toast = vm.toastText {
                Text(toast)
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(20)
                    .padding(.top, 8)
            }

            Spacer()

            HStack {
                Spacer()
                VStack(spacing: 8) {
                    Button { vm.engine.zoomCamera(scaleFactor: 1.25) } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial)
                            .cornerRadius(10)
                    }
                    Button { vm.engine.zoomCamera(scaleFactor: 0.8) } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial)
                            .cornerRadius(10)
                    }
                    Button { vm.engine.rotateCamera(deltaYaw: 0.45) } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial)
                            .cornerRadius(10)
                    }
                }
                .foregroundColor(.white)
                .padding(.trailing, 16)
            }

            VStack(spacing: 8) {
                if vm.selectedCategory == .roads {
                    HStack(spacing: 8) {
                        ForEach(RoadKind.allCases) { kind in
                            Button {
                                vm.selectedRoadKind = kind
                            } label: {
                                VStack(spacing: 2) {
                                    Text(kind.title)
                                        .font(.caption.bold())
                                    Text(vm.selectedMode == .sandbox ? "Gratis" : IDRFormat.string(kind.costIDR))
                                        .font(.caption2)
                                        .foregroundColor(.cyan)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(vm.selectedRoadKind == kind ? Color.cyan.opacity(0.35) : Color.black.opacity(0.65))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(vm.selectedRoadKind == kind ? Color.cyan : Color.clear, lineWidth: 1.5)
                                )
                                .cornerRadius(10)
                            }
                        }
                    }
                } else if vm.selectedCategory == .zones {
                    HStack(spacing: 8) {
                        ForEach(ZoneKind.allCases) { kind in
                            Button {
                                vm.selectedZoneKind = kind
                            } label: {
                                VStack(spacing: 2) {
                                    Text(kind.title)
                                        .font(.caption.bold())
                                    Text(vm.selectedMode == .sandbox ? "Gratis" : IDRFormat.string(kind.costIDR))
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(vm.selectedZoneKind == kind ? Color.green.opacity(0.35) : Color.black.opacity(0.65))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(vm.selectedZoneKind == kind ? Color.green : Color.clear, lineWidth: 1.5)
                                )
                                .cornerRadius(10)
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    ForEach(BuildCategory.allCases) { cat in
                        Button {
                            vm.selectedCategory = cat
                        } label: {
                            Label(cat.title, systemImage: cat.icon)
                                .font(.subheadline.bold())
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .background(vm.selectedCategory == cat ? Color.blue : Color.white.opacity(0.14))
                                .cornerRadius(12)
                        }
                    }
                }
            }
            .foregroundColor(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(.ultraThinMaterial)
            .cornerRadius(18)
            .padding(.bottom, 10)
        }
    }

    private func statBadge(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.gray)
            Text(value)
                .font(.caption.bold())
                .foregroundColor(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
    }
}

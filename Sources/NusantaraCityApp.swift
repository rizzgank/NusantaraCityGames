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
    @Published var happiness: Int = 88
    @Published var isNight: Bool = false
    @Published var activeCategory: BuildCategory = .roads

    @Published var selRoad: RoadKind = .fourLane
    @Published var selZone: ZoneKind = .residential
    @Published var selFacility: FacilityKind = .sdNegeri

    @Published var roads: [GridCoord: RoadTile] = [:]
    @Published var zones: [GridCoord: ZoneTile] = [:]
    @Published var facilities: [GridCoord: FacilityTile] = [:]
    @Published var toast: String? = nil

    let engine = City3DEngine()

    init() {
        engine.onTileTapped = { [weak self] coord in self?.handleTap(coord) }
    }

    func startCity() {
        roads.removeAll(); zones.removeAll(); facilities.removeAll()
        population = 0
        budgetIDR = selectedMode == .sandbox ? 999_999_999_999 : 150_000_000_000
        engine.loadMap(selectedMap, showcaseDemo: false)
        screen = .inGame
        showToast("Selamat datang di \(selectedMap.title)!")
    }

    func handleTap(_ coord: GridCoord) {
        guard screen == .inGame else { return }
        switch activeCategory {
        case .roads:
            roads[coord] = RoadTile(coord: coord, kind: selRoad)
        case .zones:
            zones[coord] = ZoneTile(coord: coord, kind: selZone, level: 1)
            recalcPop()
        case .facilities:
            facilities[coord] = FacilityTile(coord: coord, kind: selFacility)
        case .gebrakans:
            break
        }
        engine.syncWorld(roads: roads, zones: zones, facilities: facilities)
    }

    private func recalcPop() {
        var total = 0
        for z in zones.values { total += z.kind.basePopulation }
        population = total
    }

    func toggleNight() { isNight = engine.toggleNightMode() }
    private func showToast(_ msg: String) {
        toast = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in if self?.toast == msg { self?.toast = nil } }
    }
}

struct RootGameView: View {
    @StateObject private var vm = GameViewModel()

    var body: some View {
        ZStack {
            if vm.screen == .inGame || vm.screen == .mainMenu {
                SceneKitViewport(engine: vm.engine, interactive: vm.screen == .inGame).ignoresSafeArea()
            }
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
                Text("RIZZI GAMES (RG)").font(.caption.bold()).foregroundColor(.cyan)
                Text("City Building :\nNusantara Project").font(.system(size: 28, weight: .heavy)).foregroundColor(.white)
                Spacer()
                Button { vm.startCity() } label: {
                    Label("MULAI KOTA", systemImage: "play.fill").font(.headline.bold()).foregroundColor(.black)
                        .frame(maxWidth: .infinity).padding().background(Color.cyan).cornerRadius(12)
                }
            }.padding(24).frame(width: 300).background(.ultraThinMaterial).cornerRadius(20)

            VStack(alignment: .leading, spacing: 14) {
                Text("Pilih Wilayah Peta").font(.headline).foregroundColor(.white)
                HStack {
                    ForEach(CityMapType.allCases) { m in
                        Button { vm.selectedMap = m } label: {
                            Text(m.title).font(.subheadline.bold()).foregroundColor(.white).padding(12)
                                .background(vm.selectedMap == m ? Color.cyan.opacity(0.4) : Color.white.opacity(0.1))
                                .cornerRadius(10)
                        }
                    }
                }
            }.padding(24).background(.ultraThinMaterial).cornerRadius(20)
        }.padding(30)
    }

    private var inGameHUD: some View {
        VStack {
            HStack(spacing: 12) {
                Button { vm.screen = .mainMenu } label: { Image(systemName: "house.fill").padding(10).background(.ultraThinMaterial).cornerRadius(10) }
                statBadge(title: "APBD", val: IDRFormat.string(vm.budgetIDR), col: .green)
                statBadge(title: "Warga", val: "\(vm.population) Jiwa", col: .cyan)
                statBadge(title: "Bahagia", val: "\(vm.happiness)%", col: .yellow)
                Spacer()
                Button { vm.toggleNight() } label: { Image(systemName: vm.isNight ? "moon.stars.fill" : "sun.max.fill").padding(10).background(.ultraThinMaterial).cornerRadius(10) }
            }.foregroundColor(.white).padding()

            if let t = vm.toast {
                Text(t).font(.caption.bold()).foregroundColor(.white).padding(8).background(Color.black.opacity(0.8)).cornerRadius(12)
            }

            Spacer()

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    ForEach(BuildCategory.allCases) { cat in
                        Button { vm.activeCategory = cat } label: {
                            Label(cat.title, systemImage: cat.icon).font(.caption.bold()).padding(10)
                                .background(vm.activeCategory == cat ? Color.blue : Color.white.opacity(0.15)).cornerRadius(10)
                        }
                    }
                }
            }.foregroundColor(.white).padding().background(.ultraThinMaterial).cornerRadius(16).padding(.bottom, 10)
        }
    }

    private func statBadge(title: String, val: String, col: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundColor(.gray)
            Text(val).font(.caption.bold()).foregroundColor(col)
        }.padding(8).background(.ultraThinMaterial).cornerRadius(8)
    }
}

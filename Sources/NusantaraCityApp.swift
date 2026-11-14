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

    @Published var timePhase: TimeOfDayPhase = .day
    @Published var weather: CityWeather = .cerahBerawan
    @Published var hideHUDForPhoto: Bool = false
    @Published var showSubTray: Bool = true
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
    @Published var customGebrakans: [CustomAIGebrakan] = []

    @Published var showCustomGebrakanModal: Bool = false
    @Published var customGebrakanPrompt: String = ""
    @Published var isAIThinkingGebrakan: Bool = false
    @Published var draftedAIGebrakan: CustomAIGebrakan? = nil

    @Published var showAIChatDrawer: Bool = false
    @Published var chatInputText: String = ""
    @Published var chatMessages: [AIChatMessage] = []
    @Published var unreadAINotifications: Int = 0
    private var issuedPermitBrands: Set<String> = []

    @Published var settings = GameSettings()
    @Published var inspectCard: InspectCardData? = nil
    @Published var anchorCoord: GridCoord? = nil
    @Published var stagedCoords: [GridCoord] = []
    @Published var stagedSummary: String? = nil

    @Published var aiAgentMessage: String = "NUSA AI siap membantu! Ketuk ikon Chat AI di kanan atas untuk cuaca, laporan & perizinan cabang."
    @Published var accidentCoord: GridCoord? = nil
    @Published var toast: String? = nil

    private var undoStack: [UndoAction] = []
    let engine = City3DEngine()
    private var simTimer: Timer?
    private var simTickCount: Int = 0

    init() {
        engine.onTileTapped = { [weak self] coord in
            Task { @MainActor [weak self] in self?.handleGroundTap(coord) }
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
        clearSelection()
        inspectCard = nil
        hideHUDForPhoto = false
        showAIChatDrawer = false
        showCustomGebrakanModal = false
        engine.loadMap(.malang, showcaseDemo: true)
        screen = .mainMenu
    }

    func startCity() {
        roads.removeAll(); plots.removeAll(); facilities.removeAll(); utilities.removeAll()
        activeGebrakans.removeAll(); customGebrakans.removeAll(); undoStack.removeAll(); clearSelection()
        accidentCoord = nil; inspectCard = nil; hideHUDForPhoto = false; showSubTray = true
        showAIChatDrawer = false; showCustomGebrakanModal = false; issuedPermitBrands.removeAll()
        population = 0; educationIndex = 0; happiness = 85; simTickCount = 0
        budgetIDR = selectedMode == .sandbox ? 999_999_999_999_999 : 150_000_000_000

        weather = .cerahBerawan
        engine.loadMap(selectedMap, showcaseDemo: false)
        engine.setWeather(weather)
        engine.applyAtmosphere(shadows: settings.hdShadows, fog: settings.atmosphericFog, bloom: settings.hdrBloom)
        engine.cameraSensitivity = settings.cameraSensitivity
        screen = .inGame

        chatMessages = [
            AIChatMessage(
                isFromUser: false,
                senderName: "NUSA AI (Asisten Walikota)",
                text: "Selamat bertugas, Pak/Bu Walikota \(selectedMap.title)! Saya memantau cuaca real-time, kondisi APBD, dan meneruskan surat perizinan investor (seperti Indomaret, Alfamart, SPBU, atau Bank) yang ingin membuka cabang di kota Anda.",
                timestamp: currentClockText()
            )
        ]
        unreadAINotifications = 1
        aiAgentMessage = "1 jari: Geser Peta • 2 jari Kiri/Kanan: Rotasi • 2 jari Atas/Bawah: Sudut Vertikal"
        startSimulationLoop()
    }

    private func currentClockText() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: Date())
    }

    func runCustomAIGebrakanAnalysis() {
        let raw = customGebrakanPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            showToast("Tuliskan ide gebrakan yang kamu inginkan terlebih dahulu!")
            return
        }
        isAIThinkingGebrakan = true
        draftedAIGebrakan = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) { [weak self] in
            guard let self else { return }
            let lower = raw.lowercased()

            var title = "Inisiatif \(raw.prefix(28))"
            var cost: Int64 = 4_500_000_000
            var hapBonus = 6
            var taxBonus = 0.08
            var eduBonus = 4
            var reasoning = "NUSA AI menganalisis struktur APBD (\(IDRFormat.string(self.budgetIDR))) dan populasi (\(self.population) jiwa). "

            if lower.contains("umkm") || lower.contains("ekonomi") || lower.contains("pasar") || lower.contains("kuliner") || lower.contains("pajak") {
                title = "Stimulus Ekonomi & Kuliner Rakyat"
                cost = 6_500_000_000
                hapBonus = 8
                taxBonus = 0.22
                reasoning += "Fokus pada akselerasi ruko & komersial lokal meningkatkan perputaran uang warga (+22% pajak bulanan) serta menaikkan daya beli."
            } else if lower.contains("sekolah") || lower.contains("kampus") || lower.contains("riset") || lower.contains("wifi") || lower.contains("internet") || lower.contains("digital") {
                title = "Smart City & WiFi Publik Gratis"
                cost = 7_500_000_000
                hapBonus = 7
                taxBonus = 0.14
                eduBonus = 18
                reasoning += "Digitalisasi layanan publik dan akses internet merata mempercepat kenaikan level gedung hunian & kantor (+18% Indeks Pendidikan)."
            } else if lower.contains("taman") || lower.contains("hijau") || lower.contains("pohon") || lower.contains("bersih") || lower.contains("sepeda") || lower.contains("lingkungan") {
                title = "Gerakan Kota Hijau & Ruang Terbuka"
                cost = 3_800_000_000
                hapBonus = 14
                taxBonus = 0.05
                reasoning += "Penambahan ruang hijau dan jalur ramah lingkungan menurunkan tingkat stres warga (+14% Kebahagiaan) dan menaikkan nilai tanah."
            } else if lower.contains("bus") || lower.contains("angkot") || lower.contains("transport") || lower.contains("macet") || lower.contains("gratis") {
                title = "Transportasi Publik Terintegrasi"
                cost = 5_800_000_000
                hapBonus = 11
                taxBonus = 0.10
                reasoning += "Subsidi armada angkutan kota mempercepat mobilitas komuter menuju zona industri dan komersial (+11% Kebahagiaan)."
            } else {
                reasoning += "Kebijakan terpadu ini diselaraskan dengan kebutuhan tata ruang \(self.selectedMap.title) untuk mendorong kepuasan warga dan stabilitas fiskal."
            }

            self.draftedAIGebrakan = CustomAIGebrakan(
                id: UUID(),
                title: title,
                userPrompt: raw,
                aiReasoning: reasoning,
                costIDR: cost,
                happinessDelta: hapBonus,
                taxMultiplierBonus: taxBonus,
                educationDelta: eduBonus
            )
            self.isAIThinkingGebrakan = false
        }
    }

    func enactDraftedCustomGebrakan() {
        guard let policy = draftedAIGebrakan else { return }
        guard spend(policy.costIDR) else { return }
        customGebrakans.append(policy)
        draftedAIGebrakan = nil
        customGebrakanPrompt = ""
        showCustomGebrakanModal = false
        recalcStats()
        aiAgentMessage = "Gebrakan Kustom '\(policy.title)' resmi disahkan!"
        showToast("Disahkan: \(policy.title)")
    }

    func openAIChat() {
        showAIChatDrawer = true
        unreadAINotifications = 0
    }

    func sendUserChat(_ textOverride: String? = nil) {
        let query = (textOverride ?? chatInputText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        if textOverride == nil { chatInputText = "" }

        chatMessages.append(AIChatMessage(isFromUser: true, senderName: "Walikota", text: query, timestamp: currentClockText()))

        let lower = query.lowercased()
        let reply: String
        if lower.contains("cuaca") || lower.contains("angin") || lower.contains("hujan") || lower.contains("suhu") {
            reply = "🌤️ **Laporan Cuaca \(selectedMap.title):**\n• Kondisi: \(weather.title)\n• Fase Waktu: \(timePhase.title)\n• Detail Angin: \(weather.windSummary)"
        } else if lower.contains("izin") || lower.contains("indomaret") || lower.contains("alfamart") || lower.contains("cabang") || lower.contains("investor") {
            if let pending = chatMessages.first(where: { $0.permit != nil && $0.permit?.resolved == false })?.permit {
                reply = "📋 Saat ini ada permohonan izin aktif dari **\(pending.companyName)** untuk membuka **\(pending.branchTitle)**. Silakan tekan tombol **Setujui Izin** pada kartu permohonan di atas!"
            } else {
                triggerIncomingFranchisePermit(force: true)
                return
            }
        } else if lower.contains("apbd") || lower.contains("laporan") || lower.contains("kota") || lower.contains("warga") || lower.contains("stat") {
            reply = "📊 **Laporan Eksekutif Kota \(selectedMap.title):**\n• Populasi: \(population) Jiwa (Bahagia: \(happiness)%)\n• Kas APBD: \(IDRFormat.string(budgetIDR))\n• Listrik: \(powerSupply)/\(powerDemand) MW • Air: \(waterSupply)/\(waterDemand) m³\n• Indeks Pendidikan: \(educationIndex)%"
        } else if lower.contains("saran") || lower.contains("bantu") || lower.contains("bangun") {
            if roads.count < 4 {
                reply = "🛣️ **Saran NUSA AI:** Bangun terlebih dahulu jaringan **Jalan 2 Lajur** atau **Arteri 4 Lajur**, lalu cat **Zona Hunian** dan **Komersial** di petak biru tepi jalan."
            } else if powerSupply < powerDemand || waterSupply < waterDemand {
                reply = "⚡ **Prioritas Mendesak:** Pasokan listrik/air sedang defisit! Segera bangun **Gardu Listrik** dan **Menara PDAM** di menu Utilitas agar warga tidak pindah."
            } else {
                reply = "🏙️ **Rekomendasi Pengembangan:** Kota berjalan stabil! Tambahkan **SD Negeri / Universitas** untuk menaikkan level gedung hunian ke Level 5, atau buka permohonan investor cabang ritel."
            }
        } else {
            reply = "Siap, Pak/Bu Walikota! Saya telah mencatat arahan '\(query)'. Saat ini kota \(selectedMap.title) berada dalam cuaca **\(weather.title)** dengan populasi **\(population) jiwa** dan tingkat kebahagiaan **\(happiness)%**."
        }

        chatMessages.append(AIChatMessage(isFromUser: false, senderName: "NUSA AI", text: reply, timestamp: currentClockText()))
    }

    private func triggerIncomingFranchisePermit(force: Bool = false) {
        let catalog: [(brand: String, company: String, branch: String, fee: Int64, hap: Int, skin: Int)] = [
            ("Indomaret", "PT Indomarco Prismatama", "Gerai Indomaret Point", 1_500_000_000, 4, 1),
            ("Alfamart", "PT Sumber Alfaria Trijaya", "Gerai Alfamart Express", 1_400_000_000, 4, 2),
            ("Kopi Kenangan", "PT Bumi Berkah Boga", "Outlet Kopi Kenangan Drive-Thru", 1_800_000_000, 5, 0),
            ("SPBU Pertamina", "PT Pertamina Patra Niaga", "SPBU Modular Nusantara", 3_200_000_000, 3, 0),
            ("Bank BNI KCP", "PT Bank Negara Indonesia", "Kantor Cabang Pembantu (KCP)", 2_600_000_000, 3, 0)
        ]

        guard let candidate = catalog.first(where: { !issuedPermitBrands.contains($0.brand) }) ?? (force ? catalog.randomElement() : nil) else { return }
        issuedPermitBrands.insert(candidate.brand)

        let req = FranchisePermitRequest(
            id: UUID(),
            brandName: candidate.brand,
            companyName: candidate.company,
            branchTitle: candidate.branch,
            licenseFeeIDR: candidate.fee,
            happinessBonus: candidate.hap,
            zoneKind: .commercial,
            brandSkin: candidate.skin
        )

        let msg = AIChatMessage(
            isFromUser: false,
            senderName: "NUSA AI • Divisi Perizinan",
            text: "📩 **Permohonan Izin Usaha Masuk:**\n**\(candidate.company)** mengajukan izin pembukaan **\(candidate.branch)** di kota Anda.\n• Retribusi Izin ke APBD: **+\(IDRFormat.string(candidate.fee))**\n• Dampak Warga: +\(candidate.hap)% Kebahagiaan & Lapangan Kerja",
            timestamp: currentClockText(),
            permit: req
        )
        chatMessages.append(msg)
        if !showAIChatDrawer {
            unreadAINotifications += 1
        }
        aiAgentMessage = "📩 Permohonan Izin Baru: \(candidate.brand) ingin buka cabang! Buka Chat AI untuk acc."
    }

    func respondToPermit(messageID: UUID, approve: Bool) {
        guard let idx = chatMessages.firstIndex(where: { $0.id == messageID }),
              var permit = chatMessages[idx].permit, !permit.resolved else { return }

        permit.resolved = true
        permit.approved = approve
        chatMessages[idx].permit = permit

        if approve {
            budgetIDR += permit.licenseFeeIDR
            if let spot = findAvailableRoadsidePlot() {
                plots[spot] = ZonedPlot(
                    coord: spot,
                    kind: .commercial,
                    buildingLevel: 2,
                    residents: 4,
                    maxResidents: 4,
                    forcedBrandSkin: permit.brandSkin
                )
                syncEngine()
                recalcStats()
                chatMessages.append(AIChatMessage(
                    isFromUser: false,
                    senderName: "NUSA AI",
                    text: "✅ **Izin \(permit.brandName) Disetujui!** Dana retribusi **+\(IDRFormat.string(permit.licenseFeeIDR))** masuk ke APBD dan bangunan **\(permit.branchTitle)** telah resmi berdiri di koordinat (\(spot.x), \(spot.z))!",
                    timestamp: currentClockText()
                ))
            } else {
                chatMessages.append(AIChatMessage(
                    isFromUser: false,
                    senderName: "NUSA AI",
                    text: "✅ **Izin \(permit.brandName) Disetujui!** Retribusi **+\(IDRFormat.string(permit.licenseFeeIDR))** masuk ke APBD. Bangun jalan baru agar gerai fisik mereka dapat segera dibangun.",
                    timestamp: currentClockText()
                ))
            }
            NusantaraAssetBank.shared.playBuildSFX()
            showToast("Izin \(permit.brandName) disetujui (+\(IDRFormat.string(permit.licenseFeeIDR)))!")
        } else {
            chatMessages.append(AIChatMessage(
                isFromUser: false,
                senderName: "NUSA AI",
                text: "❌ Permohonan izin pembukaan cabang **\(permit.brandName)** telah ditolak secara resmi.",
                timestamp: currentClockText()
            ))
        }
    }

    private func findAvailableRoadsidePlot() -> GridCoord? {
        for r in roads.values where r.kind.isDriveable {
            let adj = [
                GridCoord(x: r.coord.x + 1, z: r.coord.z),
                GridCoord(x: r.coord.x - 1, z: r.coord.z),
                GridCoord(x: r.coord.x, z: r.coord.z + 1),
                GridCoord(x: r.coord.x, z: r.coord.z - 1)
            ]
            for c in adj {
                if abs(c.x) <= engine.gridHalfExtent && abs(c.z) <= engine.gridHalfExtent &&
                   roads[c] == nil && plots[c] == nil && facilities[c] == nil && utilities[c] == nil {
                    return c
                }
            }
        }
        return nil
    }

    func slotSnapshot(_ slot: Int) -> CitySaveSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: "nusantara.v7.slot.\(slot)") else { return nil }
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
            activeGebrakans: Array(activeGebrakans),
            customGebrakans: customGebrakans
        )
        if let encoded = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(encoded, forKey: "nusantara.v7.slot.\(slot)")
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
        customGebrakans = snap.customGebrakans
        undoStack.removeAll(); clearSelection()

        engine.loadMap(selectedMap, showcaseDemo: false)
        syncEngine()
        recalcStats()
        screen = .inGame
        startSimulationLoop()
        showToast("Kota \(selectedMap.title) dari Slot \(slot) dimuat!")
    }

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

    private func computeMarqueeBox(from a: GridCoord, to b: GridCoord) -> [GridCoord] {
        let minX = min(a.x, b.x), maxX = max(a.x, b.x)
        let minZ = min(a.z, b.z), maxZ = max(a.z, b.z)
        var list: [GridCoord] = []
        for z in minZ...maxZ {
            for x in minX...maxX {
                list.append(GridCoord(x: x, z: z))
            }
        }
        return list
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

    func clearSelection() {
        anchorCoord = nil
        stagedCoords = []
        stagedSummary = nil
        engine.updateSelectionPreview(coords: [], isValid: true, tint: .cyan)
    }

    func handleGroundTap(_ coord: GridCoord) {
        guard screen == .inGame else { return }

        if anchorCoord == nil && activeCategory != .bulldoze {
            if let p = plots[coord] {
                let stageText = p.buildingLevel == 0 ? "Konstruksi (Scaffolding)" : "Level \(p.buildingLevel) / 5"
                let brandLabel = p.forcedBrandSkin == 1 ? " (Cabang Indomaret)" : (p.forcedBrandSkin == 2 ? " (Cabang Alfamart)" : "")
                inspectCard = InspectCardData(
                    title: p.kind.title + brandLabel,
                    subtitle: "\(stageText) • (\(coord.x), \(coord.z))",
                    details: [
                        "Penghuni: \(p.residents) / \(p.maxResidents) Jiwa",
                        "Listrik: \(p.hasPower ? "Menyala" : "Byarpet") • Air: \(p.hasWater ? "Ada" : "Kering")",
                        "Pajak: \(IDRFormat.string(p.kind.monthlyTaxIDR(level: p.buildingLevel)))/bln"
                    ]
                )
                return
            } else if let f = facilities[coord] {
                inspectCard = InspectCardData(
                    title: f.kind.title,
                    subtitle: "Fasilitas Publik & Pendidikan",
                    details: [
                        "Status: Beroperasi Penuh",
                        "Indeks Pendidikan: +\(f.kind.educationScore)%"
                    ]
                )
                return
            }
        }

        inspectCard = nil

        if activeCategory == .roads || activeCategory == .zoning {
            if let start = anchorCoord {
                let path = activeCategory == .roads ? computeRoadPath(from: start, to: coord) : computeMarqueeBox(from: start, to: coord)
                stageSelection(path)
            } else {
                anchorCoord = coord
                stageSelection([coord])
            }
            return
        }

        switch activeCategory {
        case .facilities:
            guard roads[coord] == nil && plots[coord] == nil && facilities[coord] == nil && utilities[coord] == nil else {
                showToast("Pilih lahan kosong untuk \(selFacility.title).")
                return
            }
            guard spend(selFacility.costIDR) else { return }
            facilities[coord] = FacilityTile(coord: coord, kind: selFacility)
            undoStack.append(.placedFacility(coord, selFacility.costIDR))
            aiAgentMessage = "\(selFacility.title) selesai dibangun!"

        case .utilities:
            guard roads[coord] == nil && plots[coord] == nil && facilities[coord] == nil && utilities[coord] == nil else {
                showToast("Pilih lahan kosong untuk \(selUtility.title).")
                return
            }
            guard spend(selUtility.costIDR) else { return }
            utilities[coord] = UtilityTile(coord: coord, kind: selUtility)
            undoStack.append(.placedUtility(coord, selUtility.costIDR))
            aiAgentMessage = "\(selUtility.title) aktif menyuplai jaringan kota!"

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

        default:
            break
        }

        syncEngine()
        NusantaraAssetBank.shared.playBuildSFX()
        recalcStats()
    }

    private func stageSelection(_ coords: [GridCoord]) {
        stagedCoords = coords
        if activeCategory == .roads {
            let valid = coords.filter { plots[$0] == nil && facilities[$0] == nil && utilities[$0] == nil && roads[$0] == nil }
            let cost = Int64(valid.count) * selRoad.costIDR
            stagedSummary = "\(selRoad.title) (\(valid.count) Petak) • \(selectedMode == .sandbox ? "Gratis" : IDRFormat.string(cost))"
            engine.updateSelectionPreview(coords: coords, isValid: !valid.isEmpty, tint: .cyan)
        } else if activeCategory == .zoning {
            if selZoneBrush == .clearZone {
                stagedSummary = "Hapus Zona (\(coords.count) Petak)"
                engine.updateSelectionPreview(coords: coords, isValid: true, tint: .systemRed)
            } else {
                let valid = coords.filter { roads[$0] == nil && facilities[$0] == nil && utilities[$0] == nil && plots[$0] == nil && isNearRoad($0) }
                let cost = Int64(valid.count) * selZoneBrush.costIDR
                let tint: UIColor = selZoneBrush == .commercial ? .systemBlue : (selZoneBrush == .industrialOffice ? .systemYellow : .systemGreen)
                stagedSummary = "\(selZoneBrush.title) (\(valid.count) Petak) • \(selectedMode == .sandbox ? "Gratis" : IDRFormat.string(cost))"
                engine.updateSelectionPreview(coords: coords, isValid: !valid.isEmpty, tint: tint)
            }
        }
    }

    func confirmStagedBuild() {
        let coords = stagedCoords
        clearSelection()
        guard !coords.isEmpty else { return }

        if activeCategory == .roads {
            let valid = coords.filter { plots[$0] == nil && facilities[$0] == nil && utilities[$0] == nil && roads[$0] == nil }
            guard !valid.isEmpty else { showToast("Lahan sudah terisi."); return }
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
        } else if activeCategory == .zoning {
            if selZoneBrush == .clearZone {
                var cleared = 0
                for c in coords where plots.removeValue(forKey: c) != nil { cleared += 1 }
                if cleared > 0 { showToast("Cat zona dihapus dari \(cleared) petak.") }
            } else {
                let valid = coords.filter { roads[$0] == nil && facilities[$0] == nil && utilities[$0] == nil && plots[$0] == nil && isNearRoad($0) }
                guard !valid.isEmpty else {
                    showToast("Pilih petak biru di tepi jalan!")
                    return
                }
                let totalCost = Int64(valid.count) * selZoneBrush.costIDR
                guard spend(totalCost) else { return }

                for c in valid {
                    let startLv = selZoneBrush == .parkGreen ? 1 : 0
                    let cap = selZoneBrush.capacity(forLevel: max(1, startLv))
                    plots[c] = ZonedPlot(coord: c, kind: selZoneBrush, buildingLevel: startLv, residents: 0, maxResidents: cap)
                }
                undoStack.append(.placedBatchZones(valid, totalCost))
            }
        }

        syncEngine()
        NusantaraAssetBank.shared.playBuildSFX()
        recalcStats()
    }

    func selectCategory(_ cat: BuildCategory) {
        if activeCategory == cat {
            showSubTray.toggle()
        } else {
            activeCategory = cat
            showSubTray = true
        }
        clearSelection()
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
        clearSelection()
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
        showToast("Pembangunan terakhir dibatalkan.")
    }

    func triggerGebrakan(_ g: GebrakanKind) {
        if activeGebrakans.contains(g) {
            showToast("Kebijakan ini sudah aktif!")
            return
        }
        guard spend(g.costIDR) else { return }
        activeGebrakans.insert(g)
        recalcStats()
        aiAgentMessage = "Gebrakan '\(g.title)' aktif!"
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
        edu += customGebrakans.reduce(0) { $0 + $1.educationDelta }
        educationIndex = min(100, edu)

        let gebBonus = (activeGebrakans.contains(.jumatBersih) ? 10 : 0) + customGebrakans.reduce(0) { $0 + $1.happinessDelta }
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
                self.simTickCount += 1

                var visualChanged = false
                let maxAllowedLevel = min(5, 1 + (self.educationIndex / 22) + (self.happiness >= 85 ? 1 : 0))

                for key in self.plots.keys {
                    guard var p = self.plots[key], p.kind != .parkGreen else { continue }
                    let connected = self.isNearRoad(p.coord)

                    if connected && p.hasPower && p.hasWater {
                        p.isAbandoned = false
                        if p.buildingLevel == 0 {
                            p.buildingLevel = 1
                            p.maxResidents = p.kind.capacity(forLevel: 1)
                            visualChanged = true
                        } else if p.residents < p.maxResidents {
                            p.residents = min(p.maxResidents, p.residents + Int.random(in: 1...2))
                        } else if p.residents >= p.maxResidents && p.buildingLevel < maxAllowedLevel {
                            p.buildingLevel += 1
                            p.maxResidents = p.kind.capacity(forLevel: p.buildingLevel)
                            visualChanged = true
                        }
                    } else {
                        if p.residents > 0 {
                            p.residents = max(0, p.residents - 1)
                        } else if p.buildingLevel > 0 && !p.isAbandoned {
                            p.isAbandoned = true
                            visualChanged = true
                        }
                    }
                    self.plots[key] = p
                }

                if self.selectedMode == .real {
                    let customTaxBonus = self.customGebrakans.reduce(0.0) { $0 + $1.taxMultiplierBonus }
                    let mult: Double = (self.activeGebrakans.contains(.digitalUmkm) ? 1.25 : 1.0) + customTaxBonus
                    let tax = self.plots.values.reduce(Int64(0)) { acc, p in
                        guard p.buildingLevel > 0 && !p.isAbandoned else { return acc }
                        let ratio = p.maxResidents > 0 ? Double(p.residents) / Double(p.maxResidents) : 1.0
                        return acc + Int64(Double(p.kind.monthlyTaxIDR(level: p.buildingLevel)) * ratio * mult)
                    }
                    self.budgetIDR += tax
                }

                if self.simTickCount % 8 == 0 {
                    let allW = CityWeather.allCases
                    if let idx = allW.firstIndex(of: self.weather) {
                        self.weather = allW[(idx + 1) % allW.count]
                        self.engine.setWeather(self.weather)
                    }
                }

                if self.simTickCount % 4 == 0 && !self.roads.isEmpty && !self.plots.isEmpty {
                    let hasPending = self.chatMessages.contains { $0.permit != nil && $0.permit?.resolved == false }
                    if !hasPending {
                        self.triggerIncomingFranchisePermit(force: false)
                    }
                }

                let hasEmergency = self.facilities.values.contains { $0.kind == .kantorPolisi || $0.kind == .rsud }
                if self.accidentCoord == nil, self.roads.count >= 7, !hasEmergency, let r = self.roads.values.randomElement() {
                    self.accidentCoord = r.coord
                    self.engine.showAccidentMarker(at: r.coord)
                    self.aiAgentMessage = "DARURAT! Kecelakaan di (\(r.coord.x), \(r.coord.z)). Bangun RSUD / Polisi!"
                } else if self.accidentCoord != nil && hasEmergency {
                    self.accidentCoord = nil
                    self.engine.showAccidentMarker(at: nil)
                    self.aiAgentMessage = "Ambulans RSUD & Polisi mengevakuasi kecelakaan!"
                }

                if visualChanged {
                    self.syncEngine()
                }
                self.recalcStats()
            }
        }
    }

    func cycleTime() {
        timePhase = engine.cycleTimePhase()
        syncEngine()
        showToast(timePhase.title)
    }

    func switchCameraMode(_ mode: CameraMode) {
        cameraMode = mode
        if mode == .followVehicle {
            engine.cycleFollowedVehicle()
        } else {
            engine.setCameraMode(mode)
        }
    }

    private func showToast(_ msg: String) {
        toast = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            if self?.toast == msg { self?.toast = nil }
        }
    }
}

struct RootGameView: View {
    @StateObject private var vm = GameViewModel()

    var body: some View {
        ZStack {
            if vm.screen == .splashTitle || vm.screen == .splashStudio {
                Color(red: 0.04, green: 0.06, blue: 0.12).ignoresSafeArea()
            } else {
                SceneKitViewport(engine: vm.engine, interactive: vm.screen == .inGame && !vm.showAIChatDrawer && !vm.showCustomGebrakanModal)
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
                inGameSafeHUD
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
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundColor(.white)
            Text("Ketuk layar untuk melewati")
                .font(.caption2)
                .foregroundColor(.gray)
                .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { vm.enterMainMenu() }
    }

    private var splashStudioView: some View {
        VStack(spacing: 14) {
            Text("RG")
                .font(.system(size: 54, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18)
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
        GeometryReader { geo in
            HStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text("RIZZI GAMES (RG)")
                        .font(.caption.bold())
                        .tracking(2)
                        .foregroundColor(.cyan)
                    Text("City Building :\nNusantara Project")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)

                    Spacer()

                    menuButton(title: "START", icon: "play.fill", primary: true) { vm.screen = .selectMode }
                    menuButton(title: "SAVE GAME", icon: "folder.fill", primary: false) { vm.screen = .saveSlots }
                    menuButton(title: "SETTINGS", icon: "gearshape.fill", primary: false) { vm.screen = .settingsMenu }
                    menuButton(title: "EXIT", icon: "power", primary: false) { exit(0) }
                }
                .padding(20)
                .frame(width: 280)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .padding(.leading, max(geo.safeAreaInsets.leading, 20))
                .padding(.vertical, 16)

                Spacer()
            }
        }
    }

    private func menuButton(title: String, icon: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .foregroundColor(primary ? .black : .white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(primary ? Color.cyan : Color.white.opacity(0.14))
                .cornerRadius(11)
        }
    }

    private var selectModeView: some View {
        VStack(spacing: 16) {
            Text("TAHAP 1 : PILIH MODE PERMAINAN")
                .font(.headline.bold())
                .tracking(2)
                .foregroundColor(.cyan)

            HStack(spacing: 14) {
                ForEach(PlayMode.allCases) { mode in
                    Button { vm.selectedMode = mode } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(mode.title).font(.headline.bold())
                            Text(mode.subtitle).font(.caption).multilineTextAlignment(.leading)
                        }
                        .foregroundColor(.white)
                        .padding(16)
                        .frame(width: 250, height: 125, alignment: .topLeading)
                        .background(vm.selectedMode == mode ? Color.cyan.opacity(0.35) : Color.black.opacity(0.55))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(vm.selectedMode == mode ? Color.cyan : Color.white.opacity(0.2), lineWidth: 2))
                        .cornerRadius(14)
                    }
                }
            }

            HStack(spacing: 14) {
                Button("Kembali") { vm.screen = .mainMenu }
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(Color.white.opacity(0.16)).cornerRadius(10)

                Button("Lanjut Pilih Map →") { vm.screen = .selectMap }
                    .font(.subheadline.bold())
                    .foregroundColor(.black)
                    .padding(.horizontal, 22).padding(.vertical, 9)
                    .background(Color.cyan).cornerRadius(10)
            }
            .foregroundColor(.white)
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .cornerRadius(22)
    }

    private var selectMapView: some View {
        VStack(spacing: 16) {
            Text("TAHAP 2 : PILIH WILAYAH MAP NUSANTARA")
                .font(.headline.bold())
                .tracking(2)
                .foregroundColor(.cyan)

            HStack(spacing: 12) {
                ForEach(CityMapType.allCases) { m in
                    Button { vm.selectedMap = m } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(m.title).font(.headline.bold())
                            Text(m.difficultyLabel).font(.caption2.bold()).foregroundColor(.cyan)
                            Text(m.subtitle).font(.caption).multilineTextAlignment(.leading)
                        }
                        .foregroundColor(.white)
                        .padding(14)
                        .frame(width: 205, height: 135, alignment: .topLeading)
                        .background(vm.selectedMap == m ? Color.green.opacity(0.35) : Color.black.opacity(0.55))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(vm.selectedMap == m ? Color.green : Color.white.opacity(0.2), lineWidth: 2))
                        .cornerRadius(14)
                    }
                }
            }

            HStack(spacing: 14) {
                Button("← Mode") { vm.screen = .selectMode }
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(Color.white.opacity(0.16)).cornerRadius(10)

                Button("MULAI BANGUN KOTA") { vm.startCity() }
                    .font(.subheadline.bold())
                    .foregroundColor(.black)
                    .padding(.horizontal, 24).padding(.vertical, 9)
                    .background(Color.green).cornerRadius(10)
            }
            .foregroundColor(.white)
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .cornerRadius(22)
    }

    private var saveSlotsView: some View {
        VStack(spacing: 14) {
            Text("SAVE GAME SLOTS")
                .font(.headline.bold())
                .foregroundColor(.cyan)

            HStack(spacing: 12) {
                ForEach(1...3, id: \.self) { slot in
                    let snap = vm.slotSnapshot(slot)
                    VStack(alignment: .leading, spacing: 5) {
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
                                .padding(.vertical, 6)
                                .background(Color.cyan)
                                .cornerRadius(8)
                        } else {
                            Text("Kosong").font(.caption).foregroundColor(.gray)
                            Spacer()
                        }
                    }
                    .foregroundColor(.white)
                    .padding(12)
                    .frame(width: 185, height: 155, alignment: .topLeading)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(12)
                }
            }

            Button("Tutup") { vm.screen = .mainMenu }
                .foregroundColor(.white)
                .padding(.horizontal, 22).padding(.vertical, 8)
                .background(Color.white.opacity(0.16)).cornerRadius(10)
        }
        .padding(22)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
    }

    private var settingsView: some View {
        VStack(spacing: 12) {
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
            .padding(.horizontal, 22).padding(.vertical, 9)
            .background(Color.cyan).cornerRadius(10)
        }
        .foregroundColor(.white)
        .padding(22)
        .frame(width: 410)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
    }

    private var inGameSafeHUD: some View {
        GeometryReader { geo in
            let safeLeft = max(geo.safeAreaInsets.leading, 18)
            let safeRight = max(geo.safeAreaInsets.trailing, 18)
            let safeTop = max(geo.safeAreaInsets.top, 8)
            let safeBottom = max(geo.safeAreaInsets.bottom, 10)

            ZStack {
                if vm.hideHUDForPhoto {
                    VStack {
                        HStack {
                            Spacer()
                            Button { vm.hideHUDForPhoto = false } label: {
                                Label("Tampilkan UI", systemImage: "eye.fill")
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(12)
                            }
                        }
                        Spacer()
                    }
                    .padding(.top, safeTop)
                    .padding(.trailing, safeRight)
                } else {
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Button { vm.enterMainMenu() } label: {
                                    Image(systemName: "house.fill")
                                        .font(.caption.bold())
                                        .padding(6)
                                        .background(Color.white.opacity(0.14))
                                        .cornerRadius(7)
                                }
                                rciDemandMeter
                                compactStat(label: "APBD", value: IDRFormat.string(vm.budgetIDR), color: .green)
                                compactStat(label: "Warga", value: "\(vm.population)", color: .cyan)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .cornerRadius(14)

                            Spacer()

                            HStack(spacing: 9) {
                                compactStat(label: "MW", value: "\(vm.powerSupply)/\(vm.powerDemand)", color: vm.powerSupply >= vm.powerDemand ? .yellow : .red)
                                compactStat(label: "Air", value: "\(vm.waterSupply)/\(vm.waterDemand)", color: vm.waterSupply >= vm.waterDemand ? .blue : .red)

                                Button { vm.openAIChat() } label: {
                                    ZStack(alignment: .topTrailing) {
                                        Label("NUSA AI", systemImage: "bubble.left.and.sparkles.fill")
                                            .font(.caption2.bold())
                                            .foregroundColor(.black)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.cyan)
                                            .cornerRadius(8)

                                        if vm.unreadAINotifications > 0 {
                                            Text("\(vm.unreadAINotifications)")
                                                .font(.system(size: 9, weight: .black))
                                                .foregroundColor(.white)
                                                .padding(3.5)
                                                .background(Circle().fill(Color.red))
                                                .offset(x: 5, y: -5)
                                        }
                                    }
                                }

                                Button { vm.cycleTime() } label: {
                                    Image(systemName: vm.timePhase.icon)
                                        .font(.caption.bold())
                                        .foregroundColor(vm.timePhase == .night ? .yellow : .orange)
                                }
                                Button { vm.hideHUDForPhoto = true } label: {
                                    Image(systemName: "camera.fill").font(.caption.bold())
                                }
                                Button { vm.saveToSlot(1) } label: {
                                    Image(systemName: "square.and.arrow.down.fill").font(.caption.bold())
                                }
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .cornerRadius(14)
                        }
                        .foregroundColor(.white)

                        Button { vm.openAIChat() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles").font(.caption2).foregroundColor(.cyan)
                                Text(vm.aiAgentMessage)
                                    .font(.caption2.bold())
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Spacer()
                                Text("Chat →").font(.caption2.bold()).foregroundColor(.cyan)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.55))
                            .cornerRadius(8)
                        }

                        if let summary = vm.stagedSummary {
                            HStack(spacing: 10) {
                                Text(summary)
                                    .font(.caption.bold())
                                    .foregroundColor(.white)

                                Button { vm.confirmStagedBuild() } label: {
                                    Label("Bangun", systemImage: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 12).padding(.vertical, 5)
                                        .background(Color.green)
                                        .cornerRadius(8)
                                }

                                Button { vm.clearSelection() } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption.bold())
                                        .foregroundColor(.white)
                                        .padding(6)
                                        .background(Color.red.opacity(0.75))
                                        .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                        } else if let t = vm.toast {
                            Text(t)
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 12).padding(.vertical, 4)
                                .background(Color.blue.opacity(0.85))
                                .cornerRadius(10)
                        }

                        HStack(alignment: .top) {
                            if let card = vm.inspectCard {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(card.title).font(.caption.bold()).foregroundColor(.cyan)
                                        Spacer()
                                        Button { vm.inspectCard = nil } label: {
                                            Image(systemName: "xmark.circle.fill").font(.caption).foregroundColor(.gray)
                                        }
                                    }
                                    Text(card.subtitle).font(.caption2).foregroundColor(.gray)
                                    ForEach(card.details, id: \.self) { line in
                                        Text("• \(line)").font(.caption2).foregroundColor(.white)
                                    }
                                }
                                .padding(10)
                                .frame(width: 225)
                                .background(.ultraThinMaterial)
                                .cornerRadius(12)
                            }

                            Spacer()

                            VStack(spacing: 5) {
                                ForEach(CameraMode.allCases) { cm in
                                    Button { vm.switchCameraMode(cm) } label: {
                                        Image(systemName: cm.icon)
                                            .font(.caption.bold())
                                            .frame(width: 32, height: 32)
                                            .background(vm.cameraMode == cm ? Color.cyan.opacity(0.5) : Color.black.opacity(0.45))
                                            .cornerRadius(8)
                                    }
                                }
                                HStack(spacing: 4) {
                                    Button { vm.engine.orbitDualAxis(deltaYaw: -0.35, deltaPitch: 0) } label: {
                                        Image(systemName: "rotate.left.fill")
                                            .font(.caption.bold())
                                            .frame(width: 32, height: 32)
                                            .background(.ultraThinMaterial)
                                            .cornerRadius(8)
                                    }
                                    Button { vm.engine.orbitDualAxis(deltaYaw: 0.35, deltaPitch: 0) } label: {
                                        Image(systemName: "rotate.right.fill")
                                            .font(.caption.bold())
                                            .frame(width: 32, height: 32)
                                            .background(.ultraThinMaterial)
                                            .cornerRadius(8)
                                    }
                                }
                                HStack(spacing: 4) {
                                    Button { vm.engine.orbitDualAxis(deltaYaw: 0, deltaPitch: 0.14) } label: {
                                        Image(systemName: "arrow.up")
                                            .font(.caption.bold())
                                            .frame(width: 32, height: 32)
                                            .background(.ultraThinMaterial)
                                            .cornerRadius(8)
                                    }
                                    Button { vm.engine.orbitDualAxis(deltaYaw: 0, deltaPitch: -0.14) } label: {
                                        Image(systemName: "arrow.down")
                                            .font(.caption.bold())
                                            .frame(width: 32, height: 32)
                                            .background(.ultraThinMaterial)
                                            .cornerRadius(8)
                                    }
                                }
                            }
                            .foregroundColor(.white)
                        }

                        Spacer()

                        if vm.showSubTray && vm.activeCategory != .bulldoze {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 7) {
                                    if vm.activeCategory == .roads {
                                        ForEach(RoadKind.allCases) { k in
                                            subItemButton(title: k.title, price: k.costIDR, selected: vm.selRoad == k, badgeColor: .cyan) {
                                                vm.selRoad = k; vm.clearSelection()
                                            }
                                        }
                                    } else if vm.activeCategory == .zoning {
                                        ForEach(ZoneBrushKind.allCases) { z in
                                            let zCol: Color = z == .commercial ? .blue : (z == .industrialOffice ? .yellow : (z == .clearZone ? .red : .green))
                                            subItemButton(title: z.title, price: z.costIDR, selected: vm.selZoneBrush == z, badgeColor: zCol) {
                                                vm.selZoneBrush = z; vm.clearSelection()
                                            }
                                        }
                                    } else if vm.activeCategory == .facilities {
                                        ForEach(FacilityKind.allCases) { k in
                                            subItemButton(title: k.title, price: k.costIDR, selected: vm.selFacility == k, badgeColor: .cyan) {
                                                vm.selFacility = k
                                            }
                                        }
                                    } else if vm.activeCategory == .utilities {
                                        ForEach(UtilityKind.allCases) { u in
                                            subItemButton(title: u.title, price: u.costIDR, selected: vm.selUtility == u, badgeColor: .yellow) {
                                                vm.selUtility = u
                                            }
                                        }
                                    } else if vm.activeCategory == .gebrakans {
                                        Button {
                                            vm.draftedAIGebrakan = nil
                                            vm.showCustomGebrakanModal = true
                                        } label: {
                                            VStack(spacing: 1) {
                                                Text("✨ Buat Gebrakan AI").font(.caption2.bold()).foregroundColor(.black)
                                                Text("Tulis Kebijakan Sendiri").font(.system(size: 10)).foregroundColor(.black.opacity(0.8))
                                            }
                                            .padding(.horizontal, 11)
                                            .padding(.vertical, 5)
                                            .background(Color.cyan)
                                            .cornerRadius(8)
                                        }

                                        ForEach(GebrakanKind.allCases) { g in
                                            subItemButton(
                                                title: vm.activeGebrakans.contains(g) ? "✓ \(g.title)" : g.title,
                                                price: g.costIDR,
                                                selected: vm.activeGebrakans.contains(g),
                                                badgeColor: .purple
                                            ) { vm.triggerGebrakan(g) }
                                        }

                                        ForEach(vm.customGebrakans) { cg in
                                            subItemButton(
                                                title: "✓ \(cg.title)",
                                                price: 0,
                                                selected: true,
                                                badgeColor: .cyan
                                            ) { }
                                        }
                                    }
                                }
                                .padding(.horizontal, 6)
                            }
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                        }

                        HStack(spacing: 6) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(BuildCategory.allCases) { cat in
                                        Button { vm.selectCategory(cat) } label: {
                                            Label(cat.title, systemImage: cat.icon)
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 7)
                                                .background(vm.activeCategory == cat ? Color.blue : Color.white.opacity(0.14))
                                                .cornerRadius(9)
                                        }
                                    }
                                }
                            }

                            Button { vm.undoLastBuild() } label: {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.caption.bold())
                                    .padding(8)
                                    .background(Color.orange.opacity(0.65))
                                    .cornerRadius(9)
                            }
                        }
                        .foregroundColor(.white)
                        .padding(6)
                        .background(.ultraThinMaterial)
                        .cornerRadius(14)
                    }
                    .padding(.leading, safeLeft)
                    .padding(.trailing, safeRight)
                    .padding(.top, safeTop)
                    .padding(.bottom, safeBottom)
                }

                if vm.showCustomGebrakanModal {
                    customAIGebrakanModal
                }

                if vm.showAIChatDrawer {
                    nusaAIChatOverlay
                        .padding(.leading, safeLeft)
                        .padding(.trailing, safeRight)
                        .padding(.top, safeTop)
                        .padding(.bottom, safeBottom)
                }
            }
        }
    }

    private var customAIGebrakanModal: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("AI GEBRAKAN WALIKOTA", systemImage: "brain.head.profile")
                        .font(.headline.bold())
                        .foregroundColor(.cyan)
                    Spacer()
                    Button { vm.showCustomGebrakanModal = false } label: {
                        Image(systemName: "xmark.circle.fill").font(.title3).foregroundColor(.gray)
                    }
                }

                Text("Tuliskan kebijakan atau gebrakan apapun yang ingin kamu terapkan di kota ini. NUSA AI akan menganalisis anggaran & dampaknya:")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))

                HStack(spacing: 8) {
                    TextField("Contoh: Gratisin WiFi publik & bikin festival UMKM malam...", text: $vm.customGebrakanPrompt)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .foregroundColor(.black)

                    Button { vm.runCustomAIGebrakanAnalysis() } label: {
                        Text(vm.isAIThinkingGebrakan ? "Mikir..." : "Analisis AI")
                            .font(.caption.bold())
                            .foregroundColor(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.cyan)
                            .cornerRadius(8)
                    }
                    .disabled(vm.isAIThinkingGebrakan)
                }

                if vm.isAIThinkingGebrakan {
                    HStack(spacing: 8) {
                        ProgressView().tint(.cyan)
                        Text("NUSA AI sedang mikir keras menghitung dampak APBD, pajak & kebahagiaan warga...")
                            .font(.caption2)
                            .foregroundColor(.cyan)
                    }
                    .padding(.vertical, 6)
                } else if let draft = vm.draftedAIGebrakan {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("📋 \(draft.title)")
                            .font(.subheadline.bold())
                            .foregroundColor(.green)
                        Text(draft.aiReasoning)
                            .font(.caption2)
                            .foregroundColor(.white)
                        HStack(spacing: 12) {
                            Text("Biaya: \(IDRFormat.string(draft.costIDR))").font(.caption2.bold()).foregroundColor(.yellow)
                            Text("Bahagia: +\(draft.happinessDelta)%").font(.caption2.bold()).foregroundColor(.cyan)
                            Text("Pajak: +\(Int(draft.taxMultiplierBonus * 100))%").font(.caption2.bold()).foregroundColor(.green)
                        }
                        Button { vm.enactDraftedCustomGebrakan() } label: {
                            Label("Sahkan & Jalankan Gebrakan", systemImage: "checkmark.seal.fill")
                                .font(.caption.bold())
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.green)
                                .cornerRadius(9)
                        }
                        .padding(.top, 4)
                    }
                    .padding(10)
                    .background(Color.black.opacity(0.55))
                    .cornerRadius(12)
                }
            }
            .padding(18)
            .frame(width: 470)
            .background(.ultraThinMaterial)
            .cornerRadius(18)
        }
    }

    private var nusaAIChatOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { vm.showAIChatDrawer = false }

            VStack(spacing: 8) {
                HStack {
                    Label("NUSA AI • Asisten Walikota & Perizinan", systemImage: "bubble.left.and.sparkles.fill")
                        .font(.subheadline.bold())
                        .foregroundColor(.cyan)
                    Spacer()
                    Text(vm.weather.title)
                        .font(.caption2.bold())
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(6)
                    Button { vm.showAIChatDrawer = false } label: {
                        Image(systemName: "xmark.circle.fill").font(.title3).foregroundColor(.gray)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        quickChatChip("🌤️ Info Cuaca & Angin") { vm.sendUserChat("Info cuaca dan angin kota saat ini?") }
                        quickChatChip("📊 Laporan APBD & Warga") { vm.sendUserChat("Laporan kondisi kota & APBD saat ini?") }
                        quickChatChip("🏪 Cek Perizinan Investor") { vm.sendUserChat("Ada permohonan izin buka cabang baru?") }
                        quickChatChip("💡 Saran Pembangunan") { vm.sendUserChat("Apa saran pembangunan selanjutnya?") }
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(vm.chatMessages) { msg in
                            VStack(alignment: msg.isFromUser ? .trailing : .leading, spacing: 4) {
                                Text("\(msg.senderName) • \(msg.timestamp)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray)

                                Text(msg.text)
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .background(msg.isFromUser ? Color.blue.opacity(0.75) : Color.black.opacity(0.65))
                                    .cornerRadius(12)

                                if let permit = msg.permit {
                                    if !permit.resolved {
                                        HStack(spacing: 8) {
                                            Button { vm.respondToPermit(messageID: msg.id, approve: true) } label: {
                                                Label("Setujui Izin (+\(IDRFormat.string(permit.licenseFeeIDR)))", systemImage: "checkmark.circle.fill")
                                                    .font(.caption2.bold())
                                                    .foregroundColor(.black)
                                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                                    .background(Color.green)
                                                    .cornerRadius(8)
                                            }
                                            Button { vm.respondToPermit(messageID: msg.id, approve: false) } label: {
                                                Text("Tolak")
                                                    .font(.caption2.bold())
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                                    .background(Color.red.opacity(0.8))
                                                    .cornerRadius(8)
                                            }
                                        }
                                    } else {
                                        Text(permit.approved ? "Status: ✅ Izin Disetujui & Gerai Dibangun" : "Status: ❌ Izin Ditolak")
                                            .font(.caption2.bold())
                                            .foregroundColor(permit.approved ? .green : .red)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: msg.isFromUser ? .trailing : .leading)
                        }
                    }
                    .padding(.horizontal, 4)
                }

                HStack(spacing: 8) {
                    TextField("Tanya cuaca, laporan kota, atau perizinan...", text: $vm.chatInputText)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .foregroundColor(.black)

                    Button { vm.sendUserChat() } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.caption.bold())
                            .foregroundColor(.black)
                            .padding(9)
                            .background(Color.cyan)
                            .cornerRadius(9)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: 540, maxHeight: 310)
            .background(.ultraThinMaterial)
            .cornerRadius(18)
        }
    }

    private func quickChatChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.15))
                .cornerRadius(8)
        }
    }

    private var rciDemandMeter: some View {
        HStack(alignment: .bottom, spacing: 2) {
            RoundedRectangle(cornerRadius: 1.5).fill(Color.green).frame(width: 4, height: max(4, CGFloat(vm.rDemand) * 16))
            RoundedRectangle(cornerRadius: 1.5).fill(Color.blue).frame(width: 4, height: max(4, CGFloat(vm.cDemand) * 16))
            RoundedRectangle(cornerRadius: 1.5).fill(Color.yellow).frame(width: 4, height: max(4, CGFloat(vm.iDemand) * 16))
        }
    }

    private func compactStat(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.caption2).foregroundColor(.gray)
            Text(value).font(.caption2.bold()).foregroundColor(color)
        }
    }

    private func subItemButton(title: String, price: Int64, selected: Bool, badgeColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(title).font(.caption2.bold())
                Text(vm.selectedMode == .sandbox || price == 0 ? "Gratis" : IDRFormat.string(price))
                    .font(.system(size: 10))
                    .foregroundColor(badgeColor)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(selected ? badgeColor.opacity(0.32) : Color.black.opacity(0.60))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? badgeColor : Color.clear, lineWidth: 1.5))
            .cornerRadius(8)
        }
    }
}

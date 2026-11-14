import SwiftUI
import UIKit

// MARK: - 1. Router Layar Utama Aplikasi

struct RootGameContainerView: View {
    @ObservedObject var viewModel: GameSessionViewModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.screenState {
            case .bootLoading:
                BootLoadingView {
                    viewModel.completeBootLoading()
                }
                .transition(.opacity)

            case .studioLogo:
                StudioLogoView {
                    viewModel.completeStudioLogo()
                }
                .transition(.opacity)

            case .mainMenu:
                MainMenuView(viewModel: viewModel)
                    .transition(.opacity)

            case .modeSelection:
                ModeSelectionView(viewModel: viewModel)
                    .transition(.move(edge: .trailing))

            case .mapSelection:
                MapSelectionView(viewModel: viewModel)
                    .transition(.move(edge: .trailing))

            case .inGame:
                InGameHUDView(viewModel: viewModel)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: viewModel.screenState)
        .statusBar(hidden: true)
    }
}

// MARK: - 2. Animasi Loading Awal ("City Building : Nusantara Project")

struct BootLoadingView: View {
    let onFinished: () -> Void

    @State private var progress: CGFloat = 0.0
    @State private var titleOpacity: Double = 0.0
    @State private var titleScale: CGFloat = 0.92
    @State private var statusText: String = "Memuat Topografi Nusantara & Shader 3D..."

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.07, blue: 0.14),
                    Color(red: 0.08, green: 0.14, blue: 0.24),
                    Color(red: 0.03, green: 0.05, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "building.2.crop.circle.fill")
                    .font(.system(size: 54))
                    .foregroundColor(Color(red: 0.98, green: 0.76, blue: 0.28))
                    .shadow(color: Color.orange.opacity(0.55), radius: 16)

                VStack(spacing: 6) {
                    Text("CITY BUILDING")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .tracking(5)
                        .foregroundColor(Color(red: 0.98, green: 0.78, blue: 0.34))

                    Text("City Building : Nusantara Project")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }
                .opacity(titleOpacity)
                .scaleEffect(titleScale)

                VStack(spacing: 8) {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.14))
                            .frame(width: 320, height: 8)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.orange, Color.yellow],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 320 * progress, height: 8)
                    }

                    Text(statusText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                }
                .padding(.top, 8)
            }
            .padding()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                titleOpacity = 1.0
                titleScale = 1.0
            }
            withAnimation(.easeInOut(duration: 1.0)) {
                progress = 0.45
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                statusText = "Menyiapkan Vegetasi Detail & Sistem Dual-AI..."
                withAnimation(.easeInOut(duration: 1.1)) {
                    progress = 1.0
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                onFinished()
            }
        }
    }
}

// MARK: - 3. Animasi Logo Studio ("RG" - "Rizzi Games")

struct StudioLogoView: View {
    let onFinished: () -> Void

    @State private var badgeScale: CGFloat = 0.65
    @State private var badgeOpacity: Double = 0.0
    @State private var glowRadius: CGFloat = 4.0
    @State private var textOffset: CGFloat = 16.0

    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.04, blue: 0.08)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.96, green: 0.68, blue: 0.18),
                                    Color(red: 0.85, green: 0.28, blue: 0.22)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 96, height: 96)
                        .shadow(color: Color.orange.opacity(0.65), radius: glowRadius)

                    Text("RG")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                }
                .scaleEffect(badgeScale)
                .opacity(badgeOpacity)

                VStack(spacing: 4) {
                    Text("Rizzi Games")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .tracking(2)
                        .foregroundColor(.white)

                    Text("PRESENTS")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(4)
                        .foregroundColor(.white.opacity(0.6))
                }
                .opacity(badgeOpacity)
                .offset(y: textOffset)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.68)) {
                badgeScale = 1.0
                badgeOpacity = 1.0
                textOffset = 0.0
            }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                glowRadius = 22.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                onFinished()
            }
        }
    }
}

// MARK: - 4. Main Menu dengan Live 3D City Background

struct MainMenuView: View {
    @ObservedObject var viewModel: GameSessionViewModel

    @State private var showSettingsSheet = false
    @State private var showSaveLoadSheet = false
    @State private var showExitConfirmation = false

    var body: some View {
        ZStack {
            // Live 3D City Showcase Background
            City3DSceneView(controller: viewModel.engineController, isInteractive: false)
                .ignoresSafeArea()

            // Gradient gelap lembut agar tulisan & tombol tajam terbaca
            LinearGradient(
                colors: [
                    Color.black.opacity(0.45),
                    Color.black.opacity(0.20),
                    Color.black.opacity(0.75)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .ignoresSafeArea()

            VStack {
                // Bar Atas: Ikon Settings di Pojok Kiri Atas
                HStack {
                    Button {
                        showSettingsSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 18, weight: .bold))
                            Text("Settings")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.black.opacity(0.55))
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                    }

                    Spacer()

                    Text("RG • Rizzi Games")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer()

                // Konten Utama: Judul Game di Kiri & Tombol Start, Save Game, Exit di Samping Kanan
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NUSANTARA 3D CITY SIMULATOR")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(3)
                            .foregroundColor(Color(red: 0.98, green: 0.78, blue: 0.32))

                        Text("City Building :\nNusantara Project")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.8), radius: 8, x: 0, y: 3)

                        Text("Bangun kota Nusantara dari nol dengan sistem Dual-AI & grafis realistis.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(maxWidth: 340, alignment: .leading)
                    }

                    Spacer()

                    // Tombol Menu di Bagian Samping
                    VStack(spacing: 12) {
                        Button {
                            viewModel.screenState = .modeSelection
                        } label: {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Start")
                            }
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.black)
                            .frame(width: 210, height: 46)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 0.99, green: 0.80, blue: 0.30), Color.orange],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: Color.orange.opacity(0.45), radius: 10)
                        }

                        Button {
                            showSaveLoadSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill")
                                Text("Save Game")
                            }
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(width: 210, height: 42)
                            .background(Color.white.opacity(0.16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        Button {
                            showExitConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "power")
                                Text("Exit")
                            }
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(Color(red: 1.0, green: 0.52, blue: 0.52))
                            .frame(width: 210, height: 42)
                            .background(Color.red.opacity(0.18))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.red.opacity(0.45), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
            }
        }
        .sheet(isPresented: $showSettingsSheet) {
            GraphicsSettingsSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showSaveLoadSheet) {
            SaveGameManagerSheet(viewModel: viewModel, allowSaveCurrent: false)
        }
        .alert("Keluar dari Game?", isPresented: $showExitConfirmation) {
            Button("Batal", role: .cancel) {}
            Button("Keluar", role: .destructive) {
                exit(0)
            }
        } message: {
            Text("Apakah Anda yakin ingin menutup City Building : Nusantara Project?")
        }
    }
}

// MARK: - 5. Pemilihan Mode Permainan (Sandbox vs Real Mode Easy/Medium/Hard)

struct ModeSelectionView: View {
    @ObservedObject var viewModel: GameSessionViewModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.08, blue: 0.15),
                    Color(red: 0.09, green: 0.14, blue: 0.24)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                // Header Navigasi
                HStack {
                    Button {
                        viewModel.screenState = .mainMenu
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Menu Utama")
                        }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.14))
                        .clipShape(Capsule())
                    }

                    Spacer()

                    Text("LANGKAH 1 DARI 2 • PILIH MODE PERMAINAN")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(2)
                        .foregroundColor(Color(red: 0.98, green: 0.78, blue: 0.34))

                    Spacer()

                    Button {
                        viewModel.screenState = .mapSelection
                    } label: {
                        HStack(spacing: 6) {
                            Text("Pilih Peta")
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.orange)
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)

                // Kartu Pilihan Mode Sandbox & Real
                HStack(spacing: 16) {
                    // Sandbox Mode
                    Button {
                        viewModel.selectedMode = .sandbox
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "infinity.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.cyan)
                                Spacer()
                                if viewModel.selectedMode == .sandbox {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 22))
                                }
                            }

                            Text("Sandbox Mode")
                                .font(.system(size: 20, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)

                            Text("Uang Unlimited (Tak Terbatas)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.cyan)

                            Text(GameMode.sandbox.subtitle)
                                .font(.system(size: 12, design: .rounded))
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.leading)

                            Spacer()
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(viewModel.selectedMode == .sandbox ? Color.cyan.opacity(0.18) : Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(viewModel.selectedMode == .sandbox ? Color.cyan : Color.white.opacity(0.18), lineWidth: 2)
                        )
                    }

                    // Real Mode (Easy, Medium, Hard)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.orange)
                            Spacer()
                            if viewModel.selectedMode == .real {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 22))
                            }
                        }

                        Text("Real Mode (Walikota Sejati)")
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)

                        Text(GameMode.real.subtitle)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))

                        // Pemilih Tingkat Kesulitan: Easy, Medium, Hard
                        HStack(spacing: 8) {
                            ForEach(RealDifficulty.allCases) { diff in
                                Button {
                                    viewModel.selectedMode = .real
                                    viewModel.selectedDifficulty = diff
                                } label: {
                                    VStack(spacing: 3) {
                                        Text(diff.rawValue)
                                            .font(.system(size: 13, weight: .bold, design: .rounded))
                                        Text(IDRFormatter.format(diff.startingBudgetIDR))
                                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    }
                                    .foregroundColor(
                                        viewModel.selectedMode == .real && viewModel.selectedDifficulty == diff
                                            ? .black : .white
                                    )
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        viewModel.selectedMode == .real && viewModel.selectedDifficulty == diff
                                            ? Color.orange : Color.white.opacity(0.12)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                        }

                        Text(viewModel.selectedDifficulty.description)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.orange.opacity(0.95))

                        Spacer()
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(viewModel.selectedMode == .real ? Color.orange.opacity(0.18) : Color.white.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(viewModel.selectedMode == .real ? Color.orange : Color.white.opacity(0.18), lineWidth: 2)
                    )
                    .onTapGesture {
                        viewModel.selectedMode = .real
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
            }
        }
    }
}

// MARK: - 6. Pemilihan Peta Topografi Nusantara (Malang, Surabaya, Jakarta)

struct MapSelectionView: View {
    @ObservedObject var viewModel: GameSessionViewModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.09, blue: 0.14),
                    Color(red: 0.06, green: 0.15, blue: 0.20)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                HStack {
                    Button {
                        viewModel.screenState = .modeSelection
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Kembali")
                        }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.14))
                        .clipShape(Capsule())
                    }

                    Spacer()

                    Text("LANGKAH 2 DARI 2 • PILIH PETA KOTA NUSANTARA")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(2)
                        .foregroundColor(Color(red: 0.45, green: 0.92, blue: 0.65))

                    Spacer()

                    Button {
                        viewModel.startNewCitySession()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "flag.checkered")
                            Text("Mulai Memimpin")
                        }
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.green)
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)

                HStack(spacing: 14) {
                    ForEach(NusantaraCityMap.allCases) { city in
                        let isSelected = viewModel.selectedMap == city
                        Button {
                            viewModel.selectedMap = city
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: city == .malang ? "mountain.2.fill" : "water.waves")
                                        .font(.system(size: 24))
                                        .foregroundColor(isSelected ? .green : .white.opacity(0.75))
                                    Spacer()
                                    Text("0% Lahan Kosong")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.white.opacity(0.14))
                                        .clipShape(Capsule())
                                        .foregroundColor(.white)
                                }

                                Text(city.displayName)
                                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.leading)

                                Text(city.subtitle)
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundColor(.white.opacity(0.8))
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(3)

                                Spacer()

                                VStack(alignment: .leading, spacing: 4) {
                                    Label(city.iconicLandmarkName, systemImage: "mappin.and.ellipse")
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundColor(.yellow)

                                    Label("Vegetasi: \(city.defaultTreeSpecies.shortName)", systemImage: "leaf.fill")
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(isSelected ? Color.green.opacity(0.20) : Color.white.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(isSelected ? Color.green : Color.white.opacity(0.18), lineWidth: 2)
                            )
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
            }
        }
    }
}

// MARK: - 7. Layar Permainan Utama (3D Viewport + HUD Ala TheoTown + Dual-AI)

struct InGameHUDView: View {
    @ObservedObject var viewModel: GameSessionViewModel

    @State private var showGebrakanSheet = false
    @State private var showAIAgentSheet = false
    @State private var showSaveSheet = false
    @State private var showSettingsSheet = false
    @State private var showExitToMenuAlert = false

    var body: some View {
        ZStack {
            // 1. Dunia 3D Interaktif Penuh
            City3DSceneView(controller: viewModel.engineController, isInteractive: true)
                .ignoresSafeArea()

            // 2. Overlay HUD Walikota
            VStack(spacing: 0) {
                topStatusBar

                // Banner Peringatan Demo Warga (Jika Ada Demonstrasi Aktif)
                if let activeProtest = viewModel.protests.first(where: { !$0.resolved }) {
                    protestAlertBanner(protest: activeProtest)
                        .padding(.horizontal, 14)
                        .padding(.top, 6)
                }

                // Toast Notifikasi Pembangunan / AI
                if let toast = viewModel.statusToastMessage {
                    Text(toast)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.75))
                        .clipShape(Capsule())
                        .padding(.top, 6)
                }

                Spacer()

                // Baris Tengah: Pikiran NPC Warga (Kiri) & Tombol Dual-AI (Kanan)
                HStack(alignment: .bottom) {
                    citizenThoughtsFeed
                    Spacer()
                    dualAIActionButtons
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

                // Bar Bawah: Toolbar Pembangunan Ala TheoTown
                bottomBuildToolbar
            }
        }
        .sheet(isPresented: $showGebrakanSheet) {
            GebrakanWalikotaSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showAIAgentSheet) {
            AIAgentAssistantSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showSaveSheet) {
            SaveGameManagerSheet(viewModel: viewModel, allowSaveCurrent: true)
        }
        .sheet(isPresented: $showSettingsSheet) {
            GraphicsSettingsSheet(viewModel: viewModel)
        }
        .alert("Kembali ke Main Menu?", isPresented: $showExitToMenuAlert) {
            Button("Batal", role: .cancel) {}
            Button("Simpan & Keluar") {
                viewModel.saveCurrentGame(customName: nil)
                viewModel.returnToMainMenu()
            }
            Button("Keluar Tanpa Simpan", role: .destructive) {
                viewModel.returnToMainMenu()
            }
        } message: {
            Text("Pastikan progres pembangunan kota sudah tersimpan sebelum keluar.")
        }
    }

    // MARK: Top HUD Bar Ala TheoTown
    private var topStatusBar: some View {
        HStack(spacing: 10) {
            // Identitas Kota & Waktu
            HStack(spacing: 6) {
                Image(systemName: "building.columns.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text(viewModel.selectedMap.displayName)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text("Hari ke-\(viewModel.stats.dayCount) • \(viewModel.stats.formattedTimeString)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.68))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Indikator Statistik Kota
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    statChip(
                        icon: "banknote.fill",
                        color: .green,
                        value: viewModel.selectedMode == .sandbox ? "Unlimited" : IDRFormatter.format(viewModel.stats.budgetIDR)
                    )
                    statChip(
                        icon: "person.3.fill",
                        color: .cyan,
                        value: "\(viewModel.stats.population) Warga"
                    )
                    statChip(
                        icon: viewModel.stats.happinessPercent >= 60 ? "face.smiling.fill" : "exclamationmark.triangle.fill",
                        color: viewModel.stats.happinessPercent >= 60 ? .yellow : .red,
                        value: "\(Int(viewModel.stats.happinessPercent))%"
                    )
                    statChip(
                        icon: "bolt.fill",
                        color: viewModel.stats.powerSupplyMW >= viewModel.stats.powerDemandMW ? .yellow : .red,
                        value: "\(viewModel.stats.powerSupplyMW)/\(viewModel.stats.powerDemandMW) MW"
                    )
                    statChip(
                        icon: "drop.fill",
                        color: viewModel.stats.waterSupplyML >= viewModel.stats.waterDemandML ? .blue : .red,
                        value: "\(viewModel.stats.waterSupplyML)/\(viewModel.stats.waterDemandML) ML"
                    )
                    statChip(
                        icon: "graduationcap.fill",
                        color: .purple,
                        value: "SDM \(Int(viewModel.stats.educationIndex))%"
                    )
                }
            }

            // Kontrol Cepat: Mode Malam Cozy, Save, Settings, Menu
            HStack(spacing: 6) {
                Button {
                    viewModel.toggleCozyNightMode()
                } label: {
                    Image(systemName: (viewModel.settings.lockNightCozyMode || viewModel.stats.isNightTime) ? "moon.stars.fill" : "sun.max.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.yellow)
                        .frame(width: 32, height: 32)
                        .background(Color.black.opacity(0.68))
                        .clipShape(Circle())
                }

                Button {
                    showSaveSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.black.opacity(0.68))
                        .clipShape(Circle())
                }

                Button {
                    showSettingsSheet = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.black.opacity(0.68))
                        .clipShape(Circle())
                }

                Button {
                    showExitToMenuAlert = true
                } label: {
                    Image(systemName: "house.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.orange)
                        .frame(width: 32, height: 32)
                        .background(Color.black.opacity(0.68))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private func statChip(icon: String, color: Color, value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.68))
        .clipShape(Capsule())
    }

    // MARK: Banner Demo Warga
    private func protestAlertBanner(protest: CitizenProtest) -> some View {
        Button {
            viewModel.focusOnCoord(protest.location)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "megaphone.fill")
                    .foregroundColor(.yellow)
                Text("DEMO WARGA (\(protest.crowdCount) Orang): \(protest.demandMessage)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
                Text("Lihat Lokasi")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.yellow)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.red.opacity(0.88))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: Feed Pikiran NPC Real-Time
    private var citizenThoughtsFeed: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(viewModel.citizenThoughts.prefix(2)) { thought in
                Button {
                    viewModel.focusOnCoord(thought.coord)
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(thought.moodPositive ? Color.green : Color.red)
                            .frame(width: 7, height: 7)
                        Text("\(thought.citizenName) (\(thought.role)):")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundColor(.yellow)
                        Text("\"\(thought.thoughtText)\"")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: 380, alignment: .leading)
    }

    // MARK: Tombol Dual-AI (Gebrakan Walikota & AI Agent)
    private var dualAIActionButtons: some View {
        let pendingPermits = viewModel.permitRequests.filter { $0.isApproved == nil }.count
        let alertCount = viewModel.aiAlerts.count + pendingPermits

        return VStack(alignment: .trailing, spacing: 8) {
            // Tombol Gebrakan Walikota
            Button {
                showGebrakanSheet = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                    Text("Gebrakan Walikota")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.99, green: 0.82, blue: 0.30), Color.orange],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
                .shadow(color: Color.orange.opacity(0.5), radius: 8)
            }

            // Tombol AI Agent (Asisten & Perizinan)
            Button {
                showAIAgentSheet = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 14, weight: .bold))
                    Text("AI Agent")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                    if alertCount > 0 {
                        Text("\(alertCount)")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color(red: 0.12, green: 0.24, blue: 0.46).opacity(0.92))
                .overlay(
                    Capsule().stroke(Color.cyan.opacity(0.65), lineWidth: 1.5)
                )
                .clipShape(Capsule())
            }
        }
    }

    // MARK: Toolbar Pembangunan Bawah Ala TheoTown
    private var bottomBuildToolbar: some View {
        VStack(spacing: 6) {
            // Pilihan Item Spesifik Sesuai Kategori Aktif
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    switch viewModel.selectedCategory {
                    case .roads:
                        ForEach(RoadType.allCases) { road in
                            buildItemButton(
                                title: road.shortLabel,
                                cost: road.buildCostIDR,
                                isSelected: viewModel.selectedRoadType == road
                            ) {
                                viewModel.selectedRoadType = road
                            }
                        }

                    case .zones:
                        let zoneItems: [StructureType] = [.residentialHouse, .commercialShop, .cityHall, .cityPark]
                        ForEach(zoneItems) { item in
                            buildItemButton(
                                title: item.displayName,
                                cost: item.buildCostIDR,
                                isSelected: viewModel.selectedStructureType == item
                            ) {
                                viewModel.selectedStructureType = item
                            }
                        }

                    case .utilities:
                        let utilItems: [StructureType] = [.powerPlantPLN, .waterPlantPDAM]
                        ForEach(utilItems) { item in
                            buildItemButton(
                                title: item.displayName,
                                cost: item.buildCostIDR,
                                isSelected: viewModel.selectedStructureType == item
                            ) {
                                viewModel.selectedStructureType = item
                            }
                        }

                    case .education:
                        let eduItems: [StructureType] = [.eduSD, .eduSMP, .eduSMA, .eduUniversitas]
                        ForEach(eduItems) { item in
                            buildItemButton(
                                title: item.displayName,
                                cost: item.buildCostIDR,
                                isSelected: viewModel.selectedStructureType == item
                            ) {
                                viewModel.selectedStructureType = item
                            }
                        }

                    case .trees:
                        ForEach(viewModel.selectedMap.availableTrees) { tree in
                            buildItemButton(
                                title: "Tanam \(tree.shortName) di Trotoar",
                                cost: tree.buildCostIDR,
                                isSelected: viewModel.selectedTreeSpecies == tree
                            ) {
                                viewModel.selectedTreeSpecies = tree
                            }
                        }

                    case .bulldoze:
                        Text("Ketuk jalan atau bangunan di peta 3D untuk membongkarnya.")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.75))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 14)
            }

            // Tab Kategori Utama
            HStack(spacing: 8) {
                ForEach(BuildToolCategory.allCases) { category in
                    let active = viewModel.selectedCategory == category
                    Button {
                        viewModel.selectedCategory = category
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: category.systemIcon)
                                .font(.system(size: 12, weight: .bold))
                            Text(category.rawValue)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(active ? .black : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(active ? Color.orange : Color.black.opacity(0.72))
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func buildItemButton(title: String, cost: Int64, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(isSelected ? .black : .white)
                Text(viewModel.selectedMode == .sandbox ? "Gratis (Sandbox)" : IDRFormatter.format(cost))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(isSelected ? .black.opacity(0.75) : .green)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(isSelected ? Color.yellow : Color.black.opacity(0.75))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.orange : Color.white.opacity(0.2), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

// MARK: - 8. Modal Menu Gebrakan Walikota (Perencana Ide Bebas Otomatis)

struct GebrakanWalikotaSheet: View {
    @ObservedObject var viewModel: GameSessionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var ideaInput: String = ""

    private let quickIdeas = [
        "Bikin wisata kampung rumah warna-warni di tepi sungai",
        "Jadikan Gunung Arjuno sebagai wisata pendakian mulai dari basecamp sampai jalur puncak",
        "Bangun kawasan kuliner malam cozy dengan lampu kota & jalur sepeda",
        "Dirikan kawasan kampus universitas terpadu & taman literasi"
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Ketik visi atau gebrakan bebas apa pun. AI Strategic Planner akan memindai peta, memilih lokasi terbaik, dan menyusun blueprint pembangunannya secara otomatis.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary)

                    // Input Ide Bebas
                    HStack {
                        TextField("Contoh: Bikin wisata pendakian Gunung Arjuno...", text: $ideaInput)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        Button {
                            guard !ideaInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            viewModel.generateGebrakanDraft(ideaPrompt: ideaInput)
                        } label: {
                            Text("Rancang AI")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.black)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }

                    // Inspirasi Cepat
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(quickIdeas, id: \.self) { sample in
                                Button {
                                    ideaInput = sample
                                    viewModel.generateGebrakanDraft(ideaPrompt: sample)
                                } label: {
                                    Text(sample)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundColor(.primary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.orange.opacity(0.16))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    // Hasil Analisis & Blueprint dari AI
                    if let plan = viewModel.draftGebrakanPlan {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(plan.projectTitle)
                                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                                Spacer()
                                Text(viewModel.selectedMode == .sandbox ? "Sandbox Gratis" : IDRFormatter.format(plan.totalBudgetIDR))
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(.green)
                            }

                            Text("Lokasi Terpilih AI: \(plan.selectedZoneName)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.orange)

                            Text(plan.aiSpatialAnalysis)
                                .font(.system(size: 12, design: .rounded))
                                .padding(10)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            Text("Tahapan Blueprint Otomatis:")
                                .font(.system(size: 13, weight: .bold, design: .rounded))

                            ForEach(plan.steps) { step in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(step.stepNumber)")
                                        .font(.system(size: 11, weight: .black, design: .rounded))
                                        .foregroundColor(.white)
                                        .frame(width: 22, height: 22)
                                        .background(Color.orange)
                                        .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(step.title)
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                        Text(step.technicalDetail)
                                            .font(.system(size: 11, design: .rounded))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            Button {
                                viewModel.executeGebrakanPlan(plan)
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "hammer.fill")
                                    Text("Setujui & Eksekusi Blueprint ke Kota 3D")
                                }
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.green)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .padding(.top, 6)
                        }
                        .padding(14)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding()
            }
            .navigationTitle("Gebrakan Walikota (AI Planner)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Tutup") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 9. Modal AI Agent (Asisten Kota & Perizinan Swasta seperti Indomaret)

struct AIAgentAssistantSheet: View {
    @ObservedObject var viewModel: GameSessionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: Int = 0

    var body: some View {
        NavigationView {
            VStack(spacing: 10) {
                Picker("Mode AI Agent", selection: $selectedTab) {
                    Text("Asisten & Solusi Kota (\(viewModel.aiAlerts.count))").tag(0)
                    Text("Perizinan Swasta (\(viewModel.permitRequests.filter { $0.isApproved == nil }.count))").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)

                ScrollView {
                    if selectedTab == 0 {
                        VStack(spacing: 10) {
                            ForEach(viewModel.aiAlerts) { alert in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(alert.severity.rawValue)
                                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(alert.severity == .critical ? Color.red : Color.blue)
                                            .clipShape(Capsule())
                                        Spacer()
                                    }

                                    Text(alert.title)
                                        .font(.system(size: 14, weight: .bold, design: .rounded))

                                    Text(alert.diagnosis)
                                        .font(.system(size: 12, design: .rounded))
                                        .foregroundColor(.secondary)

                                    Text("Saran AI Agent: \(alert.suggestedAction)")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(.primary)

                                    if let fix = alert.quickFixStructure {
                                        Button {
                                            viewModel.triggerQuickFix(from: alert)
                                            dismiss()
                                        } label: {
                                            Text("Pilih Alat Bangun: \(fix.displayName)")
                                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                                .foregroundColor(.black)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Color.orange)
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                                .padding(12)
                                .background(Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                        .padding(.horizontal)
                    } else {
                        let pending = viewModel.permitRequests.filter { $0.isApproved == nil }
                        if pending.isEmpty {
                            Text("Belum ada pengajuan izin swasta baru. Bangun lebih banyak jalan dan permukiman untuk menarik investor seperti Indomaret.")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(.secondary)
                                .padding()
                        } else {
                            VStack(spacing: 12) {
                                ForEach(pending) { permit in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(permit.applicantName)
                                            .font(.system(size: 15, weight: .heavy, design: .rounded))

                                        Text("Lokasi Usulan: Koordinat (\(permit.proposedCoord.x), \(permit.proposedCoord.z)) • Pajak: \(IDRFormatter.format(permit.taxRevenuePerMonthIDR))/bln • +\(permit.jobsCreated) Kerja")
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .foregroundColor(.orange)

                                        Text("Analisis Pro: \(permit.aiAgentPros)")
                                            .font(.system(size: 12, design: .rounded))
                                            .foregroundColor(.green)

                                        Text("Analisis Kontra: \(permit.aiAgentCons)")
                                            .font(.system(size: 12, design: .rounded))
                                            .foregroundColor(.red)

                                        Text("Rekomendasi AI Agent: \(permit.aiRecommendation)")
                                            .font(.system(size: 11, weight: .bold, design: .rounded))

                                        HStack(spacing: 10) {
                                            Button {
                                                viewModel.decidePermit(permit, approved: true)
                                            } label: {
                                                Text("Setujui Izin & Bangun")
                                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                                    .foregroundColor(.black)
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 8)
                                                    .background(Color.green)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                            }

                                            Button {
                                                viewModel.decidePermit(permit, approved: false)
                                            } label: {
                                                Text("Tolak Izin")
                                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                                    .foregroundColor(.white)
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 8)
                                                    .background(Color.red)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                            }
                                        }
                                    }
                                    .padding(12)
                                    .background(Color.secondary.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .navigationTitle("AI Agent • Asisten Walikota")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Tutup") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 10. Modal Pengaturan Grafik & Audio (Settings)

struct GraphicsSettingsSheet: View {
    @ObservedObject var viewModel: GameSessionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Kualitas Visual & Realisme")) {
                    Picker("Preset Grafik", selection: $viewModel.settings.qualityPreset) {
                        ForEach(GraphicsQualityPreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }

                    Toggle("Angin & Daun Gugur Realistis", isOn: $viewModel.settings.enableWindAndFallingLeaves)
                    Toggle("Cozy City Lights (Lampu Malam Kota)", isOn: $viewModel.settings.enableCozyNightLights)
                    Toggle("Kunci Suasana Malam Cozy Permanen", isOn: $viewModel.settings.lockNightCozyMode)
                    Toggle("Bayangan Dinamis Real-Time", isOn: $viewModel.settings.enableDynamicShadows)
                }

                Section(header: Text("Populasi Jalanan & Audio")) {
                    VStack(alignment: .leading) {
                        Text("Kepadatan Pemotor, Mobil & Pejalan Kaki: \(Int(viewModel.settings.trafficDensity * 100))%")
                            .font(.caption)
                        Slider(value: $viewModel.settings.trafficDensity, in: 0.2...1.0)
                    }

                    VStack(alignment: .leading) {
                        Text("Volume Musik Malam & Ambien Kota: \(Int(viewModel.settings.soundVolume * 100))%")
                            .font(.caption)
                        Slider(value: $viewModel.settings.soundVolume, in: 0.0...1.0)
                    }
                }
            }
            .navigationTitle("Settings Grafik & Kota")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Terapkan") {
                        viewModel.applyGraphicsSettings()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 11. Modal Save & Load Game

struct SaveGameManagerSheet: View {
    @ObservedObject var viewModel: GameSessionViewModel
    let allowSaveCurrent: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var saveSlotName: String = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                if allowSaveCurrent {
                    HStack {
                        TextField("Nama simpanan kota (opsional)...", text: $saveSlotName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        Button("Simpan Kota") {
                            viewModel.saveCurrentGame(customName: saveSlotName.isEmpty ? nil : saveSlotName)
                            saveSlotName = ""
                        }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.green)
                        .foregroundColor(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .padding(.horizontal)
                }

                if viewModel.savedGames.isEmpty {
                    Spacer()
                    Text("Belum ada data simpanan kota.")
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    List {
                        ForEach(viewModel.savedGames) { save in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(save.saveTitle)
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                    Text("\(save.cityMap.displayName) • \(save.gameMode.rawValue) • \(save.stats.population) Warga")
                                        .font(.system(size: 11, design: .rounded))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Button("Muat") {
                                    viewModel.loadSavedGame(save)
                                    dismiss()
                                }
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.orange)
                                .foregroundColor(.black)
                                .clipShape(Capsule())
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                viewModel.deleteSavedGame(viewModel.savedGames[index])
                            }
                        }
                    }
                }
            }
            .navigationTitle("Save & Load Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Tutup") { dismiss() }
                }
            }
        }
    }
}

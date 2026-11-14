import SwiftUI
import SceneKit
import SceneKit.ModelIO
import ModelIO
import AVFoundation
import UIKit

// MARK: - Controller Utama Engine 3D SceneKit & Audio

@MainActor
final class City3DEngineController: ObservableObject {

    let scene = SCNScene()

    // Konfigurasi Skala Dunia Luas (64x64 Grid x 4.0 unit = 256x256 meter virtual)
    let gridDimension: Int = 64
    let cellSize: Float = 4.0

    // Node Hierarki Dunia 3D
    private let terrainContainer = SCNNode()
    private let waterContainer = SCNNode()
    private let wildNatureContainer = SCNNode()
    private let roadsContainer = SCNNode()
    private let structuresContainer = SCNNode()
    private let trafficContainer = SCNNode()
    private let protestsContainer = SCNNode()

    // Pencahayaan Dinamis Siang - Senja - Malam Cozy
    private let sunLightNode = SCNNode()
    private let ambientLightNode = SCNNode()
    private let cameraPivotNode = SCNNode()
    private let cameraNode = SCNNode()

    // Cache Aset & Heightmap
    private var heightGrid: [[Float]] = Array(repeating: Array(repeating: 0.0, count: 64), count: 64)
    private var activeMap: NusantaraCityMap = .malang
    private var modelCache: [String: SCNNode] = [:]
    private var textureCache: [String: UIImage] = [:]

    // Tracking State Terpasang agar Update 3D Efisien
    private var renderedRoadIDs: Set<UUID> = []
    private var renderedRoadTreeMap: [UUID: TreeSpecies?] = [:]
    private var renderedStructureIDs: Set<UUID> = []
    private var renderedProtestIDs: Set<UUID> = []
    private var activeRoads: [PlacedRoad] = []

    // Kamera & Interaksi
    var onGridTapped: ((GridCoord) -> Void)?
    private var isMenuShowcase: Bool = false
    private var cameraTarget = SCNVector3(128, 4, 128)
    private var cameraDistance: Float = 62.0
    private var cameraYaw: Float = 0.65
    private var cameraPitch: Float = 0.62

    // Audio Ambien & SFX
    private var bgmPlayer: AVAudioPlayer?
    private var sfxPlayer: AVAudioPlayer?
    private var currentAudioTrack: String = ""

    init() {
        setupSceneLightingAndCamera()
        scene.rootNode.addChildNode(terrainContainer)
        scene.rootNode.addChildNode(waterContainer)
        scene.rootNode.addChildNode(wildNatureContainer)
        scene.rootNode.addChildNode(roadsContainer)
        scene.rootNode.addChildNode(structuresContainer)
        scene.rootNode.addChildNode(trafficContainer)
        scene.rootNode.addChildNode(protestsContainer)
    }

    // =========================================================================
    // 1. SETUP PENCAHAYAAN & KAMERA 3D
    // =========================================================================

    private func setupSceneLightingAndCamera() {
        // Directional Sun / Moon Light dengan bayangan lembut
        let sunLight = SCNLight()
        sunLight.type = .directional
        sunLight.color = UIColor(red: 1.0, green: 0.95, blue: 0.88, alpha: 1.0)
        sunLight.intensity = 1050
        sunLight.castsShadow = true
        sunLight.shadowMode = .deferred
        sunLight.shadowSampleCount = 4
        sunLight.shadowRadius = 3.0
        sunLight.shadowColor = UIColor.black.withAlphaComponent(0.45)
        sunLightNode.light = sunLight
        sunLightNode.eulerAngles = SCNVector3(-0.85, 0.55, 0)
        scene.rootNode.addChildNode(sunLightNode)

        // Ambient Sky & City Glow
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(red: 0.55, green: 0.65, blue: 0.82, alpha: 1.0)
        ambient.intensity = 420
        ambientLightNode.light = ambient
        scene.rootNode.addChildNode(ambientLightNode)

        // Kamera Perspektif
        let camera = SCNCamera()
        camera.zNear = 0.5
        camera.zFar = 650.0
        camera.fieldOfView = 48.0
        camera.wantsHDR = true
        camera.bloomIntensity = 0.65
        camera.bloomThreshold = 0.82
        camera.bloomBlurRadius = 8.0
        cameraNode.camera = camera

        cameraPivotNode.position = cameraTarget
        cameraPivotNode.addChildNode(cameraNode)
        scene.rootNode.addChildNode(cameraPivotNode)
        updateCameraTransform()
    }

    func updateCameraTransform() {
        let horizontalDist = cameraDistance * cos(cameraPitch)
        let verticalDist = cameraDistance * sin(cameraPitch)
        let camX = sin(cameraYaw) * horizontalDist
        let camZ = cos(cameraYaw) * horizontalDist

        cameraPivotNode.position = cameraTarget
        cameraNode.position = SCNVector3(camX, verticalDist, camZ)
        cameraNode.look(at: cameraTarget)
    }

    func panCamera(deltaX: Float, deltaZ: Float) {
        let forwardX = -sin(cameraYaw)
        let forwardZ = -cos(cameraYaw)
        let rightX = cos(cameraYaw)
        let rightZ = -sin(cameraYaw)

        let speed = max(0.08, cameraDistance * 0.0045)
        let moveX = (rightX * -deltaX + forwardX * deltaZ) * speed
        let moveZ = (rightZ * -deltaX + forwardZ * deltaZ) * speed

        let maxWorld = Float(gridDimension) * cellSize - 16.0
        cameraTarget.x = max(16.0, min(maxWorld, cameraTarget.x + moveX))
        cameraTarget.z = max(16.0, min(maxWorld, cameraTarget.z + moveZ))
        let gx = Int(cameraTarget.x / cellSize)
        let gz = Int(cameraTarget.z / cellSize)
        cameraTarget.y = sampleElevation(gridX: gx, gridZ: gz)
        updateCameraTransform()
    }

    func zoomCamera(scale: Float) {
        cameraDistance = max(16.0, min(155.0, cameraDistance / scale))
        updateCameraTransform()
    }

    func rotateCamera(angleDelta: Float) {
        cameraYaw += angleDelta
        updateCameraTransform()
    }

    func focusCamera(on coord: GridCoord) {
        let wx = (Float(coord.x) + 0.5) * cellSize
        let wz = (Float(coord.z) + 0.5) * cellSize
        let wy = sampleElevation(gridX: coord.x, gridZ: coord.z)
        cameraTarget = SCNVector3(wx, wy, wz)
        cameraDistance = 38.0
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.65
        updateCameraTransform()
        SCNTransaction.commit()
    }

    // =========================================================================
    // 2. PEMUATAN PETA TOPOGRAFI NUSANTARA & VEGETASI ALAMI AWAL
    // =========================================================================

    func loadMap(_ map: NusantaraCityMap, isShowcaseMenu: Bool) {
        self.activeMap = map
        self.isMenuShowcase = isShowcaseMenu

        // Bersihkan seluruh node lama
        [terrainContainer, waterContainer, wildNatureContainer,
         roadsContainer, structuresContainer, trafficContainer, protestsContainer].forEach { container in
            container.childNodes.forEach { $0.removeFromParentNode() }
        }
        renderedRoadIDs.removeAll()
        renderedRoadTreeMap.removeAll()
        renderedStructureIDs.removeAll()
        renderedProtestIDs.removeAll()
        activeRoads.removeAll()

        buildTopographicTerrain(for: map)
        buildWaterPlane(for: map)
        populateNaturalWildTrees(for: map)

        if isShowcaseMenu {
            buildMainMenuShowcaseDiorama(for: map)
        } else {
            let center = GridCoord(x: 32, z: 32)
            focusCamera(on: center)
        }
    }

    private func buildTopographicTerrain(for map: NusantaraCityMap) {
        let size = gridDimension
        heightGrid = Array(repeating: Array(repeating: 0.0, count: size), count: size)

        if let img = loadTextureImage(named: map.heightmapResourceName, subdirectory: "GameAssets/Maps"),
           let cgImg = img.cgImage,
           let provider = cgImg.dataProvider,
           let rawData = provider.data,
           let ptr = CFDataGetBytePtr(rawData) {
            let imgW = cgImg.width
            let imgH = cgImg.height
            let bytesPerPixel = max(1, cgImg.bitsPerPixel / 8)
            let bytesPerRow = cgImg.bytesPerRow

            for gz in 0..<size {
                for gx in 0..<size {
                    let px = min(imgW - 1, Int((Float(gx) / Float(size - 1)) * Float(imgW - 1)))
                    let py = min(imgH - 1, Int((Float(gz) / Float(size - 1)) * Float(imgH - 1)))
                    let offset = py * bytesPerRow + px * bytesPerPixel
                    let val = Float(ptr[offset]) / 255.0
                    heightGrid[gz][gx] = val * map.elevationScale
                }
            }
        } else {
            // Fallback kontur gunung matematis jika resource belum termuat
            for gz in 0..<size {
                for gx in 0..<size {
                    let dx = Float(gx - 33) / 12.0
                    let dz = Float(gz - 9) / 10.0
                    let peak = exp(-(dx * dx + dz * dz)) * map.elevationScale * 0.75
                    heightGrid[gz][gx] = 3.0 + peak
                }
            }
        }

        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var texCoords: [CGPoint] = []
        var colors: [Float] = []
        var indices: [UInt32] = []

        for gz in 0..<size {
            for gx in 0..<size {
                let h = heightGrid[gz][gx]
                vertices.append(SCNVector3(Float(gx) * cellSize, h, Float(gz) * cellSize))
                texCoords.append(CGPoint(x: CGFloat(gx) * 0.25, y: CGFloat(gz) * 0.25))

                // Hitung normal permukaan lereng
                let hL = heightGrid[gz][max(0, gx - 1)]
                let hR = heightGrid[gz][min(size - 1, gx + 1)]
                let hD = heightGrid[max(0, gz - 1)][gx]
                let hU = heightGrid[min(size - 1, gz + 1)][gx]
                let nx = hL - hR
                let nz = hD - hU
                let ny: Float = 2.0 * cellSize
                let len = max(0.001, sqrt(nx * nx + ny * ny + nz * nz))
                normals.append(SCNVector3(nx / len, ny / len, nz / len))

                // Pewarnaan bioma tanah-rumput-lereng gunung realistis
                let normH = h / max(1.0, map.elevationScale)
                if normH < 0.11 {
                    // Pasir / tepian sungai & pesisir
                    colors.append(contentsOf: [0.76, 0.72, 0.58, 1.0])
                } else if normH > 0.58 {
                    // Lereng tinggi Gunung Arjuno / pegunungan berbatu
                    colors.append(contentsOf: [0.54, 0.48, 0.42, 1.0])
                } else {
                    // Rumput hijau subur Nusantara
                    colors.append(contentsOf: [0.88, 0.96, 0.85, 1.0])
                }
            }
        }

        for gz in 0..<(size - 1) {
            for gx in 0..<(size - 1) {
                let topLeft = UInt32(gz * size + gx)
                let topRight = UInt32(gz * size + (gx + 1))
                let bottomLeft = UInt32((gz + 1) * size + gx)
                let bottomRight = UInt32((gz + 1) * size + (gx + 1))

                indices.append(contentsOf: [topLeft, bottomLeft, topRight])
                indices.append(contentsOf: [topRight, bottomLeft, bottomRight])
            }
        }

        let vertexSource = SCNGeometrySource(vertices: vertices)
        let normalSource = SCNGeometrySource(normals: normals)
        let uvSource = SCNGeometrySource(textureCoordinates: texCoords)
        let colorData = Data(bytes: colors, count: colors.count * MemoryLayout<Float>.size)
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: vertices.count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 4
        )

        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [vertexSource, normalSource, uvSource, colorSource], elements: [element])

        let mat = SCNMaterial()
        mat.lightingModel = .physicallyBased
        if let grassTex = loadTextureImage(named: "grass_nusantara_albedo", subdirectory: "GameAssets/Textures") {
            mat.diffuse.contents = grassTex
            mat.diffuse.wrapS = .repeat
            mat.diffuse.wrapT = .repeat
        } else {
            mat.diffuse.contents = UIColor(red: 0.24, green: 0.52, blue: 0.22, alpha: 1.0)
        }
        if let grassNorm = loadTextureImage(named: "grass_normal", subdirectory: "GameAssets/Textures") {
            mat.normal.contents = grassNorm
            mat.normal.wrapS = .repeat
            mat.normal.wrapT = .repeat
            mat.normal.intensity = 0.75
        }
        mat.roughness.contents = 0.88
        geometry.materials = [mat]

        let terrainNode = SCNNode(geometry: geometry)
        terrainNode.name = "nusantara_terrain"
        terrainContainer.addChildNode(terrainNode)
    }

    private func buildWaterPlane(for map: NusantaraCityMap) {
        let totalSize = CGFloat(gridDimension) * CGFloat(cellSize)
        let plane = SCNPlane(width: totalSize, height: totalSize)
        let waterMat = SCNMaterial()
        waterMat.lightingModel = .physicallyBased
        waterMat.diffuse.contents = UIColor(red: 0.08, green: 0.34, blue: 0.48, alpha: 0.84)
        waterMat.roughness.contents = 0.14
        waterMat.metalness.contents = 0.25
        waterMat.isDoubleSided = true
        plane.materials = [waterMat]

        let waterNode = SCNNode(geometry: plane)
        waterNode.eulerAngles = SCNVector3(-Float.pi / 2.0, 0, 0)
        let waterLevel: Float = map == .malang ? 3.2 : 1.65
        waterNode.position = SCNVector3(Float(totalSize) * 0.5, waterLevel, Float(totalSize) * 0.5)
        waterContainer.addChildNode(waterNode)
    }

    private func populateNaturalWildTrees(for map: NusantaraCityMap) {
        // Peta dimulai 0% bangunan, namun alamnya kaya pepohonan spesifik kota
        let speciesList = map.availableTrees
        for gz in stride(from: 2, to: gridDimension - 2, by: 2) {
            for gx in stride(from: 2, to: gridDimension - 2, by: 2) {
                let h = heightGrid[gz][gx]
                let normH = h / max(1.0, map.elevationScale)
                // Hindari area sungai/laut & sisakan dataran tengah kota agar siap dibangun
                let distCenter = hypot(Float(gx - 32), Float(gz - 32))
                if normH > 0.14 && normH < 0.72 && distCenter > 11.0 {
                    if (gx * 17 + gz * 31) % 3 == 0 {
                        let chosen = normH > 0.38 ? .pinusMalang : speciesList[(gx + gz) % speciesList.count]
                        let treeNode = createDetailedTreeNode(species: chosen, withFallingLeaves: false)
                        let wx = (Float(gx) + 0.5) * cellSize
                        let wz = (Float(gz) + 0.5) * cellSize
                        treeNode.position = SCNVector3(wx, h, wz)
                        treeNode.eulerAngles.y = Float((gx * 13 + gz * 7) % 360) * (.pi / 180.0)
                        wildNatureContainer.addChildNode(treeNode)
                    }
                }
            }
        }
    }

    // =========================================================================
    // 3. DIORAMA LIVE 3D UNTUK MAIN MENU
    // =========================================================================

    private func buildMainMenuShowcaseDiorama(for map: NusantaraCityMap) {
        var demoRoads: [PlacedRoad] = []
        for x in 24...40 {
            demoRoads.append(PlacedRoad(
                coord: GridCoord(x: x, z: 32),
                roadType: .twoWayFourLane,
                hasStreetLights: true,
                plantedTree: map.defaultTreeSpecies
            ))
        }
        for z in 25...39 {
            demoRoads.append(PlacedRoad(
                coord: GridCoord(x: 32, z: z),
                roadType: .sidewalk,
                hasStreetLights: true,
                plantedTree: .tabebuyaSurabaya
            ))
        }

        let demoStructures: [PlacedStructure] = [
            PlacedStructure(coord: GridCoord(x: 28, z: 30), structureType: .commercialHighRise),
            PlacedStructure(coord: GridCoord(x: 35, z: 30), structureType: .kampungWarnaWarni),
            PlacedStructure(coord: GridCoord(x: 28, z: 34), structureType: .eduUniversitas),
            PlacedStructure(coord: GridCoord(x: 35, z: 34), structureType: .indomaretRetail),
            PlacedStructure(coord: GridCoord(x: 30, z: 30), structureType: .residentialHouse),
            PlacedStructure(coord: GridCoord(x: 34, z: 30), structureType: .residentialHouse)
        ]

        var showcaseStats = CityStatistics()
        showcaseStats.timeOfDayHours = 20.5 // Cozy night city lights di Main Menu
        var showcaseSettings = GraphicsSettings()
        showcaseSettings.lockNightCozyMode = true

        syncWorld(
            roads: demoRoads,
            structures: demoStructures,
            protests: [],
            stats: showcaseStats,
            settings: showcaseSettings
        )

        cameraTarget = SCNVector3(128, sampleElevation(gridX: 32, gridZ: 32) + 2.0, 128)
        cameraDistance = 42.0
        updateCameraTransform()

        // Kamera berputar sinematik perlahan mengelilingi kota malam di Main Menu
        let orbit = SCNAction.repeatForever(SCNAction.run { [weak self] _ in
            Task { @MainActor in
                self?.rotateCamera(angleDelta: 0.0035)
            }
        })
        cameraPivotNode.runAction(orbit, forKey: "menu_orbit")
    }

    // =========================================================================
    // 4. SINKRONISASI REAL-TIME JALAN, POHON, BANGUNAN, LALU LINTAS & MALAM
    // =========================================================================

    func syncWorld(
        roads: [PlacedRoad],
        structures: [PlacedStructure],
        protests: [CitizenProtest],
        stats: CityStatistics,
        settings: GraphicsSettings
    ) {
        self.activeRoads = roads
        let isNight = settings.lockNightCozyMode || stats.isNightTime

        updateDayNightAndCozyLights(stats: stats, settings: settings, isNight: isNight)
        syncRoadsAndSidewalkTrees(roads: roads, settings: settings, isNight: isNight)
        syncStructures(structures: structures, isNight: isNight)
        syncProtests(protests: protests)
        syncAmbientAudio(stats: stats, protests: protests, settings: settings, isNight: isNight)

        if trafficContainer.childNodes.isEmpty && !roads.isEmpty {
            spawnLivingTrafficAndCitizens(roads: roads, settings: settings)
        }
    }

    private func updateDayNightAndCozyLights(stats: CityStatistics, settings: GraphicsSettings, isNight: Bool) {
        sunLightNode.light?.castsShadow = settings.enableDynamicShadows

        if isNight && settings.enableCozyNightLights {
            scene.background.contents = UIColor(red: 0.04, green: 0.06, blue: 0.13, alpha: 1.0)
            scene.fogColor = UIColor(red: 0.05, green: 0.08, blue: 0.16, alpha: 1.0)
            scene.fogStartDistance = 75.0
            scene.fogEndDistance = 240.0

            sunLightNode.light?.color = UIColor(red: 0.35, green: 0.48, blue: 0.85, alpha: 1.0)
            sunLightNode.light?.intensity = 280
            ambientLightNode.light?.color = UIColor(red: 0.18, green: 0.22, blue: 0.36, alpha: 1.0)
            ambientLightNode.light?.intensity = 260
        } else {
            let hour = stats.timeOfDayHours
            let isGoldenHour = (hour >= 16.5 && hour < 18.2) || (hour > 5.5 && hour <= 7.0)
            if isGoldenHour {
                scene.background.contents = UIColor(red: 0.94, green: 0.62, blue: 0.42, alpha: 1.0)
                scene.fogColor = UIColor(red: 0.92, green: 0.65, blue: 0.48, alpha: 1.0)
                sunLightNode.light?.color = UIColor(red: 1.0, green: 0.72, blue: 0.45, alpha: 1.0)
                sunLightNode.light?.intensity = 880
            } else {
                scene.background.contents = UIColor(red: 0.52, green: 0.76, blue: 0.96, alpha: 1.0)
                scene.fogColor = UIColor(red: 0.68, green: 0.84, blue: 0.96, alpha: 1.0)
                sunLightNode.light?.color = UIColor(red: 1.0, green: 0.97, blue: 0.92, alpha: 1.0)
                sunLightNode.light?.intensity = 1150
            }
            scene.fogStartDistance = 110.0
            scene.fogEndDistance = 320.0
            ambientLightNode.light?.color = UIColor(red: 0.58, green: 0.68, blue: 0.84, alpha: 1.0)
            ambientLightNode.light?.intensity = 450
        }
    }

    private func syncRoadsAndSidewalkTrees(roads: [PlacedRoad], settings: GraphicsSettings, isNight: Bool) {
        let currentIDs = Set(roads.map { $0.id })

        // Hapus jalan yang dibongkar
        for child in roadsContainer.childNodes {
            if let name = child.name, let uuid = UUID(uuidString: name), !currentIDs.contains(uuid) {
                child.removeFromParentNode()
                renderedRoadIDs.remove(uuid)
                renderedRoadTreeMap.removeValue(forKey: uuid)
            }
        }

        for road in roads {
            let needsRebuild = !renderedRoadIDs.contains(road.id) || renderedRoadTreeMap[road.id] != road.plantedTree
            if needsRebuild {
                roadsContainer.childNode(withName: road.id.uuidString, recursively: false)?.removeFromParentNode()

                let roadNode = buildRoadNode(road: road, settings: settings, isNight: isNight)
                roadNode.name = road.id.uuidString
                roadsContainer.addChildNode(roadNode)

                renderedRoadIDs.insert(road.id)
                renderedRoadTreeMap[road.id] = road.plantedTree
            } else if let existing = roadsContainer.childNode(withName: road.id.uuidString, recursively: false) {
                // Update status lampu jalan malam hari
                existing.enumerateChildNodes { node, _ in
                    if node.name == "street_lamp_bulb" {
                        node.geometry?.firstMaterial?.emission.contents = (isNight && settings.enableCozyNightLights)
                            ? UIColor(red: 1.0, green: 0.78, blue: 0.36, alpha: 1.0)
                            : UIColor.black
                    }
                    if let light = node.light {
                        light.intensity = (isNight && settings.enableCozyNightLights) ? 280 : 0
                    }
                }
            }
        }
    }

    private func buildRoadNode(road: PlacedRoad, settings: GraphicsSettings, isNight: Bool) -> SCNNode {
        let container = SCNNode()
        let wx = (Float(road.coord.x) + 0.5) * cellSize
        let wz = (Float(road.coord.z) + 0.5) * cellSize
        let wy = sampleElevation(gridX: road.coord.x, gridZ: road.coord.z) + 0.08
        container.position = SCNVector3(wx, wy, wz)

        // Permukaan Jalan (1 Arah 2 Jalur / 2 Arah 4 Jalur / Trotoar / Jalur Sepeda)
        let slab = SCNBox(width: CGFloat(cellSize), height: 0.14, length: CGFloat(cellSize), chamferRadius: 0.02)
        let mat = SCNMaterial()
        mat.lightingModel = .physicallyBased
        if let tex = loadTextureImage(named: road.roadType.albedoTextureName, subdirectory: "GameAssets/Textures") {
            mat.diffuse.contents = tex
        } else {
            mat.diffuse.contents = UIColor.darkGray
        }
        if let norm = loadTextureImage(named: "asphalt_normal", subdirectory: "GameAssets/Textures") {
            mat.normal.contents = norm
        }
        mat.roughness.contents = isNight ? 0.32 : 0.75 // Kilau aspal malam hari
        slab.materials = [mat]
        container.addChildNode(SCNNode(geometry: slab))

        // Lampu Jalan Cozy Night Vibes
        if road.hasStreetLights {
            let lampNode = loadObjModel(named: "prop_streetlight", scale: 0.42)
            lampNode.position = SCNVector3(-cellSize * 0.42, 0.05, -cellSize * 0.42)
            lampNode.enumerateChildNodes { child, _ in
                if child.name == "bulb" {
                    child.name = "street_lamp_bulb"
                    child.geometry?.firstMaterial?.emission.contents = (isNight && settings.enableCozyNightLights)
                        ? UIColor(red: 1.0, green: 0.78, blue: 0.36, alpha: 1.0)
                        : UIColor.black
                }
            }

            let glowNode = SCNNode()
            let pointLight = SCNLight()
            pointLight.type = .omni
            pointLight.color = UIColor(red: 1.0, green: 0.76, blue: 0.38, alpha: 1.0)
            pointLight.intensity = (isNight && settings.enableCozyNightLights) ? 280 : 0
            pointLight.attenuationStartDistance = 1.0
            pointLight.attenuationEndDistance = 12.0
            glowNode.light = pointLight
            glowNode.position = SCNVector3(0.35, 1.9, 0)
            lampNode.addChildNode(glowNode)
            container.addChildNode(lampNode)
        }

        // Pohon yang Ditanam di Trotoar (dengan angin & daun gugur)
        if let treeSpecies = road.plantedTree {
            let treeNode = createDetailedTreeNode(
                species: treeSpecies,
                withFallingLeaves: settings.enableWindAndFallingLeaves
            )
            treeNode.scale = SCNVector3(0.45, 0.45, 0.45)
            treeNode.position = SCNVector3(cellSize * 0.38, 0.05, cellSize * 0.35)
            container.addChildNode(treeNode)
        }

        return container
    }

    private func syncStructures(structures: [PlacedStructure], isNight: Bool) {
        let currentIDs = Set(structures.map { $0.id })

        for child in structuresContainer.childNodes {
            if let name = child.name, let uuid = UUID(uuidString: name), !currentIDs.contains(uuid) {
                child.removeFromParentNode()
                renderedStructureIDs.remove(uuid)
            }
        }

        for structure in structures {
            if !renderedStructureIDs.contains(structure.id) {
                let node = buildStructureNode(structure: structure, isNight: isNight)
                node.name = structure.id.uuidString
                structuresContainer.addChildNode(node)
                renderedStructureIDs.insert(structure.id)
            } else if let existing = structuresContainer.childNode(withName: structure.id.uuidString, recursively: false) {
                // Update nyala jendela malam hari (padam jika kekurangan listrik)
                let nightGlowActive = isNight && structure.hasPower
                existing.enumerateChildNodes { child, _ in
                    if let mat = child.geometry?.firstMaterial {
                        if nightGlowActive,
                           let emissionTex = loadTextureImage(named: "building_facade_night_emission", subdirectory: "GameAssets/Textures") {
                            mat.emission.contents = emissionTex
                            mat.emission.intensity = 1.25
                        } else {
                            mat.emission.contents = UIColor.black
                        }
                    }
                }
            }
        }
    }

    private func buildStructureNode(structure: PlacedStructure, isNight: Bool) -> SCNNode {
        let modelNode = loadObjModel(named: structure.structureType.objModelName, scale: 0.52)
        let wx = (Float(structure.coord.x) + 0.5) * cellSize
        let wz = (Float(structure.coord.z) + 0.5) * cellSize
        let wy = sampleElevation(gridX: structure.coord.x, gridZ: structure.coord.z)
        modelNode.position = SCNVector3(wx, wy, wz)
        modelNode.eulerAngles.y = structure.rotationY

        let dayTex = loadTextureImage(named: structure.structureType.albedoTextureName, subdirectory: "GameAssets/Textures")
        let nightTex = loadTextureImage(named: "building_facade_night_emission", subdirectory: "GameAssets/Textures")

        modelNode.enumerateChildNodes { child, _ in
            if let mat = child.geometry?.firstMaterial {
                mat.lightingModel = .physicallyBased
                if let dTex = dayTex {
                    mat.diffuse.contents = dTex
                }
                if isNight && structure.hasPower, let nTex = nightTex {
                    mat.emission.contents = nTex
                    mat.emission.intensity = 1.25
                }
            }
        }

        // Animasi muncul saat baru dibangun
        modelNode.scale = SCNVector3(0.05, 0.05, 0.05)
        modelNode.runAction(SCNAction.scale(to: 0.52, duration: 0.35))
        return modelNode
    }

    // =========================================================================
    // 5. POHON DETAIL (ANGIN BERGOYANG & DAUN GUGUR REALISTIS)
    // =========================================================================

    private func createDetailedTreeNode(species: TreeSpecies, withFallingLeaves: Bool) -> SCNNode {
        let node = loadObjModel(named: species.rawValue, scale: 0.65)
        let leafTex = loadTextureImage(named: species.foliageTextureName, subdirectory: "GameAssets/Textures")

        node.enumerateChildNodes { child, _ in
            if let mat = child.geometry?.firstMaterial {
                mat.lightingModel = .physicallyBased
                if child.name == "leaves", let tex = leafTex {
                    mat.diffuse.contents = tex
                } else if child.name == "trunk" || child.name == "branches" {
                    mat.diffuse.contents = UIColor(red: 0.34, green: 0.23, blue: 0.14, alpha: 1.0)
                }
            }
        }

        // Animasi angin lembut menggerakkan ranting & dedaunan
        let swayRight = SCNAction.rotateBy(x: 0.025, y: 0, z: 0.035, duration: 2.2)
        swayRight.timingMode = .easeInEaseOut
        let swayLeft = SCNAction.rotateBy(x: -0.025, y: 0, z: -0.035, duration: 2.2)
        swayLeft.timingMode = .easeInEaseOut
        node.runAction(SCNAction.repeatForever(SCNAction.sequence([swayRight, swayLeft])))

        // Partikel Daun Gugur Jatuh ke Trotoar
        if withFallingLeaves {
            let ps = SCNParticleSystem()
            ps.birthRate = 2.5
            ps.particleLifeSpan = 4.2
            ps.particleVelocity = 0.45
            ps.particleVelocityVariation = 0.25
            ps.emittingDirection = SCNVector3(0.35, -1.0, 0.2)
            ps.spreadingAngle = 35.0
            ps.particleSize = 0.14
            ps.particleAngularVelocity = 1.6
            ps.particleImage = makeLeafParticleImage(for: species)
            ps.emitterShape = SCNSphere(radius: 1.4)

            let emitterNode = SCNNode()
            emitterNode.position = SCNVector3(0, 3.2, 0)
            emitterNode.addParticleSystem(ps)
            node.addChildNode(emitterNode)
        }

        return node
    }

    private func makeLeafParticleImage(for species: TreeSpecies) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
        return renderer.image { ctx in
            let color: UIColor
            switch species {
            case .pinusMalang:
                color = UIColor(red: 0.22, green: 0.56, blue: 0.24, alpha: 0.92)
            case .trembesiSurabaya:
                color = UIColor(red: 0.42, green: 0.68, blue: 0.24, alpha: 0.92)
            case .tabebuyaSurabaya:
                color = UIColor(red: 0.96, green: 0.64, blue: 0.78, alpha: 0.95)
            }
            color.setFill()
            let path = UIBezierPath(ovalIn: CGRect(x: 4, y: 7, width: 16, height: 10))
            path.fill()
        }
    }

    // =========================================================================
    // 6. POPULASI LALU LINTAS (PEMOTOR, MOBIL, PESEPEDA) & PEJALAN KAKI
    // =========================================================================

    private func spawnLivingTrafficAndCitizens(roads: [PlacedRoad], settings: GraphicsSettings) {
        trafficContainer.childNodes.forEach { $0.removeFromParentNode() }
        guard roads.count >= 2 else { return }

        let maxAgents = Int(Double(min(24, roads.count * 2)) * max(0.3, settings.trafficDensity))
        let motorRoads = roads.filter { $0.roadType.allowsMotorVehicles }
        let bikeRoads = roads.filter { $0.roadType == .bikeLane }

        for i in 0..<maxAgents {
            let modelName: String
            let sourceRoad: PlacedRoad

            if !bikeRoads.isEmpty && i % 4 == 0 {
                modelName = "vehicle_sepeda"
                sourceRoad = bikeRoads[i % bikeRoads.count]
            } else if !motorRoads.isEmpty && i % 3 == 0 {
                modelName = "vehicle_motor"
                sourceRoad = motorRoads[i % motorRoads.count]
            } else if !motorRoads.isEmpty && i % 3 == 1 {
                modelName = "vehicle_mobil"
                sourceRoad = motorRoads[i % motorRoads.count]
            } else {
                modelName = "npc_pedestrian"
                sourceRoad = roads[i % roads.count]
            }

            let agent = loadObjModel(named: modelName, scale: 0.48)
            let startPos = worldPosition(for: sourceRoad.coord, yOffset: 0.16)
            agent.position = startPos

            // Pilih tujuan berikutnya di jaringan jalan
            let destRoad = roads[(i * 7 + 3) % roads.count]
            let endPos = worldPosition(for: destRoad.coord, yOffset: 0.16)

            let distance = hypot(endPos.x - startPos.x, endPos.z - startPos.z)
            let duration = TimeInterval(max(4.0, distance / (modelName == "npc_pedestrian" ? 1.8 : 4.5)))

            let moveThere = SCNAction.move(to: endPos, duration: duration)
            let moveBack = SCNAction.move(to: startPos, duration: duration)
            agent.runAction(SCNAction.repeatForever(SCNAction.sequence([moveThere, moveBack])))

            trafficContainer.addChildNode(agent)
        }
    }

    // =========================================================================
    // 7. VISUALISASI KERUMUNAN AKSI DEMONSTRASI WARGA
    // =========================================================================

    private func syncProtests(protests: [CitizenProtest]) {
        let activeIDs = Set(protests.filter { !$0.resolved }.map { $0.id })

        for child in protestsContainer.childNodes {
            if let name = child.name, let uuid = UUID(uuidString: name), !activeIDs.contains(uuid) {
                child.removeFromParentNode()
                renderedProtestIDs.remove(uuid)
            }
        }

        for protest in protests where !protest.resolved {
            if !renderedProtestIDs.contains(protest.id) {
                let crowdGroup = SCNNode()
                crowdGroup.name = protest.id.uuidString
                let base = worldPosition(for: protest.location, yOffset: 0.12)
                crowdGroup.position = base

                let demonstrators = min(14, max(5, protest.crowdCount / 8))
                for idx in 0..<demonstrators {
                    let person = loadObjModel(named: "npc_pedestrian", scale: 0.50)
                    let angle = Float(idx) * (2.0 * .pi / Float(demonstrators))
                    let radius = Float(1.1 + Float(idx % 3) * 0.45)
                    person.position = SCNVector3(cos(angle) * radius, 0, sin(angle) * radius)

                    // Spanduk tuntutan demo warga
                    if idx % 2 == 0 {
                        let signBoard = SCNBox(width: 0.55, height: 0.32, length: 0.04, chamferRadius: 0)
                        signBoard.firstMaterial?.diffuse.contents = UIColor(red: 0.92, green: 0.18, blue: 0.18, alpha: 1.0)
                        let signNode = SCNNode(geometry: signBoard)
                        signNode.position = SCNVector3(0, 1.15, 0.12)
                        person.addChildNode(signNode)
                    }

                    // Gerakan orasi & melompat
                    let jumpUp = SCNAction.moveBy(x: 0, y: 0.18, z: 0, duration: 0.35 + Double(idx % 3) * 0.08)
                    let jumpDown = SCNAction.moveBy(x: 0, y: -0.18, z: 0, duration: 0.35 + Double(idx % 3) * 0.08)
                    person.runAction(SCNAction.repeatForever(SCNAction.sequence([jumpUp, jumpDown])))

                    crowdGroup.addChildNode(person)
                }

                protestsContainer.addChildNode(crowdGroup)
                renderedProtestIDs.insert(protest.id)
            }
        }
    }

    // =========================================================================
    // 8. SISTEM AUDIO AMBIEN KOTA & SUARA PEMBANGUNAN
    // =========================================================================

    private func syncAmbientAudio(
        stats: CityStatistics,
        protests: [CitizenProtest],
        settings: GraphicsSettings,
        isNight: Bool
    ) {
        let targetTrack: String
        if !protests.filter({ !$0.resolved }).isEmpty {
            targetTrack = "citizen_demo_crowd"
        } else if isNight {
            targetTrack = "cozy_night_city"
        } else if activeRoads.count >= 3 {
            targetTrack = "city_traffic_day"
        } else {
            targetTrack = "wind_leaves_mountain"
        }

        bgmPlayer?.volume = Float(settings.soundVolume) * 0.55

        guard targetTrack != currentAudioTrack else { return }
        currentAudioTrack = targetTrack

        if let url = locateResourceURL(name: targetTrack, ext: "wav", subdirectory: "GameAssets/Audio") {
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.numberOfLoops = -1
                player.volume = Float(settings.soundVolume) * 0.55
                player.prepareToPlay()
                player.play()
                bgmPlayer = player
            } catch {
                // Abaikan jika perangkat dalam mode senyap
            }
        }
    }

    func playBuildSFX(volume: Double = 0.8) {
        guard let url = locateResourceURL(name: "build_construct_sfx", ext: "wav", subdirectory: "GameAssets/Audio") else {
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = Float(volume)
            player.play()
            sfxPlayer = player
        } catch {}
    }

    // =========================================================================
    // 9. HELPER KOORDINAT GRID, ELEVASI & LOADER MODEL .OBJ / TEKSTUR
    // =========================================================================

    func sampleElevation(gridX: Int, gridZ: Int) -> Float {
        let gx = max(0, min(gridDimension - 1, gridX))
        let gz = max(0, min(gridDimension - 1, gridZ))
        return heightGrid[gz][gx]
    }

    func worldPosition(for coord: GridCoord, yOffset: Float = 0.0) -> SCNVector3 {
        let wx = (Float(coord.x) + 0.5) * cellSize
        let wz = (Float(coord.z) + 0.5) * cellSize
        let wy = sampleElevation(gridX: coord.x, gridZ: coord.z) + yOffset
        return SCNVector3(wx, wy, wz)
    }

    func gridCoord(fromWorldPosition pos: SCNVector3) -> GridCoord {
        let gx = max(1, min(gridDimension - 2, Int(floor(pos.x / cellSize))))
        let gz = max(1, min(gridDimension - 2, Int(floor(pos.z / cellSize))))
        return GridCoord(x: gx, z: gz)
    }

    private func loadObjModel(named name: String, scale: Float) -> SCNNode {
        if let cached = modelCache[name] {
            let cloned = cached.clone()
            cloned.scale = SCNVector3(scale, scale, scale)
            return cloned
        }

        if let url = locateResourceURL(name: name, ext: "obj", subdirectory: "GameAssets/Models") {
            let asset = MDLAsset(url: url)
            if asset.count > 0 {
                let container = SCNNode()
                for i in 0..<asset.count {
                    let objNode = SCNNode(mdlObject: asset.object(at: i))
                    container.addChildNode(objNode)
                }
                modelCache[name] = container
                let cloned = container.clone()
                cloned.scale = SCNVector3(scale, scale, scale)
                return cloned
            }
        }

        // Fallback geometri dasar jika asset tidak ditemukan
        let fallbackBox = SCNBox(width: 2.5, height: 2.5, length: 2.5, chamferRadius: 0.1)
        fallbackBox.firstMaterial?.diffuse.contents = UIColor.systemTeal
        let fallbackNode = SCNNode(geometry: fallbackBox)
        fallbackNode.scale = SCNVector3(scale, scale, scale)
        return fallbackNode
    }

    private func loadTextureImage(named name: String, subdirectory: String) -> UIImage? {
        let cacheKey = "\(subdirectory)/\(name)"
        if let cached = textureCache[cacheKey] {
            return cached
        }
        if let url = locateResourceURL(name: name, ext: "png", subdirectory: subdirectory),
           let img = UIImage(contentsOfFile: url.path) {
            textureCache[cacheKey] = img
            return img
        }
        return nil
    }

    private func locateResourceURL(name: String, ext: String, subdirectory: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
            return url
        }
        return Bundle.main.url(forResource: name, withExtension: ext)
    }
}

// MARK: - SwiftUI Wrapper untuk Layar 3D SceneKit

struct City3DSceneView: UIViewRepresentable {
    @ObservedObject var controller: City3DEngineController
    var isInteractive: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller, isInteractive: isInteractive)
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView(frame: .zero)
        scnView.scene = controller.scene
        scnView.allowsCameraControl = false
        scnView.antialiasingMode = .multisampling4X
        scnView.preferredFramesPerSecond = 60
        scnView.isPlaying = true
        scnView.backgroundColor = .black

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        let rotateGesture = UIRotationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleRotation(_:)))

        scnView.addGestureRecognizer(tapGesture)
        scnView.addGestureRecognizer(panGesture)
        scnView.addGestureRecognizer(pinchGesture)
        scnView.addGestureRecognizer(rotateGesture)

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.isInteractive = isInteractive
    }

    @MainActor
    final class Coordinator: NSObject {
        let controller: City3DEngineController
        var isInteractive: Bool
        private var lastPanTranslation: CGPoint = .zero

        init(controller: City3DEngineController, isInteractive: Bool) {
            self.controller = controller
            self.isInteractive = isInteractive
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard isInteractive, let scnView = gesture.view as? SCNView else { return }
            let loc = gesture.location(in: scnView)
            let hits = scnView.hitTest(loc, options: [
                SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue
            ])
            if let terrainHit = hits.first(where: { $0.node.name == "nusantara_terrain" }) ?? hits.first {
                let coord = controller.gridCoord(fromWorldPosition: terrainHit.worldCoordinates)
                controller.onGridTapped?(coord)
            }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard isInteractive else { return }
            let translation = gesture.translation(in: gesture.view)
            if gesture.state == .began {
                lastPanTranslation = translation
                return
            }
            let dx = Float(translation.x - lastPanTranslation.x)
            let dz = Float(translation.y - lastPanTranslation.y)
            lastPanTranslation = translation
            controller.panCamera(deltaX: dx, deltaZ: dz)
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard isInteractive else { return }
            if gesture.state == .changed {
                controller.zoomCamera(scale: Float(gesture.scale))
                gesture.scale = 1.0
            }
        }

        @objc func handleRotation(_ gesture: UIRotationGestureRecognizer) {
            guard isInteractive else { return }
            if gesture.state == .changed {
                controller.rotateCamera(angleDelta: Float(gesture.rotation))
                gesture.rotation = 0.0
            }
        }
    }
}

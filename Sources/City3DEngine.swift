import Foundation
import UIKit
import SceneKit
import SwiftUI
import AVFoundation
import simd

final class NusantaraAssetBank {
    static let shared = NusantaraAssetBank()
    private var imageCache: [String: UIImage] = [:]
    private var bgmPlayer: AVAudioPlayer?
    private var sfxPlayer: AVAudioPlayer?

    var bgmVolume: Float = 0.42 {
        didSet { bgmPlayer?.volume = isMuted ? 0.0 : bgmVolume }
    }
    var sfxVolume: Float = 0.65
    var isMuted: Bool = false {
        didSet { bgmPlayer?.volume = isMuted ? 0.0 : bgmVolume }
    }

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func texture(_ filename: String) -> UIImage? {
        if let cached = imageCache[filename] { return cached }
        let stem = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        if let url = Bundle.main.url(forResource: stem, withExtension: ext, subdirectory: "GameAssets/Textures"),
           let img = UIImage(contentsOfFile: url.path) {
            imageCache[filename] = img
            return img
        }
        return nil
    }

    func applyHDFilter(_ prop: SCNMaterialProperty, repeatTile: Bool = true) {
        prop.wrapS = repeatTile ? .repeat : .clamp
        prop.wrapT = repeatTile ? .repeat : .clamp
        prop.minificationFilter = .linear
        prop.magnificationFilter = .linear
        prop.mipFilter = .linear
        prop.maxAnisotropy = 16
    }

    func playBGM(night: Bool) {
        let track = night ? "cozy_night_city" : "city_traffic_day"
        guard let url = Bundle.main.url(forResource: track, withExtension: "wav", subdirectory: "GameAssets/Audio") else { return }
        if bgmPlayer?.url == url && bgmPlayer?.isPlaying == true { return }
        bgmPlayer?.stop()
        if let player = try? AVAudioPlayer(contentsOf: url) {
            player.numberOfLoops = -1
            player.volume = isMuted ? 0.0 : bgmVolume
            player.prepareToPlay()
            player.play()
            bgmPlayer = player
        }
    }

    func playBuildSFX() {
        guard !isMuted,
              let url = Bundle.main.url(forResource: "build_construct_sfx", withExtension: "wav", subdirectory: "GameAssets/Audio") else { return }
        if let player = try? AVAudioPlayer(contentsOf: url) {
            player.volume = sfxVolume
            player.play()
            sfxPlayer = player
        }
    }
}

enum VehicleKind {
    case motorbike, car, angkotBus, emergency
}

struct TrafficAgent {
    let node: SCNNode
    let kind: VehicleKind
    let laneSlot: Int // 0 = inner left lane, 1 = outer left lane (for 4-lane roads)
    var currentCoord: GridCoord
    var nextCoord: GridCoord
    var prevCoord: GridCoord
    var progress: Float
    var speed: Float
}

final class City3DEngine: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    private let worldRoot = SCNNode()
    private let terrainContainer = SCNNode()
    private let biomeContainer = SCNNode()
    private let atmosphereParticlesNode = SCNNode()
    private let zonableGridContainer = SCNNode()
    private let previewContainer = SCNNode()
    private let roadContainer = SCNNode()
    private let plotContainer = SCNNode()
    private let facilityContainer = SCNNode()
    private let utilityContainer = SCNNode()
    private let trafficContainer = SCNNode()
    private let incidentContainer = SCNNode()

    // Pure Horizontal Turntable Orbit Camera Rig (Zero Tilt/Roll!)
    private let cameraPivot = SCNNode()      // Moves on ground XZ, rotates ONLY around World Y
    private let cameraPitchNode = SCNNode()  // Tilts ONLY around local X
    private let cameraNode = SCNNode()       // Zooms ONLY along local Z

    private let sunLightNode = SCNNode()
    private let ambientLightNode = SCNNode()
    private var waterMaterial: SCNMaterial?

    private let simLock = NSLock()
    private var roadKindMap: [GridCoord: RoadKind] = [:]
    private var driveableSet: Set<GridCoord> = []
    private var agents: [TrafficAgent] = []
    private var lastUpdateTime: TimeInterval = 0
    private var waterScrollPhase: Float = 0

    private var currentMap: CityMapType = .malang
    private var timePhase: TimeOfDayPhase = .day
    private var currentWeather: CityWeather = .cerahBerawan
    private var cameraMode: CameraMode = .drone
    private var lensMode: DataLensMode = .normal
    private var showcaseActive: Bool = true
    private var followedVehicleIndex: Int = 0

    private var camYaw: Float = 0.65
    private var camPitch: Float = 0.68
    private var camDistance: Float = 38.0
    private var panTarget: SIMD2<Float> = SIMD2<Float>(0, 0)
    var cameraSensitivity: Float = 1.0

    let gridHalfExtent: Int = 18
    let tileSize: Float = 2.0

    var onTileTapped: ((GridCoord) -> Void)?

    override init() {
        super.init()
        setupSceneGraph()
        loadMap(.malang, showcaseDemo: true)
    }

    private func setupSceneGraph() {
        scene.rootNode.addChildNode(worldRoot)
        worldRoot.addChildNode(terrainContainer)
        worldRoot.addChildNode(biomeContainer)
        worldRoot.addChildNode(atmosphereParticlesNode)
        worldRoot.addChildNode(zonableGridContainer)
        worldRoot.addChildNode(previewContainer)
        worldRoot.addChildNode(roadContainer)
        worldRoot.addChildNode(plotContainer)
        worldRoot.addChildNode(facilityContainer)
        worldRoot.addChildNode(utilityContainer)
        worldRoot.addChildNode(trafficContainer)
        worldRoot.addChildNode(incidentContainer)

        // Turntable Camera Hierarchy: Pivot (Yaw Y) -> PitchNode (Pitch X) -> Camera (Distance Z)
        scene.rootNode.addChildNode(cameraPivot)
        cameraPivot.addChildNode(cameraPitchNode)
        cameraPitchNode.addChildNode(cameraNode)

        let cam = SCNCamera()
        cam.zNear = 0.3
        cam.zFar = 480.0
        cam.fieldOfView = 42.0
        cam.wantsHDR = true
        cam.bloomIntensity = 0.50
        cam.bloomThreshold = 0.85
        cam.bloomBlurRadius = 8.0
        cameraNode.camera = cam
        cameraNode.eulerAngles = SCNVector3Zero
        updateCameraTransform()

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 440
        ambient.color = UIColor(red: 0.88, green: 0.93, blue: 1.0, alpha: 1.0)
        ambientLightNode.light = ambient
        scene.rootNode.addChildNode(ambientLightNode)

        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 1400
        sun.color = UIColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1.0)
        sun.castsShadow = true
        sun.shadowMode = .deferred
        sun.shadowSampleCount = 2
        sunLightNode.light = sun
        sunLightNode.eulerAngles = SCNVector3(-Float.pi / 3.0, Float.pi / 4.0, 0)
        scene.rootNode.addChildNode(sunLightNode)

        applyAtmosphere(shadows: true, fog: true, bloom: true)
    }

    // MARK: - Ultra-HD Terrain, Sculpted Mountain Peaks & River Channel

    private func fractalMountainRidge(x: Float, z: Float) -> Float {
        let r1 = 1.0 - abs(sin(x * 0.036 + cos(z * 0.032) * 1.5))
        let r2 = 1.0 - abs(cos(z * 0.052 - sin(x * 0.044) * 1.3))
        let r3 = 1.0 - abs(sin((x + z) * 0.085))
        let sharpPeak = pow(max(0.0, r1 * r2), 1.45) * 1.35 + r3 * 0.25
        return sharpPeak
    }

    func terrainHeight(x: Float, z: Float) -> Float {
        let distFromCenter = sqrt(x * x + z * z)
        let mountainMask = max(0.0, (distFromCenter - 37.0) / 38.0)
        let mountainFactor = mountainMask * mountainMask

        switch currentMap {
        case .malang:
            let riverCenter = 18.0 + 2.4 * sin(z * 0.075)
            let brantas = exp(-pow((x - riverCenter) / 4.6, 2.0)) * -0.78
            let ridge = fractalMountainRidge(x: x, z: z) * 34.0 * mountainFactor
            let arjunoNorth = max(0.0, (-z - 32.0) * 0.42) * mountainFactor
            return brantas + ridge + arjunoNorth + sin(x * 0.08) * cos(z * 0.08) * 0.08

        case .surabaya:
            let riverCenter = 14.0 + 2.0 * cos(z * 0.07)
            let kalimas = exp(-pow((x - riverCenter) / 4.4, 2.0)) * -0.75
            let coastDrop = max(0.0, (x - 33.0) * -0.25)
            let distantHills = max(0.0, (-x - 38.0) / 32.0) * fractalMountainRidge(x: x, z: z) * 20.0
            return kalimas + coastDrop + distantHills

        case .jakarta:
            let riverCenter = 12.0 + 2.2 * sin(z * 0.085)
            let ciliwung = exp(-pow((x - riverCenter) / 4.2, 2.0)) * -0.75
            let bayDrop = max(0.0, (-z - 33.0) * -0.25)
            let salakHills = max(0.0, (z - 38.0) / 32.0) * fractalMountainRidge(x: x, z: z) * 24.0
            return ciliwung + bayDrop + salakHills
        }
    }

    func loadMap(_ mapType: CityMapType, showcaseDemo: Bool) {
        currentMap = mapType
        showcaseActive = showcaseDemo
        cameraMode = .drone

        terrainContainer.childNodes.forEach { $0.removeFromParentNode() }
        biomeContainer.childNodes.forEach { $0.removeFromParentNode() }
        atmosphereParticlesNode.removeAllParticleSystems()
        zonableGridContainer.childNodes.forEach { $0.removeFromParentNode() }
        previewContainer.childNodes.forEach { $0.removeFromParentNode() }
        roadContainer.childNodes.forEach { $0.removeFromParentNode() }
        plotContainer.childNodes.forEach { $0.removeFromParentNode() }
        facilityContainer.childNodes.forEach { $0.removeFromParentNode() }
        utilityContainer.childNodes.forEach { $0.removeFromParentNode() }
        incidentContainer.childNodes.forEach { $0.removeFromParentNode() }

        simLock.lock()
        trafficContainer.childNodes.forEach { $0.removeFromParentNode() }
        agents.removeAll()
        driveableSet.removeAll()
        roadKindMap.removeAll()
        simLock.unlock()

        panTarget = SIMD2<Float>(0, 0)
        camPitch = 0.68
        camDistance = showcaseDemo ? 34.0 : 38.0
        updateCameraTransform()

        buildHighDetailTerrainAndRiver()
        buildLushForestSwayingGrassAndLeaves()
        NusantaraAssetBank.shared.playBGM(night: timePhase == .night)

        if showcaseDemo {
            buildShowcaseCity()
        }
    }

    private func buildHighDetailTerrainAndRiver() {
        let bank = NusantaraAssetBank.shared
        let segs = 136
        let span: Float = 380.0
        let half = span * 0.5

        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var colors: [SCNVector3] = []
        var uvs: [CGPoint] = []
        var indices: [Int32] = []

        for iz in 0...segs {
            let vz = Float(iz) / Float(segs)
            let z = -half + vz * span
            for ix in 0...segs {
                let vx = Float(ix) / Float(segs)
                let x = -half + vx * span
                let y = terrainHeight(x: x, z: z)
                vertices.append(SCNVector3(x, y, z))
                uvs.append(CGPoint(x: CGFloat(vx * 44.0), y: CGFloat(vz * 44.0)))

                let eps: Float = 0.9
                let hL = terrainHeight(x: x - eps, z: z)
                let hR = terrainHeight(x: x + eps, z: z)
                let hD = terrainHeight(x: x, z: z - eps)
                let hU = terrainHeight(x: x, z: z + eps)
                let nx = hL - hR
                let ny = 2.0 * eps
                let nz = hD - hU
                let len = max(0.001, sqrt(nx * nx + ny * ny + nz * nz))
                let nyNorm = ny / len
                normals.append(SCNVector3(nx / len, nyNorm, nz / len))

                if y < -0.08 {
                    // Sandy & pebble riverbank
                    colors.append(SCNVector3(0.78, 0.72, 0.54))
                } else if y > 22.0 {
                    // High alpine mist & highland stone
                    colors.append(SCNVector3(0.72, 0.76, 0.80))
                } else if nyNorm < 0.82 || y > 8.5 {
                    // Steep rocky mountain cliff strata
                    colors.append(SCNVector3(0.42, 0.44, 0.43))
                } else {
                    // Rich emerald tropical grass
                    colors.append(SCNVector3(0.86, 0.96, 0.82))
                }
            }
        }

        let stride = Int32(segs + 1)
        for iz in 0..<Int32(segs) {
            for ix in 0..<Int32(segs) {
                let a = iz * stride + ix
                let b = a + 1
                let c = (iz + 1) * stride + ix
                let d = c + 1
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }

        let vSrc = SCNGeometrySource(vertices: vertices)
        let nSrc = SCNGeometrySource(normals: normals)
        let cData = Data(bytes: colors, count: colors.count * MemoryLayout<SCNVector3>.size)
        let cSrc = SCNGeometrySource(
            data: cData,
            semantic: .color,
            vectorCount: colors.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SCNVector3>.size
        )
        let uvSrc = SCNGeometrySource(textureCoordinates: uvs)
        let elem = SCNGeometryElement(indices: indices, primitiveType: .triangles)

        let geo = SCNGeometry(sources: [vSrc, nSrc, cSrc, uvSrc], elements: [elem])
        let mat = SCNMaterial()
        if let grassTex = bank.texture("grass_nusantara_albedo.png") {
            mat.diffuse.contents = grassTex
            bank.applyHDFilter(mat.diffuse)
            if let grassNorm = bank.texture("grass_normal.png") {
                mat.normal.contents = grassNorm
                bank.applyHDFilter(mat.normal)
            }
        } else {
            mat.diffuse.contents = UIColor(red: 0.24, green: 0.48, blue: 0.22, alpha: 1.0)
        }
        mat.roughness.contents = 0.85
        geo.materials = [mat]
        terrainContainer.addChildNode(SCNNode(geometry: geo))

        // Reflective Normal-Mapped Flowing River & Coastal Water
        let waterPlane = SCNPlane(width: 520, height: 520)
        let wMat = SCNMaterial()
        wMat.diffuse.contents = UIColor(red: 0.05, green: 0.42, blue: 0.68, alpha: 0.90)
        if let wNorm = bank.texture("water_normal.png") {
            wMat.normal.contents = wNorm
            bank.applyHDFilter(wMat.normal)
        }
        wMat.metalness.contents = 0.22
        wMat.roughness.contents = 0.08
        waterPlane.materials = [wMat]
        waterMaterial = wMat
        let waterNode = SCNNode(geometry: waterPlane)
        waterNode.eulerAngles.x = -.pi / 2
        waterNode.position.y = -0.22
        terrainContainer.addChildNode(waterNode)
    }

    private func buildLushForestSwayingGrassAndLeaves() {
        // 1. Dense Multi-Species Forest (320 trees with gentle wind sway)
        for i in 0..<320 {
            let angle = Float(i) * 0.6180339 * 2.0 * .pi
            let dist = 38.5 + Float(i % 45) * 1.45
            let tx = cos(angle) * dist
            let tz = sin(angle) * dist
            let ty = terrainHeight(x: tx, z: tz)
            if ty > 0.02 && ty < 14.0 {
                let species = currentMap == .malang ? (i % 2 == 0 ? 1 : 0) : (i % 3)
                let tree = makeAlphaFoliageTree(species: species, swayPhase: Float(i) * 0.35)
                let s = Float(0.85 + Double(i % 6) * 0.16)
                tree.scale = SCNVector3(s, s, s)
                tree.position = SCNVector3(tx, ty, tz)
                biomeContainer.addChildNode(tree)
            }
        }

        // 2. Swaying Wind-Blown Grass Tufts across meadows
        let grassMat = SCNMaterial()
        grassMat.diffuse.contents = UIColor(red: 0.22, green: 0.58, blue: 0.22, alpha: 1.0)
        grassMat.isDoubleSided = true
        let bladeGeo = SCNPlane(width: 0.36, height: 0.28)
        bladeGeo.materials = [grassMat]

        for g in 0..<240 {
            let gx = Float((g * 37) % 72 - 36)
            let gz = Float((g * 53) % 72 - 36)
            if abs(gx) < 12 && abs(gz) < 12 { continue }
            let gy = terrainHeight(x: gx, z: gz)
            if gy > 0.02 && gy < 4.0 {
                let tuft = SCNNode(geometry: bladeGeo)
                tuft.position = SCNVector3(gx, gy + 0.12, gz)
                tuft.eulerAngles.y = Float(g) * 0.8
                let swayLeft = SCNAction.rotateTo(x: 0.16, y: CGFloat(tuft.eulerAngles.y), z: 0.12, duration: 1.4 + Double(g % 4) * 0.25)
                let swayRight = SCNAction.rotateTo(x: -0.10, y: CGFloat(tuft.eulerAngles.y), z: -0.10, duration: 1.4 + Double(g % 4) * 0.25)
                swayLeft.timingMode = .easeInEaseOut
                swayRight.timingMode = .easeInEaseOut
                tuft.runAction(SCNAction.repeatForever(SCNAction.sequence([swayLeft, swayRight])))
                biomeContainer.addChildNode(tuft)
            }
        }

        // 3. Drifting Falling Leaves & Breeze Particle System
        updateWeatherParticles()
    }

    func setWeather(_ weather: CityWeather) {
        currentWeather = weather
        updateWeatherParticles()
    }

    private func updateWeatherParticles() {
        atmosphereParticlesNode.removeAllParticleSystems()
        atmosphereParticlesNode.position = SCNVector3(0, 14, 0)

        // Ambient drifting falling leaves
        let leafPS = SCNParticleSystem()
        leafPS.birthRate = currentWeather == .anginSepoi ? 36 : 16
        leafPS.particleLifeSpan = 9.0
        leafPS.particleSize = 0.14
        leafPS.particleColor = UIColor(red: 0.56, green: 0.72, blue: 0.24, alpha: 0.90)
        leafPS.emitterShape = SCNBox(width: 75, height: 2, length: 75, chamferRadius: 0)
        leafPS.emittingDirection = SCNVector3(0.45, -1.0, 0.25)
        leafPS.spreadingAngle = 32
        leafPS.particleVelocity = currentWeather == .anginSepoi ? 2.6 : 1.4
        leafPS.particleAngularVelocity = 1.8
        atmosphereParticlesNode.addParticleSystem(leafPS)

        // Tropical rain particles when raining
        if currentWeather == .hujanTropis {
            let rainPS = SCNParticleSystem()
            rainPS.birthRate = 450
            rainPS.particleLifeSpan = 1.6
            rainPS.particleSize = 0.045
            rainPS.particleColor = UIColor(red: 0.72, green: 0.86, blue: 1.0, alpha: 0.65)
            rainPS.emitterShape = SCNBox(width: 75, height: 1, length: 75, chamferRadius: 0)
            rainPS.emittingDirection = SCNVector3(0.15, -1.0, 0.05)
            rainPS.spreadingAngle = 4
            rainPS.particleVelocity = 18.0
            atmosphereParticlesNode.addParticleSystem(rainPS)
        }
    }

    private func buildShowcaseCity() {
        var demoRoads: [GridCoord: RoadTile] = [:]
        var demoPlots: [GridCoord: ZonedPlot] = [:]
        var demoFacs: [GridCoord: FacilityTile] = [:]

        for x in -5...5 {
            let c = GridCoord(x: x, z: 0)
            demoRoads[c] = RoadTile(coord: c, kind: x == 0 ? .roundabout : .fourLane)
        }
        for z in -3...3 where z != 0 {
            let c = GridCoord(x: 0, z: z)
            demoRoads[c] = RoadTile(coord: c, kind: .twoLane)
        }
        demoFacs[GridCoord(x: -2, z: -2)] = FacilityTile(coord: GridCoord(x: -2, z: -2), kind: .balaiKota)
        demoFacs[GridCoord(x: 3, z: -2)] = FacilityTile(coord: GridCoord(x: 3, z: -2), kind: .universitas)
        demoPlots[GridCoord(x: -3, z: 1)] = ZonedPlot(coord: GridCoord(x: -3, z: 1), kind: .residentialLow, buildingLevel: 4, residents: 5, maxResidents: 6)
        demoPlots[GridCoord(x: -2, z: 1)] = ZonedPlot(coord: GridCoord(x: -2, z: 1), kind: .residentialHigh, buildingLevel: 4, residents: 18, maxResidents: 20)
        demoPlots[GridCoord(x: 2, z: 1)] = ZonedPlot(coord: GridCoord(x: 2, z: 1), kind: .commercial, buildingLevel: 2, residents: 4, maxResidents: 4, forcedBrandSkin: 1)
        demoPlots[GridCoord(x: 4, z: 1)] = ZonedPlot(coord: GridCoord(x: 4, z: 1), kind: .parkGreen, buildingLevel: 1, residents: 0, maxResidents: 0)

        syncWorld(roads: demoRoads, plots: demoPlots, facilities: demoFacs, utilities: [:], showZonableGrid: false)
    }

    func syncWorld(
        roads: [GridCoord: RoadTile],
        plots: [GridCoord: ZonedPlot],
        facilities: [GridCoord: FacilityTile],
        utilities: [GridCoord: UtilityTile],
        showZonableGrid: Bool
    ) {
        roadContainer.childNodes.forEach { $0.removeFromParentNode() }
        for (_, tile) in roads {
            let n = roads[GridCoord(x: tile.coord.x, z: tile.coord.z - 1)] != nil
            let s = roads[GridCoord(x: tile.coord.x, z: tile.coord.z + 1)] != nil
            let e = roads[GridCoord(x: tile.coord.x + 1, z: tile.coord.z)] != nil
            let w = roads[GridCoord(x: tile.coord.x - 1, z: tile.coord.z)] != nil
            let node = makeAutoTiledRoadNode(tile: tile, north: n, south: s, east: e, west: w)
            node.position = worldPosition(for: tile.coord)
            roadContainer.addChildNode(node)
        }

        plotContainer.childNodes.forEach { $0.removeFromParentNode() }
        for (_, plot) in plots {
            let node = makeZonedBuildingNode(plot: plot)
            node.position = worldPosition(for: plot.coord)
            plotContainer.addChildNode(node)
        }

        facilityContainer.childNodes.forEach { $0.removeFromParentNode() }
        for (_, fac) in facilities {
            let node = makeFacilityNode(kind: fac.kind)
            node.position = worldPosition(for: fac.coord)
            facilityContainer.addChildNode(node)
        }

        utilityContainer.childNodes.forEach { $0.removeFromParentNode() }
        for (_, util) in utilities {
            let node = makeUtilityNode(kind: util.kind)
            node.position = worldPosition(for: util.coord)
            utilityContainer.addChildNode(node)
        }

        zonableGridContainer.childNodes.forEach { $0.removeFromParentNode() }
        if showZonableGrid {
            var candidateCoords = Set<GridCoord>()
            for r in roads.values where r.kind.isDriveable {
                for dz in -3...3 {
                    for dx in -3...3 {
                        if abs(dx) + abs(dz) <= 3 {
                            let c = GridCoord(x: r.coord.x + dx, z: r.coord.z + dz)
                            if abs(c.x) <= gridHalfExtent && abs(c.z) <= gridHalfExtent &&
                               roads[c] == nil && facilities[c] == nil && utilities[c] == nil {
                                candidateCoords.insert(c)
                            }
                        }
                    }
                }
            }
            let cellPlane = SCNBox(width: CGFloat(tileSize * 0.88), height: 0.02, length: CGFloat(tileSize * 0.88), chamferRadius: 0)
            let cMat = SCNMaterial()
            cMat.diffuse.contents = UIColor.cyan.withAlphaComponent(0.24)
            cellPlane.materials = [cMat]
            for c in candidateCoords {
                let n = SCNNode(geometry: cellPlane)
                let wp = worldPosition(for: c)
                n.position = SCNVector3(wp.x, wp.y + 0.03, wp.z)
                zonableGridContainer.addChildNode(n)
            }
        }

        let driveRoads = roads.filter { $0.value.kind.isDriveable }
        rebuildConnectedTrafficPool(driveRoads: driveRoads)
    }

    func updateSelectionPreview(coords: [GridCoord], isValid: Bool, tint: UIColor) {
        previewContainer.childNodes.forEach { $0.removeFromParentNode() }
        guard !coords.isEmpty else { return }
        let box = SCNBox(width: CGFloat(tileSize * 0.92), height: 0.16, length: CGFloat(tileSize * 0.92), chamferRadius: 0.04)
        let mat = SCNMaterial()
        mat.diffuse.contents = (isValid ? tint : UIColor.systemRed).withAlphaComponent(0.55)
        mat.emission.contents = (isValid ? tint : UIColor.systemRed).withAlphaComponent(0.35)
        box.materials = [mat]

        for c in coords {
            let n = SCNNode(geometry: box)
            let wp = worldPosition(for: c)
            n.position = SCNVector3(wp.x, wp.y + 0.09, wp.z)
            previewContainer.addChildNode(n)
        }
    }

    func setLensMode(_ mode: DataLensMode) {
        lensMode = mode
        switch mode {
        case .normal:
            roadContainer.opacity = 1.0
            plotContainer.opacity = 1.0
            facilityContainer.opacity = 1.0
        case .landValue:
            roadContainer.opacity = 0.55
            plotContainer.opacity = 1.0
            facilityContainer.opacity = 1.0
        case .utilities:
            roadContainer.opacity = 0.45
            plotContainer.opacity = 0.85
            facilityContainer.opacity = 0.55
        case .traffic:
            roadContainer.opacity = 1.0
            plotContainer.opacity = 0.40
            facilityContainer.opacity = 0.45
        }
    }

    func setCameraMode(_ mode: CameraMode) {
        cameraMode = mode
        if mode == .streetView {
            camDistance = 8.5
            camPitch = 0.25
        } else if mode == .drone {
            camDistance = 36.0
            camPitch = 0.68
        }
        updateCameraTransform()
    }

    func cycleFollowedVehicle() {
        simLock.lock()
        let count = agents.count
        simLock.unlock()
        guard count > 0 else { return }
        followedVehicleIndex = (followedVehicleIndex + 1) % count
        cameraMode = .followVehicle
    }

    func showAccidentMarker(at coord: GridCoord?) {
        incidentContainer.childNodes.forEach { $0.removeFromParentNode() }
        guard let coord else { return }
        let beacon = SCNCylinder(radius: 0.30, height: 1.9)
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor.systemRed
        mat.emission.contents = UIColor.systemRed
        beacon.materials = [mat]
        let node = SCNNode(geometry: beacon)
        let p = worldPosition(for: coord)
        node.position = SCNVector3(p.x, p.y + 0.95, p.z)
        incidentContainer.addChildNode(node)
    }

    // MARK: - Auto-Tiling Roads, Wide 4-Lane Boulevards & River Bridges

    private func makeAlphaFoliageTree(species: Int, swayPhase: Float = 0) -> SCNNode {
        let tree = SCNNode()
        let bank = NusantaraAssetBank.shared

        let trunk = SCNCylinder(radius: 0.055, height: 0.62)
        let tMat = SCNMaterial()
        tMat.diffuse.contents = UIColor(red: 0.36, green: 0.23, blue: 0.13, alpha: 1.0)
        trunk.materials = [tMat]
        let tNode = SCNNode(geometry: trunk)
        tNode.position.y = 0.31
        tree.addChildNode(tNode)

        let texName: String
        switch species {
        case 1: texName = "tree_pine_foliage.png"
        case 2: texName = "tree_tabebuya_foliage.png"
        default: texName = "tree_tropical_foliage.png"
        }

        let foliageMat = SCNMaterial()
        foliageMat.diffuse.contents = bank.texture(texName) ?? UIColor(red: 0.16, green: 0.52, blue: 0.20, alpha: 1.0)
        bank.applyHDFilter(foliageMat.diffuse, repeatTile: false)
        foliageMat.isDoubleSided = true
        foliageMat.transparencyMode = .aOne
        foliageMat.writesToDepthBuffer = true

        let canopy = SCNNode()
        canopy.position.y = 0.88
        for idx in 0..<3 {
            let card = SCNPlane(width: 1.24, height: 1.30)
            card.materials = [foliageMat]
            let cNode = SCNNode(geometry: card)
            cNode.eulerAngles.y = Float(idx) * (.pi / 3.0)
            canopy.addChildNode(cNode)
        }
        let s1 = SCNAction.rotateTo(x: 0.05, y: 0, z: 0.06, duration: 2.0)
        let s2 = SCNAction.rotateTo(x: -0.04, y: 0, z: -0.05, duration: 2.0)
        s1.timingMode = .easeInEaseOut
        s2.timingMode = .easeInEaseOut
        canopy.runAction(SCNAction.repeatForever(SCNAction.sequence([s1, s2])))
        tree.addChildNode(canopy)
        return tree
    }

    private func makeAutoTiledRoadNode(tile: RoadTile, north: Bool, south: Bool, east: Bool, west: Bool) -> SCNNode {
        let holder = SCNNode()
        let bank = NusantaraAssetBank.shared
        let isLit = timePhase.isLitTime
        let wp = worldPosition(for: tile.coord)
        let isOverRiver = wp.y < -0.18

        // Wide 4-lane boulevard takes extra width (2.85m = 2 full lane positions each direction)
        let roadWidth: CGFloat = tile.kind == .fourLane ? 2.85 : CGFloat(tileSize)

        if isOverRiver {
            // Automatic Concrete River Bridge Piers & Railings!
            let pier = SCNCylinder(radius: 0.24, height: 1.2)
            let pMat = SCNMaterial()
            pMat.diffuse.contents = UIColor(red: 0.55, green: 0.57, blue: 0.60, alpha: 1.0)
            pier.materials = [pMat]
            let pNode = SCNNode(geometry: pier)
            pNode.position.y = -0.35
            holder.addChildNode(pNode)
        } else {
            let foundation = SCNBox(width: roadWidth, height: 0.6, length: roadWidth, chamferRadius: 0)
            let fMat = SCNMaterial()
            fMat.diffuse.contents = UIColor(red: 0.34, green: 0.36, blue: 0.38, alpha: 1.0)
            foundation.materials = [fMat]
            let fNode = SCNNode(geometry: foundation)
            fNode.position.y = -0.28
            holder.addChildNode(fNode)
        }

        let deckY: Float = isOverRiver ? 0.28 : 0.03

        if tile.kind == .sidewalkTree {
            let paving = SCNBox(width: CGFloat(tileSize), height: 0.09, length: CGFloat(tileSize), chamferRadius: 0)
            let pMat = SCNMaterial()
            pMat.diffuse.contents = bank.texture("sidewalk_paving_albedo.png") ?? UIColor(red: 0.68, green: 0.64, blue: 0.58, alpha: 1.0)
            bank.applyHDFilter(pMat.diffuse)
            paving.materials = [pMat]
            let pNode = SCNNode(geometry: paving)
            pNode.position.y = 0.045
            holder.addChildNode(pNode)

            holder.addChildNode(makeAlphaFoliageTree(species: 0))
            return holder
        }

        let neighborCount = (north ? 1 : 0) + (south ? 1 : 0) + (east ? 1 : 0) + (west ? 1 : 0)
        let isIntersection = neighborCount >= 3

        let asphalt = SCNBox(width: roadWidth, height: 0.07, length: roadWidth, chamferRadius: 0)
        let aMat = SCNMaterial()
        let texName: String
        if isIntersection {
            texName = "road_intersection_albedo.png"
        } else {
            texName = tile.kind == .fourLane ? "road_4lane_albedo.png" : "road_2lane_albedo.png"
        }
        aMat.diffuse.contents = bank.texture(texName) ?? UIColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1.0)
        bank.applyHDFilter(aMat.diffuse, repeatTile: false)
        if let norm = bank.texture("asphalt_normal.png") {
            aMat.normal.contents = norm
            bank.applyHDFilter(aMat.normal)
        }
        asphalt.materials = [aMat]
        let aNode = SCNNode(geometry: asphalt)
        aNode.position.y = deckY

        if !isIntersection && (east || west) && !(north || south) {
            aNode.eulerAngles.y = .pi / 2.0
        } else if tile.kind == .elasticCurve {
            aNode.eulerAngles.y = tile.curveYaw
        }
        holder.addChildNode(aNode)

        if tile.kind == .roundabout {
            let island = SCNCylinder(radius: 0.72, height: 0.18)
            let iMat = SCNMaterial()
            iMat.diffuse.contents = bank.texture("grass_nusantara_albedo.png") ?? UIColor(red: 0.18, green: 0.62, blue: 0.28, alpha: 1.0)
            island.materials = [iMat]
            let iNode = SCNNode(geometry: island)
            iNode.position.y = deckY + 0.08
            holder.addChildNode(iNode)

            let monument = SCNCylinder(radius: 0.14, height: 1.12)
            let mMat = SCNMaterial()
            mMat.diffuse.contents = UIColor(red: 0.94, green: 0.88, blue: 0.74, alpha: 1.0)
            if isLit { mMat.emission.contents = UIColor.cyan.withAlphaComponent(0.75) }
            monument.materials = [mMat]
            let mNode = SCNNode(geometry: monument)
            mNode.position.y = deckY + 0.56
            holder.addChildNode(mNode)

            let blossom = makeAlphaFoliageTree(species: 2)
            blossom.scale = SCNVector3(0.65, 0.65, 0.65)
            blossom.position = SCNVector3(0.38, deckY + 0.10, 0.35)
            holder.addChildNode(blossom)
        } else if (abs(tile.coord.x) + abs(tile.coord.z)) % 2 == 0 {
            let poleOffset = Float(roadWidth) * 0.46
            let pole = SCNCylinder(radius: 0.025, height: 0.92)
            let poleMat = SCNMaterial()
            poleMat.diffuse.contents = UIColor.darkGray
            pole.materials = [poleMat]
            let poleNode = SCNNode(geometry: pole)
            poleNode.position = SCNVector3(poleOffset, deckY + 0.44, poleOffset)
            holder.addChildNode(poleNode)

            let bulb = SCNSphere(radius: 0.065)
            let bulbMat = SCNMaterial()
            bulbMat.diffuse.contents = UIColor(red: 1.0, green: 0.90, blue: 0.65, alpha: 1.0)
            bulbMat.emission.contents = isLit ? UIColor(red: 1.0, green: 0.84, blue: 0.38, alpha: 1.0) : UIColor.clear
            bulb.materials = [bulbMat]
            let bulbNode = SCNNode(geometry: bulb)
            bulbNode.position = SCNVector3(poleOffset, deckY + 0.90, poleOffset)
            holder.addChildNode(bulbNode)
        }

        return holder
    }

    private func makeZonedBuildingNode(plot: ZonedPlot) -> SCNNode {
        let holder = SCNNode()
        let w = CGFloat(tileSize * 0.94)
        let bank = NusantaraAssetBank.shared

        let foundation = SCNBox(width: w, height: 0.65, length: w, chamferRadius: 0)
        let fMat = SCNMaterial()
        fMat.diffuse.contents = UIColor(red: 0.36, green: 0.38, blue: 0.40, alpha: 1.0)
        foundation.materials = [fMat]
        let fNode = SCNNode(geometry: foundation)
        fNode.position.y = -0.30
        holder.addChildNode(fNode)

        let base = SCNBox(width: w, height: 0.05, length: w, chamferRadius: 0)
        let baseMat = SCNMaterial()
        switch plot.kind {
        case .residentialLow, .parkGreen:
            baseMat.diffuse.contents = bank.texture("grass_nusantara_albedo.png") ?? UIColor(red: 0.24, green: 0.68, blue: 0.32, alpha: 1.0)
        case .residentialHigh, .commercial:
            baseMat.diffuse.contents = bank.texture("sidewalk_paving_albedo.png") ?? UIColor(red: 0.25, green: 0.50, blue: 0.82, alpha: 1.0)
        case .industrialOffice:
            baseMat.diffuse.contents = UIColor(red: 0.52, green: 0.50, blue: 0.42, alpha: 1.0)
        case .clearZone:
            baseMat.diffuse.contents = UIColor.clear
        }
        bank.applyHDFilter(baseMat.diffuse)
        base.materials = [baseMat]
        let baseNode = SCNNode(geometry: base)
        baseNode.position.y = 0.025
        holder.addChildNode(baseNode)

        if plot.kind == .parkGreen {
            let t1 = makeAlphaFoliageTree(species: 2); t1.position = SCNVector3(-0.42, 0, -0.35)
            let t2 = makeAlphaFoliageTree(species: 0); t2.position = SCNVector3(0.42, 0, 0.35)
            holder.addChildNode(t1)
            holder.addChildNode(t2)
            return holder
        }

        if plot.buildingLevel == 0 {
            let scaffold = SCNBox(width: 1.15, height: 0.72, length: 1.15, chamferRadius: 0)
            let sMat = SCNMaterial()
            sMat.diffuse.contents = UIColor(red: 0.82, green: 0.66, blue: 0.28, alpha: 0.72)
            scaffold.materials = [sMat]
            let sNode = SCNNode(geometry: scaffold)
            sNode.position.y = 0.40
            holder.addChildNode(sNode)
            return holder
        }

        let hash = abs(plot.coord.x * 31 + plot.coord.z * 17) % 3
        let isLit = timePhase.isLitTime && plot.hasPower && !plot.isAbandoned

        switch plot.kind {
        case .residentialLow:
            let isTwoStory = plot.buildingLevel >= 3
            let floors: CGFloat = isTwoStory ? 1.38 : 0.74
            let body = SCNBox(width: 1.10, height: floors, length: 1.06, chamferRadius: 0.03)
            let mat = SCNMaterial()
            if plot.isAbandoned {
                mat.diffuse.contents = UIColor.darkGray
            } else if hash == 1, let kTex = bank.texture("kampung_warnawarni_albedo.png") {
                mat.diffuse.contents = kTex
            } else {
                mat.diffuse.contents = bank.texture("house_wall_albedo.png") ?? UIColor(red: 0.95, green: 0.92, blue: 0.86, alpha: 1.0)
            }
            bank.applyHDFilter(mat.diffuse)
            if isLit {
                mat.emission.contents = UIColor(red: 0.48, green: 0.36, blue: 0.14, alpha: 1.0)
            }
            body.materials = [mat]
            let bNode = SCNNode(geometry: body)
            bNode.position.y = Float(floors * 0.5) + 0.05
            holder.addChildNode(bNode)

            let porch = SCNBox(width: 0.85, height: 0.08, length: 0.34, chamferRadius: 0.01)
            let pMat = SCNMaterial()
            pMat.diffuse.contents = UIColor(red: 0.84, green: 0.82, blue: 0.78, alpha: 1.0)
            porch.materials = [pMat]
            let porchNode = SCNNode(geometry: porch)
            porchNode.position = SCNVector3(0, 0.42, 0.62)
            holder.addChildNode(porchNode)

            let fence = SCNBox(width: 1.66, height: 0.22, length: 0.06, chamferRadius: 0.01)
            fence.materials = [pMat]
            let fenceNode = SCNNode(geometry: fence)
            fenceNode.position = SCNVector3(0, 0.15, 0.86)
            holder.addChildNode(fenceNode)

            if isTwoStory {
                let toren = SCNCylinder(radius: 0.12, height: 0.24)
                let tMat = SCNMaterial()
                tMat.diffuse.contents = UIColor.systemOrange
                toren.materials = [tMat]
                let torenNode = SCNNode(geometry: toren)
                torenNode.position = SCNVector3(0.36, Float(floors) + 0.22, -0.32)
                holder.addChildNode(torenNode)
            }

            let roof = SCNPyramid(width: 1.26, height: 0.46, length: 1.22)
            let rMat = SCNMaterial()
            rMat.diffuse.contents = bank.texture("roof_terracotta_albedo.png") ?? UIColor(red: 0.65, green: 0.24, blue: 0.18, alpha: 1.0)
            bank.applyHDFilter(rMat.diffuse)
            roof.materials = [rMat]
            let rNode = SCNNode(geometry: roof)
            rNode.position.y = Float(floors) + 0.05
            holder.addChildNode(rNode)

        case .residentialHigh:
            let h = 1.45 + CGFloat(plot.buildingLevel) * 0.55
            let tower = SCNBox(width: 1.34, height: h, length: 1.34, chamferRadius: 0.04)
            let mat = SCNMaterial()
            mat.diffuse.contents = plot.isAbandoned ? UIColor.darkGray : (bank.texture("building_facade_day.png") ?? UIColor.lightGray)
            bank.applyHDFilter(mat.diffuse)
            mat.metalness.contents = 0.25
            mat.roughness.contents = 0.30
            if isLit {
                mat.emission.contents = bank.texture("building_facade_night_emission.png") ?? UIColor(red: 0.45, green: 0.36, blue: 0.16, alpha: 1.0)
            }
            tower.materials = [mat]
            let tNode = SCNNode(geometry: tower)
            tNode.position.y = Float(h * 0.5) + 0.05
            holder.addChildNode(tNode)

        case .commercial:
            if plot.forcedBrandSkin == 1 || (plot.forcedBrandSkin == 0 && plot.buildingLevel <= 2 && hash == 0) {
                let shop = SCNBox(width: 1.44, height: 0.94, length: 1.28, chamferRadius: 0.02)
                let sMat = SCNMaterial()
                sMat.diffuse.contents = bank.texture("indomaret_facade_albedo.png") ?? UIColor.systemBlue
                bank.applyHDFilter(sMat.diffuse, repeatTile: false)
                if isLit { sMat.emission.contents = UIColor(red: 0.32, green: 0.36, blue: 0.42, alpha: 1.0) }
                shop.materials = [sMat]
                let sNode = SCNNode(geometry: shop)
                sNode.position.y = 0.52
                holder.addChildNode(sNode)
            } else if plot.forcedBrandSkin == 2 || (plot.forcedBrandSkin == 0 && plot.buildingLevel <= 2 && hash == 1) {
                let shop = SCNBox(width: 1.44, height: 0.94, length: 1.28, chamferRadius: 0.02)
                let sMat = SCNMaterial()
                sMat.diffuse.contents = bank.texture("alfamart_facade_albedo.png") ?? UIColor.systemRed
                bank.applyHDFilter(sMat.diffuse, repeatTile: false)
                if isLit { sMat.emission.contents = UIColor(red: 0.36, green: 0.30, blue: 0.28, alpha: 1.0) }
                shop.materials = [sMat]
                let sNode = SCNNode(geometry: shop)
                sNode.position.y = 0.52
                holder.addChildNode(sNode)
            } else {
                let bHeight = 1.55 + CGFloat(plot.buildingLevel) * 0.64
                let tower = SCNBox(width: 1.36, height: bHeight, length: 1.36, chamferRadius: 0.05)
                let mat = SCNMaterial()
                mat.diffuse.contents = plot.isAbandoned ? UIColor.darkGray : (bank.texture("building_facade_day.png") ?? UIColor(red: 0.24, green: 0.46, blue: 0.74, alpha: 1.0))
                bank.applyHDFilter(mat.diffuse)
                mat.metalness.contents = 0.35
                mat.roughness.contents = 0.22
                if isLit {
                    mat.emission.contents = bank.texture("building_facade_night_emission.png") ?? UIColor(red: 0.25, green: 0.48, blue: 0.75, alpha: 1.0)
                }
                tower.materials = [mat]
                let tNode = SCNNode(geometry: tower)
                tNode.position.y = Float(bHeight * 0.5) + 0.05
                holder.addChildNode(tNode)
            }

        case .industrialOffice:
            let hallH = 1.0 + CGFloat(plot.buildingLevel) * 0.25
            let hall = SCNBox(width: 1.48, height: hallH, length: 1.24, chamferRadius: 0.02)
            let mat = SCNMaterial()
            mat.diffuse.contents = UIColor(red: 0.62, green: 0.58, blue: 0.48, alpha: 1.0)
            if isLit { mat.emission.contents = UIColor(red: 0.28, green: 0.24, blue: 0.14, alpha: 1.0) }
            hall.materials = [mat]
            let hNode = SCNNode(geometry: hall)
            hNode.position.y = Float(hallH * 0.5) + 0.05
            holder.addChildNode(hNode)

            let chimney = SCNCylinder(radius: 0.11, height: 1.95)
            let cMat = SCNMaterial()
            cMat.diffuse.contents = UIColor.darkGray
            chimney.materials = [cMat]
            let cNode = SCNNode(geometry: chimney)
            cNode.position = SCNVector3(0.45, 0.98, -0.35)
            holder.addChildNode(cNode)

        case .parkGreen, .clearZone:
            break
        }
        return holder
    }

    private func makeFacilityNode(kind: FacilityKind) -> SCNNode {
        let holder = SCNNode()
        let bank = NusantaraAssetBank.shared
        let w = CGFloat(tileSize * 0.95)
        let isLit = timePhase.isLitTime

        let plaza = SCNBox(width: w, height: 0.08, length: w, chamferRadius: 0)
        let pMat = SCNMaterial()
        pMat.diffuse.contents = bank.texture("sidewalk_paving_albedo.png") ?? UIColor.lightGray
        bank.applyHDFilter(pMat.diffuse)
        plaza.materials = [pMat]
        let pNode = SCNNode(geometry: plaza)
        pNode.position.y = 0.04
        holder.addChildNode(pNode)

        switch kind {
        case .universitas:
            let mainWing = SCNBox(width: 1.56, height: 1.95, length: 0.85, chamferRadius: 0.04)
            let mMat = SCNMaterial()
            mMat.diffuse.contents = bank.texture("school_facade_albedo.png") ?? UIColor.white
            if isLit { mMat.emission.contents = bank.texture("building_facade_night_emission.png") }
            mainWing.materials = [mMat]
            let mNode = SCNNode(geometry: mainWing)
            mNode.position = SCNVector3(0, 1.02, -0.25)
            holder.addChildNode(mNode)

            let roof = SCNPyramid(width: 1.66, height: 0.52, length: 0.96)
            let rMat = SCNMaterial()
            rMat.diffuse.contents = bank.texture("roof_terracotta_albedo.png") ?? UIColor.systemRed
            roof.materials = [rMat]
            let rNode = SCNNode(geometry: roof)
            rNode.position = SCNVector3(0, 2.0, -0.25)
            holder.addChildNode(rNode)

        case .sdNegeri, .smpUnggulan, .smaKejuruan:
            let blockA = SCNBox(width: 1.48, height: 0.92, length: 0.55, chamferRadius: 0.02)
            let sMat = SCNMaterial()
            sMat.diffuse.contents = bank.texture("school_facade_albedo.png") ?? UIColor.white
            if isLit { sMat.emission.contents = UIColor.yellow.withAlphaComponent(0.28) }
            blockA.materials = [sMat]
            let aNode = SCNNode(geometry: blockA)
            aNode.position = SCNVector3(0, 0.50, -0.45)
            holder.addChildNode(aNode)

            let roof = SCNPyramid(width: 1.56, height: 0.42, length: 0.64)
            let rMat = SCNMaterial()
            rMat.diffuse.contents = bank.texture("roof_terracotta_albedo.png") ?? UIColor.systemRed
            roof.materials = [rMat]
            let rNode = SCNNode(geometry: roof)
            rNode.position = SCNVector3(0, 0.96, -0.45)
            holder.addChildNode(rNode)

            let flagPole = SCNCylinder(radius: 0.02, height: 1.1)
            let fpNode = SCNNode(geometry: flagPole)
            fpNode.position = SCNVector3(0, 0.60, 0.35)
            holder.addChildNode(fpNode)

        case .balaiKota:
            let hall = SCNBox(width: 1.56, height: 1.35, length: 1.25, chamferRadius: 0.04)
            let bMat = SCNMaterial()
            bMat.diffuse.contents = UIColor(red: 0.95, green: 0.92, blue: 0.86, alpha: 1.0)
            if isLit { bMat.emission.contents = UIColor(red: 0.38, green: 0.30, blue: 0.14, alpha: 1.0) }
            hall.materials = [bMat]
            let hNode = SCNNode(geometry: hall)
            hNode.position.y = 0.72
            holder.addChildNode(hNode)

            let tower = SCNBox(width: 0.48, height: 2.35, length: 0.48, chamferRadius: 0.02)
            let tMat = SCNMaterial()
            tMat.diffuse.contents = UIColor(red: 0.82, green: 0.26, blue: 0.22, alpha: 1.0)
            tower.materials = [tMat]
            let tNode = SCNNode(geometry: tower)
            tNode.position.y = 1.22
            holder.addChildNode(tNode)

        case .rsud:
            let hosp = SCNBox(width: 1.54, height: 2.15, length: 1.32, chamferRadius: 0.05)
            let hMat = SCNMaterial()
            hMat.diffuse.contents = UIColor.white
            if isLit { hMat.emission.contents = bank.texture("building_facade_night_emission.png") }
            hosp.materials = [hMat]
            let hNode = SCNNode(geometry: hosp)
            hNode.position.y = 1.12
            holder.addChildNode(hNode)

            let cross = SCNBox(width: 0.45, height: 0.45, length: 1.36, chamferRadius: 0)
            let cMat = SCNMaterial()
            cMat.diffuse.contents = UIColor.systemRed
            cMat.emission.contents = UIColor.systemRed
            cross.materials = [cMat]
            let cNode = SCNNode(geometry: cross)
            cNode.position.y = 1.65
            holder.addChildNode(cNode)

        case .kantorPolisi, .pemadam:
            let station = SCNBox(width: 1.48, height: 1.15, length: 1.28, chamferRadius: 0.04)
            let stMat = SCNMaterial()
            stMat.diffuse.contents = kind == .pemadam ? UIColor.systemRed : UIColor(red: 0.22, green: 0.26, blue: 0.34, alpha: 1.0)
            station.materials = [stMat]
            let stNode = SCNNode(geometry: station)
            stNode.position.y = 0.62
            holder.addChildNode(stNode)
        }

        return holder
    }

    private func makeUtilityNode(kind: UtilityKind) -> SCNNode {
        let holder = SCNNode()
        if kind == .garduListrik {
            let sub = SCNBox(width: 1.35, height: 0.85, length: 1.35, chamferRadius: 0.03)
            let mat = SCNMaterial()
            mat.diffuse.contents = UIColor(red: 0.88, green: 0.68, blue: 0.14, alpha: 1.0)
            sub.materials = [mat]
            let node = SCNNode(geometry: sub)
            node.position.y = 0.45
            holder.addChildNode(node)
        } else {
            let tank = SCNCylinder(radius: 0.52, height: 1.45)
            let mat = SCNMaterial()
            mat.diffuse.contents = UIColor.systemCyan
            tank.materials = [mat]
            let node = SCNNode(geometry: tank)
            node.position.y = 0.75
            holder.addChildNode(node)
        }
        return holder
    }

    private func makeVehicleNode(kind: VehicleKind, index: Int) -> SCNNode {
        let holder = SCNNode()
        switch kind {
        case .motorbike:
            let body = SCNBox(width: 0.12, height: 0.16, length: 0.34, chamferRadius: 0.03)
            let bMat = SCNMaterial()
            bMat.diffuse.contents = [UIColor.systemRed, UIColor.black, UIColor.systemBlue][index % 3]
            body.materials = [bMat]
            let bNode = SCNNode(geometry: body)
            bNode.position.y = 0.12
            holder.addChildNode(bNode)

            let rider = SCNSphere(radius: 0.068)
            let rMat = SCNMaterial()
            rMat.diffuse.contents = UIColor.white
            rider.materials = [rMat]
            let rNode = SCNNode(geometry: rider)
            rNode.position = SCNVector3(0, 0.27, 0.02)
            holder.addChildNode(rNode)

        case .car:
            let chassis = SCNBox(width: 0.32, height: 0.14, length: 0.58, chamferRadius: 0.04)
            let cMat = SCNMaterial()
            cMat.diffuse.contents = [UIColor.white, UIColor.darkGray, UIColor.lightGray, UIColor.systemRed][index % 4]
            cMat.metalness.contents = 0.45
            cMat.roughness.contents = 0.22
            chassis.materials = [cMat]
            let chNode = SCNNode(geometry: chassis)
            chNode.position.y = 0.11
            holder.addChildNode(chNode)

            let cabin = SCNBox(width: 0.26, height: 0.12, length: 0.32, chamferRadius: 0.04)
            let gMat = SCNMaterial()
            gMat.diffuse.contents = UIColor(red: 0.15, green: 0.22, blue: 0.30, alpha: 1.0)
            cabin.materials = [gMat]
            let cabNode = SCNNode(geometry: cabin)
            cabNode.position = SCNVector3(0, 0.22, 0.02)
            holder.addChildNode(cabNode)

        case .angkotBus:
            let bus = SCNBox(width: 0.36, height: 0.26, length: 0.78, chamferRadius: 0.05)
            let bMat = SCNMaterial()
            bMat.diffuse.contents = UIColor.systemOrange
            bus.materials = [bMat]
            let bNode = SCNNode(geometry: bus)
            bNode.position.y = 0.16
            holder.addChildNode(bNode)

        case .emergency:
            let amb = SCNBox(width: 0.34, height: 0.24, length: 0.66, chamferRadius: 0.04)
            let aMat = SCNMaterial()
            aMat.diffuse.contents = UIColor.white
            amb.materials = [aMat]
            let aNode = SCNNode(geometry: amb)
            aNode.position.y = 0.15
            holder.addChildNode(aNode)

            let siren = SCNBox(width: 0.22, height: 0.06, length: 0.10, chamferRadius: 0.02)
            let sMat = SCNMaterial()
            sMat.diffuse.contents = UIColor.systemRed
            sMat.emission.contents = UIColor.systemRed
            siren.materials = [sMat]
            let sNode = SCNNode(geometry: siren)
            sNode.position = SCNVector3(0, 0.29, -0.10)
            holder.addChildNode(sNode)
        }

        if timePhase.isLitTime {
            let headlight = SCNSphere(radius: 0.055)
            let hMat = SCNMaterial()
            hMat.diffuse.contents = UIColor.white
            hMat.emission.contents = UIColor(red: 1.0, green: 0.96, blue: 0.78, alpha: 1.0)
            headlight.materials = [hMat]
            let hlNode = SCNNode(geometry: headlight)
            hlNode.position = SCNVector3(0, 0.11, -0.30)
            holder.addChildNode(hlNode)
        }

        return holder
    }

    // MARK: - Graph-Connected Left-Lane Traffic AI (Zero Center-Line Driving, 4-Lane Support!)

    private func connectedNeighbors(of c: GridCoord, in set: Set<GridCoord>) -> [GridCoord] {
        let candidates = [
            GridCoord(x: c.x + 1, z: c.z),
            GridCoord(x: c.x - 1, z: c.z),
            GridCoord(x: c.x, z: c.z + 1),
            GridCoord(x: c.x, z: c.z - 1)
        ]
        return candidates.filter { set.contains($0) }
    }

    private func rebuildConnectedTrafficPool(driveRoads: [GridCoord: RoadTile]) {
        simLock.lock()
        trafficContainer.childNodes.forEach { $0.removeFromParentNode() }
        agents.removeAll()
        roadKindMap = driveRoads.mapValues { $0.kind }
        driveableSet = Set(driveRoads.keys)

        let sortedCoords = driveableSet.sorted { ($0.x, $0.z) < ($1.x, $1.z) }
        if sortedCoords.count >= 2 {
            let count = min(28, max(6, sortedCoords.count * 2))
            let pattern: [VehicleKind] = [.motorbike, .car, .motorbike, .angkotBus, .car, .emergency]
            for i in 0..<count {
                let startCoord = sortedCoords[i % sortedCoords.count]
                let nbrs = connectedNeighbors(of: startCoord, in: driveableSet)
                guard let firstNext = nbrs.randomElement() else { continue }

                let vKind = pattern[i % pattern.count]
                let laneSlot = i % 2 // 0 = inner left lane, 1 = outer left lane on 4-lane roads
                let node = makeVehicleNode(kind: vKind, index: i)
                trafficContainer.addChildNode(node)
                let spd: Float = vKind == .motorbike ? 0.56 : (vKind == .emergency ? 0.64 : 0.42)
                agents.append(TrafficAgent(
                    node: node,
                    kind: vKind,
                    laneSlot: laneSlot,
                    currentCoord: startCoord,
                    nextCoord: firstNext,
                    prevCoord: startCoord,
                    progress: Float(i % 5) * 0.18,
                    speed: spd
                ))
            }
        }
        simLock.unlock()
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if lastUpdateTime == 0 { lastUpdateTime = time; return }
        let dt = Float(min(max(time - lastUpdateTime, 0.0), 0.08))
        lastUpdateTime = time

        waterScrollPhase += dt * 0.032
        waterMaterial?.normal.contentsTransform = SCNMatrix4MakeTranslation(waterScrollPhase, waterScrollPhase * 0.75, 0)

        if showcaseActive {
            camYaw += dt * 0.14
            updateCameraTransform()
        }

        simLock.lock()
        if !agents.isEmpty {
            for i in agents.indices {
                agents[i].progress += dt * agents[i].speed
                if agents[i].progress >= 1.0 {
                    agents[i].progress -= 1.0
                    let arrived = agents[i].nextCoord
                    let cameFrom = agents[i].currentCoord
                    agents[i].prevCoord = cameFrom
                    agents[i].currentCoord = arrived

                    let allNbrs = connectedNeighbors(of: arrived, in: driveableSet)
                    let forwardNbrs = allNbrs.filter { $0 != cameFrom }
                    if let chosen = forwardNbrs.randomElement() ?? allNbrs.first {
                        agents[i].nextCoord = chosen
                    }
                }

                let cA = agents[i].currentCoord
                let cB = agents[i].nextCoord
                let pA = worldPosition(for: cA)
                let pB = worldPosition(for: cB)
                let frac = agents[i].progress

                let dx = Float(cB.x - cA.x)
                let dz = Float(cB.z - cA.z)
                // Indonesian Left-Hand Traffic Normal Vector in XZ plane: Left = (dz, -dx)
                let leftX = dz
                let leftZ = -dx

                let rKind = roadKindMap[cA] ?? .twoLane
                let laneOffset: Float
                if rKind == .fourLane {
                    // Wide 4-lane boulevard: 2 distinct lanes on the left side of the median!
                    let base = agents[i].laneSlot == 0 ? Float(0.46) : Float(1.04)
                    laneOffset = agents[i].kind == .motorbike ? base + 0.16 : base
                } else {
                    // Standard 2-lane road: strictly centered in the left lane (clear of center line at 0.0!)
                    laneOffset = agents[i].kind == .motorbike ? 0.68 : 0.44
                }

                let deckLiftA: Float = pA.y < -0.18 ? 0.33 : 0.07
                let deckLiftB: Float = pB.y < -0.18 ? 0.33 : 0.07
                let wy = (pA.y + deckLiftA) + ((pB.y + deckLiftB) - (pA.y + deckLiftA)) * frac
                let wx = pA.x + (pB.x - pA.x) * frac + leftX * laneOffset
                let wz = pA.z + (pB.z - pA.z) * frac + leftZ * laneOffset

                agents[i].node.position = SCNVector3(wx, wy, wz)
                agents[i].node.look(at: SCNVector3(pB.x + leftX * laneOffset, pB.y + deckLiftB, pB.z + leftZ * laneOffset))
            }

            if cameraMode == .followVehicle, !agents.isEmpty {
                let vNode = agents[followedVehicleIndex % agents.count].node
                cameraPivot.position = vNode.position
                cameraPivot.eulerAngles = SCNVector3(0, camYaw, 0)
                cameraPitchNode.eulerAngles = SCNVector3(-0.38, 0, 0)
                cameraNode.position = SCNVector3(0, 0, 6.5)
            }
        }
        simLock.unlock()
    }

    func cycleTimePhase() -> TimeOfDayPhase {
        let all = TimeOfDayPhase.allCases
        let next = all[(timePhase.rawValue + 1) % all.count]
        timePhase = next
        applyAtmosphere(shadows: true, fog: true, bloom: true)
        NusantaraAssetBank.shared.playBGM(night: timePhase == .night)
        return timePhase
    }

    func applyAtmosphere(shadows: Bool, fog: Bool, bloom: Bool) {
        let bank = NusantaraAssetBank.shared
        sunLightNode.light?.castsShadow = shadows
        cameraNode.camera?.wantsHDR = bloom

        switch timePhase {
        case .day:
            let sky = bank.texture("sky_day_equirect.png")
            scene.background.contents = sky ?? UIColor(red: 0.48, green: 0.76, blue: 0.96, alpha: 1.0)
            scene.lightingEnvironment.contents = sky
            scene.lightingEnvironment.intensity = 1.20
            scene.fogColor = UIColor(red: 0.74, green: 0.89, blue: 0.98, alpha: 1.0)
            ambientLightNode.light?.intensity = 440
            sunLightNode.light?.intensity = 1400
            sunLightNode.light?.color = UIColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1.0)
            cameraNode.camera?.bloomIntensity = bloom ? 0.30 : 0.0

        case .sunset:
            let sky = bank.texture("sky_sunset_equirect.png")
            scene.background.contents = sky ?? UIColor(red: 0.92, green: 0.52, blue: 0.32, alpha: 1.0)
            scene.lightingEnvironment.contents = sky
            scene.lightingEnvironment.intensity = 1.08
            scene.fogColor = UIColor(red: 0.92, green: 0.58, blue: 0.38, alpha: 1.0)
            ambientLightNode.light?.intensity = 350
            sunLightNode.light?.intensity = 1120
            sunLightNode.light?.color = UIColor(red: 1.0, green: 0.68, blue: 0.38, alpha: 1.0)
            cameraNode.camera?.bloomIntensity = bloom ? 0.65 : 0.0

        case .night:
            let sky = bank.texture("sky_night_equirect.png")
            scene.background.contents = sky ?? UIColor(red: 0.02, green: 0.04, blue: 0.10, alpha: 1.0)
            scene.lightingEnvironment.contents = sky
            scene.lightingEnvironment.intensity = 0.68
            scene.fogColor = UIColor(red: 0.03, green: 0.05, blue: 0.12, alpha: 1.0)
            ambientLightNode.light?.intensity = 210
            sunLightNode.light?.intensity = 190
            sunLightNode.light?.color = UIColor(red: 0.55, green: 0.68, blue: 0.98, alpha: 1.0)
            cameraNode.camera?.bloomIntensity = bloom ? 0.92 : 0.0
        }

        scene.fogStartDistance = fog ? 68 : 360
        scene.fogEndDistance = fog ? 195 : 440
    }

    // Pure Horizontal Turntable Transform (Never Tilts/Rolls!)
    func updateCameraTransform() {
        let groundY = terrainHeight(x: panTarget.x, z: panTarget.y)
        cameraPivot.position = SCNVector3(panTarget.x, groundY, panTarget.y)
        cameraPivot.eulerAngles = SCNVector3(0, camYaw, 0)
        cameraPitchNode.eulerAngles = SCNVector3(-camPitch, 0, 0)
        cameraNode.position = SCNVector3(0, 0, camDistance)
        cameraNode.eulerAngles = SCNVector3Zero
    }

    func panCamera(dx: Float, dz: Float) {
        if cameraMode == .followVehicle { cameraMode = .drone }
        let rightX = cos(camYaw)
        let rightZ = -sin(camYaw)
        let upX = -sin(camYaw)
        let upZ = -cos(camYaw)
        let scale = camDistance * 0.0022 * cameraSensitivity
        panTarget.x = min(35, max(-35, panTarget.x - (rightX * dx - upX * dz) * scale))
        panTarget.y = min(35, max(-35, panTarget.y - (rightZ * dx - upZ * dz) * scale))
        updateCameraTransform()
    }

    func zoomCamera(scaleFactor: Float) {
        camDistance = min(78.0, max(6.8, camDistance / scaleFactor))
        updateCameraTransform()
    }

    func rotateHorizontal(deltaYaw: Float) {
        camYaw += deltaYaw * cameraSensitivity
        updateCameraTransform()
    }

    func worldPosition(for coord: GridCoord) -> SCNVector3 {
        let wx = Float(coord.x) * tileSize
        let wz = Float(coord.z) * tileSize
        let wy = terrainHeight(x: wx, z: wz)
        return SCNVector3(wx, wy, wz)
    }

    func gridCoord(at point: CGPoint, in scnView: SCNView) -> GridCoord? {
        let hits = scnView.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
        if let first = hits.first {
            let worldPos = first.worldCoordinates
            let gx = Int(round(worldPos.x / tileSize))
            let gz = Int(round(worldPos.z / tileSize))
            if abs(gx) <= gridHalfExtent && abs(gz) <= gridHalfExtent {
                return GridCoord(x: gx, z: gz)
            }
        }
        return nil
    }
}

struct SceneKitViewport: UIViewRepresentable {
    let engine: City3DEngine
    let interactive: Bool

    func makeCoordinator() -> Coordinator { Coordinator(engine: engine) }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView(frame: .zero, options: nil)
        scnView.scene = engine.scene
        scnView.delegate = engine
        scnView.isPlaying = true
        scnView.rendersContinuously = true
        scnView.antialiasingMode = .multisampling4X
        scnView.backgroundColor = .black

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onTap(_:)))
        let pan1 = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onOneFingerPan(_:)))
        pan1.minimumNumberOfTouches = 1
        pan1.maximumNumberOfTouches = 1

        let orbit2 = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onTwoFingerOrbit(_:)))
        orbit2.minimumNumberOfTouches = 2
        orbit2.maximumNumberOfTouches = 2

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onPinch(_:)))
        let rotate = UIRotationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onRotate(_:)))

        pinch.delegate = context.coordinator
        rotate.delegate = context.coordinator
        orbit2.delegate = context.coordinator

        scnView.addGestureRecognizer(tap)
        scnView.addGestureRecognizer(pan1)
        scnView.addGestureRecognizer(orbit2)
        scnView.addGestureRecognizer(pinch)
        scnView.addGestureRecognizer(rotate)

        context.coordinator.scnView = scnView
        context.coordinator.interactive = interactive
        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.interactive = interactive
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let engine: City3DEngine
        weak var scnView: SCNView?
        var interactive: Bool = true
        private var lastPan1: CGPoint = .zero
        private var lastOrbit2: CGPoint = .zero

        init(engine: City3DEngine) { self.engine = engine }

        func gestureRecognizer(_ g1: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith g2: UIGestureRecognizer) -> Bool {
            let twoFingerSet: [UIGestureRecognizer] = [g1, g2]
            let allTwoFinger = twoFingerSet.allSatisfy {
                $0 is UIPinchGestureRecognizer || $0 is UIRotationGestureRecognizer || ($0 as? UIPanGestureRecognizer)?.minimumNumberOfTouches == 2
            }
            return allTwoFinger
        }

        @objc func onTap(_ gesture: UITapGestureRecognizer) {
            guard interactive, let view = scnView else { return }
            if let coord = engine.gridCoord(at: gesture.location(in: view), in: view) {
                engine.onTileTapped?(coord)
            }
        }

        @objc func onOneFingerPan(_ gesture: UIPanGestureRecognizer) {
            guard interactive, let view = scnView else { return }
            let current = gesture.translation(in: view)
            if gesture.state == .began { lastPan1 = current; return }
            let dx = Float(current.x - lastPan1.x)
            let dy = Float(current.y - lastPan1.y)
            lastPan1 = current
            engine.panCamera(dx: dx, dz: dy)
        }

        @objc func onTwoFingerOrbit(_ gesture: UIPanGestureRecognizer) {
            guard interactive, let view = scnView else { return }
            let current = gesture.translation(in: view)
            if gesture.state == .began { lastOrbit2 = current; return }
            let dx = Float(current.x - lastOrbit2.x)
            lastOrbit2 = current
            engine.rotateHorizontal(deltaYaw: -dx * 0.008)
        }

        @objc func onPinch(_ gesture: UIPinchGestureRecognizer) {
            guard interactive else { return }
            if gesture.state == .changed {
                engine.zoomCamera(scaleFactor: Float(gesture.scale))
                gesture.scale = 1.0
            }
        }

        @objc func onRotate(_ gesture: UIRotationGestureRecognizer) {
            guard interactive else { return }
            if gesture.state == .changed {
                engine.rotateHorizontal(deltaYaw: Float(gesture.rotation))
                gesture.rotation = 0
            }
        }
    }
}

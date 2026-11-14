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
    case motorbike, ojolMotor, car, angkotBus, constructionTruck, emergency
}

struct TrafficAgent {
    let node: SCNNode
    let kind: VehicleKind
    let laneSlot: Int
    var currentCoord: GridCoord
    var nextCoord: GridCoord
    var prevCoord: GridCoord
    var progress: Float
    var baseSpeed: Float
    var pauseTimer: Float
    var weavePhase: Float
}

struct PedestrianAgent {
    let node: SCNNode
    var coordA: GridCoord
    var coordB: GridCoord
    var sideOffset: Float
    var progress: Float
    var speed: Float
}

final class City3DEngine: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    private let worldRoot = SCNNode()
    private let terrainContainer = SCNNode()
    private let riverSurfaceContainer = SCNNode()
    private let valleyNatureContainer = SCNNode()
    private let atmosphereParticlesNode = SCNNode()
    private let zonableGridContainer = SCNNode()
    private let previewContainer = SCNNode()
    private let roadContainer = SCNNode()
    private let plotContainer = SCNNode()
    private let facilityContainer = SCNNode()
    private let utilityContainer = SCNNode()
    private let trafficContainer = SCNNode()
    private let pedestrianContainer = SCNNode()
    private let incidentContainer = SCNNode()

    private let cameraPivot = SCNNode()
    private let cameraPitchNode = SCNNode()
    private let cameraNode = SCNNode()

    private let sunLightNode = SCNNode()
    private let skyFillLightNode = SCNNode()
    private let ambientLightNode = SCNNode()
    private var waterMaterial: SCNMaterial?
    private var waterNodeRef: SCNNode?

    private let simLock = NSLock()
    private var roadKindMap: [GridCoord: RoadKind] = [:]
    private var driveableSet: Set<GridCoord> = []
    private var agents: [TrafficAgent] = []
    private var pedestrians: [PedestrianAgent] = []
    private var hasActiveConstruction: Bool = false
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
    private var camPitch: Float = 0.64
    private var camDistance: Float = 34.0
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
        worldRoot.addChildNode(riverSurfaceContainer)
        worldRoot.addChildNode(valleyNatureContainer)
        worldRoot.addChildNode(atmosphereParticlesNode)
        worldRoot.addChildNode(zonableGridContainer)
        worldRoot.addChildNode(previewContainer)
        worldRoot.addChildNode(roadContainer)
        worldRoot.addChildNode(plotContainer)
        worldRoot.addChildNode(facilityContainer)
        worldRoot.addChildNode(utilityContainer)
        worldRoot.addChildNode(trafficContainer)
        worldRoot.addChildNode(pedestrianContainer)
        worldRoot.addChildNode(incidentContainer)

        scene.rootNode.addChildNode(cameraPivot)
        cameraPivot.addChildNode(cameraPitchNode)
        cameraPitchNode.addChildNode(cameraNode)

        let cam = SCNCamera()
        cam.zNear = 0.3
        cam.zFar = 460.0
        cam.fieldOfView = 40.0
        cam.wantsHDR = true
        cam.wantsExposureAdaptation = false
        cam.exposureOffset = 0.14
        cam.contrast = 1.08
        cam.saturation = 1.14
        cam.bloomIntensity = 0.30
        cam.bloomThreshold = 0.88
        cam.bloomBlurRadius = 10.0
        cam.screenSpaceAmbientOcclusionIntensity = 1.15
        cam.screenSpaceAmbientOcclusionRadius = 1.3
        cam.screenSpaceAmbientOcclusionBias = 0.04

        cameraNode.camera = cam
        cameraNode.eulerAngles = SCNVector3Zero
        updateCameraTransform()

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 410
        ambient.color = UIColor(red: 0.88, green: 0.93, blue: 1.0, alpha: 1.0)
        ambientLightNode.light = ambient
        scene.rootNode.addChildNode(ambientLightNode)

        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 320
        fill.color = UIColor(red: 0.72, green: 0.86, blue: 1.0, alpha: 1.0)
        fill.castsShadow = false
        skyFillLightNode.light = fill
        skyFillLightNode.eulerAngles = SCNVector3(-Float.pi / 3.2, -Float.pi * 0.75, 0)
        scene.rootNode.addChildNode(skyFillLightNode)

        // Clean Single-Pass 4096px Shadow Map (Zero Cascade Split Artifacts, Zero Shadow Acne!)
        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 1440
        sun.color = UIColor(red: 1.0, green: 0.96, blue: 0.90, alpha: 1.0)
        sun.castsShadow = true
        sun.shadowMode = .deferred
        sun.shadowSampleCount = 8
        sun.shadowRadius = 2.8
        sun.shadowMapSize = CGSize(width: 4096, height: 4096)
        sun.maximumShadowDistance = 64.0
        sun.shadowCascadeCount = 1
        sun.shadowBias = 0.008
        sun.orthographicScale = 44.0
        sun.shadowColor = UIColor(red: 0.12, green: 0.16, blue: 0.24, alpha: 0.42)
        sunLightNode.light = sun
        sunLightNode.eulerAngles = SCNVector3(-Float.pi / 2.2, Float.pi / 4.2, 0)
        scene.rootNode.addChildNode(sunLightNode)

        applyAtmosphere(shadows: true, fog: true, bloom: true)
    }

    // MARK: - Sculpted Valley, River Channel & Distant Mountains

    private func fractalMountainRidge(x: Float, z: Float) -> Float {
        let r1 = 1.0 - abs(sin(x * 0.036 + cos(z * 0.032) * 1.5))
        let r2 = 1.0 - abs(cos(z * 0.052 - sin(x * 0.044) * 1.3))
        let r3 = 1.0 - abs(sin((x + z) * 0.085))
        return pow(max(0.0, r1 * r2), 1.45) * 1.35 + r3 * 0.25
    }

    func riverCenterX(atZ z: Float) -> Float {
        switch currentMap {
        case .malang: return 18.0 + 2.6 * sin(z * 0.075)
        case .surabaya: return 14.0 + 2.2 * cos(z * 0.07)
        case .jakarta: return 12.0 + 2.4 * sin(z * 0.085)
        }
    }

    func terrainHeight(x: Float, z: Float) -> Float {
        let distFromCenter = sqrt(x * x + z * z)
        let mountainMask = max(0.0, (distFromCenter - 46.0) / 36.0)
        let mountainFactor = mountainMask * mountainMask

        let rCenter = riverCenterX(atZ: z)
        let riverChannel = exp(-pow((x - rCenter) / 5.2, 2.0)) * -0.95

        switch currentMap {
        case .malang:
            let ridge = fractalMountainRidge(x: x, z: z) * 30.0 * mountainFactor
            let arjunoNorth = max(0.0, (-z - 38.0) * 0.36) * mountainFactor
            return riverChannel + ridge + arjunoNorth

        case .surabaya:
            let coastDrop = max(0.0, (x - 38.0) * -0.25)
            let distantHills = max(0.0, (-x - 44.0) / 32.0) * fractalMountainRidge(x: x, z: z) * 18.0
            return riverChannel + coastDrop + distantHills

        case .jakarta:
            let bayDrop = max(0.0, (-z - 38.0) * -0.25)
            let salakHills = max(0.0, (z - 44.0) / 32.0) * fractalMountainRidge(x: x, z: z) * 20.0
            return riverChannel + bayDrop + salakHills
        }
    }

    func loadMap(_ mapType: CityMapType, showcaseDemo: Bool) {
        currentMap = mapType
        showcaseActive = showcaseDemo
        cameraMode = .drone

        terrainContainer.childNodes.forEach { $0.removeFromParentNode() }
        riverSurfaceContainer.childNodes.forEach { $0.removeFromParentNode() }
        valleyNatureContainer.childNodes.forEach { $0.removeFromParentNode() }
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
        pedestrianContainer.childNodes.forEach { $0.removeFromParentNode() }
        agents.removeAll()
        pedestrians.removeAll()
        driveableSet.removeAll()
        roadKindMap.removeAll()
        simLock.unlock()

        panTarget = SIMD2<Float>(0, 0)
        camPitch = 0.62
        camDistance = showcaseDemo ? 32.0 : 35.0
        updateCameraTransform()

        buildHighDetailTerrainAndFlowingRiver()
        populateLivingValleyGrassAndTrees(occupied: [])
        NusantaraAssetBank.shared.playBGM(night: timePhase == .night)

        if showcaseDemo {
            buildShowcaseCity()
        }
    }

    private func buildHighDetailTerrainAndFlowingRiver() {
        let bank = NusantaraAssetBank.shared
        let segs = 160
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
                uvs.append(CGPoint(x: CGFloat(vx * 84.0), y: CGFloat(vz * 84.0)))

                let eps: Float = 0.80
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

                if y < -0.52 {
                    // Deep riverbed stone & turquoise silt
                    colors.append(SCNVector3(0.24, 0.50, 0.54))
                } else if y < -0.06 {
                    // Sandy pebble riverbank visible beneath clear shallow water!
                    colors.append(SCNVector3(0.88, 0.82, 0.64))
                } else if y > 22.0 {
                    colors.append(SCNVector3(0.76, 0.80, 0.84))
                } else if nyNorm < 0.82 || y > 9.0 {
                    colors.append(SCNVector3(0.46, 0.48, 0.47))
                } else {
                    colors.append(SCNVector3(0.92, 1.0, 0.88))
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
        mat.lightingModel = .physicallyBased
        if let grassTex = bank.texture("grass_nusantara_albedo.png") {
            mat.diffuse.contents = grassTex
            bank.applyHDFilter(mat.diffuse)
            if let grassNorm = bank.texture("grass_normal.png") {
                mat.normal.contents = grassNorm
                bank.applyHDFilter(mat.normal)
            }
        } else {
            mat.diffuse.contents = UIColor(red: 0.24, green: 0.52, blue: 0.22, alpha: 1.0)
        }
        mat.roughness.contents = 0.88
        mat.metalness.contents = 0.0
        geo.materials = [mat]
        terrainContainer.addChildNode(SCNNode(geometry: geo))

        // Flowing River Surface with Whitewater Foam & Translucent Shallows
        let waterPlane = SCNPlane(width: 520, height: 520)
        let wMat = SCNMaterial()
        wMat.lightingModel = .physicallyBased
        if let riverTex = bank.texture("river_water_albedo.png") {
            wMat.diffuse.contents = riverTex
            wMat.diffuse.contentsTransform = SCNMatrix4MakeScale(44, 44, 1)
            bank.applyHDFilter(wMat.diffuse)
        } else {
            wMat.diffuse.contents = UIColor(red: 0.06, green: 0.42, blue: 0.62, alpha: 0.84)
        }
        if let wNorm = bank.texture("water_normal.png") {
            wMat.normal.contents = wNorm
            wMat.normal.contentsTransform = SCNMatrix4MakeScale(52, 52, 1)
            bank.applyHDFilter(wMat.normal)
        }
        wMat.transparency = 0.80
        wMat.metalness.contents = 0.12
        wMat.roughness.contents = 0.08
        wMat.clearCoat.contents = 1.0
        wMat.clearCoatRoughness.contents = 0.05
        waterPlane.materials = [wMat]
        waterMaterial = wMat
        let waterNode = SCNNode(geometry: waterPlane)
        waterNode.eulerAngles.x = -.pi / 2
        waterNode.position.y = -0.22
        waterNodeRef = waterNode
        riverSurfaceContainer.addChildNode(waterNode)

        // Natural Riverbank Boulders & Reeds along both banks
        let rockMat = SCNMaterial()
        rockMat.lightingModel = .physicallyBased
        rockMat.diffuse.contents = UIColor(red: 0.44, green: 0.45, blue: 0.46, alpha: 1.0)
        rockMat.roughness.contents = 0.85
        let rockGeo = SCNSphere(radius: 0.34)
        rockGeo.materials = [rockMat]

        for r in 0..<110 {
            let rz = -38.0 + Float(r) * 0.70
            let center = riverCenterX(atZ: rz)
            let side: Float = (r % 2 == 0) ? -3.8 : 3.8
            let rx = center + side + Float(r % 3) * 0.25
            let ry = terrainHeight(x: rx, z: rz)
            if ry > -0.26 && ry < 0.02 {
                let boulder = SCNNode(geometry: rockGeo)
                boulder.scale = SCNVector3(1.5, 0.62, 1.15)
                boulder.position = SCNVector3(rx, ry + 0.05, rz)
                terrainContainer.addChildNode(boulder)
            }
        }
    }

    // MARK: - Valley-Wide 3D Grass Tufts, Tropical Trees & Falling Leaves

    private func populateLivingValleyGrassAndTrees(occupied: Set<GridCoord>) {
        valleyNatureContainer.childNodes.forEach { $0.removeFromParentNode() }
        let bank = NusantaraAssetBank.shared

        // 1. Crossed 3D Meadow Grass Tufts across the ENTIRE buildable valley & foothills!
        let tuftMat = SCNMaterial()
        tuftMat.lightingModel = .physicallyBased
        tuftMat.diffuse.contents = bank.texture("grass_tuft_cutout.png") ?? UIColor(red: 0.22, green: 0.62, blue: 0.22, alpha: 1.0)
        bank.applyHDFilter(tuftMat.diffuse, repeatTile: false)
        tuftMat.isDoubleSided = true
        tuftMat.transparencyMode = .aOne
        tuftMat.writesToDepthBuffer = true

        let cardA = SCNPlane(width: 0.68, height: 0.46)
        cardA.materials = [tuftMat]
        let cardB = SCNPlane(width: 0.68, height: 0.46)
        cardB.materials = [tuftMat]

        for g in 0..<520 {
            let gx = Float((g * 37) % 76 - 38) + Float(g % 5) * 0.18
            let gz = Float((g * 53) % 76 - 38) + Float((g + 2) % 5) * 0.18
            let coord = GridCoord(x: Int(round(gx / tileSize)), z: Int(round(gz / tileSize)))
            if occupied.contains(coord) { continue }

            let gy = terrainHeight(x: gx, z: gz)
            if gy > -0.02 && gy < 6.5 {
                let clump = SCNNode()
                let n1 = SCNNode(geometry: cardA)
                let n2 = SCNNode(geometry: cardB)
                n2.eulerAngles.y = .pi / 2.0
                clump.addChildNode(n1)
                clump.addChildNode(n2)
                clump.position = SCNVector3(gx, gy + 0.20, gz)
                clump.eulerAngles.y = Float(g) * 0.7

                if g % 2 == 0 {
                    let swayA = SCNAction.rotateTo(x: 0.14, y: CGFloat(clump.eulerAngles.y), z: 0.12, duration: 1.5 + Double(g % 4) * 0.25)
                    let swayB = SCNAction.rotateTo(x: -0.10, y: CGFloat(clump.eulerAngles.y), z: -0.10, duration: 1.5 + Double(g % 4) * 0.25)
                    swayA.timingMode = .easeInEaseOut
                    swayB.timingMode = .easeInEaseOut
                    clump.runAction(SCNAction.repeatForever(SCNAction.sequence([swayA, swayB])))
                }
                valleyNatureContainer.addChildNode(clump)
            }
        }

        // 2. Natural Tropical Trees INSIDE the valley + dense forest around the mountains
        for t in 0..<320 {
            let tx: Float
            let tz: Float
            if t < 95 {
                // Trees dotted naturally inside the buildable valley (cleared automatically when player builds there!)
                tx = Float((t * 43) % 68 - 34)
                tz = Float((t * 61) % 68 - 34)
                if abs(tx) < 7 && abs(tz) < 7 { continue }
            } else {
                let angle = Float(t) * 0.6180339 * 2.0 * .pi
                let dist = 39.0 + Float(t % 42) * 1.45
                tx = cos(angle) * dist
                tz = sin(angle) * dist
            }

            let coord = GridCoord(x: Int(round(tx / tileSize)), z: Int(round(tz / tileSize)))
            if occupied.contains(coord) { continue }

            let ty = terrainHeight(x: tx, z: tz)
            if ty > 0.02 && ty < 13.0 {
                let species = currentMap == .malang ? (t % 2 == 0 ? 1 : 0) : (t % 3)
                let tree = makeAlphaFoliageTree(species: species)
                let s = Float(0.88 + Double(t % 5) * 0.15)
                tree.scale = SCNVector3(s, s, s)
                tree.position = SCNVector3(tx, ty, tz)
                valleyNatureContainer.addChildNode(tree)
            }
        }

        updateWeatherParticles()
    }

    func setWeather(_ weather: CityWeather) {
        currentWeather = weather
        // Rise river level slightly during heavy tropical rain
        waterNodeRef?.position.y = weather == .hujanTropis ? -0.13 : -0.22
        updateWeatherParticles()
    }

    private func updateWeatherParticles() {
        atmosphereParticlesNode.removeAllParticleSystems()
        atmosphereParticlesNode.position = SCNVector3(0, 12, 0)

        // Falling Wind-Blown Leaves & Pink Tabebuya Petals
        let leafPS = SCNParticleSystem()
        leafPS.birthRate = currentWeather == .anginSepoi ? 42 : 18
        leafPS.particleLifeSpan = 8.5
        leafPS.particleSize = 0.14
        leafPS.particleColor = UIColor(red: 0.62, green: 0.74, blue: 0.24, alpha: 0.92)
        leafPS.emitterShape = SCNBox(width: 72, height: 2, length: 72, chamferRadius: 0)
        leafPS.emittingDirection = SCNVector3(0.45, -1.0, 0.25)
        leafPS.spreadingAngle = 35
        leafPS.particleVelocity = currentWeather == .anginSepoi ? 2.8 : 1.5
        leafPS.particleAngularVelocity = 2.0
        atmosphereParticlesNode.addParticleSystem(leafPS)

        if currentWeather == .hujanTropis {
            let rainPS = SCNParticleSystem()
            rainPS.birthRate = 480
            rainPS.particleLifeSpan = 1.6
            rainPS.particleSize = 0.045
            rainPS.particleColor = UIColor(red: 0.72, green: 0.86, blue: 1.0, alpha: 0.65)
            rainPS.emitterShape = SCNBox(width: 72, height: 1, length: 72, chamferRadius: 0)
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
        demoPlots[GridCoord(x: -3, z: 1)] = ZonedPlot(coord: GridCoord(x: -3, z: 1), kind: .residentialLow, buildingLevel: 6, residents: 5, maxResidents: 6)
        demoPlots[GridCoord(x: -2, z: 1)] = ZonedPlot(coord: GridCoord(x: -2, z: 1), kind: .residentialHigh, buildingLevel: 7, residents: 22, maxResidents: 24)
        demoPlots[GridCoord(x: 2, z: 1)] = ZonedPlot(coord: GridCoord(x: 2, z: 1), kind: .commercial, buildingLevel: 4, residents: 4, maxResidents: 4, forcedBrandSkin: 1)
        demoPlots[GridCoord(x: 4, z: 1)] = ZonedPlot(coord: GridCoord(x: 4, z: 1), kind: .commercial, buildingLevel: 6, residents: 6, maxResidents: 6)

        syncWorld(roads: demoRoads, plots: demoPlots, facilities: demoFacs, utilities: [:], showZonableGrid: false)
    }

    func syncWorld(
        roads: [GridCoord: RoadTile],
        plots: [GridCoord: ZonedPlot],
        facilities: [GridCoord: FacilityTile],
        utilities: [GridCoord: UtilityTile],
        showZonableGrid: Bool
    ) {
        var occupied = Set<GridCoord>()
        roads.keys.forEach { occupied.insert($0) }
        plots.keys.forEach { occupied.insert($0) }
        facilities.keys.forEach { occupied.insert($0) }
        utilities.keys.forEach { occupied.insert($0) }
        populateLivingValleyGrassAndTrees(occupied: occupied)

        hasActiveConstruction = plots.values.contains { $0.buildingLevel < 3 }

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
            let cellPlane = SCNBox(width: CGFloat(tileSize * 0.90), height: 0.015, length: CGFloat(tileSize * 0.90), chamferRadius: 0)
            let cMat = SCNMaterial()
            cMat.diffuse.contents = UIColor.cyan.withAlphaComponent(0.24)
            cellPlane.materials = [cMat]
            for c in candidateCoords {
                let n = SCNNode(geometry: cellPlane)
                let wp = worldPosition(for: c)
                n.position = SCNVector3(wp.x, wp.y + 0.02, wp.z)
                zonableGridContainer.addChildNode(n)
            }
        }

        let driveRoads = roads.filter { $0.value.kind.isDriveable }
        rebuildConnectedTrafficAndPedestrians(driveRoads: driveRoads)
    }

    func updateSelectionPreview(coords: [GridCoord], isValid: Bool, tint: UIColor) {
        previewContainer.childNodes.forEach { $0.removeFromParentNode() }
        guard !coords.isEmpty else { return }
        let box = SCNBox(width: CGFloat(tileSize * 0.94), height: 0.12, length: CGFloat(tileSize * 0.94), chamferRadius: 0.03)
        let mat = SCNMaterial()
        mat.diffuse.contents = (isValid ? tint : UIColor.systemRed).withAlphaComponent(0.55)
        mat.emission.contents = (isValid ? tint : UIColor.systemRed).withAlphaComponent(0.35)
        box.materials = [mat]

        for c in coords {
            let n = SCNNode(geometry: box)
            let wp = worldPosition(for: c)
            n.position = SCNVector3(wp.x, wp.y + 0.07, wp.z)
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
            camDistance = 8.0
            camPitch = 0.24
        } else if mode == .drone {
            camDistance = 34.0
            camPitch = 0.62
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
        let beacon = SCNCylinder(radius: 0.28, height: 1.8)
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor.systemRed
        mat.emission.contents = UIColor.systemRed
        beacon.materials = [mat]
        let node = SCNNode(geometry: beacon)
        let p = worldPosition(for: coord)
        node.position = SCNVector3(p.x, p.y + 0.90, p.z)
        incidentContainer.addChildNode(node)
    }

    // MARK: - Grounded Contact Shadows, Staged Construction & PBR Architecture

    private func makeContactShadowPlane(width: CGFloat, length: CGFloat) -> SCNNode {
        let p = SCNPlane(width: width, height: length)
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(red: 0.04, green: 0.06, blue: 0.08, alpha: 0.44)
        mat.writesToDepthBuffer = false
        p.materials = [mat]
        let n = SCNNode(geometry: p)
        n.eulerAngles.x = -.pi / 2
        n.position.y = 0.008
        return n
    }

    private func makeRoofSlabMaterial() -> SCNMaterial {
        let mat = SCNMaterial()
        mat.lightingModel = .physicallyBased
        mat.diffuse.contents = UIColor(red: 0.48, green: 0.50, blue: 0.53, alpha: 1.0)
        mat.roughness.contents = 0.88
        mat.metalness.contents = 0.05
        return mat
    }

    private func makeSkyscraperTowerMaterial(isLit: Bool, isAbandoned: Bool) -> SCNMaterial {
        let bank = NusantaraAssetBank.shared
        let mat = SCNMaterial()
        mat.lightingModel = .physicallyBased
        if isAbandoned {
            mat.diffuse.contents = UIColor.darkGray
            mat.roughness.contents = 0.90
            return mat
        }
        mat.diffuse.contents = bank.texture("building_facade_day.png") ?? UIColor(red: 0.28, green: 0.48, blue: 0.72, alpha: 1.0)
        bank.applyHDFilter(mat.diffuse)

        if let norm = bank.texture("building_facade_normal.png") {
            mat.normal.contents = norm
            bank.applyHDFilter(mat.normal)
        }
        if let met = bank.texture("building_facade_metalness.png") {
            mat.metalness.contents = met
            bank.applyHDFilter(mat.metalness)
        } else {
            mat.metalness.contents = 0.65
        }
        if let rough = bank.texture("building_facade_roughness.png") {
            mat.roughness.contents = rough
            bank.applyHDFilter(mat.roughness)
        } else {
            mat.roughness.contents = 0.18
        }
        if isLit {
            mat.emission.contents = bank.texture("building_facade_night_emission.png") ?? UIColor(red: 0.45, green: 0.36, blue: 0.16, alpha: 1.0)
        }
        return mat
    }

    private func addRooftopDetails(to parent: SCNNode, width: CGFloat, depth: CGFloat, topY: Float, tallBeacon: Bool) {
        let concreteMat = makeRoofSlabMaterial()
        let pThick: CGFloat = 0.07
        let pHeight: CGFloat = 0.14
        let frontBack = SCNBox(width: width, height: pHeight, length: pThick, chamferRadius: 0.01)
        frontBack.materials = [concreteMat]
        let leftRight = SCNBox(width: pThick, height: pHeight, length: depth, chamferRadius: 0.01)
        leftRight.materials = [concreteMat]

        let n1 = SCNNode(geometry: frontBack); n1.position = SCNVector3(0, topY + 0.07, Float(depth * 0.5 - pThick * 0.5))
        let n2 = SCNNode(geometry: frontBack); n2.position = SCNVector3(0, topY + 0.07, -Float(depth * 0.5 - pThick * 0.5))
        let n3 = SCNNode(geometry: leftRight); n3.position = SCNVector3(Float(width * 0.5 - pThick * 0.5), topY + 0.07, 0)
        let n4 = SCNNode(geometry: leftRight); n4.position = SCNVector3(-Float(width * 0.5 - pThick * 0.5), topY + 0.07, 0)
        parent.addChildNode(n1); parent.addChildNode(n2); parent.addChildNode(n3); parent.addChildNode(n4)

        let pent = SCNBox(width: width * 0.36, height: 0.28, length: depth * 0.34, chamferRadius: 0.02)
        pent.materials = [concreteMat]
        let pNode = SCNNode(geometry: pent)
        pNode.position = SCNVector3(-Float(width * 0.16), topY + 0.14, -Float(depth * 0.16))
        parent.addChildNode(pNode)

        let hvacMat = SCNMaterial()
        hvacMat.lightingModel = .physicallyBased
        hvacMat.diffuse.contents = UIColor(red: 0.72, green: 0.75, blue: 0.78, alpha: 1.0)
        hvacMat.metalness.contents = 0.5
        hvacMat.roughness.contents = 0.35
        let hvac = SCNCylinder(radius: 0.13, height: 0.14)
        hvac.materials = [hvacMat]
        let hNode = SCNNode(geometry: hvac)
        hNode.position = SCNVector3(Float(width * 0.20), topY + 0.07, Float(depth * 0.18))
        parent.addChildNode(hNode)

        if tallBeacon {
            let spire = SCNCylinder(radius: 0.018, height: 0.65)
            spire.materials = [hvacMat]
            let sNode = SCNNode(geometry: spire)
            sNode.position = SCNVector3(-Float(width * 0.16), topY + 0.55, -Float(depth * 0.16))
            parent.addChildNode(sNode)

            let beacon = SCNSphere(radius: 0.036)
            let bMat = SCNMaterial()
            bMat.diffuse.contents = UIColor.systemRed
            bMat.emission.contents = UIColor.systemRed
            beacon.materials = [bMat]
            let bNode = SCNNode(geometry: beacon)
            bNode.position = SCNVector3(-Float(width * 0.16), topY + 0.88, -Float(depth * 0.16))
            parent.addChildNode(bNode)
        }
    }

    private func makeAlphaFoliageTree(species: Int) -> SCNNode {
        let tree = SCNNode()
        let bank = NusantaraAssetBank.shared
        tree.addChildNode(makeContactShadowPlane(width: 0.92, length: 0.92))

        let trunk = SCNCylinder(radius: 0.052, height: 0.62)
        let tMat = SCNMaterial()
        tMat.lightingModel = .physicallyBased
        tMat.diffuse.contents = UIColor(red: 0.36, green: 0.23, blue: 0.13, alpha: 1.0)
        tMat.roughness.contents = 0.85
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
        foliageMat.lightingModel = .physicallyBased
        foliageMat.diffuse.contents = bank.texture(texName) ?? UIColor(red: 0.16, green: 0.52, blue: 0.20, alpha: 1.0)
        bank.applyHDFilter(foliageMat.diffuse, repeatTile: false)
        foliageMat.roughness.contents = 0.72
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
        let s1 = SCNAction.rotateTo(x: 0.04, y: 0, z: 0.05, duration: 2.1)
        let s2 = SCNAction.rotateTo(x: -0.04, y: 0, z: -0.05, duration: 2.1)
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

        let roadWidth: CGFloat = tile.kind == .fourLane ? 2.85 : CGFloat(tileSize)

        if isOverRiver {
            let bridgeMat = makeRoofSlabMaterial()
            let pier = SCNCylinder(radius: 0.22, height: 1.1)
            pier.materials = [bridgeMat]
            let pNode = SCNNode(geometry: pier)
            pNode.position.y = -0.25
            holder.addChildNode(pNode)

            let rail = SCNBox(width: roadWidth, height: 0.18, length: 0.10, chamferRadius: 0.02)
            rail.materials = [bridgeMat]
            let r1 = SCNNode(geometry: rail); r1.position = SCNVector3(0, 0.36, Float(roadWidth * 0.46))
            let r2 = SCNNode(geometry: rail); r2.position = SCNVector3(0, 0.36, -Float(roadWidth * 0.46))
            holder.addChildNode(r1); holder.addChildNode(r2)
        }

        let deckY: Float = isOverRiver ? 0.28 : 0.022

        if tile.kind == .sidewalkTree {
            let paving = SCNBox(width: CGFloat(tileSize), height: 0.045, length: CGFloat(tileSize), chamferRadius: 0)
            let pMat = SCNMaterial()
            pMat.lightingModel = .physicallyBased
            pMat.diffuse.contents = bank.texture("sidewalk_paving_albedo.png") ?? UIColor(red: 0.74, green: 0.72, blue: 0.68, alpha: 1.0)
            pMat.roughness.contents = 0.82
            bank.applyHDFilter(pMat.diffuse)
            paving.materials = [pMat]
            let pNode = SCNNode(geometry: paving)
            pNode.position.y = 0.022
            holder.addChildNode(pNode)
            holder.addChildNode(makeAlphaFoliageTree(species: 0))
            return holder
        }

        let neighborCount = (north ? 1 : 0) + (south ? 1 : 0) + (east ? 1 : 0) + (west ? 1 : 0)
        let isIntersection = neighborCount >= 3

        let asphalt = SCNBox(width: roadWidth, height: 0.045, length: roadWidth, chamferRadius: 0)
        let aMat = SCNMaterial()
        aMat.lightingModel = .physicallyBased
        let texName: String
        if isIntersection {
            texName = "road_intersection_albedo.png"
        } else {
            texName = tile.kind == .fourLane ? "road_4lane_albedo.png" : "road_2lane_albedo.png"
        }
        aMat.diffuse.contents = bank.texture(texName) ?? UIColor(red: 0.18, green: 0.19, blue: 0.22, alpha: 1.0)
        bank.applyHDFilter(aMat.diffuse, repeatTile: false)
        if let norm = bank.texture("asphalt_normal.png") {
            aMat.normal.contents = norm
            bank.applyHDFilter(aMat.normal)
        }
        aMat.roughness.contents = currentWeather == .hujanTropis ? 0.18 : 0.78
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
            let island = SCNCylinder(radius: 0.72, height: 0.12)
            let iMat = SCNMaterial()
            iMat.lightingModel = .physicallyBased
            iMat.diffuse.contents = bank.texture("grass_nusantara_albedo.png") ?? UIColor(red: 0.22, green: 0.58, blue: 0.24, alpha: 1.0)
            iMat.roughness.contents = 0.85
            island.materials = [iMat]
            let iNode = SCNNode(geometry: island)
            iNode.position.y = deckY + 0.06
            holder.addChildNode(iNode)

            let monument = SCNCylinder(radius: 0.13, height: 1.12)
            let mMat = SCNMaterial()
            mMat.lightingModel = .physicallyBased
            mMat.diffuse.contents = UIColor(red: 0.94, green: 0.88, blue: 0.74, alpha: 1.0)
            mMat.metalness.contents = 0.4
            mMat.roughness.contents = 0.3
            if isLit { mMat.emission.contents = UIColor.cyan.withAlphaComponent(0.75) }
            monument.materials = [mMat]
            let mNode = SCNNode(geometry: monument)
            mNode.position.y = deckY + 0.56
            holder.addChildNode(mNode)

            // Night Angkringan Cart beside Alun-Alun Roundabout!
            if isLit {
                let cart = SCNBox(width: 0.42, height: 0.26, length: 0.22, chamferRadius: 0.02)
                let cMat = SCNMaterial()
                cMat.diffuse.contents = UIColor(red: 0.55, green: 0.34, blue: 0.16, alpha: 1.0)
                cart.materials = [cMat]
                let cartNode = SCNNode(geometry: cart)
                cartNode.position = SCNVector3(-0.36, deckY + 0.22, 0.36)
                holder.addChildNode(cartNode)

                let lantern = SCNSphere(radius: 0.05)
                let lMat = SCNMaterial()
                lMat.diffuse.contents = UIColor.orange
                lMat.emission.contents = UIColor(red: 1.0, green: 0.74, blue: 0.24, alpha: 1.0)
                lantern.materials = [lMat]
                let lNode = SCNNode(geometry: lantern)
                lNode.position = SCNVector3(-0.36, deckY + 0.45, 0.36)
                holder.addChildNode(lNode)
            }
        } else if (abs(tile.coord.x) + abs(tile.coord.z)) % 2 == 0 {
            let poleOffset = Float(roadWidth) * 0.46
            let pole = SCNCylinder(radius: 0.022, height: 0.92)
            let poleMat = SCNMaterial()
            poleMat.lightingModel = .physicallyBased
            poleMat.diffuse.contents = UIColor.darkGray
            poleMat.metalness.contents = 0.7
            pole.materials = [poleMat]
            let poleNode = SCNNode(geometry: pole)
            poleNode.position = SCNVector3(poleOffset, deckY + 0.44, poleOffset)
            holder.addChildNode(poleNode)

            let bulb = SCNSphere(radius: 0.06)
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
        let w = CGFloat(tileSize * 0.95)
        let bank = NusantaraAssetBank.shared

        let base = SCNBox(width: w, height: 0.025, length: w, chamferRadius: 0)
        let baseMat = SCNMaterial()
        baseMat.lightingModel = .physicallyBased
        switch plot.kind {
        case .residentialLow, .parkGreen:
            baseMat.diffuse.contents = bank.texture("grass_nusantara_albedo.png") ?? UIColor(red: 0.24, green: 0.62, blue: 0.26, alpha: 1.0)
            baseMat.roughness.contents = 0.88
        case .residentialHigh, .commercial:
            baseMat.diffuse.contents = bank.texture("sidewalk_paving_albedo.png") ?? UIColor(red: 0.74, green: 0.72, blue: 0.68, alpha: 1.0)
            baseMat.roughness.contents = 0.80
        case .industrialOffice:
            baseMat.diffuse.contents = UIColor(red: 0.56, green: 0.55, blue: 0.52, alpha: 1.0)
            baseMat.roughness.contents = 0.85
        case .clearZone:
            baseMat.diffuse.contents = UIColor.clear
        }
        bank.applyHDFilter(baseMat.diffuse)
        base.materials = [baseMat]
        let baseNode = SCNNode(geometry: base)
        baseNode.position.y = 0.012
        holder.addChildNode(baseNode)

        if plot.kind == .parkGreen {
            let t1 = makeAlphaFoliageTree(species: 2); t1.position = SCNVector3(-0.42, 0, -0.35)
            let t2 = makeAlphaFoliageTree(species: 0); t2.position = SCNVector3(0.42, 0, 0.35)
            holder.addChildNode(t1)
            holder.addChildNode(t2)
            return holder
        }

        // Realistic Multi-Stage Construction Phases (0 -> 1 -> 2 before completed building >= 3!)
        if plot.buildingLevel == 0 {
            // Stage 0: Patok Tanah Kayu & Tumpukan Bata/Pasir
            let sandMound = SCNSphere(radius: 0.28)
            let sMat = SCNMaterial(); sMat.diffuse.contents = UIColor(red: 0.68, green: 0.62, blue: 0.50, alpha: 1.0)
            sandMound.materials = [sMat]
            let sNode = SCNNode(geometry: sandMound)
            sNode.scale = SCNVector3(1.2, 0.45, 1.0)
            sNode.position = SCNVector3(-0.32, 0.08, 0.24)
            holder.addChildNode(sNode)

            let brickStack = SCNBox(width: 0.36, height: 0.22, length: 0.26, chamferRadius: 0.01)
            let bMat = SCNMaterial(); bMat.diffuse.contents = bank.texture("brick_construction_albedo.png") ?? UIColor.brown
            brickStack.materials = [bMat]
            let bNode = SCNNode(geometry: brickStack)
            bNode.position = SCNVector3(0.32, 0.12, -0.22)
            holder.addChildNode(bNode)

            for sx in [-0.55, 0.55] as [Float] {
                for sz in [-0.55, 0.55] as [Float] {
                    let stake = SCNCylinder(radius: 0.025, height: 0.36)
                    let stMat = SCNMaterial(); stMat.diffuse.contents = UIColor.systemOrange
                    stake.materials = [stMat]
                    let stNode = SCNNode(geometry: stake)
                    stNode.position = SCNVector3(sx, 0.18, sz)
                    holder.addChildNode(stNode)
                }
            }
            return holder
        }

        if plot.buildingLevel == 1 {
            // Stage 1: Pondasi Batu Kali & Kolom Beton Awal
            let foundation = SCNBox(width: 1.12, height: 0.20, length: 1.08, chamferRadius: 0.01)
            let fMat = SCNMaterial(); fMat.diffuse.contents = UIColor(red: 0.46, green: 0.47, blue: 0.49, alpha: 1.0)
            foundation.materials = [fMat]
            let fNode = SCNNode(geometry: foundation)
            fNode.position.y = 0.11
            holder.addChildNode(fNode)

            for px in [-0.46, 0.46] as [Float] {
                for pz in [-0.44, 0.44] as [Float] {
                    let col = SCNBox(width: 0.08, height: 0.56, length: 0.08, chamferRadius: 0)
                    col.materials = [fMat]
                    let cNode = SCNNode(geometry: col)
                    cNode.position = SCNVector3(px, 0.38, pz)
                    holder.addChildNode(cNode)
                }
            }
            return holder
        }

        if plot.buildingLevel == 2 {
            // Stage 2: Dinding Bata Merah & Perancah Bambu (Scaffolding)
            let brickWall = SCNBox(width: 1.08, height: 0.68, length: 1.04, chamferRadius: 0.01)
            let bMat = SCNMaterial()
            bMat.lightingModel = .physicallyBased
            bMat.diffuse.contents = bank.texture("brick_construction_albedo.png") ?? UIColor(red: 0.68, green: 0.32, blue: 0.22, alpha: 1.0)
            bank.applyHDFilter(bMat.diffuse)
            brickWall.materials = [bMat]
            let wNode = SCNNode(geometry: brickWall)
            wNode.position.y = 0.36
            holder.addChildNode(wNode)

            let bambooMat = SCNMaterial()
            bambooMat.diffuse.contents = UIColor(red: 0.76, green: 0.64, blue: 0.28, alpha: 1.0)
            for bx in [-0.62, 0.62] as [Float] {
                let pole = SCNCylinder(radius: 0.022, height: 0.94)
                pole.materials = [bambooMat]
                let pNode = SCNNode(geometry: pole)
                pNode.position = SCNVector3(bx, 0.47, 0.58)
                holder.addChildNode(pNode)
            }
            let crossBeam = SCNBox(width: 1.32, height: 0.03, length: 0.04, chamferRadius: 0)
            crossBeam.materials = [bambooMat]
            let cbNode = SCNNode(geometry: crossBeam)
            cbNode.position = SCNVector3(0, 0.62, 0.58)
            holder.addChildNode(cbNode)
            return holder
        }

        // Completed Architectural Levels (level >= 3 maps to Building Tier 1..5)
        let tier = max(1, plot.buildingLevel - 2)
        let hash = abs(plot.coord.x * 31 + plot.coord.z * 17) % 3
        let isLit = timePhase.isLitTime && plot.hasPower && !plot.isAbandoned

        holder.addChildNode(makeContactShadowPlane(width: 1.48, length: 1.44))

        switch plot.kind {
        case .residentialLow:
            let isTwoStory = tier >= 3
            let floors: CGFloat = isTwoStory ? 1.36 : 0.72
            let body = SCNBox(width: 1.08, height: floors, length: 1.04, chamferRadius: 0.02)
            let mat = SCNMaterial()
            mat.lightingModel = .physicallyBased
            mat.roughness.contents = 0.72
            if plot.isAbandoned {
                mat.diffuse.contents = UIColor.darkGray
            } else if hash == 1, let kTex = bank.texture("kampung_warnawarni_albedo.png") {
                mat.diffuse.contents = kTex
            } else {
                mat.diffuse.contents = bank.texture("house_wall_albedo.png") ?? UIColor(red: 0.95, green: 0.92, blue: 0.86, alpha: 1.0)
            }
            bank.applyHDFilter(mat.diffuse)
            if isLit {
                mat.emission.contents = UIColor(red: 0.44, green: 0.34, blue: 0.14, alpha: 1.0)
            }
            body.materials = [mat]
            let bNode = SCNNode(geometry: body)
            bNode.position.y = Float(floors * 0.5) + 0.025
            holder.addChildNode(bNode)

            let trimMat = SCNMaterial()
            trimMat.lightingModel = .physicallyBased
            trimMat.diffuse.contents = UIColor(red: 0.92, green: 0.90, blue: 0.86, alpha: 1.0)
            trimMat.roughness.contents = 0.65

            let porchRoof = SCNBox(width: 0.88, height: 0.07, length: 0.36, chamferRadius: 0.01)
            porchRoof.materials = [trimMat]
            let prNode = SCNNode(geometry: porchRoof)
            prNode.position = SCNVector3(0, 0.46, 0.64)
            holder.addChildNode(prNode)

            for px in [-0.36, 0.36] as [Float] {
                let pillar = SCNCylinder(radius: 0.032, height: 0.44)
                pillar.materials = [trimMat]
                let pNode = SCNNode(geometry: pillar)
                pNode.position = SCNVector3(px, 0.24, 0.76)
                holder.addChildNode(pNode)
            }

            let fence = SCNBox(width: 1.66, height: 0.20, length: 0.05, chamferRadius: 0.01)
            fence.materials = [trimMat]
            let fenceNode = SCNNode(geometry: fence)
            fenceNode.position = SCNVector3(0, 0.12, 0.88)
            holder.addChildNode(fenceNode)

            let roof = SCNPyramid(width: 1.32, height: 0.48, length: 1.28)
            let rMat = SCNMaterial()
            rMat.lightingModel = .physicallyBased
            rMat.diffuse.contents = bank.texture("roof_terracotta_albedo.png") ?? UIColor(red: 0.68, green: 0.26, blue: 0.18, alpha: 1.0)
            if let rNorm = bank.texture("roof_normal.png") {
                rMat.normal.contents = rNorm
                bank.applyHDFilter(rMat.normal)
            }
            rMat.roughness.contents = 0.68
            bank.applyHDFilter(rMat.diffuse)
            roof.materials = [rMat]
            let rNode = SCNNode(geometry: roof)
            rNode.position.y = Float(floors) + 0.01
            holder.addChildNode(rNode)

        case .residentialHigh:
            let roofMat = makeRoofSlabMaterial()
            let glassMat = makeSkyscraperTowerMaterial(isLit: isLit, isAbandoned: plot.isAbandoned)

            let podium = SCNBox(width: 1.46, height: 0.42, length: 1.46, chamferRadius: 0.02)
            podium.materials = [roofMat]
            let podNode = SCNNode(geometry: podium)
            podNode.position.y = 0.23
            holder.addChildNode(podNode)

            let shaftH = 1.15 + CGFloat(tier) * 0.52
            let tower = SCNBox(width: 1.32, height: shaftH, length: 1.32, chamferRadius: 0.03)
            tower.materials = [glassMat, glassMat, glassMat, glassMat, roofMat, roofMat]
            let tNode = SCNNode(geometry: tower)
            let topY = Float(0.44 + shaftH)
            tNode.position.y = Float(0.44 + shaftH * 0.5)
            holder.addChildNode(tNode)

            addRooftopDetails(to: holder, width: 1.32, depth: 1.32, topY: topY, tallBeacon: tier >= 4)

        case .commercial:
            let roofMat = makeRoofSlabMaterial()
            if plot.forcedBrandSkin == 1 || (plot.forcedBrandSkin == 0 && tier <= 2 && hash == 0) {
                let shop = SCNBox(width: 1.46, height: 0.94, length: 1.28, chamferRadius: 0.02)
                let sMat = SCNMaterial()
                sMat.lightingModel = .physicallyBased
                sMat.diffuse.contents = bank.texture("indomaret_facade_albedo.png") ?? UIColor.systemBlue
                sMat.roughness.contents = 0.45
                bank.applyHDFilter(sMat.diffuse, repeatTile: false)
                if isLit { sMat.emission.contents = UIColor(red: 0.32, green: 0.36, blue: 0.42, alpha: 1.0) }
                shop.materials = [sMat, sMat, sMat, sMat, roofMat, roofMat]
                let sNode = SCNNode(geometry: shop)
                sNode.position.y = 0.49
                holder.addChildNode(sNode)
                addRooftopDetails(to: holder, width: 1.46, depth: 1.28, topY: 0.96, tallBeacon: false)
            } else if plot.forcedBrandSkin == 2 || (plot.forcedBrandSkin == 0 && tier <= 2 && hash == 1) {
                let shop = SCNBox(width: 1.46, height: 0.94, length: 1.28, chamferRadius: 0.02)
                let sMat = SCNMaterial()
                sMat.lightingModel = .physicallyBased
                sMat.diffuse.contents = bank.texture("alfamart_facade_albedo.png") ?? UIColor.systemRed
                sMat.roughness.contents = 0.45
                bank.applyHDFilter(sMat.diffuse, repeatTile: false)
                if isLit { sMat.emission.contents = UIColor(red: 0.36, green: 0.30, blue: 0.28, alpha: 1.0) }
                shop.materials = [sMat, sMat, sMat, sMat, roofMat, roofMat]
                let sNode = SCNNode(geometry: shop)
                sNode.position.y = 0.49
                holder.addChildNode(sNode)
                addRooftopDetails(to: holder, width: 1.46, depth: 1.28, topY: 0.96, tallBeacon: false)
            } else {
                let glassMat = makeSkyscraperTowerMaterial(isLit: isLit, isAbandoned: plot.isAbandoned)
                let podium = SCNBox(width: 1.48, height: 0.48, length: 1.48, chamferRadius: 0.02)
                podium.materials = [roofMat]
                let podNode = SCNNode(geometry: podium)
                podNode.position.y = 0.26
                holder.addChildNode(podNode)

                let lowerH = 1.15 + CGFloat(tier) * 0.46
                let lowerTower = SCNBox(width: 1.34, height: lowerH, length: 1.34, chamferRadius: 0.03)
                lowerTower.materials = [glassMat, glassMat, glassMat, glassMat, roofMat, roofMat]
                let ltNode = SCNNode(geometry: lowerTower)
                ltNode.position.y = Float(0.50 + lowerH * 0.5)
                holder.addChildNode(ltNode)

                let upperH = 0.65 + CGFloat(tier) * 0.24
                let upperTower = SCNBox(width: 1.02, height: upperH, length: 1.02, chamferRadius: 0.03)
                upperTower.materials = [glassMat, glassMat, glassMat, glassMat, roofMat, roofMat]
                let utNode = SCNNode(geometry: upperTower)
                let topY = Float(0.50 + lowerH + upperH)
                utNode.position.y = Float(0.50 + lowerH + upperH * 0.5)
                holder.addChildNode(utNode)

                addRooftopDetails(to: holder, width: 1.02, depth: 1.02, topY: topY, tallBeacon: true)
            }

        case .industrialOffice:
            let roofMat = makeRoofSlabMaterial()
            let hallH = 0.98 + CGFloat(tier) * 0.24
            let hall = SCNBox(width: 1.48, height: hallH, length: 1.24, chamferRadius: 0.02)
            let mat = SCNMaterial()
            mat.lightingModel = .physicallyBased
            mat.diffuse.contents = UIColor(red: 0.62, green: 0.60, blue: 0.54, alpha: 1.0)
            mat.roughness.contents = 0.78
            if isLit { mat.emission.contents = UIColor(red: 0.28, green: 0.24, blue: 0.14, alpha: 1.0) }
            hall.materials = [mat, mat, mat, mat, roofMat, roofMat]
            let hNode = SCNNode(geometry: hall)
            hNode.position.y = Float(hallH * 0.5) + 0.025
            holder.addChildNode(hNode)

            let chimney = SCNCylinder(radius: 0.11, height: 1.95)
            let cMat = SCNMaterial()
            cMat.lightingModel = .physicallyBased
            cMat.diffuse.contents = UIColor.darkGray
            cMat.metalness.contents = 0.6
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
        let roofMat = makeRoofSlabMaterial()

        let plaza = SCNBox(width: w, height: 0.03, length: w, chamferRadius: 0)
        let pMat = SCNMaterial()
        pMat.lightingModel = .physicallyBased
        pMat.diffuse.contents = bank.texture("sidewalk_paving_albedo.png") ?? UIColor.lightGray
        pMat.roughness.contents = 0.80
        bank.applyHDFilter(pMat.diffuse)
        plaza.materials = [pMat]
        let pNode = SCNNode(geometry: plaza)
        pNode.position.y = 0.015
        holder.addChildNode(pNode)

        switch kind {
        case .universitas:
            let mainWing = SCNBox(width: 1.56, height: 1.95, length: 0.85, chamferRadius: 0.03)
            let mMat = SCNMaterial()
            mMat.lightingModel = .physicallyBased
            mMat.diffuse.contents = bank.texture("school_facade_albedo.png") ?? UIColor.white
            if isLit { mMat.emission.contents = bank.texture("building_facade_night_emission.png") }
            mainWing.materials = [mMat, mMat, mMat, mMat, roofMat, roofMat]
            let mNode = SCNNode(geometry: mainWing)
            mNode.position = SCNVector3(0, 1.00, -0.25)
            holder.addChildNode(mNode)

            let roof = SCNPyramid(width: 1.68, height: 0.52, length: 0.98)
            let rMat = SCNMaterial()
            rMat.lightingModel = .physicallyBased
            rMat.diffuse.contents = bank.texture("roof_terracotta_albedo.png") ?? UIColor.systemRed
            roof.materials = [rMat]
            let rNode = SCNNode(geometry: roof)
            rNode.position = SCNVector3(0, 1.96, -0.25)
            holder.addChildNode(rNode)

        case .sdNegeri, .smpUnggulan, .smaKejuruan:
            let blockA = SCNBox(width: 1.48, height: 0.92, length: 0.55, chamferRadius: 0.02)
            let sMat = SCNMaterial()
            sMat.lightingModel = .physicallyBased
            sMat.diffuse.contents = bank.texture("school_facade_albedo.png") ?? UIColor.white
            if isLit { sMat.emission.contents = UIColor.yellow.withAlphaComponent(0.28) }
            blockA.materials = [sMat, sMat, sMat, sMat, roofMat, roofMat]
            let aNode = SCNNode(geometry: blockA)
            aNode.position = SCNVector3(0, 0.48, -0.45)
            holder.addChildNode(aNode)

            let roof = SCNPyramid(width: 1.60, height: 0.42, length: 0.68)
            let rMat = SCNMaterial()
            rMat.lightingModel = .physicallyBased
            rMat.diffuse.contents = bank.texture("roof_terracotta_albedo.png") ?? UIColor.systemRed
            roof.materials = [rMat]
            let rNode = SCNNode(geometry: roof)
            rNode.position = SCNVector3(0, 0.94, -0.45)
            holder.addChildNode(rNode)

            let flagPole = SCNCylinder(radius: 0.02, height: 1.1)
            let fpNode = SCNNode(geometry: flagPole)
            fpNode.position = SCNVector3(0, 0.58, 0.35)
            holder.addChildNode(fpNode)

        case .balaiKota:
            let hall = SCNBox(width: 1.56, height: 1.35, length: 1.25, chamferRadius: 0.03)
            let bMat = SCNMaterial()
            bMat.lightingModel = .physicallyBased
            bMat.diffuse.contents = UIColor(red: 0.95, green: 0.92, blue: 0.86, alpha: 1.0)
            bMat.roughness.contents = 0.65
            if isLit { bMat.emission.contents = UIColor(red: 0.38, green: 0.30, blue: 0.14, alpha: 1.0) }
            hall.materials = [bMat]
            let hNode = SCNNode(geometry: hall)
            hNode.position.y = 0.70
            holder.addChildNode(hNode)

            let tower = SCNBox(width: 0.48, height: 2.35, length: 0.48, chamferRadius: 0.02)
            let tMat = SCNMaterial()
            tMat.lightingModel = .physicallyBased
            tMat.diffuse.contents = UIColor(red: 0.82, green: 0.26, blue: 0.22, alpha: 1.0)
            tower.materials = [tMat]
            let tNode = SCNNode(geometry: tower)
            tNode.position.y = 1.20
            holder.addChildNode(tNode)

        case .rsud:
            let hosp = SCNBox(width: 1.54, height: 2.15, length: 1.32, chamferRadius: 0.04)
            let hMat = SCNMaterial()
            hMat.lightingModel = .physicallyBased
            hMat.diffuse.contents = UIColor.white
            hMat.roughness.contents = 0.40
            if isLit { hMat.emission.contents = bank.texture("building_facade_night_emission.png") }
            hosp.materials = [hMat, hMat, hMat, hMat, roofMat, roofMat]
            let hNode = SCNNode(geometry: hosp)
            hNode.position.y = 1.10
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
            let station = SCNBox(width: 1.48, height: 1.15, length: 1.28, chamferRadius: 0.03)
            let stMat = SCNMaterial()
            stMat.lightingModel = .physicallyBased
            stMat.diffuse.contents = kind == .pemadam ? UIColor.systemRed : UIColor(red: 0.22, green: 0.26, blue: 0.34, alpha: 1.0)
            station.materials = [stMat]
            let stNode = SCNNode(geometry: station)
            stNode.position.y = 0.60
            holder.addChildNode(stNode)
        }

        return holder
    }

    private func makeUtilityNode(kind: UtilityKind) -> SCNNode {
        let holder = SCNNode()
        if kind == .garduListrik {
            let sub = SCNBox(width: 1.35, height: 0.85, length: 1.35, chamferRadius: 0.03)
            let mat = SCNMaterial()
            mat.lightingModel = .physicallyBased
            mat.diffuse.contents = UIColor(red: 0.88, green: 0.68, blue: 0.14, alpha: 1.0)
            mat.metalness.contents = 0.4
            sub.materials = [mat]
            let node = SCNNode(geometry: sub)
            node.position.y = 0.44
            holder.addChildNode(node)
        } else {
            let tank = SCNCylinder(radius: 0.52, height: 1.45)
            let mat = SCNMaterial()
            mat.lightingModel = .physicallyBased
            mat.diffuse.contents = UIColor.systemCyan
            mat.metalness.contents = 0.3
            tank.materials = [mat]
            let node = SCNNode(geometry: tank)
            node.position.y = 0.74
            holder.addChildNode(node)
        }
        return holder
    }

    private func makeVehicleNode(kind: VehicleKind, index: Int) -> SCNNode {
        let holder = SCNNode()
        holder.addChildNode(makeContactShadowPlane(width: kind == .motorbike || kind == .ojolMotor ? 0.24 : 0.46, length: 0.66))

        switch kind {
        case .motorbike, .ojolMotor:
            let body = SCNBox(width: 0.12, height: 0.16, length: 0.34, chamferRadius: 0.03)
            let bMat = SCNMaterial()
            bMat.lightingModel = .physicallyBased
            bMat.diffuse.contents = kind == .ojolMotor ? UIColor.systemGreen : [UIColor.systemRed, UIColor.black, UIColor.systemBlue][index % 3]
            body.materials = [bMat]
            let bNode = SCNNode(geometry: body)
            bNode.position.y = 0.11
            holder.addChildNode(bNode)

            let rider = SCNSphere(radius: 0.068)
            let rMat = SCNMaterial()
            rMat.diffuse.contents = kind == .ojolMotor ? UIColor(red: 0.12, green: 0.72, blue: 0.32, alpha: 1.0) : UIColor.white
            rider.materials = [rMat]
            let rNode = SCNNode(geometry: rider)
            rNode.position = SCNVector3(0, 0.26, 0.02)
            holder.addChildNode(rNode)

        case .car:
            let chassis = SCNBox(width: 0.32, height: 0.14, length: 0.58, chamferRadius: 0.04)
            let cMat = SCNMaterial()
            cMat.lightingModel = .physicallyBased
            cMat.diffuse.contents = [UIColor.white, UIColor.darkGray, UIColor.lightGray, UIColor.systemRed][index % 4]
            cMat.metalness.contents = 0.65
            cMat.roughness.contents = 0.18
            chassis.materials = [cMat]
            let chNode = SCNNode(geometry: chassis)
            chNode.position.y = 0.10
            holder.addChildNode(chNode)

            let cabin = SCNBox(width: 0.26, height: 0.12, length: 0.32, chamferRadius: 0.04)
            let gMat = SCNMaterial()
            gMat.lightingModel = .physicallyBased
            gMat.diffuse.contents = UIColor(red: 0.12, green: 0.18, blue: 0.26, alpha: 1.0)
            gMat.metalness.contents = 0.85
            gMat.roughness.contents = 0.08
            cabin.materials = [gMat]
            let cabNode = SCNNode(geometry: cabin)
            cabNode.position = SCNVector3(0, 0.21, 0.02)
            holder.addChildNode(cabNode)

        case .angkotBus:
            let bus = SCNBox(width: 0.36, height: 0.26, length: 0.78, chamferRadius: 0.05)
            let bMat = SCNMaterial()
            bMat.lightingModel = .physicallyBased
            bMat.diffuse.contents = UIColor.systemOrange
            bMat.metalness.contents = 0.35
            bMat.roughness.contents = 0.30
            bus.materials = [bMat]
            let bNode = SCNNode(geometry: bus)
            bNode.position.y = 0.15
            holder.addChildNode(bNode)

        case .constructionTruck:
            let cab = SCNBox(width: 0.34, height: 0.24, length: 0.28, chamferRadius: 0.03)
            let cMat = SCNMaterial(); cMat.diffuse.contents = UIColor.systemYellow
            cab.materials = [cMat]
            let cabNode = SCNNode(geometry: cab)
            cabNode.position = SCNVector3(0, 0.14, -0.22)
            holder.addChildNode(cabNode)

            let bed = SCNBox(width: 0.36, height: 0.20, length: 0.48, chamferRadius: 0.02)
            let bMat = SCNMaterial(); bMat.diffuse.contents = UIColor(red: 0.68, green: 0.34, blue: 0.22, alpha: 1.0)
            bed.materials = [bMat]
            let bedNode = SCNNode(geometry: bed)
            bedNode.position = SCNVector3(0, 0.14, 0.14)
            holder.addChildNode(bedNode)

        case .emergency:
            let amb = SCNBox(width: 0.34, height: 0.24, length: 0.66, chamferRadius: 0.04)
            let aMat = SCNMaterial()
            aMat.lightingModel = .physicallyBased
            aMat.diffuse.contents = UIColor.white
            amb.materials = [aMat]
            let aNode = SCNNode(geometry: amb)
            aNode.position.y = 0.14
            holder.addChildNode(aNode)

            let siren = SCNBox(width: 0.22, height: 0.06, length: 0.10, chamferRadius: 0.02)
            let sMat = SCNMaterial()
            sMat.diffuse.contents = UIColor.systemRed
            sMat.emission.contents = UIColor.systemRed
            siren.materials = [sMat]
            let sNode = SCNNode(geometry: siren)
            sNode.position = SCNVector3(0, 0.28, -0.10)
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

    private func makePedestrianNode(index: Int) -> SCNNode {
        let p = SCNNode()
        p.addChildNode(makeContactShadowPlane(width: 0.18, length: 0.18))

        let torso = SCNCylinder(radius: 0.055, height: 0.22)
        let tMat = SCNMaterial()
        tMat.diffuse.contents = [UIColor.systemBlue, UIColor.systemRed, UIColor.systemTeal, UIColor.systemYellow][index % 4]
        torso.materials = [tMat]
        let tNode = SCNNode(geometry: torso)
        tNode.position.y = 0.14
        p.addChildNode(tNode)

        let head = SCNSphere(radius: 0.048)
        let hMat = SCNMaterial()
        hMat.diffuse.contents = UIColor(red: 0.86, green: 0.68, blue: 0.54, alpha: 1.0)
        head.materials = [hMat]
        let hNode = SCNNode(geometry: head)
        hNode.position.y = 0.29
        p.addChildNode(hNode)
        return p
    }

    // MARK: - Realistic Indonesian Traffic AI (Selap-Selip Motor, Ngetem Angkot, Truk Proyek, Pejalan Kaki)

    private func connectedNeighbors(of c: GridCoord, in set: Set<GridCoord>) -> [GridCoord] {
        let candidates = [
            GridCoord(x: c.x + 1, z: c.z),
            GridCoord(x: c.x - 1, z: c.z),
            GridCoord(x: c.x, z: c.z + 1),
            GridCoord(x: c.x, z: c.z - 1)
        ]
        return candidates.filter { set.contains($0) }
    }

    private func rebuildConnectedTrafficAndPedestrians(driveRoads: [GridCoord: RoadTile]) {
        simLock.lock()
        trafficContainer.childNodes.forEach { $0.removeFromParentNode() }
        pedestrianContainer.childNodes.forEach { $0.removeFromParentNode() }
        agents.removeAll()
        pedestrians.removeAll()
        roadKindMap = driveRoads.mapValues { $0.kind }
        driveableSet = Set(driveRoads.keys)

        let sortedCoords = driveableSet.sorted { ($0.x, $0.z) < ($1.x, $1.z) }
        if sortedCoords.count >= 2 {
            let count = min(30, max(7, sortedCoords.count * 2))
            var pattern: [VehicleKind] = [.ojolMotor, .car, .motorbike, .angkotBus, .car, .ojolMotor, .emergency]
            if hasActiveConstruction {
                pattern.insert(.constructionTruck, at: 2)
            }

            for i in 0..<count {
                let startCoord = sortedCoords[i % sortedCoords.count]
                let nbrs = connectedNeighbors(of: startCoord, in: driveableSet)
                guard let firstNext = nbrs.randomElement() else { continue }

                let vKind = pattern[i % pattern.count]
                let laneSlot = i % 2
                let node = makeVehicleNode(kind: vKind, index: i)
                trafficContainer.addChildNode(node)
                let spd: Float = (vKind == .motorbike || vKind == .ojolMotor) ? 0.58 : (vKind == .emergency ? 0.66 : 0.40)
                agents.append(TrafficAgent(
                    node: node,
                    kind: vKind,
                    laneSlot: laneSlot,
                    currentCoord: startCoord,
                    nextCoord: firstNext,
                    prevCoord: startCoord,
                    progress: Float(i % 5) * 0.18,
                    baseSpeed: spd,
                    pauseTimer: 0,
                    weavePhase: Float(i) * 1.1
                ))
            }

            // Spawn Sidewalk Pedestrians walking along connected roads
            let pedCount = min(18, sortedCoords.count)
            for pIdx in 0..<pedCount {
                let cA = sortedCoords[pIdx % sortedCoords.count]
                let nbrs = connectedNeighbors(of: cA, in: driveableSet)
                guard let cB = nbrs.randomElement() else { continue }
                let pNode = makePedestrianNode(index: pIdx)
                pedestrianContainer.addChildNode(pNode)
                pedestrians.append(PedestrianAgent(
                    node: pNode,
                    coordA: cA,
                    coordB: cB,
                    sideOffset: pIdx % 2 == 0 ? 0.86 : -0.86,
                    progress: Float(pIdx % 4) * 0.22,
                    speed: 0.22
                ))
            }
        }
        simLock.unlock()
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if lastUpdateTime == 0 { lastUpdateTime = time; return }
        let dt = Float(min(max(time - lastUpdateTime, 0.0), 0.08))
        lastUpdateTime = time

        // Animated River Flow & Whitewater Foam
        waterScrollPhase += dt * 0.055
        var foamTransform = SCNMatrix4MakeScale(44, 44, 1)
        foamTransform = SCNMatrix4Translate(foamTransform, 0, waterScrollPhase, 0)
        waterMaterial?.diffuse.contentsTransform = foamTransform

        var normTransform = SCNMatrix4MakeScale(52, 52, 1)
        normTransform = SCNMatrix4Translate(normTransform, waterScrollPhase * 0.4, waterScrollPhase * 1.2, 0)
        waterMaterial?.normal.contentsTransform = normTransform

        if showcaseActive {
            camYaw += dt * 0.14
            updateCameraTransform()
        }

        simLock.lock()
        if !agents.isEmpty {
            let rushMult: Float = (timePhase == .sunset) ? 1.15 : 1.0
            for i in agents.indices {
                // Angkot & Ojol stop briefly at roadside to pick up/drop passengers ("Ngetem")
                if agents[i].pauseTimer > 0 {
                    agents[i].pauseTimer -= dt
                    continue
                }

                agents[i].weavePhase += dt * 3.8
                agents[i].progress += dt * agents[i].baseSpeed * rushMult

                if agents[i].progress >= 1.0 {
                    agents[i].progress -= 1.0
                    let arrived = agents[i].nextCoord
                    let cameFrom = agents[i].currentCoord
                    agents[i].prevCoord = cameFrom
                    agents[i].currentCoord = arrived

                    let allNbrs = connectedNeighbors(of: arrived, in: driveableSet)
                    // At intersections (3+ neighbors), vehicles briefly yield/slow down
                    if allNbrs.count >= 3 && (agents[i].kind == .angkotBus || agents[i].kind == .ojolMotor) && Int.random(in: 0...4) == 0 {
                        agents[i].pauseTimer = 1.6
                    }

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
                let leftX = dz
                let leftZ = -dx

                let rKind = roadKindMap[cA] ?? .twoLane
                let laneOffset: Float
                if rKind == .fourLane {
                    let base = agents[i].laneSlot == 0 ? Float(0.46) : Float(1.04)
                    if agents[i].kind == .motorbike || agents[i].kind == .ojolMotor {
                        // Indonesian motorcycle lane-filtering ("selap-selip") weave
                        laneOffset = base + 0.16 + sin(agents[i].weavePhase) * 0.18
                    } else {
                        laneOffset = base
                    }
                } else {
                    if agents[i].kind == .motorbike || agents[i].kind == .ojolMotor {
                        laneOffset = 0.62 + sin(agents[i].weavePhase) * 0.16
                    } else {
                        laneOffset = 0.44
                    }
                }

                let deckLiftA: Float = pA.y < -0.18 ? 0.31 : 0.05
                let deckLiftB: Float = pB.y < -0.18 ? 0.31 : 0.05
                let wy = (pA.y + deckLiftA) + ((pB.y + deckLiftB) - (pA.y + deckLiftA)) * frac
                let wx = pA.x + (pB.x - pA.x) * frac + leftX * laneOffset
                let wz = pA.z + (pB.z - pA.z) * frac + leftZ * laneOffset

                agents[i].node.position = SCNVector3(wx, wy, wz)
                agents[i].node.look(at: SCNVector3(pB.x + leftX * laneOffset, pB.y + deckLiftB, pB.z + leftZ * laneOffset))
            }

            // Update Sidewalk Pedestrians
            for pIdx in pedestrians.indices {
                pedestrians[pIdx].progress += dt * pedestrians[pIdx].speed
                if pedestrians[pIdx].progress >= 1.0 {
                    pedestrians[pIdx].progress -= 1.0
                    let arrived = pedestrians[pIdx].coordB
                    let cameFrom = pedestrians[pIdx].coordA
                    pedestrians[pIdx].coordA = arrived
                    let nbrs = connectedNeighbors(of: arrived, in: driveableSet)
                    if let next = nbrs.filter({ $0 != cameFrom }).randomElement() ?? nbrs.first {
                        pedestrians[pIdx].coordB = next
                    }
                }
                let cA = pedestrians[pIdx].coordA
                let cB = pedestrians[pIdx].coordB
                let pA = worldPosition(for: cA)
                let pB = worldPosition(for: cB)
                let frac = pedestrians[pIdx].progress
                let dx = Float(cB.x - cA.x)
                let dz = Float(cB.z - cA.z)
                let off = pedestrians[pIdx].sideOffset
                let deckA: Float = pA.y < -0.18 ? 0.31 : 0.05
                let deckB: Float = pB.y < -0.18 ? 0.31 : 0.05
                let wy = (pA.y + deckA) + ((pB.y + deckB) - (pA.y + deckA)) * frac
                let wx = pA.x + (pB.x - pA.x) * frac + dz * off
                let wz = pA.z + (pB.z - pA.z) * frac - dx * off
                pedestrians[pIdx].node.position = SCNVector3(wx, wy, wz)
            }

            if cameraMode == .followVehicle, !agents.isEmpty {
                let vNode = agents[followedVehicleIndex % agents.count].node
                cameraPivot.position = vNode.position
                cameraPivot.eulerAngles = SCNVector3(0, camYaw, 0)
                cameraPitchNode.eulerAngles = SCNVector3(-0.34, 0, 0)
                cameraNode.position = SCNVector3(0, 0, 6.2)
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
            scene.lightingEnvironment.intensity = 1.35
            scene.fogColor = UIColor(red: 0.76, green: 0.90, blue: 0.99, alpha: 1.0)
            ambientLightNode.light?.intensity = 410
            skyFillLightNode.light?.intensity = 320
            sunLightNode.light?.intensity = 1440
            sunLightNode.light?.color = UIColor(red: 1.0, green: 0.96, blue: 0.90, alpha: 1.0)
            cameraNode.camera?.bloomIntensity = bloom ? 0.28 : 0.0

        case .sunset:
            let sky = bank.texture("sky_sunset_equirect.png")
            scene.background.contents = sky ?? UIColor(red: 0.92, green: 0.52, blue: 0.32, alpha: 1.0)
            scene.lightingEnvironment.contents = sky
            scene.lightingEnvironment.intensity = 1.15
            scene.fogColor = UIColor(red: 0.92, green: 0.58, blue: 0.38, alpha: 1.0)
            ambientLightNode.light?.intensity = 320
            skyFillLightNode.light?.intensity = 240
            sunLightNode.light?.intensity = 1150
            sunLightNode.light?.color = UIColor(red: 1.0, green: 0.68, blue: 0.38, alpha: 1.0)
            cameraNode.camera?.bloomIntensity = bloom ? 0.62 : 0.0

        case .night:
            let sky = bank.texture("sky_night_equirect.png")
            scene.background.contents = sky ?? UIColor(red: 0.02, green: 0.04, blue: 0.10, alpha: 1.0)
            scene.lightingEnvironment.contents = sky
            scene.lightingEnvironment.intensity = 0.72
            scene.fogColor = UIColor(red: 0.03, green: 0.05, blue: 0.12, alpha: 1.0)
            ambientLightNode.light?.intensity = 200
            skyFillLightNode.light?.intensity = 140
            sunLightNode.light?.intensity = 180
            sunLightNode.light?.color = UIColor(red: 0.55, green: 0.68, blue: 0.98, alpha: 1.0)
            cameraNode.camera?.bloomIntensity = bloom ? 0.92 : 0.0
        }

        scene.fogStartDistance = fog ? 75 : 360
        scene.fogEndDistance = fog ? 210 : 440
    }

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
        camDistance = min(76.0, max(6.2, camDistance / scaleFactor))
        updateCameraTransform()
    }

    func orbitDualAxis(deltaYaw: Float, deltaPitch: Float) {
        if cameraMode == .followVehicle { cameraMode = .drone }
        camYaw += deltaYaw * cameraSensitivity
        camPitch = min(1.28, max(0.16, camPitch + deltaPitch * cameraSensitivity))
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
        scnView.preferredFramesPerSecond = 60
        scnView.contentScaleFactor = UIScreen.main.nativeScale
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

        pinch.delegate = context.coordinator
        orbit2.delegate = context.coordinator

        scnView.addGestureRecognizer(tap)
        scnView.addGestureRecognizer(pan1)
        scnView.addGestureRecognizer(orbit2)
        scnView.addGestureRecognizer(pinch)

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
            return twoFingerSet.allSatisfy {
                $0 is UIPinchGestureRecognizer || ($0 as? UIPanGestureRecognizer)?.minimumNumberOfTouches == 2
            }
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
            let dy = Float(current.y - lastOrbit2.y)
            lastOrbit2 = current
            engine.orbitDualAxis(deltaYaw: -dx * 0.0085, deltaPitch: dy * 0.0065)
        }

        @objc func onPinch(_ gesture: UIPinchGestureRecognizer) {
            guard interactive else { return }
            if gesture.state == .changed {
                engine.zoomCamera(scaleFactor: Float(gesture.scale))
                gesture.scale = 1.0
            }
        }
    }
}

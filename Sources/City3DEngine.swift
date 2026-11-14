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

final class City3DEngine: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    private let worldRoot = SCNNode()
    private let terrainContainer = SCNNode()
    private let biomeContainer = SCNNode()
    private let zonableGridContainer = SCNNode()
    private let previewContainer = SCNNode()
    private let roadContainer = SCNNode()
    private let plotContainer = SCNNode()
    private let facilityContainer = SCNNode()
    private let utilityContainer = SCNNode()
    private let trafficContainer = SCNNode()
    private let incidentContainer = SCNNode()

    private let cameraPivot = SCNNode()
    private let cameraNode = SCNNode()
    private let sunLightNode = SCNNode()
    private let ambientLightNode = SCNNode()
    private var waterMaterial: SCNMaterial?

    private let simLock = NSLock()
    private var activeDriveCoords: [GridCoord] = []
    private var vehicles: [(node: SCNNode, kind: VehicleKind, progress: Float, indexOffset: Int, speed: Float)] = []
    private var lastUpdateTime: TimeInterval = 0
    private var waterScrollPhase: Float = 0

    private var currentMap: CityMapType = .malang
    private var timePhase: TimeOfDayPhase = .day
    private var cameraMode: CameraMode = .drone
    private var lensMode: DataLensMode = .normal
    private var showcaseActive: Bool = true
    private var followedVehicleIndex: Int = 0

    private var camYaw: Float = 0.65
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
        worldRoot.addChildNode(zonableGridContainer)
        worldRoot.addChildNode(previewContainer)
        worldRoot.addChildNode(roadContainer)
        worldRoot.addChildNode(plotContainer)
        worldRoot.addChildNode(facilityContainer)
        worldRoot.addChildNode(utilityContainer)
        worldRoot.addChildNode(trafficContainer)
        worldRoot.addChildNode(incidentContainer)

        cameraPivot.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(cameraPivot)

        let cam = SCNCamera()
        cam.zNear = 0.3
        cam.zFar = 450.0
        cam.fieldOfView = 42.0
        cam.wantsHDR = true
        cam.bloomIntensity = 0.55
        cam.bloomThreshold = 0.85
        cam.bloomBlurRadius = 8.0
        cameraNode.camera = cam
        cameraPivot.addChildNode(cameraNode)
        updateCameraTransform()

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 420
        ambient.color = UIColor(red: 0.86, green: 0.92, blue: 1.0, alpha: 1.0)
        ambientLightNode.light = ambient
        scene.rootNode.addChildNode(ambientLightNode)

        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 1350
        sun.color = UIColor(red: 1.0, green: 0.95, blue: 0.86, alpha: 1.0)
        sun.castsShadow = true
        sun.shadowMode = .deferred
        sun.shadowSampleCount = 2
        sunLightNode.light = sun
        sunLightNode.eulerAngles = SCNVector3(-Float.pi / 3.0, Float.pi / 4.0, 0)
        scene.rootNode.addChildNode(sunLightNode)

        applyAtmosphere(shadows: true, fog: true, bloom: true)
    }

    // MARK: - Seamless Horizon Terrain Heightmap (No Floating Edges)

    private func fractalRidge(x: Float, z: Float) -> Float {
        let n1 = abs(sin(x * 0.042 + cos(z * 0.036) * 1.4))
        let n2 = abs(cos(z * 0.058 - sin(x * 0.048) * 1.2))
        let n3 = sin(x * 0.13) * cos(z * 0.13) * 0.25
        return (1.0 - n1 * 0.55) * (1.0 - n2 * 0.45) + n3
    }

    func terrainHeight(x: Float, z: Float) -> Float {
        let distFromCenter = sqrt(x * x + z * z)
        let mountainMask = max(0.0, (distFromCenter - 38.0) / 42.0)
        let mountainFactor = mountainMask * mountainMask

        switch currentMap {
        case .malang:
            let brantas = exp(-pow((x - (18.0 + 2.2 * sin(z * 0.08))) / 4.2, 2.0)) * -0.48
            let ridge = fractalRidge(x: x, z: z) * 28.0 * mountainFactor
            let northBias = max(0.0, (-z - 34.0) * 0.35) * mountainFactor
            return brantas + ridge + northBias + sin(x * 0.08) * cos(z * 0.08) * 0.10

        case .surabaya:
            let kalimas = exp(-pow((x - (14.0 + 1.8 * cos(z * 0.07))) / 4.0, 2.0)) * -0.45
            let coastDrop = max(0.0, (x - 32.0) * -0.22)
            let distantHills = max(0.0, (-x - 38.0) / 34.0) * fractalRidge(x: x, z: z) * 16.0
            return kalimas + coastDrop + distantHills

        case .jakarta:
            let ciliwung = exp(-pow((x - (12.0 + 2.0 * sin(z * 0.09))) / 3.8, 2.0)) * -0.45
            let bayDrop = max(0.0, (-z - 32.0) * -0.22)
            let salakHills = max(0.0, (z - 38.0) / 34.0) * fractalRidge(x: x, z: z) * 18.0
            return ciliwung + bayDrop + salakHills
        }
    }

    func loadMap(_ mapType: CityMapType, showcaseDemo: Bool) {
        currentMap = mapType
        showcaseActive = showcaseDemo
        cameraMode = .drone

        terrainContainer.childNodes.forEach { $0.removeFromParentNode() }
        biomeContainer.childNodes.forEach { $0.removeFromParentNode() }
        zonableGridContainer.childNodes.forEach { $0.removeFromParentNode() }
        previewContainer.childNodes.forEach { $0.removeFromParentNode() }
        roadContainer.childNodes.forEach { $0.removeFromParentNode() }
        plotContainer.childNodes.forEach { $0.removeFromParentNode() }
        facilityContainer.childNodes.forEach { $0.removeFromParentNode() }
        utilityContainer.childNodes.forEach { $0.removeFromParentNode() }
        incidentContainer.childNodes.forEach { $0.removeFromParentNode() }

        simLock.lock()
        trafficContainer.childNodes.forEach { $0.removeFromParentNode() }
        vehicles.removeAll()
        activeDriveCoords.removeAll()
        simLock.unlock()

        panTarget = SIMD2<Float>(0, 0)
        camDistance = showcaseDemo ? 34.0 : 38.0
        updateCameraTransform()

        buildSeamlessTerrainMesh()
        buildAlphaFoliageForest()
        NusantaraAssetBank.shared.playBGM(night: timePhase == .night)

        if showcaseDemo {
            buildShowcaseCity()
        }
    }

    private func buildSeamlessTerrainMesh() {
        let bank = NusantaraAssetBank.shared
        let segs = 104
        let span: Float = 360.0
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
                uvs.append(CGPoint(x: CGFloat(vx * 36.0), y: CGFloat(vz * 36.0)))

                let eps: Float = 1.0
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

                if y < -0.05 {
                    colors.append(SCNVector3(0.76, 0.72, 0.58))
                } else if nyNorm < 0.84 || y > 9.0 {
                    colors.append(SCNVector3(0.46, 0.48, 0.46))
                } else {
                    colors.append(SCNVector3(0.86, 0.94, 0.82))
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
            mat.diffuse.wrapS = .repeat
            mat.diffuse.wrapT = .repeat
            if let grassNorm = bank.texture("grass_normal.png") {
                mat.normal.contents = grassNorm
                mat.normal.wrapS = .repeat
                mat.normal.wrapT = .repeat
            }
        } else {
            mat.diffuse.contents = UIColor(red: 0.24, green: 0.48, blue: 0.22, alpha: 1.0)
        }
        mat.roughness.contents = 0.88
        geo.materials = [mat]

        terrainContainer.addChildNode(SCNNode(geometry: geo))

        // Reflective Normal-Mapped Water Plane
        let waterPlane = SCNPlane(width: 480, height: 480)
        let wMat = SCNMaterial()
        wMat.diffuse.contents = UIColor(red: 0.06, green: 0.38, blue: 0.64, alpha: 0.92)
        if let wNorm = bank.texture("water_normal.png") {
            wMat.normal.contents = wNorm
            wMat.normal.wrapS = .repeat
            wMat.normal.wrapT = .repeat
        }
        wMat.metalness.contents = 0.15
        wMat.roughness.contents = 0.12
        waterPlane.materials = [wMat]
        waterMaterial = wMat
        let waterNode = SCNNode(geometry: waterPlane)
        waterNode.eulerAngles.x = -.pi / 2
        waterNode.position.y = -0.18
        terrainContainer.addChildNode(waterNode)
    }

    private func buildAlphaFoliageForest() {
        for i in 0..<130 {
            let angle = Float(i) * 0.6180339 * 2.0 * .pi
            let dist = 39.5 + Float(i % 26) * 1.6
            let tx = cos(angle) * dist
            let tz = sin(angle) * dist
            let ty = terrainHeight(x: tx, z: tz)
            if ty > 0.0 && ty < 11.0 {
                let species = currentMap == .malang ? (i % 2 == 0 ? 1 : 0) : (i % 3)
                let tree = makeAlphaFoliageTree(species: species)
                let s = Float(0.85 + Double(i % 5) * 0.15)
                tree.scale = SCNVector3(s, s, s)
                tree.position = SCNVector3(tx, ty, tz)
                biomeContainer.addChildNode(tree)
            }
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
        demoPlots[GridCoord(x: 2, z: 1)] = ZonedPlot(coord: GridCoord(x: 2, z: 1), kind: .commercial, buildingLevel: 4, residents: 5, maxResidents: 6)
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

        let newDriveCoords = roads.values.filter { $0.kind.isDriveable }.map { $0.coord }
        rebuildTrafficPool(driveCoords: newDriveCoords)
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
            camDistance = 8.0
            panTarget = SIMD2<Float>(0, 0)
        } else if mode == .drone {
            camDistance = 36.0
        }
        updateCameraTransform()
    }

    func cycleFollowedVehicle() {
        simLock.lock()
        let count = vehicles.count
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

    // MARK: - Auto-Tiling Roads, Crosswalks & Multi-Detail Nusantara Architecture

    private func makeAlphaFoliageTree(species: Int) -> SCNNode {
        let tree = SCNNode()
        let bank = NusantaraAssetBank.shared

        let trunk = SCNCylinder(radius: 0.055, height: 0.58)
        let tMat = SCNMaterial()
        tMat.diffuse.contents = UIColor(red: 0.36, green: 0.23, blue: 0.13, alpha: 1.0)
        trunk.materials = [tMat]
        let tNode = SCNNode(geometry: trunk)
        tNode.position.y = 0.29
        tree.addChildNode(tNode)

        let texName: String
        switch species {
        case 1: texName = "tree_pine_foliage.png"
        case 2: texName = "tree_tabebuya_foliage.png"
        default: texName = "tree_tropical_foliage.png"
        }

        let foliageMat = SCNMaterial()
        foliageMat.diffuse.contents = bank.texture(texName) ?? UIColor(red: 0.16, green: 0.52, blue: 0.20, alpha: 1.0)
        foliageMat.isDoubleSided = true
        foliageMat.transparencyMode = .aOne
        foliageMat.writesToDepthBuffer = true

        for idx in 0..<3 {
            let card = SCNPlane(width: 1.18, height: 1.24)
            card.materials = [foliageMat]
            let cNode = SCNNode(geometry: card)
            cNode.position.y = 0.86
            cNode.eulerAngles.y = Float(idx) * (.pi / 3.0)
            tree.addChildNode(cNode)
        }
        return tree
    }

    private func makeAutoTiledRoadNode(tile: RoadTile, north: Bool, south: Bool, east: Bool, west: Bool) -> SCNNode {
        let holder = SCNNode()
        let w = CGFloat(tileSize)
        let bank = NusantaraAssetBank.shared
        let isLit = timePhase.isLitTime

        let foundation = SCNBox(width: w, height: 0.6, length: w, chamferRadius: 0)
        let fMat = SCNMaterial()
        fMat.diffuse.contents = UIColor(red: 0.34, green: 0.36, blue: 0.38, alpha: 1.0)
        foundation.materials = [fMat]
        let fNode = SCNNode(geometry: foundation)
        fNode.position.y = -0.28
        holder.addChildNode(fNode)

        if tile.kind == .sidewalkTree {
            let paving = SCNBox(width: w, height: 0.09, length: w, chamferRadius: 0)
            let pMat = SCNMaterial()
            pMat.diffuse.contents = bank.texture("sidewalk_paving_albedo.png") ?? UIColor(red: 0.68, green: 0.64, blue: 0.58, alpha: 1.0)
            paving.materials = [pMat]
            let pNode = SCNNode(geometry: paving)
            pNode.position.y = 0.045
            holder.addChildNode(pNode)

            holder.addChildNode(makeAlphaFoliageTree(species: 0))
            return holder
        }

        let neighborCount = (north ? 1 : 0) + (south ? 1 : 0) + (east ? 1 : 0) + (west ? 1 : 0)
        let isIntersection = neighborCount >= 3

        let asphalt = SCNBox(width: w, height: 0.06, length: w, chamferRadius: 0)
        let aMat = SCNMaterial()
        let texName: String
        if isIntersection {
            texName = "road_intersection_albedo.png"
        } else {
            texName = tile.kind == .fourLane ? "road_4lane_albedo.png" : "road_2lane_albedo.png"
        }
        aMat.diffuse.contents = bank.texture(texName) ?? UIColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1.0)
        if let norm = bank.texture("asphalt_normal.png") {
            aMat.normal.contents = norm
        }
        asphalt.materials = [aMat]
        let aNode = SCNNode(geometry: asphalt)
        aNode.position.y = 0.03

        // Orientasi marka jalan otomatis mengikuti arah E-W vs N-S
        if !isIntersection && (east || west) && !(north || south) {
            aNode.eulerAngles.y = .pi / 2.0
        } else if tile.kind == .elasticCurve {
            aNode.eulerAngles.y = tile.curveYaw
        }
        holder.addChildNode(aNode)

        // Trotoar beton timbul di sisi yang tidak terhubung jalan
        let curbMat = SCNMaterial()
        curbMat.diffuse.contents = UIColor(red: 0.72, green: 0.72, blue: 0.70, alpha: 1.0)
        if !north {
            let c = SCNBox(width: w, height: 0.11, length: 0.16, chamferRadius: 0.01)
            c.materials = [curbMat]
            let n = SCNNode(geometry: c); n.position = SCNVector3(0, 0.055, -tileSize * 0.46)
            holder.addChildNode(n)
        }
        if !south {
            let c = SCNBox(width: w, height: 0.11, length: 0.16, chamferRadius: 0.01)
            c.materials = [curbMat]
            let n = SCNNode(geometry: c); n.position = SCNVector3(0, 0.055, tileSize * 0.46)
            holder.addChildNode(n)
        }

        if tile.kind == .roundabout {
            let island = SCNCylinder(radius: 0.72, height: 0.18)
            let iMat = SCNMaterial()
            iMat.diffuse.contents = bank.texture("grass_nusantara_albedo.png") ?? UIColor(red: 0.18, green: 0.62, blue: 0.28, alpha: 1.0)
            island.materials = [iMat]
            let iNode = SCNNode(geometry: island)
            iNode.position.y = 0.09
            holder.addChildNode(iNode)

            let monument = SCNCylinder(radius: 0.14, height: 1.12)
            let mMat = SCNMaterial()
            mMat.diffuse.contents = UIColor(red: 0.94, green: 0.88, blue: 0.74, alpha: 1.0)
            if isLit { mMat.emission.contents = UIColor.cyan.withAlphaComponent(0.75) }
            monument.materials = [mMat]
            let mNode = SCNNode(geometry: monument)
            mNode.position.y = 0.58
            holder.addChildNode(mNode)

            let blossom = makeAlphaFoliageTree(species: 2)
            blossom.scale = SCNVector3(0.65, 0.65, 0.65)
            blossom.position = SCNVector3(0.38, 0.12, 0.35)
            holder.addChildNode(blossom)
        } else if (abs(tile.coord.x) + abs(tile.coord.z)) % 2 == 0 {
            let pole = SCNCylinder(radius: 0.025, height: 0.92)
            let poleMat = SCNMaterial()
            poleMat.diffuse.contents = UIColor.darkGray
            pole.materials = [poleMat]
            let poleNode = SCNNode(geometry: pole)
            poleNode.position = SCNVector3(tileSize * 0.44, 0.47, tileSize * 0.44)
            holder.addChildNode(poleNode)

            let bulb = SCNSphere(radius: 0.065)
            let bulbMat = SCNMaterial()
            bulbMat.diffuse.contents = UIColor(red: 1.0, green: 0.90, blue: 0.65, alpha: 1.0)
            bulbMat.emission.contents = isLit ? UIColor(red: 1.0, green: 0.84, blue: 0.38, alpha: 1.0) : UIColor.clear
            bulb.materials = [bulbMat]
            let bulbNode = SCNNode(geometry: bulb)
            bulbNode.position = SCNVector3(tileSize * 0.44, 0.93, tileSize * 0.44)
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
        case .residentialLow:
            baseMat.diffuse.contents = bank.texture("grass_nusantara_albedo.png") ?? UIColor(red: 0.24, green: 0.68, blue: 0.32, alpha: 1.0)
        case .residentialHigh:
            baseMat.diffuse.contents = bank.texture("sidewalk_paving_albedo.png") ?? UIColor(red: 0.22, green: 0.52, blue: 0.30, alpha: 1.0)
        case .commercial:
            baseMat.diffuse.contents = bank.texture("sidewalk_paving_albedo.png") ?? UIColor(red: 0.25, green: 0.50, blue: 0.82, alpha: 1.0)
        case .industrialOffice:
            baseMat.diffuse.contents = UIColor(red: 0.52, green: 0.50, blue: 0.42, alpha: 1.0)
        case .parkGreen:
            baseMat.diffuse.contents = bank.texture("grass_nusantara_albedo.png") ?? UIColor(red: 0.18, green: 0.62, blue: 0.28, alpha: 1.0)
        case .clearZone:
            baseMat.diffuse.contents = UIColor.clear
        }
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
            if isLit {
                mat.emission.contents = UIColor(red: 0.48, green: 0.36, blue: 0.14, alpha: 1.0)
            }
            body.materials = [mat]
            let bNode = SCNNode(geometry: body)
            bNode.position.y = Float(floors * 0.5) + 0.05
            holder.addChildNode(bNode)

            // Teras depan & pagar halaman khas rumah Indonesia
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
                let balcony = SCNBox(width: 1.18, height: 0.14, length: 0.36, chamferRadius: 0.01)
                balcony.materials = [pMat]
                let balNode = SCNNode(geometry: balcony)
                balNode.position = SCNVector3(0, 0.84, 0.62)
                holder.addChildNode(balNode)

                // Toren air oranye khas atap rumah bertingkat di Indonesia
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
            roof.materials = [rMat]
            let rNode = SCNNode(geometry: roof)
            rNode.position.y = Float(floors) + 0.05
            holder.addChildNode(rNode)

        case .residentialHigh:
            let h = 1.45 + CGFloat(plot.buildingLevel) * 0.55
            let tower = SCNBox(width: 1.34, height: h, length: 1.34, chamferRadius: 0.04)
            let mat = SCNMaterial()
            mat.diffuse.contents = plot.isAbandoned ? UIColor.darkGray : (bank.texture("building_facade_day.png") ?? UIColor.lightGray)
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
            if plot.buildingLevel <= 2 && hash == 0 {
                let shop = SCNBox(width: 1.42, height: 0.92, length: 1.26, chamferRadius: 0.02)
                let sMat = SCNMaterial()
                sMat.diffuse.contents = bank.texture("indomaret_facade_albedo.png") ?? UIColor.systemBlue
                if isLit { sMat.emission.contents = UIColor(red: 0.32, green: 0.36, blue: 0.42, alpha: 1.0) }
                shop.materials = [sMat]
                let sNode = SCNNode(geometry: shop)
                sNode.position.y = 0.51
                holder.addChildNode(sNode)
            } else {
                let bHeight = 1.55 + CGFloat(plot.buildingLevel) * 0.64
                let tower = SCNBox(width: 1.36, height: bHeight, length: 1.36, chamferRadius: 0.05)
                let mat = SCNMaterial()
                mat.diffuse.contents = plot.isAbandoned ? UIColor.darkGray : (bank.texture("building_facade_day.png") ?? UIColor(red: 0.24, green: 0.46, blue: 0.74, alpha: 1.0))
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
            cMat.metalness.contents = 0.4
            cMat.roughness.contents = 0.25
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

    private func rebuildTrafficPool(driveCoords: [GridCoord]) {
        simLock.lock()
        trafficContainer.childNodes.forEach { $0.removeFromParentNode() }
        vehicles.removeAll()
        activeDriveCoords = driveCoords

        if driveCoords.count >= 2 {
            let count = min(22, max(4, driveCoords.count))
            let pattern: [VehicleKind] = [.motorbike, .car, .motorbike, .angkotBus, .car, .emergency]
            for i in 0..<count {
                let vKind = pattern[i % pattern.count]
                let node = makeVehicleNode(kind: vKind, index: i)
                trafficContainer.addChildNode(node)
                let spd: Float = vKind == .motorbike ? 0.48 : (vKind == .emergency ? 0.55 : 0.36)
                vehicles.append((node: node, kind: vKind, progress: Float(i) / Float(count), indexOffset: i * 3, speed: spd))
            }
        }
        simLock.unlock()
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if lastUpdateTime == 0 { lastUpdateTime = time; return }
        let dt = Float(min(max(time - lastUpdateTime, 0.0), 0.08))
        lastUpdateTime = time

        waterScrollPhase += dt * 0.028
        waterMaterial?.normal.contentsTransform = SCNMatrix4MakeTranslation(waterScrollPhase, waterScrollPhase * 0.7, 0)

        if showcaseActive {
            camYaw += dt * 0.14
            updateCameraTransform()
        }

        simLock.lock()
        let total = activeDriveCoords.count
        if total >= 2 {
            for i in vehicles.indices {
                vehicles[i].progress += dt * vehicles[i].speed
                let rawIdx = Int(vehicles[i].progress) + vehicles[i].indexOffset
                let frac = vehicles[i].progress - floor(vehicles[i].progress)
                let cA = activeDriveCoords[rawIdx % total]
                let cB = activeDriveCoords[(rawIdx + 1) % total]

                let pA = worldPosition(for: cA)
                let pB = worldPosition(for: cB)

                if abs(cA.x - cB.x) + abs(cA.z - cB.z) == 1 {
                    let dx = Float(cB.x - cA.x)
                    let dz = Float(cB.z - cA.z)
                    let laneOffset: Float = vehicles[i].kind == .motorbike ? 0.34 : 0.18
                    let leftX = dz * laneOffset
                    let leftZ = -dx * laneOffset
                    let wy = pA.y + (pB.y - pA.y) * frac + 0.06
                    vehicles[i].node.position = SCNVector3(
                        pA.x + (pB.x - pA.x) * frac + leftX,
                        wy,
                        pA.z + (pB.z - pA.z) * frac + leftZ
                    )
                    vehicles[i].node.look(at: SCNVector3(pB.x + leftX, wy, pB.z + leftZ))
                } else {
                    vehicles[i].node.position = SCNVector3(pA.x, pA.y + 0.06, pA.z)
                }
            }

            if cameraMode == .followVehicle, !vehicles.isEmpty {
                let vNode = vehicles[followedVehicleIndex % vehicles.count].node
                cameraPivot.position = vNode.position
                cameraNode.position = SCNVector3(sin(camYaw) * 4.5, 2.8, cos(camYaw) * 4.5)
                cameraNode.look(at: SCNVector3(vNode.position.x, vNode.position.y + 0.4, vNode.position.z))
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
            scene.lightingEnvironment.intensity = 1.15
            scene.fogColor = UIColor(red: 0.72, green: 0.88, blue: 0.98, alpha: 1.0)
            ambientLightNode.light?.intensity = 420
            sunLightNode.light?.intensity = 1350
            sunLightNode.light?.color = UIColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1.0)
            cameraNode.camera?.bloomIntensity = bloom ? 0.30 : 0.0

        case .sunset:
            let sky = bank.texture("sky_sunset_equirect.png")
            scene.background.contents = sky ?? UIColor(red: 0.92, green: 0.52, blue: 0.32, alpha: 1.0)
            scene.lightingEnvironment.contents = sky
            scene.lightingEnvironment.intensity = 1.05
            scene.fogColor = UIColor(red: 0.92, green: 0.58, blue: 0.38, alpha: 1.0)
            ambientLightNode.light?.intensity = 340
            sunLightNode.light?.intensity = 1080
            sunLightNode.light?.color = UIColor(red: 1.0, green: 0.68, blue: 0.38, alpha: 1.0)
            cameraNode.camera?.bloomIntensity = bloom ? 0.65 : 0.0

        case .night:
            let sky = bank.texture("sky_night_equirect.png")
            scene.background.contents = sky ?? UIColor(red: 0.02, green: 0.04, blue: 0.10, alpha: 1.0)
            scene.lightingEnvironment.contents = sky
            scene.lightingEnvironment.intensity = 0.65
            scene.fogColor = UIColor(red: 0.03, green: 0.05, blue: 0.12, alpha: 1.0)
            ambientLightNode.light?.intensity = 200
            sunLightNode.light?.intensity = 180
            sunLightNode.light?.color = UIColor(red: 0.55, green: 0.68, blue: 0.98, alpha: 1.0)
            cameraNode.camera?.bloomIntensity = bloom ? 0.92 : 0.0
        }

        scene.fogStartDistance = fog ? 62 : 340
        scene.fogEndDistance = fog ? 185 : 420
    }

    func updateCameraTransform() {
        let pitch: Float = cameraMode == .streetView ? 0.24 : 0.72
        let hDist = camDistance * cos(pitch)
        let vDist = camDistance * sin(pitch)
        let groundY = terrainHeight(x: panTarget.x, z: panTarget.y)
        cameraPivot.position = SCNVector3(panTarget.x, groundY, panTarget.y)
        cameraNode.position = SCNVector3(sin(camYaw) * hDist, vDist, cos(camYaw) * hDist)
        cameraNode.look(at: cameraPivot.position)
    }

    func panCamera(dx: Float, dz: Float) {
        if cameraMode == .followVehicle { cameraMode = .drone }
        let forwardX = -sin(camYaw)
        let forwardZ = -cos(camYaw)
        let rightX = cos(camYaw)
        let rightZ = -sin(camYaw)
        let scale = camDistance * 0.0022 * cameraSensitivity
        panTarget.x = min(34, max(-34, panTarget.x - (rightX * dx - forwardX * dz) * scale))
        panTarget.y = min(34, max(-34, panTarget.y - (rightZ * dx - forwardZ * dz) * scale))
        updateCameraTransform()
    }

    func zoomCamera(scaleFactor: Float) {
        camDistance = min(76.0, max(6.8, camDistance / scaleFactor))
        updateCameraTransform()
    }

    func rotateCamera(deltaYaw: Float) {
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
        scnView.antialiasingMode = .multisampling2X
        scnView.backgroundColor = .black

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onTap(_:)))
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onPan(_:)))
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onPinch(_:)))
        let rotate = UIRotationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onRotate(_:)))

        pinch.delegate = context.coordinator
        rotate.delegate = context.coordinator

        scnView.addGestureRecognizer(tap)
        scnView.addGestureRecognizer(pan)
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
        private var lastPan: CGPoint = .zero

        init(engine: City3DEngine) { self.engine = engine }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return (gestureRecognizer is UIPinchGestureRecognizer && otherGestureRecognizer is UIRotationGestureRecognizer) ||
                   (gestureRecognizer is UIRotationGestureRecognizer && otherGestureRecognizer is UIPinchGestureRecognizer)
        }

        @objc func onTap(_ gesture: UITapGestureRecognizer) {
            guard interactive, let view = scnView else { return }
            if let coord = engine.gridCoord(at: gesture.location(in: view), in: view) {
                engine.onTileTapped?(coord)
            }
        }

        @objc func onPan(_ gesture: UIPanGestureRecognizer) {
            guard interactive, let view = scnView else { return }
            let current = gesture.translation(in: view)
            if gesture.state == .began { lastPan = current; return }
            let dx = Float(current.x - lastPan.x)
            let dy = Float(current.y - lastPan.y)
            lastPan = current
            engine.panCamera(dx: dx, dz: dy)
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
                engine.rotateCamera(deltaYaw: Float(gesture.rotation))
                gesture.rotation = 0
            }
        }
    }
}

import simd
import Foundation
import UIKit
import SceneKit
import SwiftUI
import AVFoundation

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
    private let roadContainer = SCNNode()
    private let zoneContainer = SCNNode()
    private let facilityContainer = SCNNode()
    private let utilityContainer = SCNNode()
    private let trafficContainer = SCNNode()
    private let incidentContainer = SCNNode()

    private let cameraPivot = SCNNode()
    private let cameraNode = SCNNode()
    private let sunLightNode = SCNNode()
    private let ambientLightNode = SCNNode()

    private var roadNodes: [GridCoord: SCNNode] = [:]
    private var zoneNodes: [GridCoord: SCNNode] = [:]
    private var facilityNodes: [GridCoord: SCNNode] = [:]
    private var utilityNodes: [GridCoord: SCNNode] = [:]

    private var activeDriveCoords: [GridCoord] = []
    private var vehicles: [(node: SCNNode, kind: VehicleKind, progress: Float, indexOffset: Int, speed: Float)] = []
    private var lastUpdateTime: TimeInterval = 0

    private var currentMap: CityMapType = .malang
    private var isNightMode: Bool = false
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
        worldRoot.addChildNode(roadContainer)
        worldRoot.addChildNode(zoneContainer)
        worldRoot.addChildNode(facilityContainer)
        worldRoot.addChildNode(utilityContainer)
        worldRoot.addChildNode(trafficContainer)
        worldRoot.addChildNode(incidentContainer)

        cameraPivot.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(cameraPivot)

        let cam = SCNCamera()
        cam.zNear = 0.3
        cam.zFar = 320.0
        cam.fieldOfView = 45.0
        cameraNode.camera = cam
        cameraPivot.addChildNode(cameraNode)
        updateCameraTransform()

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 560
        ambient.color = UIColor(red: 0.88, green: 0.92, blue: 1.0, alpha: 1.0)
        ambientLightNode.light = ambient
        scene.rootNode.addChildNode(ambientLightNode)

        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 1220
        sun.color = UIColor(red: 1.0, green: 0.95, blue: 0.85, alpha: 1.0)
        sun.castsShadow = true
        sun.shadowMode = .deferred
        sun.shadowSampleCount = 2
        sunLightNode.light = sun
        sunLightNode.eulerAngles = SCNVector3(-Float.pi / 3.0, Float.pi / 4.0, 0)
        scene.rootNode.addChildNode(sunLightNode)

        applyAtmosphere(shadows: true, fog: true)
    }

    // MARK: - Fungsi Elevasi Kontur Tanah 3D Nyata (Pegunungan, Lembah Sungai & Pesisir)

    func terrainHeight(x: Float, z: Float) -> Float {
        switch currentMap {
        case .malang:
            // Lembah Sungai Brantas di sisi timur (x ~ 18) & perbukitan di tepi utara/barat
            let brantas = exp(-pow((x - (18.0 + 2.2 * sin(z * 0.08))) / 4.2, 2.0)) * -0.45
            let northSlope = max(0.0, (-z - 22.0) * 0.14)
            let westHill = max(0.0, (-x - 24.0) * 0.10)
            let gentleRoll = sin(x * 0.09) * cos(z * 0.09) * 0.18
            return brantas + northSlope + westHill + gentleRoll

        case .surabaya:
            let kalimas = exp(-pow((x - (14.0 + 1.8 * cos(z * 0.07))) / 4.0, 2.0)) * -0.42
            let coastDrop = max(0.0, (x - 28.0) * -0.18)
            return kalimas + coastDrop + sin(x * 0.08) * 0.08

        case .jakarta:
            let ciliwung = exp(-pow((x - (12.0 + 2.0 * sin(z * 0.09))) / 3.8, 2.0)) * -0.42
            let bayDrop = max(0.0, (-z - 28.0) * -0.18)
            return ciliwung + bayDrop + cos(z * 0.08) * 0.08
        }
    }

    func loadMap(_ mapType: CityMapType, showcaseDemo: Bool) {
        currentMap = mapType
        showcaseActive = showcaseDemo
        cameraMode = .drone

        terrainContainer.childNodes.forEach { $0.removeFromParentNode() }
        biomeContainer.childNodes.forEach { $0.removeFromParentNode() }
        roadContainer.childNodes.forEach { $0.removeFromParentNode() }
        zoneContainer.childNodes.forEach { $0.removeFromParentNode() }
        facilityContainer.childNodes.forEach { $0.removeFromParentNode() }
        utilityContainer.childNodes.forEach { $0.removeFromParentNode() }
        trafficContainer.childNodes.forEach { $0.removeFromParentNode() }
        incidentContainer.childNodes.forEach { $0.removeFromParentNode() }

        roadNodes.removeAll()
        zoneNodes.removeAll()
        facilityNodes.removeAll()
        utilityNodes.removeAll()
        vehicles.removeAll()
        activeDriveCoords.removeAll()

        panTarget = SIMD2<Float>(0, 0)
        camDistance = showcaseDemo ? 34.0 : 38.0
        updateCameraTransform()

        buildCustomTerrainMesh()
        buildNaturalBiomeAndMountains()
        NusantaraAssetBank.shared.playBGM(night: isNightMode)

        if showcaseDemo {
            buildShowcaseCity()
        }
    }

    private func buildCustomTerrainMesh() {
        let bank = NusantaraAssetBank.shared
        let segs = 64
        let span: Float = 136.0
        let half = span * 0.5

        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
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
                uvs.append(CGPoint(x: CGFloat(vx * 14.0), y: CGFloat(vz * 14.0)))

                let eps: Float = 0.6
                let hL = terrainHeight(x: x - eps, z: z)
                let hR = terrainHeight(x: x + eps, z: z)
                let hD = terrainHeight(x: x, z: z - eps)
                let hU = terrainHeight(x: x, z: z + eps)
                let nx = hL - hR
                let ny = 2.0 * eps
                let nz = hD - hU
                let len = max(0.001, sqrt(nx * nx + ny * ny + nz * nz))
                normals.append(SCNVector3(nx / len, ny / len, nz / len))
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
        let uvSrc = SCNGeometrySource(textureCoordinates: uvs)
        let elem = SCNGeometryElement(indices: indices, primitiveType: .triangles)

        let geo = SCNGeometry(sources: [vSrc, nSrc, uvSrc], elements: [elem])
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
            mat.diffuse.contents = UIColor(red: 0.22, green: 0.48, blue: 0.22, alpha: 1.0)
        }
        mat.roughness.contents = 0.90
        geo.materials = [mat]

        let terrainNode = SCNNode(geometry: geo)
        terrainNode.name = "terrain_mesh"
        terrainContainer.addChildNode(terrainNode)

        // Permukaan Air Sungai / Laut Reflektif
        let waterPlane = SCNPlane(width: 240, height: 240)
        let wMat = SCNMaterial()
        wMat.diffuse.contents = UIColor(red: 0.08, green: 0.42, blue: 0.68, alpha: 0.92)
        wMat.specular.contents = UIColor.white
        wMat.shininess = 0.90
        waterPlane.materials = [wMat]
        let waterNode = SCNNode(geometry: waterPlane)
        waterNode.eulerAngles.x = -.pi / 2
        waterNode.position.y = -0.16
        terrainContainer.addChildNode(waterNode)

        // Grid tipis pada area pembangunan agar presisi menaruh jalan/bangunan
        let boardSpan = CGFloat(gridHalfExtent * 2 + 1) * CGFloat(tileSize)
        let gridMat = SCNMaterial()
        gridMat.diffuse.contents = UIColor.white.withAlphaComponent(0.09)
        for i in -gridHalfExtent...(gridHalfExtent + 1) {
            let offset = (Float(i) - 0.5) * tileSize
            let lineX = SCNBox(width: boardSpan, height: 0.01, length: 0.03, chamferRadius: 0)
            lineX.materials = [gridMat]
            let nX = SCNNode(geometry: lineX)
            nX.position = SCNVector3(0, 0.02, offset)
            terrainContainer.addChildNode(nX)

            let lineZ = SCNBox(width: 0.03, height: 0.01, length: boardSpan, chamferRadius: 0)
            lineZ.materials = [gridMat]
            let nZ = SCNNode(geometry: lineZ)
            nZ.position = SCNVector3(offset, 0.02, 0)
            terrainContainer.addChildNode(nZ)
        }
    }

    private func buildNaturalBiomeAndMountains() {
        // Gugusan Pegunungan 3D Berlapis di Cakrawala
        let ridges: [(x: Float, z: Float, r: CGFloat, h: CGFloat)] = currentMap == .malang
            ? [(-32, -62, 24, 28), (-4, -68, 28, 34), (28, -64, 22, 26), (-58, -28, 22, 24), (56, -34, 20, 22)]
            : [(-48, -76, 22, 16), (12, -80, 26, 18)]

        for ridge in ridges {
            let peak = SCNCone(topRadius: 2.6, bottomRadius: ridge.r, height: ridge.h)
            let pMat = SCNMaterial()
            pMat.diffuse.contents = UIColor(red: 0.16, green: 0.34, blue: 0.22, alpha: 1.0)
            pMat.roughness.contents = 0.95
            peak.materials = [pMat]
            let pNode = SCNNode(geometry: peak)
            pNode.position = SCNVector3(ridge.x, Float(ridge.h) * 0.45, ridge.z)
            biomeContainer.addChildNode(pNode)
        }

        // Hutan Alami & Rumpun Rumput di Luar Area Kota
        for i in 0..<75 {
            let angle = Float(i) * 0.6180339 * 2.0 * .pi
            let dist = 39.0 + Float(i % 14) * 1.6
            let tx = cos(angle) * dist
            let tz = sin(angle) * dist
            let ty = terrainHeight(x: tx, z: tz)
            if ty > -0.05 {
                let tree = makeRealisticTree(species: i % 3)
                tree.position = SCNVector3(tx, ty, tz)
                biomeContainer.addChildNode(tree)
            }
        }
    }

    private func buildShowcaseCity() {
        var demoRoads: [GridCoord: RoadTile] = [:]
        var demoZones: [GridCoord: ZoneTile] = [:]
        var demoFacs: [GridCoord: FacilityTile] = [:]

        for x in -5...5 {
            let c = GridCoord(x: x, z: 0)
            demoRoads[c] = RoadTile(coord: c, kind: x == 0 ? .roundabout : .fourLane)
        }
        demoFacs[GridCoord(x: 0, z: -2)] = FacilityTile(coord: GridCoord(x: 0, z: -2), kind: .balaiKota)
        demoFacs[GridCoord(x: -3, z: -2)] = FacilityTile(coord: GridCoord(x: -3, z: -2), kind: .universitas)
        demoZones[GridCoord(x: -2, z: 1)] = ZoneTile(coord: GridCoord(x: -2, z: 1), kind: .residentialMulti, residents: 10, maxResidents: 14)
        demoZones[GridCoord(x: 2, z: 1)] = ZoneTile(coord: GridCoord(x: 2, z: 1), kind: .commercial, residents: 4, maxResidents: 4)
        demoZones[GridCoord(x: 4, z: 1)] = ZoneTile(coord: GridCoord(x: 4, z: 1), kind: .park, residents: 0, maxResidents: 0)

        syncWorld(roads: demoRoads, zones: demoZones, facilities: demoFacs, utilities: [:])
    }

    func syncWorld(
        roads: [GridCoord: RoadTile],
        zones: [GridCoord: ZoneTile],
        facilities: [GridCoord: FacilityTile],
        utilities: [GridCoord: UtilityTile]
    ) {
        roadNodes.values.forEach { $0.removeFromParentNode() }
        roadNodes.removeAll()
        for (coord, tile) in roads {
            let node = makeRoadNode(tile: tile)
            node.position = worldPosition(for: coord)
            roadContainer.addChildNode(node)
            roadNodes[coord] = node
        }

        zoneNodes.values.forEach { $0.removeFromParentNode() }
        zoneNodes.removeAll()
        for (coord, tile) in zones {
            let node = makeZoneNode(tile: tile)
            node.position = worldPosition(for: coord)
            zoneContainer.addChildNode(node)
            zoneNodes[coord] = node
        }

        facilityNodes.values.forEach { $0.removeFromParentNode() }
        facilityNodes.removeAll()
        for (coord, fac) in facilities {
            let node = makeFacilityNode(kind: fac.kind)
            node.position = worldPosition(for: coord)
            facilityContainer.addChildNode(node)
            facilityNodes[coord] = node
        }

        utilityNodes.values.forEach { $0.removeFromParentNode() }
        utilityNodes.removeAll()
        for (coord, util) in utilities {
            let node = makeUtilityNode(kind: util.kind)
            node.position = worldPosition(for: coord)
            utilityContainer.addChildNode(node)
            utilityNodes[coord] = node
        }

        activeDriveCoords = roads.values.filter { $0.kind.isDriveable }.map { $0.coord }
        rebuildTrafficPool()
    }

    func setLensMode(_ mode: DataLensMode) {
        lensMode = mode
        if mode == .traffic {
            roadContainer.opacity = 1.0
            zoneContainer.opacity = 0.45
        } else if mode == .coverage {
            facilityContainer.opacity = 1.0
            zoneContainer.opacity = 0.55
        } else {
            roadContainer.opacity = 1.0
            zoneContainer.opacity = 1.0
            facilityContainer.opacity = 1.0
        }
    }

    func setCameraMode(_ mode: CameraMode) {
        cameraMode = mode
        if mode == .streetView {
            camDistance = 9.5
            panTarget = SIMD2<Float>(0, 0)
        } else if mode == .drone {
            camDistance = 36.0
        }
        updateCameraTransform()
    }

    func cycleFollowedVehicle() {
        guard !vehicles.isEmpty else { return }
        followedVehicleIndex = (followedVehicleIndex + 1) % vehicles.count
        cameraMode = .followVehicle
    }

    func showAccidentMarker(at coord: GridCoord?) {
        incidentContainer.childNodes.forEach { $0.removeFromParentNode() }
        guard let coord else { return }
        let beacon = SCNCylinder(radius: 0.32, height: 1.8)
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor.systemRed
        mat.emission.contents = UIColor.systemRed
        beacon.materials = [mat]
        let node = SCNNode(geometry: beacon)
        let p = worldPosition(for: coord)
        node.position = SCNVector3(p.x, p.y + 0.9, p.z)
        incidentContainer.addChildNode(node)
    }

    // MARK: - Pembuat Model 3D Jalan, Bundaran Alun-Alun, Bangunan & Kendaraan

    private func makeRoadNode(tile: RoadTile) -> SCNNode {
        let holder = SCNNode()
        let w = CGFloat(tileSize)
        let bank = NusantaraAssetBank.shared

        // Talud beton penahan tanah miring
        let foundation = SCNBox(width: w, height: 0.6, length: w, chamferRadius: 0)
        let fMat = SCNMaterial()
        fMat.diffuse.contents = UIColor(red: 0.34, green: 0.36, blue: 0.38, alpha: 1.0)
        foundation.materials = [fMat]
        let fNode = SCNNode(geometry: foundation)
        fNode.position.y = -0.28
        holder.addChildNode(fNode)

        if tile.kind == .sidewalkTree {
            let paving = SCNBox(width: w, height: 0.08, length: w, chamferRadius: 0)
            let pMat = SCNMaterial()
            pMat.diffuse.contents = bank.texture("sidewalk_paving_albedo.png") ?? UIColor(red: 0.68, green: 0.64, blue: 0.58, alpha: 1.0)
            paving.materials = [pMat]
            let pNode = SCNNode(geometry: paving)
            pNode.position.y = 0.04
            holder.addChildNode(pNode)

            holder.addChildNode(makeRealisticTree(species: 1))
            holder.addChildNode(makeGrassTuft(x: 0.45, z: -0.42))
            return holder
        }

        let asphalt = SCNBox(width: w, height: 0.06, length: w, chamferRadius: 0)
        let aMat = SCNMaterial()
        let texName = tile.kind == .fourLane ? "road_4lane_albedo.png" : "road_2lane_albedo.png"
        aMat.diffuse.contents = bank.texture(texName) ?? UIColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1.0)
        if let norm = bank.texture("asphalt_normal.png") {
            aMat.normal.contents = norm
        }
        asphalt.materials = [aMat]
        let aNode = SCNNode(geometry: asphalt)
        aNode.position.y = 0.03
        if tile.kind == .elasticCurve {
            aNode.eulerAngles.y = tile.curveYaw
        }
        holder.addChildNode(aNode)

        if tile.kind == .roundabout {
            let island = SCNCylinder(radius: 0.72, height: 0.16)
            let iMat = SCNMaterial()
            iMat.diffuse.contents = bank.texture("grass_nusantara_albedo.png") ?? UIColor(red: 0.18, green: 0.62, blue: 0.28, alpha: 1.0)
            island.materials = [iMat]
            let iNode = SCNNode(geometry: island)
            iNode.position.y = 0.09
            holder.addChildNode(iNode)

            let monument = SCNCylinder(radius: 0.15, height: 1.05)
            let mMat = SCNMaterial()
            mMat.diffuse.contents = UIColor(red: 0.92, green: 0.86, blue: 0.72, alpha: 1.0)
            if isNightMode { mMat.emission.contents = UIColor.cyan.withAlphaComponent(0.6) }
            monument.materials = [mMat]
            let mNode = SCNNode(geometry: monument)
            mNode.position.y = 0.56
            holder.addChildNode(mNode)

            let blossom = makeRealisticTree(species: 2)
            blossom.scale = SCNVector3(0.65, 0.65, 0.65)
            blossom.position = SCNVector3(0.38, 0.12, 0.35)
            holder.addChildNode(blossom)
        } else if (abs(tile.coord.x) + abs(tile.coord.z)) % 2 == 0 {
            let pole = SCNCylinder(radius: 0.028, height: 0.88)
            let poleMat = SCNMaterial()
            poleMat.diffuse.contents = UIColor.darkGray
            pole.materials = [poleMat]
            let poleNode = SCNNode(geometry: pole)
            poleNode.position = SCNVector3(tileSize * 0.42, 0.46, tileSize * 0.42)
            holder.addChildNode(poleNode)

            let bulb = SCNSphere(radius: 0.07)
            let bulbMat = SCNMaterial()
            bulbMat.diffuse.contents = UIColor(red: 1.0, green: 0.90, blue: 0.65, alpha: 1.0)
            bulbMat.emission.contents = isNightMode ? UIColor(red: 1.0, green: 0.82, blue: 0.35, alpha: 1.0) : UIColor.clear
            bulb.materials = [bulbMat]
            let bulbNode = SCNNode(geometry: bulb)
            bulbNode.position = SCNVector3(tileSize * 0.42, 0.90, tileSize * 0.42)
            holder.addChildNode(bulbNode)
        }

        return holder
    }

    private func makeZoneNode(tile: ZoneTile) -> SCNNode {
        let holder = SCNNode()
        let w = CGFloat(tileSize * 0.94)
        let bank = NusantaraAssetBank.shared

        // Talud beton otomatis di bawah kapling agar tidak melayang di lereng
        let foundation = SCNBox(width: w, height: 0.65, length: w, chamferRadius: 0)
        let fMat = SCNMaterial()
        fMat.diffuse.contents = UIColor(red: 0.36, green: 0.38, blue: 0.40, alpha: 1.0)
        foundation.materials = [fMat]
        let fNode = SCNNode(geometry: foundation)
        fNode.position.y = -0.30
        holder.addChildNode(fNode)

        let base = SCNBox(width: w, height: 0.05, length: w, chamferRadius: 0)
        let baseMat = SCNMaterial()
        switch tile.kind {
        case .residentialSingle, .residentialMulti:
            baseMat.diffuse.contents = bank.texture("grass_nusantara_albedo.png") ?? UIColor(red: 0.22, green: 0.65, blue: 0.32, alpha: 1.0)
        case .commercial:
            baseMat.diffuse.contents = bank.texture("sidewalk_paving_albedo.png") ?? UIColor(red: 0.45, green: 0.50, blue: 0.58, alpha: 1.0)
        case .industrial:
            baseMat.diffuse.contents = UIColor(red: 0.42, green: 0.42, blue: 0.44, alpha: 1.0)
        case .park:
            baseMat.diffuse.contents = bank.texture("grass_nusantara_albedo.png") ?? UIColor(red: 0.18, green: 0.62, blue: 0.28, alpha: 1.0)
        }
        base.materials = [baseMat]
        let baseNode = SCNNode(geometry: base)
        baseNode.position.y = 0.025
        holder.addChildNode(baseNode)

        if tile.kind == .park {
            let t1 = makeRealisticTree(species: 2); t1.position = SCNVector3(-0.42, 0, -0.35)
            let t2 = makeRealisticTree(species: 1); t2.position = SCNVector3(0.45, 0, 0.38)
            holder.addChildNode(t1)
            holder.addChildNode(t2)
            holder.addChildNode(makeGrassTuft(x: -0.2, z: 0.4))
            holder.addChildNode(makeGrassTuft(x: 0.35, z: -0.3))
            return holder
        }

        let hash = abs(tile.coord.x * 31 + tile.coord.z * 17) % 3
        let isLit = isNightMode && tile.hasPower

        switch tile.kind {
        case .residentialSingle, .residentialMulti:
            let floors: CGFloat = tile.kind == .residentialMulti ? 1.45 : 0.78
            let body = SCNBox(width: 1.12, height: floors, length: 1.12, chamferRadius: 0.04)
            let mat = SCNMaterial()
            if hash == 1, let kTex = bank.texture("kampung_warnawarni_albedo.png") {
                mat.diffuse.contents = kTex
            } else {
                mat.diffuse.contents = [UIColor(red: 0.96, green: 0.93, blue: 0.86, alpha: 1.0), UIColor.systemOrange, UIColor(red: 0.82, green: 0.90, blue: 0.94, alpha: 1.0)][hash]
            }
            if isLit {
                mat.emission.contents = UIColor(red: 0.42, green: 0.32, blue: 0.14, alpha: 1.0)
            }
            body.materials = [mat]
            let bNode = SCNNode(geometry: body)
            bNode.position.y = Float(floors * 0.5) + 0.05
            holder.addChildNode(bNode)

            // Atap Genteng Terakota
            let roof = SCNPyramid(width: 1.28, height: 0.48, length: 1.28)
            let rMat = SCNMaterial()
            rMat.diffuse.contents = bank.texture("roof_terracotta_albedo.png") ?? UIColor(red: 0.65, green: 0.24, blue: 0.18, alpha: 1.0)
            roof.materials = [rMat]
            let rNode = SCNNode(geometry: roof)
            rNode.position.y = Float(floors) + 0.05
            holder.addChildNode(rNode)

            holder.addChildNode(makeGrassTuft(x: 0.68, z: 0.62))

        case .commercial:
            if hash == 0 {
                let shop = SCNBox(width: 1.42, height: 0.90, length: 1.26, chamferRadius: 0.02)
                let sMat = SCNMaterial()
                sMat.diffuse.contents = bank.texture("indomaret_facade_albedo.png") ?? UIColor.systemBlue
                if isLit { sMat.emission.contents = UIColor(red: 0.30, green: 0.34, blue: 0.40, alpha: 1.0) }
                shop.materials = [sMat]
                let sNode = SCNNode(geometry: shop)
                sNode.position.y = 0.50
                holder.addChildNode(sNode)
            } else {
                let bHeight = 1.7 + CGFloat(hash) * 0.95
                let tower = SCNBox(width: 1.32, height: bHeight, length: 1.32, chamferRadius: 0.05)
                let mat = SCNMaterial()
                mat.diffuse.contents = bank.texture("building_facade_day.png") ?? UIColor(red: 0.24, green: 0.46, blue: 0.74, alpha: 1.0)
                if isLit {
                    mat.emission.contents = bank.texture("building_facade_night_emission.png") ?? UIColor(red: 0.25, green: 0.48, blue: 0.75, alpha: 1.0)
                }
                tower.materials = [mat]
                let tNode = SCNNode(geometry: tower)
                tNode.position.y = Float(bHeight * 0.5) + 0.05
                holder.addChildNode(tNode)
            }

        case .industrial:
            let hall = SCNBox(width: 1.48, height: 1.15, length: 1.22, chamferRadius: 0.02)
            let mat = SCNMaterial()
            mat.diffuse.contents = UIColor(red: 0.62, green: 0.58, blue: 0.48, alpha: 1.0)
            hall.materials = [mat]
            let hNode = SCNNode(geometry: hall)
            hNode.position.y = 0.62
            holder.addChildNode(hNode)

            let chimney = SCNCylinder(radius: 0.12, height: 1.95)
            let cMat = SCNMaterial()
            cMat.diffuse.contents = UIColor.darkGray
            chimney.materials = [cMat]
            let cNode = SCNNode(geometry: chimney)
            cNode.position = SCNVector3(0.45, 0.98, -0.35)
            holder.addChildNode(cNode)

        case .park:
            break
        }
        return holder
    }

    private func makeFacilityNode(kind: FacilityKind) -> SCNNode {
        let holder = SCNNode()
        let bank = NusantaraAssetBank.shared
        let w = CGFloat(tileSize * 0.95)

        let plaza = SCNBox(width: w, height: 0.08, length: w, chamferRadius: 0)
        let pMat = SCNMaterial()
        pMat.diffuse.contents = bank.texture("sidewalk_paving_albedo.png") ?? UIColor.lightGray
        plaza.materials = [pMat]
        let pNode = SCNNode(geometry: plaza)
        pNode.position.y = 0.04
        holder.addChildNode(pNode)

        switch kind {
        case .universitas:
            // Kompleks Rektorat Utama + Sayap Kiri-Kanan + Menara Kampus
            let mainWing = SCNBox(width: 1.56, height: 1.95, length: 0.85, chamferRadius: 0.04)
            let mMat = SCNMaterial()
            mMat.diffuse.contents = bank.texture("school_facade_albedo.png") ?? UIColor.white
            if isNightMode { mMat.emission.contents = bank.texture("building_facade_night_emission.png") }
            mainWing.materials = [mMat]
            let mNode = SCNNode(geometry: mainWing)
            mNode.position = SCNVector3(0, 1.02, -0.25)
            holder.addChildNode(mNode)

            let roof = SCNPyramid(width: 1.66, height: 0.52, length: 0.96)
            let rMat = SCNMaterial()
            rMat.diffuse.contents = bank.texture("roof_terracotta_albedo.png") ?? UIColor.brown
            roof.materials = [rMat]
            let rNode = SCNNode(geometry: roof)
            rNode.position = SCNVector3(0, 2.0, -0.25)
            holder.addChildNode(rNode)

            let gate = SCNBox(width: 0.85, height: 0.65, length: 0.22, chamferRadius: 0.02)
            gate.materials = [rMat]
            let gNode = SCNNode(geometry: gate)
            gNode.position = SCNVector3(0, 0.36, 0.62)
            holder.addChildNode(gNode)

        case .sdNegeri, .smpUnggulan, .smaKejuruan:
            // Gedung Sekolah Bentuk L Khas Indonesia + Lapangan Upacara
            let blockA = SCNBox(width: 1.48, height: 0.92, length: 0.55, chamferRadius: 0.02)
            let sMat = SCNMaterial()
            sMat.diffuse.contents = bank.texture("school_facade_albedo.png") ?? UIColor.white
            if isNightMode { sMat.emission.contents = UIColor.yellow.withAlphaComponent(0.25) }
            blockA.materials = [sMat]
            let aNode = SCNNode(geometry: blockA)
            aNode.position = SCNVector3(0, 0.50, -0.45)
            holder.addChildNode(aNode)

            let roof = SCNPyramid(width: 1.56, height: 0.42, length: 0.64)
            let rMat = SCNMaterial()
            rMat.diffuse.contents = bank.texture("roof_terracotta_albedo.png") ?? UIColor.brown
            roof.materials = [rMat]
            let rNode = SCNNode(geometry: roof)
            rNode.position = SCNVector3(0, 0.96, -0.45)
            holder.addChildNode(rNode)

            // Tiang Bendera di Lapangan Upacara
            let flagPole = SCNCylinder(radius: 0.02, height: 1.1)
            let fpNode = SCNNode(geometry: flagPole)
            fpNode.position = SCNVector3(0, 0.60, 0.35)
            holder.addChildNode(fpNode)

        case .balaiKota:
            // Pendopo-Modern Balai Kota + Menara Jam
            let hall = SCNBox(width: 1.56, height: 1.35, length: 1.25, chamferRadius: 0.04)
            let bMat = SCNMaterial()
            bMat.diffuse.contents = UIColor(red: 0.95, green: 0.92, blue: 0.86, alpha: 1.0)
            if isNightMode { bMat.emission.contents = UIColor(red: 0.38, green: 0.30, blue: 0.14, alpha: 1.0) }
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
            if isNightMode { hMat.emission.contents = bank.texture("building_facade_night_emission.png") }
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

    private func makeRealisticTree(species: Int) -> SCNNode {
        let tree = SCNNode()
        let trunk = SCNCylinder(radius: 0.06, height: 0.52)
        let tMat = SCNMaterial()
        tMat.diffuse.contents = UIColor(red: 0.40, green: 0.26, blue: 0.15, alpha: 1.0)
        trunk.materials = [tMat]
        let tNode = SCNNode(geometry: trunk)
        tNode.position.y = 0.26
        tree.addChildNode(tNode)

        let leafColor: UIColor
        switch species {
        case 0: leafColor = UIColor(red: 0.12, green: 0.42, blue: 0.18, alpha: 1.0) // Pinus / Cemara
        case 1: leafColor = UIColor(red: 0.18, green: 0.56, blue: 0.22, alpha: 1.0) // Trembesi
        default: leafColor = UIColor(red: 0.94, green: 0.52, blue: 0.68, alpha: 1.0) // Tabebuya Mekar
        }

        let offsets: [(x: Float, y: Float, z: Float, r: CGFloat)] = [
            (0.0, 0.68, 0.0, 0.34),
            (-0.18, 0.58, 0.14, 0.24),
            (0.18, 0.60, -0.14, 0.24)
        ]
        for o in offsets {
            let crown = SCNSphere(radius: o.r)
            let cMat = SCNMaterial()
            cMat.diffuse.contents = leafColor
            crown.materials = [cMat]
            let cNode = SCNNode(geometry: crown)
            cNode.position = SCNVector3(o.x, o.y, o.z)
            tree.addChildNode(cNode)
        }
        return tree
    }

    private func makeGrassTuft(x: Float, z: Float) -> SCNNode {
        let tuft = SCNNode()
        let blade = SCNCone(topRadius: 0.01, bottomRadius: 0.16, height: 0.22)
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(red: 0.22, green: 0.64, blue: 0.24, alpha: 1.0)
        blade.materials = [mat]
        let bNode = SCNNode(geometry: blade)
        bNode.position.y = 0.11
        tuft.addChildNode(bNode)
        tuft.position = SCNVector3(x, 0.02, z)
        return tuft
    }

    private func makeVehicleNode(kind: VehicleKind, index: Int) -> SCNNode {
        let holder = SCNNode()
        switch kind {
        case .motorbike:
            // Sepeda Motor + Siluet Pengendara Berhelm
            let body = SCNBox(width: 0.12, height: 0.16, length: 0.34, chamferRadius: 0.03)
            let bMat = SCNMaterial()
            bMat.diffuse.contents = [UIColor.systemRed, UIColor.black, UIColor.systemBlue][index % 3]
            body.materials = [bMat]
            let bNode = SCNNode(geometry: body)
            bNode.position.y = 0.12
            holder.addChildNode(bNode)

            let rider = SCNSphere(radius: 0.07)
            let rMat = SCNMaterial()
            rMat.diffuse.contents = UIColor.white
            rider.materials = [rMat]
            let rNode = SCNNode(geometry: rider)
            rNode.position = SCNVector3(0, 0.27, 0.02)
            holder.addChildNode(rNode)

        case .car:
            // Mobil Sedan / MPV + Kabin Kaca + Roda + Lampu Depan/Rem
            let chassis = SCNBox(width: 0.32, height: 0.14, length: 0.58, chamferRadius: 0.04)
            let cMat = SCNMaterial()
            cMat.diffuse.contents = [UIColor.white, UIColor.darkGray, UIColor.lightGray, UIColor.systemRed][index % 4]
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

        if isNightMode {
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

    private func rebuildTrafficPool() {
        trafficContainer.childNodes.forEach { $0.removeFromParentNode() }
        vehicles.removeAll()
        guard activeDriveCoords.count >= 2 else { return }

        let count = min(18, max(4, activeDriveCoords.count))
        let pattern: [VehicleKind] = [.motorbike, .car, .motorbike, .angkotBus, .car, .emergency]

        for i in 0..<count {
            let vKind = pattern[i % pattern.count]
            let node = makeVehicleNode(kind: vKind, index: i)
            trafficContainer.addChildNode(node)
            let spd: Float = vKind == .motorbike ? 0.48 : (vKind == .emergency ? 0.55 : 0.36)
            vehicles.append((node: node, kind: vKind, progress: Float(i) / Float(count), indexOffset: i * 3, speed: spd))
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            self?.stepSimulationFrame(time: time)
        }
    }

    private func stepSimulationFrame(time: TimeInterval) {
        if lastUpdateTime == 0 { lastUpdateTime = time; return }
        let dt = Float(min(max(time - lastUpdateTime, 0.0), 0.08))
        lastUpdateTime = time

        // Rotasi kamera otomatis saat berada di Menu Utama
        if showcaseActive {
            camYaw += dt * 0.14
            updateCameraTransform()
        }

        let total = activeDriveCoords.count
        guard total >= 2 else { return }

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
                // Jalur kiri Indonesia (motor lebih ke sisi kiri, mobil di lajur utama kiri)
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

    func toggleNightMode() -> Bool {
        isNightMode.toggle()
        applyAtmosphere(shadows: true, fog: true)
        NusantaraAssetBank.shared.playBGM(night: isNightMode)
        return isNightMode
    }

    func applyAtmosphere(shadows: Bool, fog: Bool) {
        sunLightNode.light?.castsShadow = shadows
        if isNightMode {
            scene.background.contents = UIColor(red: 0.03, green: 0.05, blue: 0.12, alpha: 1.0)
            scene.fogColor = UIColor(red: 0.03, green: 0.05, blue: 0.12, alpha: 1.0)
            ambientLightNode.light?.intensity = 220
            sunLightNode.light?.intensity = 180
        } else {
            scene.background.contents = UIColor(red: 0.52, green: 0.78, blue: 0.96, alpha: 1.0)
            scene.fogColor = UIColor(red: 0.72, green: 0.88, blue: 0.98, alpha: 1.0)
            ambientLightNode.light?.intensity = 560
            sunLightNode.light?.intensity = 1220
        }
        scene.fogStartDistance = fog ? 48 : 260
        scene.fogEndDistance = fog ? 135 : 300
    }

    func updateCameraTransform() {
        let pitch: Float = cameraMode == .streetView ? 0.25 : 0.72
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
        camDistance = min(74.0, max(8.0, camDistance / scaleFactor))
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

    func handleTap(at point: CGPoint, in scnView: SCNView) {
        let hits = scnView.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
        if let first = hits.first {
            let worldPos = first.worldCoordinates
            let gx = Int(round(worldPos.x / tileSize))
            let gz = Int(round(worldPos.z / tileSize))
            if abs(gx) <= gridHalfExtent && abs(gz) <= gridHalfExtent {
                onTileTapped?(GridCoord(x: gx, z: gz))
            }
        }
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

    final class Coordinator: NSObject {
        let engine: City3DEngine
        weak var scnView: SCNView?
        var interactive: Bool = true
        private var lastPan: CGPoint = .zero

        init(engine: City3DEngine) { self.engine = engine }

        @objc func onTap(_ gesture: UITapGestureRecognizer) {
            guard interactive, let view = scnView else { return }
            engine.handleTap(at: gesture.location(in: view), in: view)
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


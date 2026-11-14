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
    var isMuted: Bool = false {
        didSet { bgmPlayer?.volume = isMuted ? 0.0 : 0.40 }
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
            player.volume = isMuted ? 0.0 : 0.40
            player.prepareToPlay()
            player.play()
            bgmPlayer = player
        }
    }

    func playBuildSFX() {
        guard !isMuted,
              let url = Bundle.main.url(forResource: "build_construct_sfx", withExtension: "wav", subdirectory: "GameAssets/Audio") else { return }
        if let player = try? AVAudioPlayer(contentsOf: url) {
            player.volume = 0.6
            player.play()
            sfxPlayer = player
        }
    }
}

final class City3DEngine: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    private let worldRoot = SCNNode()
    private let terrainContainer = SCNNode()
    private let roadContainer = SCNNode()
    private let zoneContainer = SCNNode()
    private let facilityContainer = SCNNode()
    private let trafficContainer = SCNNode()
    private let incidentContainer = SCNNode()

    private let cameraPivot = SCNNode()
    private let cameraNode = SCNNode()
    private let sunLightNode = SCNNode()
    private let ambientLightNode = SCNNode()

    private var roadNodes: [GridCoord: SCNNode] = [:]
    private var zoneNodes: [GridCoord: SCNNode] = [:]
    private var facilityNodes: [GridCoord: SCNNode] = [:]
    private var activeDriveCoords: [GridCoord] = []
    private var vehicles: [(node: SCNNode, progress: Float, indexOffset: Int, speed: Float)] = []
    private var lastUpdateTime: TimeInterval = 0

    private var currentMap: CityMapType = .malang
    private var isNightMode: Bool = false
    private var camYaw: Float = 0.65
    private var camDistance: Float = 36.0
    private var panTarget: SIMD2<Float> = SIMD2<Float>(0, 0)

    let gridHalfExtent: Int = 16
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
        worldRoot.addChildNode(roadContainer)
        worldRoot.addChildNode(zoneContainer)
        worldRoot.addChildNode(facilityContainer)
        worldRoot.addChildNode(trafficContainer)
        worldRoot.addChildNode(incidentContainer)

        cameraPivot.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(cameraPivot)

        let cam = SCNCamera()
        cam.zNear = 0.5
        cam.zFar = 280.0
        cam.fieldOfView = 45.0
        cameraNode.camera = cam
        cameraPivot.addChildNode(cameraNode)
        updateCameraTransform()

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 540
        ambient.color = UIColor(red: 0.88, green: 0.92, blue: 1.0, alpha: 1.0)
        ambientLightNode.light = ambient
        scene.rootNode.addChildNode(ambientLightNode)

        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 1200
        sun.color = UIColor(red: 1.0, green: 0.95, blue: 0.85, alpha: 1.0)
        sun.castsShadow = true
        sun.shadowMode = .deferred
        sun.shadowSampleCount = 2
        sunLightNode.light = sun
        sunLightNode.eulerAngles = SCNVector3(-Float.pi / 3.0, Float.pi / 4.0, 0)
        scene.rootNode.addChildNode(sunLightNode)

        applyAtmosphere()
    }

    func loadMap(_ mapType: CityMapType, showcaseDemo: Bool) {
        currentMap = mapType
        terrainContainer.childNodes.forEach { $0.removeFromParentNode() }
        roadContainer.childNodes.forEach { $0.removeFromParentNode() }
        zoneContainer.childNodes.forEach { $0.removeFromParentNode() }
        facilityContainer.childNodes.forEach { $0.removeFromParentNode() }
        trafficContainer.childNodes.forEach { $0.removeFromParentNode() }
        incidentContainer.childNodes.forEach { $0.removeFromParentNode() }
        roadNodes.removeAll()
        zoneNodes.removeAll()
        facilityNodes.removeAll()
        vehicles.removeAll()
        activeDriveCoords.removeAll()

        panTarget = SIMD2<Float>(0, 0)
        camDistance = showcaseDemo ? 34.0 : 38.0
        updateCameraTransform()
        buildTerrain(for: mapType)
        applyAtmosphere()
        NusantaraAssetBank.shared.playBGM(night: isNightMode)

        if showcaseDemo { buildShowcaseCity() }
    }

    private func buildTerrain(for mapType: CityMapType) {
        let boardSpan = CGFloat(gridHalfExtent * 2 + 1) * CGFloat(tileSize)
        let bank = NusantaraAssetBank.shared

        let outerPlane = SCNPlane(width: 260, height: 260)
        let outerMat = SCNMaterial()
        outerMat.diffuse.contents = mapType == .malang
            ? UIColor(red: 0.14, green: 0.30, blue: 0.16, alpha: 1.0)
            : UIColor(red: 0.06, green: 0.28, blue: 0.48, alpha: 1.0)
        outerPlane.materials = [outerMat]
        let outerNode = SCNNode(geometry: outerPlane)
        outerNode.eulerAngles.x = -.pi / 2
        outerNode.position.y = -0.18
        terrainContainer.addChildNode(outerNode)

        let groundBox = SCNBox(width: boardSpan, height: 0.3, length: boardSpan, chamferRadius: 0)
        let groundMat = SCNMaterial()
        if let grassTex = bank.texture("grass_nusantara_albedo.png") {
            groundMat.diffuse.contents = grassTex
            groundMat.diffuse.contentsTransform = SCNMatrix4MakeScale(10, 10, 1)
            groundMat.diffuse.wrapS = .repeat
            groundMat.diffuse.wrapT = .repeat
        } else {
            groundMat.diffuse.contents = UIColor(red: 0.22, green: 0.46, blue: 0.22, alpha: 1.0)
        }
        groundBox.materials = [groundMat]
        let groundNode = SCNNode(geometry: groundBox)
        groundNode.position = SCNVector3(0, -0.15, 0)
        terrainContainer.addChildNode(groundNode)

        let gridMat = SCNMaterial()
        gridMat.diffuse.contents = UIColor.white.withAlphaComponent(0.11)
        for i in -gridHalfExtent...(gridHalfExtent + 1) {
            let offset = (Float(i) - 0.5) * tileSize
            let lineX = SCNBox(width: boardSpan, height: 0.01, length: 0.04, chamferRadius: 0)
            lineX.materials = [gridMat]
            let nodeX = SCNNode(geometry: lineX)
            nodeX.position = SCNVector3(0, 0.006, offset)
            terrainContainer.addChildNode(nodeX)

            let lineZ = SCNBox(width: 0.04, height: 0.01, length: boardSpan, chamferRadius: 0)
            lineZ.materials = [gridMat]
            let nodeZ = SCNNode(geometry: lineZ)
            nodeZ.position = SCNVector3(offset, 0.006, 0)
            terrainContainer.addChildNode(nodeZ)
        }

        let waterMat = SCNMaterial()
        waterMat.diffuse.contents = UIColor(red: 0.10, green: 0.46, blue: 0.72, alpha: 0.92)
        waterMat.specular.contents = UIColor.white
        waterMat.shininess = 0.85

        if mapType == .malang {
            let river = SCNBox(width: 4.2, height: 0.04, length: boardSpan, chamferRadius: 0)
            river.materials = [waterMat]
            let rNode = SCNNode(geometry: river)
            rNode.position = SCNVector3(18.0, 0.01, 0)
            terrainContainer.addChildNode(rNode)

            let peaks: [(x: Float, z: Float, r: CGFloat, h: CGFloat)] = [
                (-16, -54, 18, 22), (8, -58, 22, 26), (32, -52, 16, 19), (-44, -22, 16, 18)
            ]
            for p in peaks {
                let mountain = SCNCone(topRadius: 2.2, bottomRadius: p.r, height: p.h)
                let mMat = SCNMaterial()
                mMat.diffuse.contents = UIColor(red: 0.16, green: 0.34, blue: 0.21, alpha: 1.0)
                mountain.materials = [mMat]
                let mNode = SCNNode(geometry: mountain)
                mNode.position = SCNVector3(p.x, Float(p.h) * 0.48, p.z)
                terrainContainer.addChildNode(mNode)
            }
        } else {
            let river = SCNBox(width: 4.5, height: 0.04, length: boardSpan, chamferRadius: 0)
            river.materials = [waterMat]
            let rNode = SCNNode(geometry: river)
            rNode.position = SCNVector3(14.0, 0.01, 0)
            terrainContainer.addChildNode(rNode)
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
        demoZones[GridCoord(x: -2, z: 1)] = ZoneTile(coord: GridCoord(x: -2, z: 1), kind: .residential, level: 1)
        demoZones[GridCoord(x: 2, z: 1)] = ZoneTile(coord: GridCoord(x: 2, z: 1), kind: .commercial, level: 1)
        demoZones[GridCoord(x: 4, z: 1)] = ZoneTile(coord: GridCoord(x: 4, z: 1), kind: .park, level: 1)

        syncWorld(roads: demoRoads, zones: demoZones, facilities: demoFacs)
    }

    func syncWorld(roads: [GridCoord: RoadTile], zones: [GridCoord: ZoneTile], facilities: [GridCoord: FacilityTile]) {
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

        activeDriveCoords = roads.values.filter { $0.kind.isDriveable }.map { $0.coord }
        rebuildTrafficPool()
    }

    func showAccidentMarker(at coord: GridCoord?) {
        incidentContainer.childNodes.forEach { $0.removeFromParentNode() }
        guard let coord else { return }
        let beacon = SCNCylinder(radius: 0.35, height: 1.6)
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor.systemRed
        mat.emission.contents = UIColor.systemRed
        beacon.materials = [mat]
        let node = SCNNode(geometry: beacon)
        let p = worldPosition(for: coord)
        node.position = SCNVector3(p.x, 0.85, p.z)
        incidentContainer.addChildNode(node)
    }

    private func makeRoadNode(tile: RoadTile) -> SCNNode {
        let holder = SCNNode()
        let w = CGFloat(tileSize)
        let bank = NusantaraAssetBank.shared

        if tile.kind == .sidewalkTree {
            let paving = SCNBox(width: w, height: 0.08, length: w, chamferRadius: 0)
            let pMat = SCNMaterial()
            pMat.diffuse.contents = bank.texture("sidewalk_paving_albedo.png") ?? UIColor(red: 0.68, green: 0.64, blue: 0.58, alpha: 1.0)
            paving.materials = [pMat]
            let pNode = SCNNode(geometry: paving)
            pNode.position.y = 0.04
            holder.addChildNode(pNode)
            holder.addChildNode(makeTreeNode())
            return holder
        }

        let asphalt = SCNBox(width: w, height: 0.06, length: w, chamferRadius: 0)
        let aMat = SCNMaterial()
        let texName = tile.kind == .fourLane ? "road_4lane_albedo.png" : "road_2lane_albedo.png"
        aMat.diffuse.contents = bank.texture(texName) ?? UIColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1.0)
        asphalt.materials = [aMat]
        let aNode = SCNNode(geometry: asphalt)
        aNode.position.y = 0.03
        holder.addChildNode(aNode)

        if tile.kind == .roundabout {
            // Bundaran Alun-Alun Hijau + Tugu Tengah
            let island = SCNCylinder(radius: 0.65, height: 0.14)
            let iMat = SCNMaterial()
            iMat.diffuse.contents = UIColor(red: 0.18, green: 0.62, blue: 0.28, alpha: 1.0)
            island.materials = [iMat]
            let iNode = SCNNode(geometry: island)
            iNode.position.y = 0.09
            holder.addChildNode(iNode)

            let monument = SCNCylinder(radius: 0.14, height: 0.95)
            let mMat = SCNMaterial()
            mMat.diffuse.contents = UIColor(red: 0.92, green: 0.86, blue: 0.72, alpha: 1.0)
            if isNightMode { mMat.emission.contents = UIColor.cyan.withAlphaComponent(0.5) }
            monument.materials = [mMat]
            let mNode = SCNNode(geometry: monument)
            mNode.position.y = 0.52
            holder.addChildNode(mNode)
        } else if (abs(tile.coord.x) + abs(tile.coord.z)) % 2 == 0 {
            let pole = SCNCylinder(radius: 0.03, height: 0.85)
            let poleMat = SCNMaterial()
            poleMat.diffuse.contents = UIColor.darkGray
            pole.materials = [poleMat]
            let poleNode = SCNNode(geometry: pole)
            poleNode.position = SCNVector3(tileSize * 0.42, 0.45, tileSize * 0.42)
            holder.addChildNode(poleNode)

            let bulb = SCNSphere(radius: 0.07)
            let bulbMat = SCNMaterial()
            bulbMat.diffuse.contents = UIColor(red: 1.0, green: 0.90, blue: 0.65, alpha: 1.0)
            bulbMat.emission.contents = isNightMode ? UIColor(red: 1.0, green: 0.82, blue: 0.35, alpha: 1.0) : UIColor.clear
            bulb.materials = [bulbMat]
            let bulbNode = SCNNode(geometry: bulb)
            bulbNode.position = SCNVector3(tileSize * 0.42, 0.88, tileSize * 0.42)
            holder.addChildNode(bulbNode)
        }

        return holder
    }

    private func makeZoneNode(tile: ZoneTile) -> SCNNode {
        let holder = SCNNode()
        let w = CGFloat(tileSize * 0.94)
        let bank = NusantaraAssetBank.shared

        let base = SCNBox(width: w, height: 0.05, length: w, chamferRadius: 0)
        let baseMat = SCNMaterial()
        switch tile.kind {
        case .residential: baseMat.diffuse.contents = UIColor(red: 0.22, green: 0.68, blue: 0.34, alpha: 0.88)
        case .commercial: baseMat.diffuse.contents = UIColor(red: 0.18, green: 0.52, blue: 0.88, alpha: 0.88)
        case .industrial: baseMat.diffuse.contents = UIColor(red: 0.88, green: 0.68, blue: 0.16, alpha: 0.88)
        case .park: baseMat.diffuse.contents = UIColor(red: 0.18, green: 0.62, blue: 0.28, alpha: 1.0)
        }
        base.materials = [baseMat]
        let baseNode = SCNNode(geometry: base)
        baseNode.position.y = 0.025
        holder.addChildNode(baseNode)

        if tile.kind == .park {
            let t1 = makeTreeNode(); t1.position = SCNVector3(-0.42, 0, -0.35)
            let t2 = makeTreeNode(); t2.position = SCNVector3(0.45, 0, 0.38)
            holder.addChildNode(t1); holder.addChildNode(t2)
            return holder
        }

        let hash = abs(tile.coord.x * 31 + tile.coord.z * 17) % 3
        switch tile.kind {
        case .residential:
            let bHeight = 0.78 + CGFloat(hash) * 0.28
            let body = SCNBox(width: 1.15, height: bHeight, length: 1.15, chamferRadius: 0.04)
            let mat = SCNMaterial()
            if hash == 1, let kTex = bank.texture("kampung_warnawarni_albedo.png") {
                mat.diffuse.contents = kTex
            } else {
                mat.diffuse.contents = [UIColor(red: 0.95, green: 0.92, blue: 0.85, alpha: 1.0), UIColor.systemOrange, UIColor.systemTeal][hash]
            }
            if isNightMode { mat.emission.contents = UIColor(red: 0.35, green: 0.28, blue: 0.12, alpha: 1.0) }
            body.materials = [mat]
            let bNode = SCNNode(geometry: body)
            bNode.position.y = Float(bHeight * 0.5) + 0.05
            holder.addChildNode(bNode)

            let roof = SCNPyramid(width: 1.28, height: 0.45, length: 1.28)
            let rMat = SCNMaterial()
            rMat.diffuse.contents = UIColor(red: 0.65, green: 0.24, blue: 0.18, alpha: 1.0)
            roof.materials = [rMat]
            let rNode = SCNNode(geometry: roof)
            rNode.position.y = Float(bHeight) + 0.05
            holder.addChildNode(rNode)

        case .commercial:
            if hash == 0 {
                let shop = SCNBox(width: 1.42, height: 0.85, length: 1.25, chamferRadius: 0.02)
                let sMat = SCNMaterial()
                sMat.diffuse.contents = bank.texture("indomaret_facade_albedo.png") ?? UIColor.systemBlue
                if isNightMode { sMat.emission.contents = UIColor(red: 0.28, green: 0.32, blue: 0.38, alpha: 1.0) }
                shop.materials = [sMat]
                let sNode = SCNNode(geometry: shop)
                sNode.position.y = 0.47
                holder.addChildNode(sNode)
            } else {
                let bHeight = 1.6 + CGFloat(hash) * 0.95
                let tower = SCNBox(width: 1.32, height: bHeight, length: 1.32, chamferRadius: 0.05)
                let mat = SCNMaterial()
                mat.diffuse.contents = bank.texture("building_facade_day.png") ?? UIColor(red: 0.24, green: 0.46, blue: 0.74, alpha: 1.0)
                if isNightMode {
                    mat.emission.contents = bank.texture("building_facade_night_emission.png") ?? UIColor(red: 0.25, green: 0.48, blue: 0.75, alpha: 1.0)
                }
                tower.materials = [mat]
                let tNode = SCNNode(geometry: tower)
                tNode.position.y = Float(bHeight * 0.5) + 0.05
                holder.addChildNode(tNode)
            }

        case .industrial:
            let hall = SCNBox(width: 1.48, height: 1.1, length: 1.22, chamferRadius: 0.02)
            let mat = SCNMaterial()
            mat.diffuse.contents = UIColor(red: 0.62, green: 0.58, blue: 0.48, alpha: 1.0)
            hall.materials = [mat]
            let hNode = SCNNode(geometry: hall)
            hNode.position.y = 0.6
            holder.addChildNode(hNode)

        case .park:
            break
        }
        return holder
    }

    private func makeFacilityNode(kind: FacilityKind) -> SCNNode {
        let holder = SCNNode()
        let bank = NusantaraAssetBank.shared
        let height: CGFloat = (kind == .universitas || kind == .balaiKota || kind == .rsud) ? 2.4 : 1.5
        let box = SCNBox(width: 1.68, height: height, length: 1.68, chamferRadius: 0.06)
        let mat = SCNMaterial()
        switch kind {
        case .balaiKota: mat.diffuse.contents = UIColor(red: 0.85, green: 0.28, blue: 0.24, alpha: 1.0)
        case .sdNegeri, .smpUnggulan, .smaKejuruan: mat.diffuse.contents = UIColor(red: 0.24, green: 0.56, blue: 0.86, alpha: 1.0)
        case .universitas: mat.diffuse.contents = bank.texture("building_facade_day.png") ?? UIColor.systemIndigo
        case .rsud: mat.diffuse.contents = UIColor.white
        case .kantorPolisi: mat.diffuse.contents = UIColor(red: 0.22, green: 0.24, blue: 0.30, alpha: 1.0)
        case .pemadam: mat.diffuse.contents = UIColor.systemRed
        }
        if isNightMode {
            mat.emission.contents = bank.texture("building_facade_night_emission.png") ?? UIColor.yellow.withAlphaComponent(0.32)
        }
        box.materials = [mat]
        let node = SCNNode(geometry: box)
        node.position.y = Float(height * 0.5)
        holder.addChildNode(node)
        return holder
    }

    private func makeTreeNode() -> SCNNode {
        let tree = SCNNode()
        let trunk = SCNCylinder(radius: 0.06, height: 0.45)
        let tMat = SCNMaterial()
        tMat.diffuse.contents = UIColor(red: 0.42, green: 0.28, blue: 0.16, alpha: 1.0)
        trunk.materials = [tMat]
        let tNode = SCNNode(geometry: trunk)
        tNode.position.y = 0.24
        tree.addChildNode(tNode)

        let crown = SCNSphere(radius: 0.34)
        let cMat = SCNMaterial()
        cMat.diffuse.contents = currentMap == .malang
            ? UIColor(red: 0.12, green: 0.44, blue: 0.18, alpha: 1.0)
            : UIColor(red: 0.20, green: 0.58, blue: 0.24, alpha: 1.0)
        crown.materials = [cMat]
        let cNode = SCNNode(geometry: crown)
        cNode.position.y = 0.62
        tree.addChildNode(cNode)
        return tree
    }

    private func rebuildTrafficPool() {
        trafficContainer.childNodes.forEach { $0.removeFromParentNode() }
        vehicles.removeAll()
        guard activeDriveCoords.count >= 2 else { return }

        let count = min(14, max(2, activeDriveCoords.count / 2))
        let carColors: [UIColor] = [.white, .systemRed, .systemYellow, .systemBlue, .darkGray]
        for i in 0..<count {
            let carBody = SCNBox(width: 0.30, height: 0.18, length: 0.54, chamferRadius: 0.05)
            let mat = SCNMaterial()
            mat.diffuse.contents = carColors[i % carColors.count]
            carBody.materials = [mat]
            let node = SCNNode(geometry: carBody)

            if isNightMode {
                let beam = SCNSphere(radius: 0.06)
                let bMat = SCNMaterial()
                bMat.diffuse.contents = UIColor.white
                bMat.emission.contents = UIColor(red: 1.0, green: 0.95, blue: 0.75, alpha: 1.0)
                beam.materials = [bMat]
                let bNode = SCNNode(geometry: beam)
                bNode.position = SCNVector3(0, 0, -0.28)
                node.addChildNode(bNode)
            }

            trafficContainer.addChildNode(node)
            vehicles.append((node: node, progress: Float(i) / Float(count), indexOffset: i * 3, speed: 0.38))
        }
    }

    nonisolated func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async { [weak self] in self?.stepTraffic(time: time) }
    }

    private func stepTraffic(time: TimeInterval) {
        if lastUpdateTime == 0 { lastUpdateTime = time; return }
        let dt = Float(min(max(time - lastUpdateTime, 0.0), 0.08))
        lastUpdateTime = time

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
                // Jalur kiri Indonesia (offset -0.22 tegak lurus arah gerak)
                let dx = Float(cB.x - cA.x)
                let dz = Float(cB.z - cA.z)
                let leftX = dz * 0.22
                let leftZ = -dx * 0.22
                vehicles[i].node.position = SCNVector3(
                    pA.x + (pB.x - pA.x) * frac + leftX,
                    0.15,
                    pA.z + (pB.z - pA.z) * frac + leftZ
                )
                vehicles[i].node.look(at: SCNVector3(pB.x + leftX, 0.15, pB.z + leftZ))
            } else {
                vehicles[i].node.position = SCNVector3(pA.x, 0.15, pA.z)
            }
        }
    }

    func toggleNightMode() -> Bool {
        isNightMode.toggle()
        applyAtmosphere()
        NusantaraAssetBank.shared.playBGM(night: isNightMode)
        return isNightMode
    }

    private func applyAtmosphere() {
        if isNightMode {
            scene.background.contents = UIColor(red: 0.03, green: 0.05, blue: 0.12, alpha: 1.0)
            scene.fogColor = UIColor(red: 0.03, green: 0.05, blue: 0.12, alpha: 1.0)
            ambientLightNode.light?.intensity = 220
            sunLightNode.light?.intensity = 180
        } else {
            scene.background.contents = UIColor(red: 0.52, green: 0.78, blue: 0.96, alpha: 1.0)
            scene.fogColor = UIColor(red: 0.72, green: 0.88, blue: 0.98, alpha: 1.0)
            ambientLightNode.light?.intensity = 540
            sunLightNode.light?.intensity = 1200
        }
        scene.fogStartDistance = 45
        scene.fogEndDistance = 130
    }

    func updateCameraTransform() {
        let pitch: Float = 0.72
        let hDist = camDistance * cos(pitch)
        let vDist = camDistance * sin(pitch)
        cameraPivot.position = SCNVector3(panTarget.x, 0, panTarget.y)
        cameraNode.position = SCNVector3(sin(camYaw) * hDist, vDist, cos(camYaw) * hDist)
        cameraNode.look(at: cameraPivot.position)
    }

    func panCamera(dx: Float, dz: Float) {
        let forwardX = -sin(camYaw)
        let forwardZ = -cos(camYaw)
        let rightX = cos(camYaw)
        let rightZ = -sin(camYaw)
        let scale = camDistance * 0.0022
        panTarget.x = min(30, max(-30, panTarget.x - (rightX * dx - forwardX * dz) * scale))
        panTarget.y = min(30, max(-30, panTarget.y - (rightZ * dx - forwardZ * dz) * scale))
        updateCameraTransform()
    }

    func zoomCamera(scaleFactor: Float) {
        camDistance = min(72.0, max(12.0, camDistance / scaleFactor))
        updateCameraTransform()
    }

    func rotateCamera(deltaYaw: Float) {
        camYaw += deltaYaw
        updateCameraTransform()
    }

    func worldPosition(for coord: GridCoord) -> SCNVector3 {
        SCNVector3(Float(coord.x) * tileSize, 0, Float(coord.z) * tileSize)
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

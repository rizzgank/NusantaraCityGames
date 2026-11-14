import Foundation
import UIKit
import SceneKit
import SwiftUI
import AVFoundation

// MARK: - Safe Asset Loader (Anti-Crash Fallback)

final class NusantaraAssetBank {
    static let shared = NusantaraAssetBank()

    private var imageCache: [String: UIImage] = [:]
    private var bgmPlayer: AVAudioPlayer?
    private var sfxPlayer: AVAudioPlayer?
    var isMuted: Bool = false {
        didSet {
            bgmPlayer?.volume = isMuted ? 0.0 : 0.42
        }
    }

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func texture(_ filename: String) -> UIImage? {
        if let cached = imageCache[filename] {
            return cached
        }
        let stem = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        if let url = Bundle.main.url(forResource: stem, withExtension: ext, subdirectory: "GameAssets/Textures"),
           let img = UIImage(contentsOfFile: url.path) {
            imageCache[filename] = img
            return img
        }
        return nil
    }

    func playBGM(night: Bool, map: CityMapType) {
        let track = night ? "cozy_night_city" : (map == .malang ? "wind_leaves_mountain" : "city_traffic_day")
        guard let url = Bundle.main.url(forResource: track, withExtension: "wav", subdirectory: "GameAssets/Audio") else {
            return
        }
        if bgmPlayer?.url == url && bgmPlayer?.isPlaying == true {
            return
        }
        bgmPlayer?.stop()
        if let player = try? AVAudioPlayer(contentsOf: url) {
            player.numberOfLoops = -1
            player.volume = isMuted ? 0.0 : 0.42
            player.prepareToPlay()
            player.play()
            bgmPlayer = player
        }
    }

    func playBuildSFX() {
        guard !isMuted,
              let url = Bundle.main.url(forResource: "build_construct_sfx", withExtension: "wav", subdirectory: "GameAssets/Audio") else {
            return
        }
        if let player = try? AVAudioPlayer(contentsOf: url) {
            player.volume = 0.65
            player.play()
            sfxPlayer = player
        }
    }
}

// MARK: - SceneKit 3D Engine (PBR Textures + Safe Geometry)

final class City3DEngine: NSObject, SCNSceneRendererDelegate {

    let scene = SCNScene()
    private let worldRoot = SCNNode()
    private let terrainContainer = SCNNode()
    private let roadContainer = SCNNode()
    private let zoneContainer = SCNNode()
    private let trafficContainer = SCNNode()

    private let cameraPivot = SCNNode()
    private let cameraNode = SCNNode()
    private let sunLightNode = SCNNode()
    private let ambientLightNode = SCNNode()

    private var roadNodes: [GridCoord: SCNNode] = [:]
    private var zoneNodes: [GridCoord: SCNNode] = [:]
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
        worldRoot.addChildNode(trafficContainer)

        cameraPivot.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(cameraPivot)

        let cam = SCNCamera()
        cam.zNear = 0.5
        cam.zFar = 260.0
        cam.fieldOfView = 45.0
        cameraNode.camera = cam
        cameraPivot.addChildNode(cameraNode)
        updateCameraTransform()

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 520
        ambient.color = UIColor(red: 0.85, green: 0.90, blue: 1.0, alpha: 1.0)
        ambientLightNode.light = ambient
        scene.rootNode.addChildNode(ambientLightNode)

        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 1150
        sun.color = UIColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1.0)
        sun.castsShadow = true
        sun.shadowMode = .deferred
        sun.shadowSampleCount = 2
        sunLightNode.light = sun
        sunLightNode.eulerAngles = SCNVector3(-Float.pi / 3.2, Float.pi / 4.0, 0)
        scene.rootNode.addChildNode(sunLightNode)

        applyAtmosphere()
    }

    func loadMap(_ mapType: CityMapType, showcaseDemo: Bool) {
        currentMap = mapType
        terrainContainer.childNodes.forEach { $0.removeFromParentNode() }
        roadContainer.childNodes.forEach { $0.removeFromParentNode() }
        zoneContainer.childNodes.forEach { $0.removeFromParentNode() }
        trafficContainer.childNodes.forEach { $0.removeFromParentNode() }
        roadNodes.removeAll()
        zoneNodes.removeAll()
        vehicles.removeAll()
        activeDriveCoords.removeAll()

        panTarget = SIMD2<Float>(0, 0)
        camDistance = showcaseDemo ? 34.0 : 38.0
        updateCameraTransform()

        buildTerrain(for: mapType)
        applyAtmosphere()
        NusantaraAssetBank.shared.playBGM(night: isNightMode, map: mapType)

        if showcaseDemo {
            buildShowcaseCity()
        }
    }

    private func buildTerrain(for mapType: CityMapType) {
        let boardSpan = CGFloat(gridHalfExtent * 2 + 1) * CGFloat(tileSize)
        let bank = NusantaraAssetBank.shared

        let outerPlane = SCNPlane(width: 240, height: 240)
        let outerMat = SCNMaterial()
        outerMat.diffuse.contents = mapType == .malang
            ? UIColor(red: 0.14, green: 0.32, blue: 0.16, alpha: 1.0)
            : UIColor(red: 0.06, green: 0.28, blue: 0.48, alpha: 1.0)
        outerPlane.materials = [outerMat]
        let outerNode = SCNNode(geometry: outerPlane)
        outerNode.eulerAngles.x = -.pi / 2
        outerNode.position.y = -0.18
        terrainContainer.addChildNode(outerNode)

        let groundBox = SCNBox(width: boardSpan, height: 0.3, length: boardSpan, chamferRadius: 0.0)
        let groundMat = SCNMaterial()
        if let grassTex = bank.texture("grass_nusantara_albedo.png") {
            groundMat.diffuse.contents = grassTex
            groundMat.diffuse.contentsTransform = SCNMatrix4MakeScale(10, 10, 1)
            groundMat.diffuse.wrapS = .repeat
            groundMat.diffuse.wrapT = .repeat
            if let grassNorm = bank.texture("grass_normal.png") {
                groundMat.normal.contents = grassNorm
                groundMat.normal.contentsTransform = SCNMatrix4MakeScale(10, 10, 1)
                groundMat.normal.wrapS = .repeat
                groundMat.normal.wrapT = .repeat
            }
        } else {
            groundMat.diffuse.contents = UIColor(red: 0.24, green: 0.49, blue: 0.23, alpha: 1.0)
        }
        groundMat.roughness.contents = 0.88
        groundBox.materials = [groundMat]
        let groundNode = SCNNode(geometry: groundBox)
        groundNode.position = SCNVector3(0, -0.15, 0)
        groundNode.name = "terrain_ground"
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

            let mountain = SCNCone(topRadius: 1.5, bottomRadius: 14.0, height: 15.0)
            let mMat = SCNMaterial()
            mMat.diffuse.contents = UIColor(red: 0.18, green: 0.36, blue: 0.22, alpha: 1.0)
            mountain.materials = [mMat]
            let mNode = SCNNode(geometry: mountain)
            mNode.position = SCNVector3(-8.0, 7.2, -46.0)
            terrainContainer.addChildNode(mNode)
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

        for x in -6...6 {
            let c1 = GridCoord(x: x, z: -2)
            let c2 = GridCoord(x: x, z: 3)
            demoRoads[c1] = RoadTile(coord: c1, kind: .fourLane)
            demoRoads[c2] = RoadTile(coord: c2, kind: .twoLane)
        }
        for z in -5...5 {
            let c3 = GridCoord(x: 0, z: z)
            demoRoads[c3] = RoadTile(coord: c3, kind: .fourLane)
        }
        for x in -5...5 where x != 0 {
            let r1 = GridCoord(x: x, z: -1)
            let c1 = GridCoord(x: x, z: 1)
            let i1 = GridCoord(x: x, z: 4)
            demoZones[r1] = ZoneTile(coord: r1, kind: .residential, level: 2)
            demoZones[c1] = ZoneTile(coord: c1, kind: .commercial, level: 2)
            demoZones[i1] = ZoneTile(coord: i1, kind: .park, level: 1)
        }

        syncWorld(roads: demoRoads, zones: demoZones)
    }

    func syncWorld(roads: [GridCoord: RoadTile], zones: [GridCoord: ZoneTile]) {
        for (coord, node) in roadNodes where roads[coord] == nil {
            node.removeFromParentNode()
            roadNodes.removeValue(forKey: coord)
        }
        for (coord, tile) in roads {
            roadNodes[coord]?.removeFromParentNode()
            let node = makeRoadNode(tile: tile)
            node.position = worldPosition(for: coord)
            roadContainer.addChildNode(node)
            roadNodes[coord] = node
        }

        for (coord, node) in zoneNodes where zones[coord] == nil {
            node.removeFromParentNode()
            zoneNodes.removeValue(forKey: coord)
        }
        for (coord, tile) in zones {
            zoneNodes[coord]?.removeFromParentNode()
            let hasAdjacentRoad = roads[GridCoord(x: coord.x + 1, z: coord.z)] != nil ||
                                  roads[GridCoord(x: coord.x - 1, z: coord.z)] != nil ||
                                  roads[GridCoord(x: coord.x, z: coord.z + 1)] != nil ||
                                  roads[GridCoord(x: coord.x, z: coord.z - 1)] != nil
            let node = makeZoneNode(tile: tile, connectedToRoad: hasAdjacentRoad)
            node.position = worldPosition(for: coord)
            zoneContainer.addChildNode(node)
            zoneNodes[coord] = node
        }

        activeDriveCoords = roads.values.filter { $0.kind.isDriveable }.map { $0.coord }
        rebuildTrafficPool()
    }

    private func makeRoadNode(tile: RoadTile) -> SCNNode {
        let holder = SCNNode()
        let w = CGFloat(tileSize)
        let bank = NusantaraAssetBank.shared

        if tile.kind == .sidewalkTree {
            let paving = SCNBox(width: w, height: 0.08, length: w, chamferRadius: 0)
            let pMat = SCNMaterial()
            if let tex = bank.texture("sidewalk_paving_albedo.png") {
                pMat.diffuse.contents = tex
            } else {
                pMat.diffuse.contents = UIColor(red: 0.68, green: 0.64, blue: 0.58, alpha: 1.0)
            }
            paving.materials = [pMat]
            let pNode = SCNNode(geometry: paving)
            pNode.position.y = 0.04
            holder.addChildNode(pNode)

            holder.addChildNode(makeTreeNode())
            return holder
        }

        let asphalt = SCNBox(width: w, height: 0.06, length: w, chamferRadius: 0)
        let aMat = SCNMaterial()
        let texName = tile.kind == .fourLane ? "road_2way_4lane_albedo.png" : "road_1way_2lane_albedo.png"
        if let tex = bank.texture(texName) {
            aMat.diffuse.contents = tex
            if let norm = bank.texture("asphalt_normal.png") {
                aMat.normal.contents = norm
            }
        } else {
            aMat.diffuse.contents = UIColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1.0)
        }
        asphalt.materials = [aMat]
        let aNode = SCNNode(geometry: asphalt)
        aNode.position.y = 0.03
        holder.addChildNode(aNode)

        if (abs(tile.coord.x) + abs(tile.coord.z)) % 2 == 0 {
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
            bulbMat.emission.contents = isNightMode
                ? UIColor(red: 1.0, green: 0.82, blue: 0.35, alpha: 1.0)
                : UIColor.clear
            bulb.materials = [bulbMat]
            let bulbNode = SCNNode(geometry: bulb)
            bulbNode.position = SCNVector3(tileSize * 0.42, 0.88, tileSize * 0.42)
            holder.addChildNode(bulbNode)
        }

        return holder
    }

    private func makeZoneNode(tile: ZoneTile, connectedToRoad: Bool) -> SCNNode {
        let holder = SCNNode()
        let w = CGFloat(tileSize * 0.94)
        let bank = NusantaraAssetBank.shared

        let base = SCNBox(width: w, height: 0.05, length: w, chamferRadius: 0)
        let baseMat = SCNMaterial()
        switch tile.kind {
        case .residential:
            baseMat.diffuse.contents = UIColor(red: 0.22, green: 0.68, blue: 0.34, alpha: 0.88)
        case .commercial:
            baseMat.diffuse.contents = UIColor(red: 0.18, green: 0.52, blue: 0.88, alpha: 0.88)
        case .industrial:
            baseMat.diffuse.contents = UIColor(red: 0.88, green: 0.68, blue: 0.16, alpha: 0.88)
        case .park:
            baseMat.diffuse.contents = UIColor(red: 0.18, green: 0.62, blue: 0.28, alpha: 1.0)
        }
        base.materials = [baseMat]
        let baseNode = SCNNode(geometry: base)
        baseNode.position.y = 0.025
        holder.addChildNode(baseNode)

        if tile.kind == .park {
            let t1 = makeTreeNode()
            t1.position = SCNVector3(-0.42, 0, -0.35)
            let t2 = makeTreeNode()
            t2.position = SCNVector3(0.45, 0, 0.38)
            holder.addChildNode(t1)
            holder.addChildNode(t2)
            return holder
        }

        let heightBoost: CGFloat = connectedToRoad ? 1.0 : 0.55
        let hash = abs(tile.coord.x * 31 + tile.coord.z * 17) % 3

        switch tile.kind {
        case .residential:
            let bHeight = (0.75 + CGFloat(hash) * 0.35) * heightBoost
            let body = SCNBox(width: 1.15, height: bHeight, length: 1.15, chamferRadius: 0.04)
            let mat = SCNMaterial()
            if hash == 1, let kampungTex = bank.texture("kampung_warnawarni_albedo.png") {
                mat.diffuse.contents = kampungTex
            } else {
                let colors: [UIColor] = [
                    UIColor(red: 0.95, green: 0.92, blue: 0.85, alpha: 1.0),
                    UIColor(red: 0.92, green: 0.45, blue: 0.38, alpha: 1.0),
                    UIColor(red: 0.35, green: 0.72, blue: 0.88, alpha: 1.0)
                ]
                mat.diffuse.contents = colors[hash]
            }
            if isNightMode {
                mat.emission.contents = UIColor(red: 0.35, green: 0.28, blue: 0.12, alpha: 1.0)
            }
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
                // Minimarket Nusantara (Indomaret)
                let shop = SCNBox(width: 1.42, height: 0.85, length: 1.25, chamferRadius: 0.02)
                let sMat = SCNMaterial()
                sMat.diffuse.contents = bank.texture("indomaret_facade_albedo.png") ?? UIColor.systemBlue
                if isNightMode {
                    sMat.emission.contents = UIColor(red: 0.28, green: 0.32, blue: 0.38, alpha: 1.0)
                }
                shop.materials = [sMat]
                let sNode = SCNNode(geometry: shop)
                sNode.position.y = 0.47
                holder.addChildNode(sNode)
            } else {
                let bHeight = (1.6 + CGFloat(hash) * 0.95) * heightBoost
                let tower = SCNBox(width: 1.32, height: bHeight, length: 1.32, chamferRadius: 0.05)
                let mat = SCNMaterial()
                mat.diffuse.contents = bank.texture("building_facade_day.png") ?? UIColor(red: 0.24, green: 0.46, blue: 0.74, alpha: 1.0)
                mat.specular.contents = UIColor.white
                if isNightMode {
                    mat.emission.contents = bank.texture("building_facade_night_emission.png") ?? UIColor(red: 0.25, green: 0.48, blue: 0.75, alpha: 1.0)
                }
                tower.materials = [mat]
                let tNode = SCNNode(geometry: tower)
                tNode.position.y = Float(bHeight * 0.5) + 0.05
                holder.addChildNode(tNode)
            }

        case .industrial:
            let bHeight = (1.05 + CGFloat(hash) * 0.25) * heightBoost
            let hall = SCNBox(width: 1.48, height: bHeight, length: 1.22, chamferRadius: 0.02)
            let mat = SCNMaterial()
            mat.diffuse.contents = UIColor(red: 0.62, green: 0.58, blue: 0.48, alpha: 1.0)
            hall.materials = [mat]
            let hNode = SCNNode(geometry: hall)
            hNode.position.y = Float(bHeight * 0.5) + 0.05
            holder.addChildNode(hNode)

            let chimney = SCNCylinder(radius: 0.12, height: bHeight + 0.75)
            let cMat = SCNMaterial()
            cMat.diffuse.contents = UIColor.darkGray
            chimney.materials = [cMat]
            let cNode = SCNNode(geometry: chimney)
            cNode.position = SCNVector3(0.45, Float((bHeight + 0.75) * 0.5), -0.35)
            holder.addChildNode(cNode)

        case .park:
            break
        }

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
            let carBody = SCNBox(width: 0.32, height: 0.20, length: 0.56, chamferRadius: 0.05)
            let mat = SCNMaterial()
            mat.diffuse.contents = carColors[i % carColors.count]
            carBody.materials = [mat]
            let node = SCNNode(geometry: carBody)
            trafficContainer.addChildNode(node)
            vehicles.append((
                node: node,
                progress: Float(i) / Float(count),
                indexOffset: i * 3,
                speed: 0.35 + Float(i % 3) * 0.08
            ))
        }
    }

    nonisolated func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            self?.stepTraffic(time: time)
        }
    }

    private func stepTraffic(time: TimeInterval) {
        if lastUpdateTime == 0 {
            lastUpdateTime = time
            return
        }
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
                vehicles[i].node.position = SCNVector3(
                    pA.x + (pB.x - pA.x) * frac,
                    0.16,
                    pA.z + (pB.z - pA.z) * frac
                )
                vehicles[i].node.look(at: SCNVector3(pB.x, 0.16, pB.z))
            } else {
                vehicles[i].node.position = SCNVector3(pA.x, 0.16, pA.z)
            }
        }
    }

    func toggleNightMode() -> Bool {
        isNightMode.toggle()
        applyAtmosphere()
        NusantaraAssetBank.shared.playBGM(night: isNightMode, map: currentMap)
        return isNightMode
    }

    private func applyAtmosphere() {
        if isNightMode {
            scene.background.contents = UIColor(red: 0.04, green: 0.07, blue: 0.14, alpha: 1.0)
            scene.fogColor = UIColor(red: 0.04, green: 0.07, blue: 0.14, alpha: 1.0)
            ambientLightNode.light?.intensity = 240
            sunLightNode.light?.intensity = 220
            sunLightNode.light?.color = UIColor(red: 0.45, green: 0.60, blue: 0.95, alpha: 1.0)
        } else {
            scene.background.contents = UIColor(red: 0.52, green: 0.78, blue: 0.96, alpha: 1.0)
            scene.fogColor = UIColor(red: 0.72, green: 0.88, blue: 0.98, alpha: 1.0)
            ambientLightNode.light?.intensity = 550
            sunLightNode.light?.intensity = 1150
            sunLightNode.light?.color = UIColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1.0)
        }
        scene.fogStartDistance = 42
        scene.fogEndDistance = 120
    }

    func updateCameraTransform() {
        let pitch: Float = 0.72
        let horizontalDist = camDistance * cos(pitch)
        let verticalDist = camDistance * sin(pitch)

        cameraPivot.position = SCNVector3(panTarget.x, 0, panTarget.y)
        cameraNode.position = SCNVector3(
            sin(camYaw) * horizontalDist,
            verticalDist,
            cos(camYaw) * horizontalDist
        )
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

    func makeCoordinator() -> Coordinator {
        Coordinator(engine: engine)
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView(frame: .zero, options: nil)
        scnView.scene = engine.scene
        scnView.delegate = engine
        scnView.isPlaying = true
        scnView.rendersContinuously = true
        scnView.antialiasingMode = .multisampling2X
        scnView.backgroundColor = .black
        scnView.allowsCameraControl = false

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

        init(engine: City3DEngine) {
            self.engine = engine
        }

        @objc func onTap(_ gesture: UITapGestureRecognizer) {
            guard interactive, let view = scnView else { return }
            engine.handleTap(at: gesture.location(in: view), in: view)
        }

        @objc func onPan(_ gesture: UIPanGestureRecognizer) {
            guard interactive, let view = scnView else { return }
            let current = gesture.translation(in: view)
            if gesture.state == .began {
                lastPan = current
                return
            }
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

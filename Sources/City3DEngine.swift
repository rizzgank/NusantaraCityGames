import Foundation
import UIKit
import SceneKit
import SwiftUI

final class City3DEngine: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    private let worldRoot = SCNNode()
    private let terrainContainer = SCNNode()
    private let roadContainer = SCNNode()
    private let zoneContainer = SCNNode()
    private let facilityContainer = SCNNode()
    private let trafficContainer = SCNNode()

    private let cameraPivot = SCNNode()
    private let cameraNode = SCNNode()
    private let sunLightNode = SCNNode()
    private let ambientLightNode = SCNNode()

    private var roadNodes: [GridCoord: SCNNode] = [:]
    private var zoneNodes: [GridCoord: SCNNode] = [:]
    private var facilityNodes: [GridCoord: SCNNode] = [:]
    private var activeDriveCoords: [GridCoord] = []
    private var vehicles: [(node: SCNNode, progress: Float, speed: Float)] = []
    private var lastUpdateTime: TimeInterval = 0

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
        ambient.color = UIColor(red: 0.88, green: 0.92, blue: 1.0, alpha: 1.0)
        ambientLightNode.light = ambient
        scene.rootNode.addChildNode(ambientLightNode)

        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 1200
        sun.color = UIColor(red: 1.0, green: 0.95, blue: 0.85, alpha: 1.0)
        sun.castsShadow = true
        sunLightNode.light = sun
        sunLightNode.eulerAngles = SCNVector3(-Float.pi / 3.0, Float.pi / 4.0, 0)
        scene.rootNode.addChildNode(sunLightNode)

        applyAtmosphere()
    }

    func loadMap(_ mapType: CityMapType, showcaseDemo: Bool) {
        terrainContainer.childNodes.forEach { $0.removeFromParentNode() }
        roadContainer.childNodes.forEach { $0.removeFromParentNode() }
        zoneContainer.childNodes.forEach { $0.removeFromParentNode() }
        facilityContainer.childNodes.forEach { $0.removeFromParentNode() }
        trafficContainer.childNodes.forEach { $0.removeFromParentNode() }
        roadNodes.removeAll()
        zoneNodes.removeAll()
        facilityNodes.removeAll()
        vehicles.removeAll()

        panTarget = SIMD2<Float>(0, 0)
        camDistance = 36.0
        updateCameraTransform()
        buildTerrain(for: mapType)
        applyAtmosphere()

        if showcaseDemo { buildShowcaseCity() }
    }

    private func buildTerrain(for mapType: CityMapType) {
        let boardSpan = CGFloat(gridHalfExtent * 2 + 1) * CGFloat(tileSize)
        let groundBox = SCNBox(width: boardSpan, height: 0.3, length: boardSpan, chamferRadius: 0)
        let groundMat = SCNMaterial()
        groundMat.diffuse.contents = UIColor(red: 0.22, green: 0.46, blue: 0.22, alpha: 1.0)
        groundBox.materials = [groundMat]
        let groundNode = SCNNode(geometry: groundBox)
        groundNode.position = SCNVector3(0, -0.15, 0)
        terrainContainer.addChildNode(groundNode)

        // Pegunungan latar belakang realistis
        if mapType == .malang {
            let mountain = SCNCone(topRadius: 2.0, bottomRadius: 18.0, height: 18.0)
            let mMat = SCNMaterial()
            mMat.diffuse.contents = UIColor(red: 0.16, green: 0.32, blue: 0.20, alpha: 1.0)
            mountain.materials = [mMat]
            let mNode = SCNNode(geometry: mountain)
            mNode.position = SCNVector3(-12.0, 9.0, -50.0)
            terrainContainer.addChildNode(mNode)
        }
    }

    private func buildShowcaseCity() {
        var demoRoads: [GridCoord: RoadTile] = [:]
        var demoZones: [GridCoord: ZoneTile] = [:]
        var demoFacs: [GridCoord: FacilityTile] = [:]

        for x in -4...4 {
            let c = GridCoord(x: x, z: 0)
            demoRoads[c] = RoadTile(coord: c, kind: .fourLane)
        }
        demoFacs[GridCoord(x: 0, z: -2)] = FacilityTile(coord: GridCoord(x: 0, z: -2), kind: .balaiKota)
        demoZones[GridCoord(x: -2, z: 1)] = ZoneTile(coord: GridCoord(x: -2, z: 1), kind: .residential, level: 1)
        demoZones[GridCoord(x: 2, z: 1)] = ZoneTile(coord: GridCoord(x: 2, z: 1), kind: .commercial, level: 1)

        syncWorld(roads: demoRoads, zones: demoZones, facilities: demoFacs)
    }

    func syncWorld(roads: [GridCoord: RoadTile], zones: [GridCoord: ZoneTile], facilities: [FacilityTile]) {
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
        for fac in facilities {
            let node = makeFacilityNode(kind: fac.kind)
            node.position = worldPosition(for: fac.coord)
            facilityContainer.addChildNode(node)
            facilityNodes[fac.coord] = node
        }

        activeDriveCoords = roads.values.filter { $0.kind.isDriveable }.map { $0.coord }
        rebuildTrafficPool()
    }

    private func makeRoadNode(tile: RoadTile) -> SCNNode {
        let holder = SCNNode()
        let box = SCNBox(width: CGFloat(tileSize), height: 0.06, length: CGFloat(tileSize), chamferRadius: 0)
        let mat = SCNMaterial()
        mat.diffuse.contents = tile.kind == .roundabout ? UIColor.darkGray : UIColor(red: 0.18, green: 0.19, blue: 0.22, alpha: 1.0)
        box.materials = [mat]
        let node = SCNNode(geometry: box)
        node.position.y = 0.03
        holder.addChildNode(node)
        return holder
    }

    private func makeZoneNode(tile: ZoneTile) -> SCNNode {
        let holder = SCNNode()
        let box = SCNBox(width: 1.2, height: 1.0, length: 1.2, chamferRadius: 0.05)
        let mat = SCNMaterial()
        switch tile.kind {
        case .residential: mat.diffuse.contents = UIColor(red: 0.25, green: 0.72, blue: 0.38, alpha: 1.0)
        case .commercial: mat.diffuse.contents = UIColor(red: 0.20, green: 0.55, blue: 0.88, alpha: 1.0)
        case .industrial: mat.diffuse.contents = UIColor(red: 0.88, green: 0.68, blue: 0.18, alpha: 1.0)
        case .park: mat.diffuse.contents = UIColor(red: 0.18, green: 0.65, blue: 0.28, alpha: 1.0)
        }
        if isNightMode {
            mat.emission.contents = UIColor(red: 0.3, green: 0.25, blue: 0.1, alpha: 1.0)
        }
        box.materials = [mat]
        let node = SCNNode(geometry: box)
        node.position.y = 0.5
        holder.addChildNode(node)
        return holder
    }

    private func makeFacilityNode(kind: FacilityKind) -> SCNNode {
        let holder = SCNNode()
        let box = SCNBox(width: 1.8, height: 2.2, length: 1.8, chamferRadius: 0.08)
        let mat = SCNMaterial()
        mat.diffuse.contents = kind == .balaiKota ? UIColor(red: 0.85, green: 0.32, blue: 0.28, alpha: 1.0) : UIColor(red: 0.35, green: 0.42, blue: 0.55, alpha: 1.0)
        if isNightMode { mat.emission.contents = UIColor.yellow.withAlphaComponent(0.3) }
        box.materials = [mat]
        let node = SCNNode(geometry: box)
        node.position.y = 1.1
        holder.addChildNode(node)
        return holder
    }

    private func rebuildTrafficPool() {
        trafficContainer.childNodes.forEach { $0.removeFromParentNode() }
        vehicles.removeAll()
        guard activeDriveCoords.count >= 2 else { return }

        for i in 0..<8 {
            let car = SCNBox(width: 0.3, height: 0.18, length: 0.5, chamferRadius: 0.04)
            let mat = SCNMaterial()
            mat.diffuse.contents = [UIColor.white, UIColor.systemRed, UIColor.systemBlue][i % 3]
            car.materials = [mat]
            let node = SCNNode(geometry: car)
            trafficContainer.addChildNode(node)
            vehicles.append((node: node, progress: Float(i) * 0.2, speed: 0.4))
        }
    }

    nonisolated func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async { [weak self] in self?.stepTraffic(time: time) }
    }

    private func stepTraffic(time: TimeInterval) {
        if lastUpdateTime == 0 { lastUpdateTime = time; return }
        let dt = Float(min(time - lastUpdateTime, 0.05))
        lastUpdateTime = time
        let total = activeDriveCoords.count
        guard total >= 2 else { return }

        for i in vehicles.indices {
            vehicles[i].progress += dt * vehicles[i].speed
            let idx = Int(vehicles[i].progress) % total
            let pos = worldPosition(for: activeDriveCoords[idx])
            vehicles[i].node.position = SCNVector3(pos.x, 0.15, pos.z)
        }
    }

    func toggleNightMode() -> Bool {
        isNightMode.toggle()
        applyAtmosphere()
        return isNightMode
    }

    private func applyAtmosphere() {
        if isNightMode {
            scene.background.contents = UIColor(red: 0.03, green: 0.05, blue: 0.12, alpha: 1.0)
            ambientLightNode.light?.intensity = 200
            sunLightNode.light?.intensity = 150
        } else {
            scene.background.contents = UIColor(red: 0.52, green: 0.78, blue: 0.96, alpha: 1.0)
            ambientLightNode.light?.intensity = 520
            sunLightNode.light?.intensity = 1200
        }
    }

    func updateCameraTransform() {
        let pitch: Float = 0.72
        let hDist = camDistance * cos(pitch)
        let vDist = camDistance * sin(pitch)
        cameraPivot.position = SCNVector3(panTarget.x, 0, panTarget.y)
        cameraNode.position = SCNVector3(sin(camYaw) * hDist, vDist, cos(camYaw) * hDist)
        cameraNode.look(at: cameraPivot.position)
    }

    func zoomCamera(f: Float) { camDistance = min(70, max(12, camDistance / f)); updateCameraTransform() }
    func rotateCamera(dy: Float) { camYaw += dy; updateCameraTransform() }
    func worldPosition(for coord: GridCoord) -> SCNVector3 { SCNVector3(Float(coord.x) * tileSize, 0, Float(coord.z) * tileSize) }

    func handleTap(at point: CGPoint, in scnView: SCNView) {
        let hits = scnView.hitTest(point, options: nil)
        if let first = hits.first {
            let pos = first.worldCoordinates
            let gx = Int(round(pos.x / tileSize))
            let gz = Int(round(pos.z / tileSize))
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
        let v = SCNView()
        v.scene = engine.scene
        v.delegate = engine
        v.isPlaying = true
        v.rendersContinuously = true
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onTap(_:)))
        v.addGestureRecognizer(tap)
        context.coordinator.scnView = v
        return v
    }
    func updateUIView(_ uiView: SCNView, context: Context) {}
    final class Coordinator: NSObject {
        let engine: City3DEngine
        weak var scnView: SCNView?
        init(engine: City3DEngine) { self.engine = engine }
        @objc func onTap(_ gesture: UITapGestureRecognizer) {
            guard let v = scnView else { return }
            engine.handleTap(at: gesture.location(in: v), in: v)
        }
    }
}

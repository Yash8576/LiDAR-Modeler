import ARKit
import RealityKit
import SwiftUI

class PointCloudManager: NSObject, ObservableObject, ARSessionDelegate {
    var arView: ARView?
    var currentPoints: [SIMD3<Float>] = []
    private var lastUpdateTime = Date()

    // Define bounding cube size and position
    let boxSize: Float = 0.3
    let boxPosition = SIMD3<Float>(0, 0, -0.4) // 40 cm in front of camera

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let now = Date()
        guard now.timeIntervalSince(lastUpdateTime) > 1.0 else { return }
        lastUpdateTime = now

        guard let sceneDepth = frame.sceneDepth else { return }

        let depthMap = sceneDepth.depthMap
        let intrinsics = frame.camera.intrinsics
        let cameraTransform = frame.camera.transform

        DispatchQueue.global(qos: .userInitiated).async {
            let allPoints = self.convertToPointCloud(depthMap: depthMap, intrinsics: intrinsics, cameraTransform: cameraTransform)

            // Filter points inside the cube
            let filtered = allPoints.filter { point in
                let local = point - self.boxWorldPosition(cameraTransform)
                return abs(local.x) < self.boxSize / 2 &&
                       abs(local.y) < self.boxSize / 2 &&
                       abs(local.z) < self.boxSize / 2
            }

            DispatchQueue.main.async {
                self.currentPoints = filtered
                self.showBoxInAR() // show cube only, no dots
            }
        }
    }

    func convertToPointCloud(depthMap: CVPixelBuffer, intrinsics: simd_float3x3, cameraTransform: simd_float4x4) -> [SIMD3<Float>] {
        var points: [SIMD3<Float>] = []

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let rowStride = bytesPerRow / MemoryLayout<Float32>.stride

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            return []
        }

        for y in stride(from: 0, to: height, by: 8) {
            let rowPtr = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float32.self)
            for x in stride(from: 0, to: width, by: 8) {
                let z = rowPtr[x]
                if z == 0 { continue }

                let xn = (Float(x) - intrinsics[0,2]) / intrinsics[0,0]
                let yn = (Float(y) - intrinsics[1,2]) / intrinsics[1,1]
                let pointCamera = SIMD3<Float>(xn * z, yn * z, -z)

                let pointWorld4 = cameraTransform * SIMD4<Float>(pointCamera, 1)
                let pointWorld = SIMD3<Float>(pointWorld4.x, pointWorld4.y, pointWorld4.z)
                points.append(pointWorld)
            }
        }

        CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
        return points
    }

    func boxWorldPosition(_ cameraTransform: simd_float4x4) -> SIMD3<Float> {
        let localPosition = SIMD4<Float>(boxPosition, 1)
        let worldPosition = cameraTransform * localPosition
        return SIMD3<Float>(worldPosition.x, worldPosition.y, worldPosition.z)
    }

    func showBoxInAR() {
        guard let arView else { return }
        arView.scene.anchors.removeAll()

        let anchor = AnchorEntity(world: boxWorldPosition(arView.session.currentFrame?.camera.transform ?? matrix_identity_float4x4))
        let box = ModelEntity(mesh: .generateBox(size: [boxSize, boxSize, boxSize]),
                              materials: [SimpleMaterial(color: .red.withAlphaComponent(0.2), isMetallic: false)])
        anchor.addChild(box)
        arView.scene.anchors.append(anchor)
    }

    func exportCurrentPointCloud() {
        guard !currentPoints.isEmpty else { return }

        var text = """
        ply
        format ascii 1.0
        element vertex \(currentPoints.count)
        property float x
        property float y
        property float z
        end_header
        """

        for point in currentPoints {
            text += "\n\(point.x) \(point.y) \(point.z)"
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("scan.ply")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            print("✅ Exported to: \(url)")
            shareFile(at: url)
        } catch {
            print("❌ Failed to write file: \(error)")
        }
    }

    func shareFile(at url: URL) {
        guard let rootVC = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first?.windows.first?.rootViewController else { return }

        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        rootVC.present(activityVC, animated: true)
    }
}

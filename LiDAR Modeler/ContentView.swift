import SwiftUI
import RealityKit
import ARKit

struct ContentView: View {
    @StateObject private var cloudManager = PointCloudManager()

    var body: some View {
        ZStack {
            ARViewContainer(manager: cloudManager)
                .edgesIgnoringSafeArea(.all)

            VStack {
                Spacer()
                HStack {
                    Button("🔴 Export PLY") {
                        cloudManager.exportCurrentPointCloud()
                    }
                    .padding()
                    .background(Color.white.opacity(0.8))
                    .cornerRadius(10)
                }
                .padding()
            }
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    let manager: PointCloudManager

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        let config = ARWorldTrackingConfiguration()

        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }

        arView.session.delegate = manager
        arView.session.run(config)
        manager.arView = arView

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

import SwiftUI

struct ContentView: View {
    enum Route: Hashable {
        case sendPhoto, probe, testPattern
    }

    @State private var path: [Route] = Self.initialPath

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink(value: Route.sendPhoto) {
                        Label("Send Photo", systemImage: "photo")
                    }
                }
                Section("Lab") {
                    NavigationLink(value: Route.probe) {
                        Label("Device Probe", systemImage: "magnifyingglass")
                    }
                    NavigationLink(value: Route.testPattern) {
                        Label("Test Pattern", systemImage: "rectangle.split.3x1")
                    }
                }
            }
            .navigationTitle("InkyTap")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .sendPhoto:
                    SendPhotoView(initialPhotoData: Self.demoPhotoData)
                case .probe:
                    DeviceProbeView(initialResult: Self.demoProbeResult)
                case .testPattern:
                    TestPatternView()
                }
            }
        }
    }

    // Debug-only deep links for screenshots; see DemoData.
    private static var initialPath: [Route] {
        #if DEBUG
        switch DemoData.requestedScreen {
        case .sendPhoto: [.sendPhoto]
        case .probe: [.probe]
        case .testPattern: [.testPattern]
        case nil: []
        }
        #else
        []
        #endif
    }

    private static var demoPhotoData: Data? {
        #if DEBUG
        DemoData.requestedScreen == .sendPhoto ? DemoData.samplePhotoData : nil
        #else
        nil
        #endif
    }

    private static var demoProbeResult: DeviceProbeResult? {
        #if DEBUG
        DemoData.requestedScreen == .probe ? DemoData.probeResult : nil
        #else
        nil
        #endif
    }
}

#Preview {
    ContentView()
}

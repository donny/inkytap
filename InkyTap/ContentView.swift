import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        SendPhotoView()
                    } label: {
                        Label("Send Photo", systemImage: "photo")
                    }
                }
                Section("Lab") {
                    NavigationLink {
                        DeviceProbeView()
                    } label: {
                        Label("Device Probe", systemImage: "magnifyingglass")
                    }
                    NavigationLink {
                        TestPatternView()
                    } label: {
                        Label("Test Pattern", systemImage: "rectangle.split.3x1")
                    }
                }
            }
            .navigationTitle("InkyTap")
        }
    }
}

#Preview {
    ContentView()
}

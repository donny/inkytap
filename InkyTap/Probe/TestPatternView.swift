import SwiftUI

struct TestPatternView: View {
    @State private var pattern: TestPattern = .colorBars
    @State private var layout = PanelLayout()
    @State private var isSending = false
    @State private var log: [String] = []

    private var image: PixelImage { pattern.render() }

    var body: some View {
        List {
            Section("Pattern") {
                Picker("Pattern", selection: $pattern) {
                    ForEach(TestPattern.allCases) { Text($0.rawValue).tag($0) }
                }
                if let preview = image.uiImage() {
                    Image(uiImage: preview)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .border(.secondary)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }

            Section {
                DisclosureGroup("Advanced layout (defaults verified)") {
                Toggle("Mirror columns (left ↔ right)", isOn: $layout.mirrorColumns)
                Toggle("Mirror rows (top ↔ bottom)", isOn: $layout.mirrorRows)
                Toggle("Low nibble first", isOn: $layout.lowNibbleFirst)
                Toggle("Padding rows before image", isOn: $layout.padAtStart)
                Picker("Padding color", selection: $layout.paddingColor) {
                    ForEach(SpectraColor.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                }
            } header: {
                Text("Panel layout")
            } footer: {
                Text("4 bpp, \(PanelLayout.nativeRows) native rows × \(PanelLayout.bytesPerNativeRow) bytes = \(PanelLayout.totalBytes) bytes, sent as \(PanelLayout.imageCount) image slots of \(PanelLayout.imageBytes) bytes. Each native row is one column of the upright panel.")
            }

            Section {
                Button {
                    Task { await send() }
                } label: {
                    Label(isSending ? "Sending…" : "Send to display", systemImage: "wave.3.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                Text("Hold the phone on the display for the whole upload and refresh. A Spectra 6 refresh can take 20–30 seconds.")
            }

            if !log.isEmpty {
                Section {
                    ForEach(Array(log.enumerated()), id: \.offset) { _, entry in
                        Text(entry)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    Button("Copy log") {
                        UIPasteboard.general.string = log.joined(separator: "\n\n")
                    }
                    Button("Clear log", role: .destructive) {
                        log.removeAll()
                    }
                } header: {
                    Text("Log")
                }
            }
        }
        .navigationTitle("Test Pattern")
    }

    private func send() async {
        isSending = true
        defer { isSending = false }

        let chunks = Framebuffer.imageChunks(Framebuffer.pack(image, layout: layout))
        let description = "\(pattern.rawValue) | \(layout.summary)"
        let stamp = Date().formatted(date: .omitted, time: .standard)
        do {
            let report = try await EPaperTagSession.run(alertMessage: "Hold your iPhone on the e-ink display.") { tag, setMessage in
                try await EPaperUploader.send(
                    chunks: chunks,
                    layoutDescription: description,
                    tag: tag,
                    setMessage: setMessage
                )
            }
            log.insert("[\(stamp)] OK\n" + report.text, at: 0)
        } catch {
            log.insert("[\(stamp)] FAILED\n\(description)\n\(error.localizedDescription)", at: 0)
        }
    }
}

#Preview {
    NavigationStack {
        TestPatternView()
    }
}

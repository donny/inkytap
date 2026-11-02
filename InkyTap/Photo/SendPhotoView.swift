import PhotosUI
import SwiftUI

struct SendPhotoView: View {
    @State private var pickerItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var settings = PhotoProcessor.Settings()
    @State private var preview: PixelImage?
    @State private var previewImage: UIImage?
    @State private var isProcessing = false
    @State private var isSending = false
    @State private var status: String?

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    ZStack {
                        Rectangle()
                            .fill(.quaternary)
                            .aspectRatio(3.0 / 4.0, contentMode: .fit)
                        if let previewImage {
                            Image(uiImage: previewImage)
                                .resizable()
                                .interpolation(.none)
                                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                        } else {
                            Text(isProcessing ? "Processing…" : "Pick a photo to preview it in six colors.")
                                .foregroundStyle(.secondary)
                                .padding()
                        }
                    }
                    .frame(maxHeight: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(photoData == nil ? "Choose photo" : "Choose another photo", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .listRowBackground(Color.clear)
            }

            Section("Adjust") {
                Toggle("Dither", isOn: $settings.dither)
                Toggle("Rotate landscape photos", isOn: $settings.rotateLandscape)
                LabeledContent("Saturation") {
                    Slider(value: $settings.saturation, in: 0.5...2.5, step: 0.1)
                }
                LabeledContent("Contrast") {
                    Slider(value: $settings.contrast, in: 0.6...1.8, step: 0.05)
                }
                LabeledContent("Brightness") {
                    Slider(value: $settings.brightness, in: -0.3...0.3, step: 0.02)
                }
            }

            Section {
                Button {
                    Task { await send() }
                } label: {
                    Label(isSending ? "Sending…" : "Send to display", systemImage: "wave.3.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(preview == nil || isSending || isProcessing)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                if let status {
                    Text(status)
                }
            }
        }
        .navigationTitle("Send Photo")
        .onChange(of: pickerItem) { _, item in
            Task { await load(item) }
        }
        .onChange(of: settings) { _, _ in
            Task { await reprocess() }
        }
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            photoData = try await item.loadTransferable(type: Data.self)
            await reprocess()
        } catch {
            status = "Could not load photo: \(error.localizedDescription)"
        }
    }

    private func reprocess() async {
        guard let photoData else { return }
        isProcessing = true
        let settings = settings
        let processed = await Task.detached(priority: .userInitiated) {
            PhotoProcessor.process(imageData: photoData, settings: settings)
        }.value
        preview = processed
        previewImage = processed?.uiImage()
        isProcessing = false
        if processed == nil {
            status = "That file is not an image iOS can decode."
        }
    }

    private func send() async {
        guard let preview else { return }
        isSending = true
        defer { isSending = false }
        status = nil
        let chunks = Framebuffer.imageChunks(Framebuffer.pack(preview, layout: PanelLayout()))
        do {
            let report = try await EPaperTagSession.run(alertMessage: "Hold your iPhone on the e-ink display.") { tag, setMessage in
                try await EPaperUploader.send(chunks: chunks, layoutDescription: "photo", tag: tag, setMessage: setMessage)
            }
            status = "Sent. Upload \(String(format: "%.1f", report.uploadSeconds)) s, refresh \(String(format: "%.1f", report.refreshSeconds)) s, \(report.compressedBytes) bytes compressed."
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        SendPhotoView()
    }
}

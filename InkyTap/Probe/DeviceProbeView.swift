import SwiftUI

struct DeviceProbeView: View {
    enum Phase: Equatable {
        case idle
        case scanning
        case done(DeviceProbeResult)
        case failed(String)
    }

    @State private var phase: Phase = .idle
    @State private var copied = false

    var body: some View {
        List {
            Section {
                Button {
                    Task { await scan() }
                } label: {
                    Label(phase == .scanning ? "Scanning…" : "Scan e-ink display", systemImage: "wave.3.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(phase == .scanning)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                Text("Reads the display's configuration over NFC. Nothing is written and the panel is not refreshed.")
            }

            switch phase {
            case .idle, .scanning:
                EmptyView()
            case let .failed(message):
                Section("Error") {
                    Text(message).foregroundStyle(.red)
                }
            case let .done(result):
                resultSections(result)
            }
        }
        .navigationTitle("Device Probe")
    }

    @ViewBuilder
    private func resultSections(_ result: DeviceProbeResult) -> some View {
        Section("Tag") {
            row("UID", result.tagIdentifier.hexString)
            row("AID", result.selectedAID)
            row("Historical", result.historicalBytes?.hexString ?? "-")
        }

        if let info = result.deviceInfo {
            Section("Interpretation") {
                if let name = info.name { row("Name", name) }
                if let uid = info.uid { row("Device UID", String(format: "%08X", uid)) }
                ForEach(info.panelNotes, id: \.self) { note in
                    Text(note).font(.callout)
                }
                if let slots = info.imageCapacity { row("Image slots", "\(slots)") }
                if let kb = info.userDataKB { row("User data", "\(kb) KB") }
                if let battery = info.batteryPowered { row("Power", battery ? "Battery" : "NFC field") }
                if let lzo = info.compressionSupported { row("LZO upload", lzo ? "Yes" : "No") }
                if let fw = info.firmwareVersion { row("Firmware", String(format: "%02X", fw)) }
            }
            Section("Config TLVs") {
                ForEach(info.tlvs) { tlv in
                    row(String(format: "%02X (%d)", tlv.tag, tlv.value.count), tlv.value.hexString)
                }
            }
        }

        Section("Commands") {
            ForEach(result.records) { record in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(record.name)
                        Spacer()
                        Text(record.response.statusHex)
                            .foregroundStyle(record.response.isSuccess ? .green : .orange)
                    }
                    if !record.response.payload.isEmpty {
                        Text(record.response.payload.hexString)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        Section {
            Button {
                UIPasteboard.general.string = result.report
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy full report", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer()
            Text(value)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func scan() async {
        phase = .scanning
        copied = false
        do {
            phase = .done(try await DeviceProbe.run())
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

#Preview {
    NavigationStack {
        DeviceProbeView()
    }
}

import CoreBluetooth
import SwiftUI

/// Finds nearby printers and connects with one tap.
struct PrinterPickerSheet: View {
    @Environment(PrinterService.self) private var printer
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var connectingID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            List {
                if printer.bluetoothState != .poweredOn, printer.bluetoothState != .unknown {
                    Section {
                        Label(printer.bluetoothState.userMessage, systemImage: "antenna.radiowaves.left.and.right.slash")
                            .foregroundStyle(.orange)
                        if printer.bluetoothState == .unauthorized {
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                        }
                    }
                }

                Section {
                    if printers.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(printer.isScanning ? "Looking for printers…" : "No printers found yet")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                    ForEach(printers) { device in
                        row(for: device)
                    }
                } header: {
                    Text("Nearby printers")
                } footer: {
                    Text("Switch the printer on (hold the power button for about 3 seconds) and keep it close. A printer can only be connected to one phone at a time.")
                }

                if settings.showAllDevices {
                    Section("Other Bluetooth devices") {
                        if others.isEmpty {
                            Text("None found").foregroundStyle(.secondary)
                        }
                        ForEach(others) { device in
                            row(for: device)
                        }
                    }
                }

                Section {
                    Toggle("Show all Bluetooth devices", isOn: $settings.showAllDevices)
                } footer: {
                    Text("Turn this on if your printer has an unusual name and doesn't appear above.")
                }
            }
            .navigationTitle("Choose Printer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if printer.isScanning {
                        ProgressView()
                    } else {
                        Button("Scan") { printer.startScan() }
                    }
                }
            }
            .alert("Couldn't connect", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { printer.startScan() }
        .onDisappear { printer.stopScan() }
    }

    private var printers: [DiscoveredPrinter] {
        printer.discovered.filter(\.isLikelyPrinter)
    }

    private var others: [DiscoveredPrinter] {
        printer.discovered.filter { !$0.isLikelyPrinter }
    }

    private func row(for device: DiscoveredPrinter) -> some View {
        let isConnected = printer.isReady && printer.connectedID == device.id
        return Button {
            connect(device)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: device.isLikelyPrinter ? "printer.fill" : "dot.radiowaves.left.and.right")
                    .font(.title3)
                    .foregroundStyle(device.isLikelyPrinter ? Color.accentColor : Color.secondary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(device.profile?.name ?? (device.isLikelyPrinter ? "Compatible printer" : "Unknown device"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if connectingID == device.id {
                    ProgressView()
                } else if isConnected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    SignalBars(rssi: device.rssi)
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(connectingID != nil)
    }

    private func connect(_ device: DiscoveredPrinter) {
        connectingID = device.id
        Task {
            defer { connectingID = nil }
            do {
                try await printer.connect(to: device)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct SignalBars: View {
    let rssi: Int

    private var level: Int {
        switch rssi {
        case (-60)...: return 4
        case (-70)...: return 3
        case (-80)...: return 2
        default: return 1
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1)
                    .fill(bar <= level ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: 4, height: CGFloat(4 + bar * 3))
            }
        }
        .accessibilityLabel("Signal \(level) of 4")
    }
}

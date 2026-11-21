import CoreBluetooth
import SwiftUI

enum PrinterRoute: Hashable {
    case advanced, diagnostics
}

struct PrinterView: View {
    @Environment(PrinterService.self) private var printer
    @Environment(AppSettings.self) private var settings

    @State private var showPicker = false
    @State private var testJob: PrintJob?
    @State private var errorMessage: String?
    @State private var confirmForget = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            List {
                Section {
                    PrinterStatusCard(onChoose: { showPicker = true })
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } footer: {
                    if let refreshHint {
                        Text(refreshHint)
                    }
                }

                Section("Paper") {
                    HStack(spacing: 12) {
                        paperButton("Feed", systemImage: "arrow.up.doc") { try await printer.feedPaper() }
                        paperButton("Retract", systemImage: "arrow.down.doc") { try await printer.retractPaper() }
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    Button {
                        testJob = TestPage.make(printerName: printer.printerName ?? "Not connected",
                                                profile: printer.activeProfile, darkness: settings.darkness)
                    } label: {
                        Label("Print Test Page", systemImage: "checkmark.seal")
                    }
                }

                Section {
                    DarknessPicker(darkness: $settings.darkness)
                        .padding(.vertical, 4)
                    Picker(selection: $settings.feedAmount) {
                        ForEach(FeedAmount.allCases) { Text($0.title).tag($0) }
                    } label: {
                        Label("Paper after printing", systemImage: "arrow.up.to.line")
                    }
                } header: {
                    Text("Print quality")
                } footer: {
                    Text("Use a higher darkness for sticker paper or faint prints. “Paper after printing” controls how far the paper advances so the print clears the tear bar.")
                }

                Section("Behaviour") {
                    Toggle(isOn: $settings.autoConnect) {
                        Label("Connect automatically", systemImage: "bolt.horizontal.circle")
                    }
                    Toggle(isOn: $settings.keepScreenAwake) {
                        Label("Keep screen on while printing", systemImage: "sun.max")
                    }
                }

                Section {
                    NavigationLink(value: PrinterRoute.advanced) {
                        Label("Advanced", systemImage: "slider.horizontal.3")
                    }
                    NavigationLink(value: PrinterRoute.diagnostics) {
                        Label("Diagnostics", systemImage: "stethoscope")
                    }
                    if printer.hasSavedPrinter {
                        Button(role: .destructive) {
                            confirmForget = true
                        } label: {
                            Label("Forget This Printer", systemImage: "trash")
                        }
                    }
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.appVersion)
                    LabeledContent("Works offline", value: "Yes")
                } header: {
                    Text("About")
                } footer: {
                    Text("PocketPrint talks directly to your printer over Bluetooth. No account, no cloud and no tracking — everything stays on this iPhone.")
                }
            }
            .refreshable {
                await printer.refreshStatus()
            }
            // Registered outside `refreshable`, so pushed screens don't inherit the pull-to-refresh.
            .navigationDestination(for: PrinterRoute.self) { route in
                switch route {
                case .advanced: AdvancedPrinterSettingsView()
                case .diagnostics: DiagnosticsView()
                }
            }
            .navigationTitle("Printer")
            .sheet(isPresented: $showPicker) { PrinterPickerSheet() }
            .sheet(item: $testJob) { PrintSheet(job: $0) }
            .alert("Printer", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .confirmationDialog("Forget \(printer.printerName ?? "printer")?", isPresented: $confirmForget, titleVisibility: .visible) {
                Button("Forget Printer", role: .destructive) { printer.forgetPrinter() }
            } message: {
                Text("You can find and connect it again at any time.")
            }
        }
    }

    private var refreshHint: String? {
        guard printer.bluetoothState == .poweredOn else { return nil }
        switch printer.phase {
        case .ready:
            if let checked = printer.lastStatusUpdate {
                return "Checked at \(checked.formatted(date: .omitted, time: .shortened)). Pull down to check battery and paper again."
            }
            return "Pull down to check battery and paper."
        case .connecting:
            return nil
        case .disconnected:
            return printer.hasSavedPrinter ? "Pull down to reconnect." : nil
        }
    }

    private func paperButton(_ title: String, systemImage: String, action: @escaping () async throws -> Void) -> some View {
        Button {
            Task {
                do { try await action() } catch { errorMessage = error.localizedDescription }
            }
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .secondaryActionStyle()
        .disabled(printer.isPrinting)
    }
}

/// Big connection card shown on the Printer tab and (compact) on the Create screen.
struct PrinterStatusCard: View {
    @Environment(PrinterService.self) private var printer
    var compact = false
    var onChoose: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.accentColor.gradient)
                Image(systemName: "printer.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            .frame(width: compact ? 46 : 56, height: compact ? 46 : 56)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                    if let percent = printer.batteryPercent {
                        BatteryBadge(percent: percent, isLow: printer.statusFlags.contains(.lowBattery))
                    }
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(subtitleColor)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            actionButton
        }
        .padding(compact ? 12 : 16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var title: String {
        printer.printerName ?? "No printer yet"
    }

    private var subtitle: String {
        if printer.bluetoothState != .poweredOn && printer.bluetoothState != .unknown {
            return printer.bluetoothState.userMessage
        }
        if let warning = printer.statusFlags.messages.first, printer.isReady { return warning }
        switch printer.phase {
        case .ready: return "Connected · \(printer.activeProfile.name)"
        case .connecting: return "Connecting…"
        case .disconnected:
            return printer.hasSavedPrinter ? "Not connected — turn the printer on" : "Tap Connect to find your printer"
        }
    }

    private var subtitleColor: Color {
        if printer.bluetoothState != .poweredOn && printer.bluetoothState != .unknown { return .orange }
        if printer.isReady && !printer.statusFlags.isEmpty { return .orange }
        return printer.isReady ? .green : .secondary
    }

    @ViewBuilder
    private var actionButton: some View {
        switch printer.phase {
        case .ready:
            Menu {
                Button("Change Printer", systemImage: "arrow.left.arrow.right") { onChoose() }
                Button("Disconnect", systemImage: "xmark.circle") { printer.disconnect() }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
            }
            .accessibilityLabel("Printer options")
        case .connecting:
            ProgressView()
        case .disconnected:
            Button(printer.hasSavedPrinter ? "Connect" : "Find") {
                if printer.hasSavedPrinter {
                    Task {
                        do { try await printer.ensureConnected() } catch { onChoose() }
                    }
                } else {
                    onChoose()
                }
            }
            .prominentActionStyle()
            .controlSize(.small)
        }
    }
}

struct AdvancedPrinterSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PrinterService.self) private var printer

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Model", selection: $settings.profileOverrideID) {
                    Text("Detect automatically").tag(String?.none)
                    ForEach(PrinterCatalog.allProfiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
                LabeledContent("Detected", value: printer.detectedProfile?.name ?? "Unknown — using P1 settings")
            } header: {
                Text("Printer model")
            } footer: {
                Text("The model sets speed and heat. It's detected from the Bluetooth name, e.g. “P1-28F2”.")
            }

            Section {
                Picker("Transfer speed", selection: $settings.transferSpeed) {
                    ForEach(TransferSpeed.allCases) { Text($0.title).tag($0) }
                }
                Text(settings.transferSpeed.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Picker("Packet size", selection: $settings.maxPacketSize) {
                    ForEach([20, 100, 180, 240, 512], id: \.self) { Text("\($0) bytes").tag($0) }
                }
            } header: {
                Text("Bluetooth")
            }

            Section {
                Picker("Heat", selection: $settings.heat) {
                    ForEach(HeatLevel.allCases) { Text($0.title).tag($0) }
                }
                Picker("Compression", selection: $settings.compressionChoice) {
                    Text("Automatic").tag(OverrideChoice.automatic)
                    Text("On").tag(OverrideChoice.on)
                    Text("Off").tag(OverrideChoice.off)
                }
                Picker("Protocol", selection: $settings.dialectChoice) {
                    ForEach(DialectChoice.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Troubleshooting")
            } footer: {
                Text("Only change these if prints don't come out right. If nothing prints at all, try the other protocol. If prints are garbled, turn compression off or pick Reliable transfer speed.")
            }

            Section {
                Button("Restore Defaults", role: .destructive) { settings.resetAdvanced() }
            }
        }
        .navigationTitle("Advanced")
    }
}

struct DiagnosticsView: View {
    @Environment(PrinterService.self) private var printer

    var body: some View {
        List {
            Section("Connection") {
                LabeledContent("Bluetooth", value: printer.bluetoothState.label.capitalized)
                LabeledContent("Printer", value: printer.printerName ?? "—")
                LabeledContent("State", value: stateText)
                if let link = printer.link {
                    LabeledContent("Service", value: link.service)
                    LabeledContent("Write", value: "\(link.writeCharacteristic) (\(link.writeWithoutResponse ? "no response" : "with response"))")
                    LabeledContent("Notify", value: link.notifyCharacteristic ?? "—")
                    LabeledContent("Max packet", value: "\(link.maximumWriteLength) bytes")
                }
                if !printer.lastStatusPayload.isEmpty {
                    LabeledContent("Last status", value: Data(printer.lastStatusPayload).hexString)
                }
                LabeledContent("Battery", value: batteryText)
            }
            Section {
                if printer.logEntries.isEmpty {
                    Text("No activity yet").foregroundStyle(.secondary)
                }
                ForEach(printer.logEntries.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.date, format: .dateTime.hour().minute().second())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(entry.message)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            } header: {
                Text("Activity")
            }
        }
        .refreshable {
            await printer.refreshStatus()
        }
        .navigationTitle("Diagnostics")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: printer.logText.isEmpty ? "No activity" : printer.logText) {
                    Image(systemName: "square.and.arrow.up")
                }
                Button {
                    printer.clearLog()
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Clear log")
            }
        }
    }

    private var stateText: String {
        switch printer.phase {
        case .ready: return "Ready"
        case .connecting: return "Connecting"
        case .disconnected: return "Not connected"
        }
    }

    private var batteryText: String {
        if let percent = printer.batteryPercent, let gauge = printer.batteryGauge {
            return "About \(percent)% (gauge \(String(format: "0x%02X", gauge)))"
        }
        if !printer.isReady { return "—" }
        return printer.reportsBatteryLevel ? "Waiting for printer…" : "Not reported by this model"
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

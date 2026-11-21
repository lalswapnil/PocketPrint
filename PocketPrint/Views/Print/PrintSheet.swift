import SwiftUI

/// The single, consistent print step used by every feature.
struct PrintSheet: View {
    let job: PrintJob

    @Environment(PrinterService.self) private var printer
    @Environment(AppSettings.self) private var settings
    @Environment(HistoryStore.self) private var history
    @Environment(\.dismiss) private var dismiss

    @State private var copies = 1
    @State private var task: Task<Void, Never>?
    @State private var outcome: Outcome?
    @State private var showPrinterPicker = false
    @State private var printAfterConnecting = false
    @State private var preview: RasterPreview?

    private enum Outcome: Equatable {
        case printed
        case failed(String)
    }

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summary
                    printerRow
                    if !printer.statusFlags.messages.isEmpty {
                        Label(printer.statusFlags.messages.joined(separator: " · "), systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    DarknessPicker(darkness: $settings.darkness)
                    Stepper(value: $copies, in: 1...20) {
                        Label(copies == 1 ? "1 copy" : "\(copies) copies", systemImage: "square.on.square")
                            .font(.subheadline)
                    }
                    if case .failed(let message) = outcome {
                        Label(message, systemImage: "exclamationmark.octagon.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) { actionArea }
            .navigationTitle("Print")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .disabled(printer.isPrinting)
                }
            }
        }
        .presentationDetents([.height(560), .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(printer.isPrinting)
        .sensoryFeedback(.success, trigger: outcome) { _, new in new == .printed }
        .sheet(isPresented: $showPrinterPicker, onDismiss: {
            if printAfterConnecting, printer.isReady { startPrinting() }
            printAfterConnecting = false
        }) {
            PrinterPickerSheet()
        }
        .task {
            preview = RasterPreview(job.bitmap.height > 1200 ? job.bitmap.cropped(x: 0, y: 0, width: job.bitmap.width, height: 1200) : job.bitmap)
        }
        .onDisappear { task?.cancel() }
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 16) {
            Group {
                if let preview {
                    Image(uiImage: preview.image)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Color.white
                }
            }
            .frame(width: 76, height: 96, alignment: .top)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(.separator)))

            VStack(alignment: .leading, spacing: 6) {
                Text(job.title)
                    .font(.headline)
                    .lineLimit(2)
                Label("48 mm × \(PaperLength.describe(dots: job.bitmap.height))", systemImage: "ruler")
                Label(job.isTextMode ? "Crisp text mode" : "Photo mode", systemImage: job.isTextMode ? "textformat" : "photo")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var printerRow: some View {
        HStack {
            Image(systemName: "printer.fill")
                .foregroundStyle(Color.accentColor)
            PrinterStatusBadge()
            Spacer()
            if let percent = printer.batteryPercent {
                BatteryBadge(percent: percent, isLow: printer.statusFlags.contains(.lowBattery))
            }
            Button(printer.isReady ? "Change" : "Choose") {
                showPrinterPicker = true
            }
            .font(.subheadline.weight(.semibold))
            .disabled(printer.isPrinting)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }

    @ViewBuilder
    private var actionArea: some View {
        VStack(spacing: 10) {
            if let progress = printer.progress {
                VStack(spacing: 8) {
                    ProgressView(value: progress.stage == .connecting ? nil : progress.fraction)
                    HStack {
                        Text(stageText(progress))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel", role: .cancel) { task?.cancel() }
                            .font(.footnote.weight(.semibold))
                    }
                }
            } else if outcome == .printed {
                Label("Printed", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, minHeight: 50)
            } else {
                Button {
                    startPrinting()
                } label: {
                    Label(printLabel, systemImage: "printer.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .prominentActionStyle()
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private var printLabel: String {
        if printer.isReady { return copies > 1 ? "Print \(copies) Copies" : "Print" }
        return printer.hasSavedPrinter ? "Connect & Print" : "Choose Printer"
    }

    private func stageText(_ progress: PrintProgress) -> String {
        switch progress.stage {
        case .connecting: return "Connecting to \(printer.printerName ?? "printer")…"
        case .sending:
            let percent = Int((progress.fraction * 100).rounded())
            return progress.copies > 1 ? "Printing copy \(progress.copy) of \(progress.copies) · \(percent)%" : "Printing · \(percent)%"
        case .waitingForPrinter: return "Waiting for the printer to catch up…"
        case .finishing: return "Finishing…"
        }
    }

    private func startPrinting() {
        guard task == nil else { return }
        if !printer.isReady, !printer.hasSavedPrinter {
            printAfterConnecting = true
            showPrinterPicker = true
            return
        }
        outcome = nil
        task = Task {
            defer { task = nil }
            do {
                try await printer.print(job, copies: copies, darkness: settings.darkness)
                history.add(job)
                outcome = .printed
                try? await Task.sleep(for: .seconds(1.2))
                if !Task.isCancelled { dismiss() }
            } catch is CancellationError {
                outcome = nil
            } catch PrinterError.noPrinterSelected {
                printAfterConnecting = true
                showPrinterPicker = true
            } catch {
                outcome = Task.isCancelled ? nil : .failed(error.localizedDescription)
            }
        }
    }
}

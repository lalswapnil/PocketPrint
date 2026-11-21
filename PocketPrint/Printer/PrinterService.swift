import CoreBluetooth
import Observation
import UIKit

struct DiscoveredPrinter: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rssi: Int
    var profile: PrinterProfile?
    /// Matches a known printer name or advertises a printer service.
    var isLikelyPrinter: Bool
}

enum ConnectionPhase: Equatable {
    case disconnected, connecting, ready
}

struct PrintProgress: Equatable {
    enum Stage: Equatable { case connecting, sending, waitingForPrinter, finishing }
    var stage: Stage = .connecting
    var fraction: Double = 0
    var copy = 1
    var copies = 1
}

struct LinkDetails: Equatable {
    var service: String
    var writeCharacteristic: String
    var notifyCharacteristic: String?
    var writeWithoutResponse: Bool
    var maximumWriteLength: Int
}

struct LogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let message: String
}

enum PrinterError: LocalizedError, Equatable {
    case bluetoothUnavailable(String)
    case noPrinterSelected
    case printerNotFound
    case connectionFailed(String)
    case connectionTimedOut
    case incompatibleDevice
    case disconnected
    case printerStalled
    case busy

    var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable(let message): return message
        case .noPrinterSelected: return "Choose a printer first."
        case .printerNotFound: return "The printer wasn't found. Turn it on and keep it close to your phone."
        case .connectionFailed(let reason): return "Couldn't connect to the printer. \(reason)"
        case .connectionTimedOut: return "The printer didn't respond. Make sure it's switched on, charged and not connected to another phone."
        case .incompatibleDevice: return "This Bluetooth device doesn't look like a supported printer."
        case .disconnected: return "The printer disconnected."
        case .printerStalled: return "The printer stopped accepting data. Check the paper and lid, then try again."
        case .busy: return "The printer is busy with another job."
        }
    }
}

@MainActor
@Observable
final class PrinterService {
    private(set) var bluetoothState: CBManagerState = .unknown
    private(set) var isScanning = false
    private(set) var discovered: [DiscoveredPrinter] = []
    private(set) var phase: ConnectionPhase = .disconnected
    private(set) var connectedID: UUID?
    private(set) var connectedName: String?
    private(set) var link: LinkDetails?
    private(set) var progress: PrintProgress?
    private(set) var statusFlags: PrinterStatusFlags = []
    private(set) var lastStatusPayload: [UInt8] = []
    /// Approximate charge (six steps) while connected, for printers that report it.
    private(set) var batteryPercent: Int?
    private(set) var batteryGauge: UInt8?
    /// When the printer last answered a status request.
    private(set) var lastStatusUpdate: Date?
    private(set) var logEntries: [LogEntry] = []
    private(set) var lastConnectionError: String?

    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private let proxy = BluetoothProxy()
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var writeCharacteristic: CBCharacteristic?
    @ObservationIgnored private var notifyCharacteristic: CBCharacteristic?
    @ObservationIgnored private var writeType: CBCharacteristicWriteType = .withoutResponse
    @ObservationIgnored private var servicesPendingDiscovery = 0
    @ObservationIgnored private var decoder = TinyStreamDecoder()
    @ObservationIgnored private var flowPaused = false
    @ObservationIgnored private var awaitingWriteResponse = false
    @ObservationIgnored private var writeFailure: String?
    @ObservationIgnored private var connectContinuation: CheckedContinuation<Void, Error>?
    @ObservationIgnored private var connectTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var scanStopTask: Task<Void, Never>?
    @ObservationIgnored private var pendingScan = false
    @ObservationIgnored private var didAttemptAutoConnect = false
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored private var statusPollTask: Task<Void, Never>?

    var isReady: Bool { phase == .ready }
    var isPrinting: Bool { progress != nil }
    var printerName: String? { connectedName ?? settings.lastPrinterName }
    var hasSavedPrinter: Bool { settings.lastPrinterID != nil }

    /// Manual override, else detected from the Bluetooth name, else the P1 defaults.
    var activeProfile: PrinterProfile {
        if let id = settings.profileOverrideID, let profile = PrinterCatalog.profile(id: id) { return profile }
        return PrinterCatalog.profile(forDeviceName: printerName) ?? PrinterCatalog.pocketPrinter
    }

    var detectedProfile: PrinterProfile? {
        PrinterCatalog.profile(forDeviceName: printerName)
    }

    /// Battery is only decoded for a known model that has a gauge, never for the P1 fallback
    /// used with unrecognised printers.
    var reportsBatteryLevel: Bool {
        let known = settings.profileOverrideID.flatMap(PrinterCatalog.profile(id:)) ?? detectedProfile
        return known?.batteryGauge ?? false
    }

    init(settings: AppSettings) {
        self.settings = settings
        proxy.owner = self
        central = CBCentralManager(delegate: proxy, queue: .main,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }

    // MARK: - Scanning

    func startScan() {
        guard bluetoothState == .poweredOn else {
            pendingScan = true
            return
        }
        if !isScanning {
            // Start fresh so switched-off printers disappear; keep the connected one visible.
            discovered.removeAll { $0.id != connectedID || phase != .ready }
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            isScanning = true
            appendLog("Scanning for printers")
        }
        scanStopTask?.cancel()
        scanStopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled else { return }
            self?.stopScan()
        }
    }

    func stopScan() {
        pendingScan = false
        scanStopTask?.cancel()
        scanStopTask = nil
        guard isScanning else { return }
        if bluetoothState == .poweredOn { central.stopScan() }
        isScanning = false
    }

    // MARK: - Connection

    func connect(to printer: DiscoveredPrinter) async throws {
        try await connect(id: printer.id, name: printer.name)
    }

    func connect(id: UUID, name: String? = nil) async throws {
        try await waitForBluetooth()
        if phase == .ready, connectedID == id { return }
        if phase == .connecting {
            if connectedID == id {
                try await waitForConnectionAttempt()
                return
            }
            failConnection(.connectionFailed("Cancelled."))
        }
        if phase == .ready { disconnect() }

        let target = peripherals[id] ?? central.retrievePeripherals(withIdentifiers: [id]).first
        guard let target else { throw PrinterError.printerNotFound }
        stopScan()
        peripheral = target
        target.delegate = proxy
        connectedID = id
        connectedName = name ?? target.name ?? settings.lastPrinterName
        phase = .connecting
        lastConnectionError = nil
        appendLog("Connecting to \(connectedName ?? "printer")")
        central.connect(target, options: nil)

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connectContinuation = continuation
                connectTimeoutTask?.cancel()
                connectTimeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(15))
                    guard !Task.isCancelled, let self, self.phase == .connecting else { return }
                    self.failConnection(.connectionTimedOut)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.phase == .connecting else { return }
                self.failConnection(.connectionFailed("Cancelled."))
            }
        }
    }

    /// Connects to the last used printer if needed. Throws `.noPrinterSelected` if there is none.
    func ensureConnected() async throws {
        if phase == .ready { return }
        try await waitForBluetooth()
        if phase == .connecting {
            try await waitForConnectionAttempt()
            return
        }
        guard let id = settings.lastPrinterID else { throw PrinterError.noPrinterSelected }
        try await connect(id: id, name: settings.lastPrinterName)
    }

    func disconnect() {
        guard let target = peripheral else { return }
        appendLog("Disconnecting")
        central.cancelPeripheralConnection(target)
        resetConnection()
    }

    func forgetPrinter() {
        disconnect()
        settings.lastPrinterID = nil
        settings.lastPrinterName = nil
        connectedName = nil
        connectedID = nil
    }

    private func waitForBluetooth() async throws {
        var waited = 0
        while bluetoothState == .unknown || bluetoothState == .resetting, waited < 30 {
            try await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        guard bluetoothState == .poweredOn else {
            throw PrinterError.bluetoothUnavailable(bluetoothState.userMessage)
        }
    }

    private func waitForConnectionAttempt() async throws {
        while phase == .connecting {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard phase == .ready else {
            throw PrinterError.connectionFailed(lastConnectionError ?? "")
        }
    }

    private func completeConnection() {
        connectTimeoutTask?.cancel()
        phase = .ready
        if let id = connectedID {
            settings.lastPrinterID = id
            settings.lastPrinterName = connectedName
        }
        appendLog("Ready to print")
        connectContinuation?.resume()
        connectContinuation = nil
    }

    private func failConnection(_ error: PrinterError) {
        connectTimeoutTask?.cancel()
        if let target = peripheral { central.cancelPeripheralConnection(target) }
        lastConnectionError = error.errorDescription
        appendLog("Connection failed: \(error.errorDescription ?? "")")
        resetConnection()
        connectContinuation?.resume(throwing: error)
        connectContinuation = nil
    }

    private func resetConnection() {
        phase = .disconnected
        peripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        link = nil
        flowPaused = false
        awaitingWriteResponse = false
        statusFlags = []
        batteryPercent = nil
        batteryGauge = nil
        lastStatusUpdate = nil
        statusPollTask?.cancel()
        statusPollTask = nil
        decoder = TinyStreamDecoder()
    }

    // MARK: - Printing

    func print(_ job: PrintJob, copies: Int, darkness: Int) async throws {
        guard progress == nil else { throw PrinterError.busy }
        let total = max(1, copies)
        progress = PrintProgress(copies: total)
        defer {
            progress = nil
            endBackgroundWork()
        }
        try await ensureConnected()
        beginBackgroundWork()

        let options = jobOptions(isTextMode: job.isTextMode, darkness: darkness)
        let bitmap = job.bitmap
        let data = await Task.detached(priority: .userInitiated) {
            TinyProtocol.encodeJob(bitmap, options: options)
        }.value
        appendLog("Printing “\(job.title)”: \(bitmap.height) rows, \(data.count) bytes, "
                  + "\(options.isTextMode ? "text" : "image") mode, density \(options.blackening), energy \(options.energy)")
        progress?.stage = .sending
        do {
            for copy in 1...total {
                progress?.copy = copy
                try await send(data) { [weak self] fraction in
                    self?.progress?.fraction = (Double(copy - 1) + fraction) / Double(total)
                }
            }
        } catch is CancellationError {
            // Feed out what has already printed so it can be torn off.
            sendImmediately(Data(TinyProtocol.feedPaper(dots: 48, dialect: options.dialect)))
            appendLog("Printing cancelled")
            throw CancellationError()
        }
        progress?.stage = .finishing
        appendLog("Job sent")
    }

    func feedPaper() async throws {
        let dialect = settings.dialectChoice.dialect ?? activeProfile.dialect
        try await sendCommand(TinyProtocol.feedPaper(dots: 80, dialect: dialect))
    }

    func retractPaper() async throws {
        let dialect = settings.dialectChoice.dialect ?? activeProfile.dialect
        try await sendCommand(TinyProtocol.retractPaper(dots: 48, dialect: dialect))
    }

    func requestStatus() {
        guard phase == .ready, progress == nil else { return }
        let dialect = settings.dialectChoice.dialect ?? activeProfile.dialect
        sendImmediately(Data(TinyProtocol.deviceState(dialect: dialect)))
    }

    /// Pull to refresh: reconnects to the saved printer if needed, then waits briefly
    /// for a fresh status reply (battery, paper, lid, temperature).
    func refreshStatus() async {
        guard progress == nil, bluetoothState == .poweredOn else { return }
        if phase != .ready {
            guard hasSavedPrinter || phase == .connecting else { return }
            do {
                try await ensureConnected()
            } catch {
                return
            }
        }
        let previous = lastStatusUpdate
        requestStatus()
        let deadline = ContinuousClock.now + .seconds(3)
        while lastStatusUpdate == previous, phase == .ready, ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    func jobOptions(isTextMode: Bool, darkness: Int) -> TinyJobOptions {
        let profile = activeProfile
        var options = TinyJobOptions()
        options.dialect = settings.dialectChoice.dialect ?? profile.dialect
        options.isTextMode = isTextMode
        options.speed = isTextMode ? profile.textSpeed : profile.imageSpeed
        let baseEnergy = Double(isTextMode ? profile.textEnergy : profile.imageEnergy)
        options.energy = baseEnergy > 0 ? UInt16(clamping: Int((baseEnergy * settings.heat.multiplier).rounded())) : 0
        options.blackening = min(5, max(1, darkness))
        switch settings.compressionChoice {
        case .automatic: options.compress = profile.compress
        case .on: options.compress = true
        case .off: options.compress = false
        }
        options.dpi = profile.dpi
        options.postPrintFeedCount = settings.feedAmount.steps
        return options
    }

    private func sendCommand(_ bytes: [UInt8]) async throws {
        guard progress == nil else { throw PrinterError.busy }
        try await ensureConnected()
        try await send(Data(bytes))
    }

    /// Streams data in packets, honouring Bluetooth back-pressure, the printer's
    /// pause/resume notifications and the configured average data rate.
    private func send(_ data: Data, progress onProgress: ((Double) -> Void)? = nil) async throws {
        guard phase == .ready, let target = peripheral else { throw PrinterError.disconnected }
        // The write-without-response limit reflects the negotiated MTU; using it for both write
        // types avoids long (prepared) writes, which many small printers don't support.
        let maxLength = max(20, target.maximumWriteValueLength(for: .withoutResponse))
        let chunkSize = max(20, min(maxLength, settings.maxPacketSize))
        let rate = settings.transferSpeed.bytesPerSecond
        var offset = 0
        var reported = 0.0
        while offset < data.count {
            try Task.checkCancellation()
            try await waitUntilWritable()
            guard let target = peripheral, let characteristic = writeCharacteristic else { throw PrinterError.disconnected }
            let end = min(data.count, offset + chunkSize)
            let chunk = data.subdata(in: offset..<end)
            if writeType == .withResponse {
                awaitingWriteResponse = true
                target.writeValue(chunk, for: characteristic, type: .withResponse)
                try await waitForWriteResponse()
            } else {
                target.writeValue(chunk, for: characteristic, type: .withoutResponse)
            }
            offset = end
            let fraction = Double(offset) / Double(data.count)
            if fraction - reported >= 0.005 || offset == data.count {
                reported = fraction
                onProgress?(fraction)
            }
            try await Task.sleep(for: .seconds(Double(chunk.count) / rate))
        }
    }

    private func waitUntilWritable() async throws {
        let start = ContinuousClock.now
        var pausedSince: ContinuousClock.Instant?
        while true {
            guard phase == .ready, let target = peripheral else { throw PrinterError.disconnected }
            let linkReady = writeType == .withResponse || target.canSendWriteWithoutResponse
            if !flowPaused, linkReady {
                if progress?.stage == .waitingForPrinter { progress?.stage = .sending }
                return
            }
            if flowPaused {
                if pausedSince == nil {
                    pausedSince = .now
                    if progress != nil { progress?.stage = .waitingForPrinter }
                }
                if let since = pausedSince, ContinuousClock.now - since > .seconds(60) { throw PrinterError.printerStalled }
            } else if ContinuousClock.now - start > .seconds(20) {
                throw PrinterError.printerStalled
            }
            try await Task.sleep(for: .milliseconds(4))
        }
    }

    private func waitForWriteResponse() async throws {
        let start = ContinuousClock.now
        while awaitingWriteResponse {
            guard phase == .ready else { throw PrinterError.disconnected }
            if ContinuousClock.now - start > .seconds(5) { throw PrinterError.printerStalled }
            try await Task.sleep(for: .milliseconds(2))
        }
        if let failure = writeFailure {
            writeFailure = nil
            throw PrinterError.connectionFailed(failure)
        }
    }

    /// Fire-and-forget write for small control commands.
    private func sendImmediately(_ data: Data) {
        guard phase == .ready, let target = peripheral, let characteristic = writeCharacteristic else { return }
        target.writeValue(data, for: characteristic, type: writeType)
    }

    private func beginBackgroundWork() {
        if settings.keepScreenAwake { UIApplication.shared.isIdleTimerDisabled = true }
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Printing") { [weak self] in
            MainActor.assumeIsolated { self?.endBackgroundWork() }
        }
    }

    private func endBackgroundWork() {
        UIApplication.shared.isIdleTimerDisabled = false
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: - Diagnostics

    func clearLog() {
        logEntries.removeAll()
    }

    var logText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return logEntries.map { "\(formatter.string(from: $0.date))  \($0.message)" }.joined(separator: "\n")
    }

    private func appendLog(_ message: String) {
        logEntries.append(LogEntry(date: Date(), message: message))
        if logEntries.count > 400 { logEntries.removeFirst(logEntries.count - 400) }
    }

    // MARK: - Delegate events (always delivered on the main queue)

    fileprivate func handleStateUpdate(_ state: CBManagerState) {
        bluetoothState = state
        appendLog("Bluetooth: \(state.label)")
        if state == .poweredOn {
            if pendingScan {
                pendingScan = false
                startScan()
            }
            if !didAttemptAutoConnect, settings.autoConnect, let id = settings.lastPrinterID, phase == .disconnected {
                didAttemptAutoConnect = true
                Task { try? await self.connect(id: id, name: self.settings.lastPrinterName) }
            }
        } else {
            isScanning = false
            if phase != .disconnected {
                if connectContinuation != nil {
                    failConnection(.bluetoothUnavailable(state.userMessage))
                } else {
                    resetConnection()
                }
            }
        }
    }

    fileprivate func handleDiscovery(_ found: CBPeripheral, advertisement: [String: Any], rssi: NSNumber) {
        let name = (advertisement[CBAdvertisementDataLocalNameKey] as? String) ?? found.name
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let services = (advertisement[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let profile = PrinterCatalog.profile(forDeviceName: name)
        let likely = profile != nil || !PrinterCatalog.advertisedServiceHints.isDisjoint(with: services)
        peripherals[found.identifier] = found
        let signal = rssi.intValue == 127 ? -100 : rssi.intValue
        if let index = discovered.firstIndex(where: { $0.id == found.identifier }) {
            if abs(discovered[index].rssi - signal) >= 4 || discovered[index].name != name {
                discovered[index].rssi = signal
                discovered[index].name = name
            }
        } else {
            discovered.append(DiscoveredPrinter(id: found.identifier, name: name, rssi: signal,
                                                profile: profile, isLikelyPrinter: likely))
            discovered.sort { lhs, rhs in
                if lhs.isLikelyPrinter != rhs.isLikelyPrinter { return lhs.isLikelyPrinter }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            if likely { appendLog("Found \(name)") }
        }
    }

    fileprivate func handleConnected(_ connected: CBPeripheral) {
        guard connected == peripheral else { return }
        appendLog("Connected, discovering services")
        connected.discoverServices(nil)
    }

    fileprivate func handleFailedToConnect(_ failed: CBPeripheral, error: Error?) {
        guard failed == peripheral else { return }
        failConnection(.connectionFailed(error?.localizedDescription ?? ""))
    }

    fileprivate func handleDisconnected(_ lost: CBPeripheral, error: Error?) {
        guard lost == peripheral || peripheral == nil else { return }
        appendLog("Disconnected\(error.map { ": \($0.localizedDescription)" } ?? "")")
        if connectContinuation != nil {
            failConnection(.connectionFailed(error?.localizedDescription ?? "The printer closed the connection."))
        } else if lost == peripheral {
            resetConnection()
        }
    }

    fileprivate func handleServicesDiscovered(_ target: CBPeripheral, error: Error?) {
        guard target == peripheral else { return }
        if let error {
            failConnection(.connectionFailed(error.localizedDescription))
            return
        }
        let services = target.services ?? []
        appendLog("Services: \(services.map(\.uuid.uuidString).joined(separator: ", "))")
        guard !services.isEmpty else {
            failConnection(.incompatibleDevice)
            return
        }
        servicesPendingDiscovery = services.count
        for service in services {
            target.discoverCharacteristics(nil, for: service)
        }
    }

    fileprivate func handleCharacteristicsDiscovered(_ target: CBPeripheral, service: CBService, error: Error?) {
        guard target == peripheral, phase == .connecting else { return }
        if let error { appendLog("Characteristics of \(service.uuid.uuidString) failed: \(error.localizedDescription)") }
        servicesPendingDiscovery -= 1
        guard servicesPendingDiscovery <= 0 else { return }
        selectCharacteristics(on: target)
    }

    private func selectCharacteristics(on target: CBPeripheral) {
        let services = target.services ?? []
        var choice: (service: CBService, write: CBCharacteristic, notify: CBCharacteristic?)?
        for layout in PrinterCatalog.gattLayouts {
            guard let service = services.first(where: { $0.uuid == layout.service }),
                  let write = service.characteristics?.first(where: { $0.uuid == layout.write && $0.canWrite }) else { continue }
            let preferredNotify = layout.notify.flatMap { uuid in service.characteristics?.first { $0.uuid == uuid && $0.canNotify } }
            choice = (service, write, preferredNotify ?? service.characteristics?.first { $0.canNotify })
            break
        }
        if choice == nil {
            let ignored: Set<CBUUID> = [CBUUID(string: "1800"), CBUUID(string: "1801"), CBUUID(string: "180A"), CBUUID(string: "180F")]
            for service in services where !ignored.contains(service.uuid) {
                let writable = service.characteristics?.filter(\.canWrite) ?? []
                guard let write = writable.first(where: { $0.properties.contains(.writeWithoutResponse) }) ?? writable.first else { continue }
                choice = (service, write, service.characteristics?.first { $0.canNotify })
                break
            }
        }
        guard let choice else {
            failConnection(.incompatibleDevice)
            return
        }
        writeCharacteristic = choice.write
        notifyCharacteristic = choice.notify
        writeType = choice.write.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        if let notify = choice.notify {
            target.setNotifyValue(true, for: notify)
        }
        link = LinkDetails(service: choice.service.uuid.uuidString,
                           writeCharacteristic: choice.write.uuid.uuidString,
                           notifyCharacteristic: choice.notify?.uuid.uuidString,
                           writeWithoutResponse: writeType == .withoutResponse,
                           maximumWriteLength: target.maximumWriteValueLength(for: .withoutResponse))
        appendLog("Using service \(choice.service.uuid.uuidString), write \(choice.write.uuid.uuidString)"
                  + (choice.notify.map { ", notify \($0.uuid.uuidString)" } ?? "")
                  + ", packet \(target.maximumWriteValueLength(for: .withoutResponse)) bytes")
        completeConnection()
    }

    fileprivate func handleNotificationState(_ characteristic: CBCharacteristic, error: Error?) {
        if let error {
            appendLog("Notifications unavailable: \(error.localizedDescription)")
        } else if characteristic.isNotifying {
            appendLog("Listening for printer status")
            requestStatus()
            startStatusPolling()
        }
    }

    fileprivate func handleValue(_ characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value, !data.isEmpty else { return }
        handleNotification(data)
    }

    /// Processes bytes received on the notify characteristic.
    func handleNotification(_ data: Data) {
        let packets = decoder.feed(data)
        if packets.isEmpty { appendLog("RX \(data.hexString)") }
        for packet in packets {
            switch packet.command {
            case TinyCommand.flowControl where packet.payload == [0x10]:
                if !flowPaused { appendLog("Printer buffer full, pausing") }
                flowPaused = true
            case TinyCommand.flowControl where packet.payload == [0x00]:
                if flowPaused { appendLog("Printer ready, resuming") }
                flowPaused = false
            case TinyCommand.deviceState:
                applyDeviceState(packet.payload)
            default:
                appendLog("RX \(String(format: "%02X", packet.command)) \(Data(packet.payload).hexString)")
            }
        }
    }

    private func applyDeviceState(_ payload: [UInt8]) {
        let state = DeviceState(payload: payload, hasBatteryGauge: reportsBatteryLevel)
        lastStatusPayload = payload
        lastStatusUpdate = Date()
        statusFlags = state.flags
        if let percent = state.batteryPercent {
            batteryPercent = percent
            batteryGauge = state.batteryGauge
        }
        appendLog("Status \(Data(payload).hexString)" + (state.batteryPercent.map { " · battery about \($0)%" } ?? ""))
    }

    /// Asks for status until the first reply arrives (an early query is sometimes ignored),
    /// then once a minute so the battery level stays current.
    private func startStatusPolling() {
        statusPollTask?.cancel()
        statusPollTask = Task { [weak self] in
            var interval = Duration.seconds(2)
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self, self.phase == .ready else { return }
                self.requestStatus()
                interval = self.lastStatusUpdate == nil ? .seconds(3) : .seconds(60)
            }
        }
    }

    fileprivate func handleWrite(_ characteristic: CBCharacteristic, error: Error?) {
        if let error {
            writeFailure = error.localizedDescription
            appendLog("Write failed: \(error.localizedDescription)")
        }
        awaitingWriteResponse = false
    }
}

/// Receives CoreBluetooth callbacks (on the main queue) and forwards them to the service.
private final class BluetoothProxy: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    weak var owner: PrinterService?

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        MainActor.assumeIsolated { owner?.handleStateUpdate(state) }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated { owner?.handleDiscovery(peripheral, advertisement: advertisementData, rssi: RSSI) }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated { owner?.handleConnected(peripheral) }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { owner?.handleFailedToConnect(peripheral, error: error) }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { owner?.handleDisconnected(peripheral, error: error) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated { owner?.handleServicesDiscovered(peripheral, error: error) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated { owner?.handleCharacteristicsDiscovered(peripheral, service: service, error: error) }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated { owner?.handleNotificationState(characteristic, error: error) }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated { owner?.handleValue(characteristic, error: error) }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated { owner?.handleWrite(characteristic, error: error) }
    }
}

private extension CBCharacteristic {
    var canWrite: Bool { properties.contains(.write) || properties.contains(.writeWithoutResponse) }
    var canNotify: Bool { properties.contains(.notify) || properties.contains(.indicate) }
}

extension CBManagerState {
    var label: String {
        switch self {
        case .poweredOn: return "on"
        case .poweredOff: return "off"
        case .unauthorized: return "not allowed"
        case .unsupported: return "unsupported"
        case .resetting: return "resetting"
        case .unknown: return "starting"
        @unknown default: return "unknown"
        }
    }

    var userMessage: String {
        switch self {
        case .poweredOff: return "Bluetooth is off. Turn it on in Control Center or Settings."
        case .unauthorized: return "PocketPrint isn't allowed to use Bluetooth. Allow it in Settings › Apps › PocketPrint."
        case .unsupported: return "Bluetooth printing isn't available on this device."
        case .resetting: return "Bluetooth is restarting. Try again in a moment."
        default: return "Bluetooth is starting up. Try again in a moment."
        }
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

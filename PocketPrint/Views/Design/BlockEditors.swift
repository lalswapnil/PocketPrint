import SwiftUI

extension BlockContent {
    var textValue: TextBlock? { if case .text(let value) = self { return value }; return nil }
    var imageValue: ImageBlock? { if case .image(let value) = self { return value }; return nil }
    var checklistValue: ChecklistBlock? { if case .checklist(let value) = self { return value }; return nil }
    var qrValue: QRBlock? { if case .qr(let value) = self { return value }; return nil }
    var barcodeValue: BarcodeBlock? { if case .barcode(let value) = self { return value }; return nil }
    var dividerValue: DividerBlock? { if case .divider(let value) = self { return value }; return nil }
    var spacerValue: SpacerBlock? { if case .spacer(let value) = self { return value }; return nil }
    var symbolValue: SymbolBlock? { if case .symbol(let value) = self { return value }; return nil }
    var calendarValue: CalendarBlock? { if case .calendar(let value) = self { return value }; return nil }
}

struct BlockEditorSheet: View {
    @Binding var block: Block
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMove: (Int) -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                editor
                Section {
                    HStack(spacing: 10) {
                        actionButton("Up", "arrow.up", enabled: canMoveUp) { onMove(-1) }
                        actionButton("Down", "arrow.down", enabled: canMoveDown) { onMove(1) }
                        actionButton("Copy", "plus.square.on.square", enabled: true, action: onDuplicate)
                        actionButton("Delete", "trash", enabled: true, role: .destructive, action: onDelete)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
            }
            .navigationTitle(block.content.kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var editor: some View {
        switch block.content {
        case .text: TextBlockEditor(block: payload(\.textValue, BlockContent.text, fallback: TextBlock()))
        case .image: ImageBlockEditor(block: payload(\.imageValue, BlockContent.image, fallback: ImageBlock(imageID: "")))
        case .checklist: ChecklistEditor(block: payload(\.checklistValue, BlockContent.checklist, fallback: ChecklistBlock()))
        case .qr: QREditor(block: payload(\.qrValue, BlockContent.qr, fallback: QRBlock()))
        case .barcode: BarcodeEditor(block: payload(\.barcodeValue, BlockContent.barcode, fallback: BarcodeBlock()))
        case .divider: DividerEditor(block: payload(\.dividerValue, BlockContent.divider, fallback: DividerBlock()))
        case .spacer: SpacerEditor(block: payload(\.spacerValue, BlockContent.spacer, fallback: SpacerBlock()))
        case .symbol: SymbolEditor(block: payload(\.symbolValue, BlockContent.symbol, fallback: SymbolBlock()))
        case .calendar: CalendarEditor(block: payload(\.calendarValue, BlockContent.calendar, fallback: .currentMonth))
        }
    }

    private func payload<T>(_ extract: @escaping (BlockContent) -> T?, _ embed: @escaping (T) -> BlockContent, fallback: T) -> Binding<T> {
        Binding(
            get: { extract(block.content) ?? fallback },
            set: { block.content = embed($0) }
        )
    }

    private func actionButton(_ title: String, _ systemImage: String, enabled: Bool, role: ButtonRole? = nil,
                              action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(role == .destructive ? .red : .accentColor)
        .disabled(!enabled)
    }
}

// MARK: - Shared style controls

struct FontChips: View {
    @Binding var font: FontFamily

    var body: some View {
        ChipPicker(options: FontFamily.allCases, selection: $font) { family in
            Text(family.title)
                .font(Font(family.font(size: 16, bold: false) as CTFont))
        }
    }
}

struct TextStyleControls: View {
    @Binding var style: TextStyle
    var sizeRange: ClosedRange<Double> = 14...160
    var showAlignment = true

    var body: some View {
        FontChips(font: $style.font)
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        LabeledSlider(title: "Size", value: $style.size, range: sizeRange, step: 1,
                      format: { String(format: "%.1f mm", $0 / 8) })
        HStack(spacing: 8) {
            Toggle(isOn: $style.bold) { Image(systemName: "bold") }
                .accessibilityLabel("Bold")
            Toggle(isOn: $style.italic) { Image(systemName: "italic") }
                .accessibilityLabel("Italic")
            Toggle(isOn: $style.underline) { Image(systemName: "underline") }
                .accessibilityLabel("Underline")
            if showAlignment {
                Spacer()
                Picker("Alignment", selection: $style.align) {
                    ForEach(TextAlign.allCases) { align in
                        Image(systemName: align.systemImage).tag(align)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 150)
            }
        }
        .toggleStyle(.button)
    }
}

// MARK: - Text

struct TextBlockEditor: View {
    @Binding var block: TextBlock
    @FocusState private var focused: Bool

    var body: some View {
        Section {
            TextField("Type something…", text: $block.text, axis: .vertical)
                .lineLimit(2...8)
                .focused($focused)
                .accessibilityIdentifier("textBlockField")
            Menu {
                ForEach(TextTokens.all, id: \.token) { token in
                    Button("\(token.title) (updates when printed)") { insert(token.token) }
                }
                Button("Today's date") {
                    insert(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none))
                }
            } label: {
                Label("Insert date or time", systemImage: "calendar.badge.plus")
                    .font(.subheadline)
            }
        }
        Section("Style") {
            TextStyleControls(style: $block.style)
            Toggle("White text on black", isOn: $block.inverted)
        }
        .task {
            if block.text.isEmpty {
                try? await Task.sleep(for: .milliseconds(400))
                focused = true
            }
        }
    }

    private func insert(_ value: String) {
        if block.text.isEmpty || block.text.hasSuffix(" ") || block.text.hasSuffix("\n") {
            block.text += value
        } else {
            block.text += " " + value
        }
    }
}

// MARK: - Image

struct ImageBlockEditor: View {
    @Binding var block: ImageBlock

    var body: some View {
        PhotoAdjustmentsPanel(block: $block, showsSize: true)
    }
}

// MARK: - Checklist

struct ChecklistEditor: View {
    @Binding var block: ChecklistBlock
    @FocusState private var focusedItem: UUID?

    var body: some View {
        Section {
            ForEach($block.items) { $item in
                HStack(spacing: 12) {
                    Button {
                        item.checked.toggle()
                    } label: {
                        Image(systemName: item.checked ? "checkmark.square.fill" : "square")
                            .font(.title3)
                            .foregroundStyle(item.checked ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.checked ? "Checked" : "Not checked")
                    TextField("Item (leave empty for a writing line)", text: $item.text)
                        .focused($focusedItem, equals: item.id)
                        .submitLabel(.next)
                        .onSubmit { addItem(after: item.id) }
                }
            }
            .onDelete { block.items.remove(atOffsets: $0) }
            Button {
                addItem(after: block.items.last?.id)
            } label: {
                Label("Add Item", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Items")
        } footer: {
            Text("Swipe left on an item to delete it.")
        }
        Section("Style") {
            ChipPicker(options: ChecklistMarker.allCases, selection: $block.marker) { marker in
                Label(marker.title, systemImage: marker.systemImage)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            TextStyleControls(style: $block.style, sizeRange: 14...80, showAlignment: false)
        }
    }

    private func addItem(after id: UUID?) {
        let item = ChecklistItem()
        if let id, let index = block.items.firstIndex(where: { $0.id == id }) {
            block.items.insert(item, at: index + 1)
        } else {
            block.items.append(item)
        }
        focusedItem = item.id
    }
}

// MARK: - QR code

struct QREditor: View {
    @Binding var block: QRBlock

    var body: some View {
        Section {
            Picker("Type", selection: $block.mode) {
                ForEach(QRMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            switch block.mode {
            case .text:
                TextField("Text or web link", text: $block.text, axis: .vertical)
                    .lineLimit(1...5)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("qrTextField")
            case .wifi:
                TextField("Network name", text: $block.wifiSSID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if block.wifiSecurity != .open {
                    TextField("Password", text: $block.wifiPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Picker("Security", selection: $block.wifiSecurity) {
                    ForEach(WiFiSecurity.allCases) { Text($0.title).tag($0) }
                }
            case .contact:
                TextField("Name", text: $block.contactName)
                    .textContentType(.name)
                TextField("Phone", text: $block.contactPhone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                TextField("Email", text: $block.contactEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .textContentType(.emailAddress)
            }
            if !block.payload.isEmpty, CodeRaster.qrModules(block.payload, correction: block.correction) == nil {
                Label("This is too long for a QR code.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Content")
        } footer: {
            Text(block.mode == .wifi ? "Guests can scan this with their camera to join your Wi-Fi." : "Generated on this iPhone.")
        }
        Section("Look") {
            LabeledSlider(title: "Size", value: $block.sizePercent, range: 30...100, step: 5, format: { "\(Int($0))%" })
            TextField("Caption under the code (optional)", text: $block.caption)
            Picker("Damage tolerance", selection: $block.correction) {
                ForEach(CodeRaster.Correction.allCases) { Text($0.title).tag($0) }
            }
        }
    }
}

// MARK: - Barcode

struct BarcodeEditor: View {
    @Binding var block: BarcodeBlock

    var body: some View {
        Section {
            TextField("Letters and numbers", text: $block.text)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            if !block.text.isEmpty, CodeRaster.code128Bitmap(block.text, maxWidth: PrinterCatalog.printWidth - 8, height: 8) == nil {
                Label(block.text.allSatisfy(\.isASCII) ? "Too long to fit on the paper." : "Use plain letters, numbers and symbols only.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Code 128 barcode")
        }
        Section("Look") {
            LabeledSlider(title: "Height", value: Binding(get: { Double(block.height) }, set: { block.height = Int($0) }),
                          range: 32...200, step: 4, format: { String(format: "%.0f mm", $0 / 8) })
            Toggle("Show text under bars", isOn: $block.showText)
        }
    }
}

// MARK: - Divider & space

struct DividerEditor: View {
    @Binding var block: DividerBlock

    var body: some View {
        Section("Style") {
            ChipPicker(options: DividerStyle.allCases, selection: $block.style) { Text($0.title) }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            LabeledSlider(title: "Thickness", value: Binding(get: { Double(block.thickness) }, set: { block.thickness = Int($0) }),
                          range: 1...8, step: 1, format: { "\(Int($0))" })
        }
    }
}

struct SpacerEditor: View {
    @Binding var block: SpacerBlock

    var body: some View {
        Section {
            LabeledSlider(title: "Height", value: Binding(get: { Double(block.height) }, set: { block.height = Int($0) }),
                          range: 8...480, step: 8, format: { String(format: "%.0f mm", $0 / 8) })
        } footer: {
            Text("Blank paper — handy for handwritten notes or to separate items.")
        }
    }
}

// MARK: - Emoji & icons

struct SymbolEditor: View {
    @Binding var block: SymbolBlock

    private static let emoji = ["😀", "😍", "🥳", "😎", "🤩", "🥰", "🎉", "❤️", "⭐️", "🌸", "🌈", "☀️",
                                "🐶", "🐱", "🦄", "🐻", "🍕", "🍩", "☕️", "🎂", "🎁", "🎈", "⚽️", "📚",
                                "✈️", "🏠", "💡", "🔔", "📌", "✅", "👍", "🙏"]
    private static let icons = ["heart.fill", "star.fill", "sun.max.fill", "moon.fill", "cloud.fill", "snowflake",
                                "leaf.fill", "flame.fill", "bolt.fill", "drop.fill", "gift.fill", "birthday.cake.fill",
                                "cup.and.saucer.fill", "fork.knife", "cart.fill", "house.fill", "car.fill", "airplane",
                                "pawprint.fill", "music.note", "book.fill", "graduationcap.fill", "phone.fill", "envelope.fill",
                                "checkmark.seal.fill", "exclamationmark.triangle.fill", "hand.thumbsup.fill", "face.smiling",
                                "crown.fill", "trophy.fill", "camera.fill", "scissors", "pin.fill", "bell.fill",
                                "clock.fill", "location.fill", "wifi", "globe", "trash.fill", "lock.fill"]

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 8)]

    var body: some View {
        Section {
            Picker("Kind", selection: $block.kind) {
                Text("Emoji").tag(SymbolKind.emoji)
                Text("Icon").tag(SymbolKind.icon)
            }
            .pickerStyle(.segmented)
            .onChange(of: block.kind) { _, kind in
                block.value = kind == .emoji ? Self.emoji[0] : Self.icons[0]
            }
            if block.kind == .emoji {
                TextField("Type or pick an emoji", text: $block.value)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Self.emoji, id: \.self) { value in
                        Button { block.value = value } label: {
                            Text(value)
                                .font(.title)
                                .frame(width: 44, height: 44)
                                .background(RoundedRectangle(cornerRadius: 10)
                                    .fill(block.value == value ? Color.accentColor.opacity(0.2) : Color.clear))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Self.icons, id: \.self) { name in
                        Button { block.value = name } label: {
                            Image(systemName: name)
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(RoundedRectangle(cornerRadius: 10)
                                    .fill(block.value == name ? Color.accentColor.opacity(0.2) : Color.clear))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(name)
                    }
                }
            }
        }
        Section("Look") {
            LabeledSlider(title: "Size", value: $block.size, range: 40...384, step: 4, format: { String(format: "%.0f mm", $0 / 8) })
            Picker("Position", selection: $block.align) {
                ForEach(TextAlign.allCases) { align in
                    Image(systemName: align.systemImage).tag(align)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

// MARK: - Calendar

struct CalendarEditor: View {
    @Binding var block: CalendarBlock

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("LLLL y")
        let date = Calendar.current.date(from: DateComponents(year: block.year, month: block.month, day: 1)) ?? Date()
        return formatter.string(from: date)
    }

    var body: some View {
        Section("Month") {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous month")
                Spacer()
                Text(monthTitle).font(.headline)
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Next month")
            }
            .buttonStyle(.borderless)
            Button("This Month") {
                let current = CalendarBlock.currentMonth
                block.year = current.year
                block.month = current.month
            }
        }
        Section("Options") {
            Toggle("Show month name", isOn: $block.showTitle)
            Toggle("Highlight today", isOn: $block.highlightToday)
            Picker("Week starts on", selection: $block.firstWeekday) {
                Text("System setting").tag(0)
                Text("Sunday").tag(1)
                Text("Monday").tag(2)
            }
        }
    }

    private func shift(_ months: Int) {
        var total = block.year * 12 + (block.month - 1) + months
        total = max(0, total)
        block.year = total / 12
        block.month = total % 12 + 1
    }
}

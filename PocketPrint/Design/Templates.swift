import Foundation

struct DesignTemplate: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String
    let category: Category
    let make: @Sendable () -> Design

    enum Category: String, CaseIterable, Identifiable {
        case lists = "Lists & Notes"
        case labels = "Labels & Tags"
        case planning = "Planning"
        case cards = "Cards"
        var id: String { rawValue }
    }

    static func == (lhs: DesignTemplate, rhs: DesignTemplate) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private func text(_ value: String, size: Double = 30, bold: Bool = false, align: TextAlign = .left,
                  font: FontFamily = .system, inverted: Bool = false) -> Block {
    Block(.text(TextBlock(text: value, style: TextStyle(font: font, size: size, bold: bold, align: align), inverted: inverted)))
}

private func checklist(_ items: [String], marker: ChecklistMarker = .box, size: Double = 30) -> Block {
    Block(.checklist(ChecklistBlock(items: items.map { ChecklistItem(text: $0) }, marker: marker, style: TextStyle(size: size))))
}

private func divider(_ style: DividerStyle = .dashed) -> Block {
    Block(.divider(DividerBlock(style: style)))
}

extension Design {
    // MARK: Starters used by the Create screen

    static func note() -> Design {
        Design(title: "Note", blocks: [text("", size: 34)])
    }

    static func checklistStarter() -> Design {
        Design(title: "Checklist", blocks: [
            text("To Do", size: 42, bold: true, align: .center),
            Block(.checklist(ChecklistBlock())),
        ])
    }

    static func label() -> Design {
        Design(title: "Label", blocks: [text("Label", size: 64, bold: true, align: .center)], frame: .rounded, spacing: 10)
    }

    static func qrStarter() -> Design {
        Design(title: "QR Code", blocks: [Block(.qr(QRBlock()))])
    }

    static func calendarStarter() -> Design {
        Design(title: "Calendar", blocks: [Block(.calendar(.currentMonth))])
    }

    static func scannedText(_ value: String) -> Design {
        Design(title: "Scanned Text", blocks: [text(value, size: 28)])
    }

    static func pastedText(_ value: String) -> Design {
        Design(title: "Pasted Text", blocks: [text(value, size: 28)])
    }

    /// Several pasted pictures printed one after another, full width.
    static func pastedImages(_ imageIDs: [String], style: DitherStyle) -> Design {
        let blocks = imageIDs.map { Block(.image(ImageBlock(imageID: $0, adjustments: ImageAdjustments(style: style)))) }
        return Design(title: "Pasted Images", blocks: blocks, margin: 0, spacing: 24)
    }
}

enum Templates {
    static let all: [DesignTemplate] = [
        DesignTemplate(id: "todo", title: "To-Do List", systemImage: "checklist", category: .lists) {
            Design(title: "To-Do List", blocks: [
                text("TO DO", size: 48, bold: true, align: .center),
                text("{weekday}, {date}", size: 22, align: .center),
                divider(),
                checklist(["", "", "", "", ""]),
            ])
        },
        DesignTemplate(id: "shopping", title: "Shopping List", systemImage: "cart", category: .lists) {
            Design(title: "Shopping List", blocks: [
                Block(.symbol(SymbolBlock(kind: .icon, value: "cart", size: 90))),
                text("Shopping List", size: 40, bold: true, align: .center),
                divider(.dotted),
                checklist(["Milk", "Eggs", "Bread", "Fruit", "Coffee", ""]),
            ])
        },
        DesignTemplate(id: "sticky", title: "Sticky Note", systemImage: "note.text", category: .lists) {
            Design(title: "Sticky Note", blocks: [
                text("Note", size: 36, bold: true, font: .handwriting),
                text("Don't forget to call back after lunch!", size: 32, font: .handwriting),
                text("{date}", size: 20, align: .right),
            ], frame: .rounded)
        },
        DesignTemplate(id: "reminder", title: "Reminder", systemImage: "alarm", category: .lists) {
            Design(title: "Reminder", blocks: [
                text("REMINDER", size: 34, bold: true, align: .center, inverted: true),
                text("Water the plants", size: 40, bold: true, align: .center),
                text("{weekday} · {time}", size: 22, align: .center),
            ], frame: .line)
        },
        DesignTemplate(id: "meeting", title: "Meeting Notes", systemImage: "person.3", category: .lists) {
            Design(title: "Meeting Notes", blocks: [
                text("Meeting Notes", size: 38, bold: true),
                text("{date} · {time}", size: 22),
                divider(.solid),
                text("Attendees", size: 26, bold: true),
                checklist(["", ""], marker: .bullet, size: 26),
                text("Action items", size: 26, bold: true),
                checklist(["", "", ""], size: 26),
            ])
        },
        DesignTemplate(id: "name", title: "Name Tag", systemImage: "person.text.rectangle", category: .labels) {
            Design(title: "Name Tag", blocks: [
                text("HELLO my name is", size: 26, bold: true, align: .center, inverted: true),
                text("Alex", size: 80, bold: true, align: .center, font: .marker),
            ], frame: .double, spacing: 10, lengthMM: 40)
        },
        DesignTemplate(id: "price", title: "Price Tag", systemImage: "tag", category: .labels) {
            Design(title: "Price Tag", blocks: [
                text("SALE", size: 36, bold: true, align: .center, inverted: true),
                text("$19.99", size: 84, bold: true, align: .center, font: .condensed),
                Block(.barcode(BarcodeBlock(text: "SKU-10442", height: 56))),
            ], frame: .ticket, spacing: 10)
        },
        DesignTemplate(id: "jar", title: "Jar Label", systemImage: "takeoutbag.and.cup.and.straw", category: .labels) {
            Design(title: "Jar Label", blocks: [
                text("Homemade", size: 28, align: .center, font: .script),
                text("Strawberry Jam", size: 46, bold: true, align: .center, font: .elegant),
                divider(.stars),
                text("Made {month} {year}", size: 22, align: .center),
            ], frame: .rounded, spacing: 10)
        },
        DesignTemplate(id: "address", title: "Address Label", systemImage: "envelope", category: .labels) {
            Design(title: "Address Label", blocks: [
                text("FROM", size: 18, bold: true),
                text("Your Name\n12 Example Street", size: 22),
                divider(.dotted),
                text("TO", size: 22, bold: true),
                text("Recipient Name\n34 Sample Road\nCity 560001", size: 34, bold: true),
            ], frame: .line, spacing: 8)
        },
        DesignTemplate(id: "gift", title: "Gift Tag", systemImage: "gift", category: .labels) {
            Design(title: "Gift Tag", blocks: [
                Block(.symbol(SymbolBlock(kind: .emoji, value: "🎁", size: 130))),
                text("Happy Birthday!", size: 46, bold: true, align: .center, font: .handwriting),
                text("To: ________\nFrom: ______", size: 28, align: .center),
            ], frame: .stamp)
        },
        DesignTemplate(id: "planner", title: "Daily Planner", systemImage: "sun.max", category: .planning) {
            Design(title: "Daily Planner", blocks: [
                text("{weekday}", size: 46, bold: true, align: .center),
                text("{date}", size: 24, align: .center),
                divider(.double),
                text("Top 3 priorities", size: 26, bold: true),
                checklist(["", "", ""]),
                text("Notes", size: 26, bold: true),
                Block(.spacer(SpacerBlock(height: 120))),
                divider(.scissors),
            ])
        },
        DesignTemplate(id: "habit", title: "Habit Tracker", systemImage: "calendar.badge.checkmark", category: .planning) {
            Design(title: "Habit Tracker", blocks: [
                text("Habit: ____________", size: 30, bold: true),
                Block(.calendar(CalendarBlock(year: CalendarBlock.currentMonth.year, month: CalendarBlock.currentMonth.month, highlightToday: false))),
                text("Tick a box every day you do it!", size: 22, align: .center),
            ])
        },
        DesignTemplate(id: "calendar", title: "Month Calendar", systemImage: "calendar", category: .planning) {
            Design.calendarStarter()
        },
        DesignTemplate(id: "recipe", title: "Recipe Card", systemImage: "fork.knife", category: .planning) {
            Design(title: "Recipe Card", blocks: [
                text("Pancakes", size: 44, bold: true, align: .center, font: .elegant),
                text("Serves 2 · 20 min", size: 22, align: .center),
                divider(),
                text("Ingredients", size: 28, bold: true),
                checklist(["1 cup flour", "1 cup milk", "1 egg", "1 tbsp sugar", "Pinch of salt"], marker: .bullet, size: 26),
                text("Steps", size: 28, bold: true),
                checklist(["Whisk everything together", "Rest the batter 5 minutes", "Cook on a hot pan until golden"],
                          marker: .number, size: 26),
            ])
        },
        DesignTemplate(id: "wifi", title: "Wi-Fi Card", systemImage: "wifi", category: .cards) {
            Design(title: "Wi-Fi Card", blocks: [
                Block(.symbol(SymbolBlock(kind: .icon, value: "wifi", size: 80))),
                text("Scan to join Wi-Fi", size: 32, bold: true, align: .center),
                Block(.qr(QRBlock(mode: .wifi, wifiSSID: "MyNetwork", wifiPassword: "password123", sizePercent: 75))),
                text("Network: MyNetwork\nPassword: password123", size: 22, align: .center, font: .mono),
            ], frame: .rounded)
        },
        DesignTemplate(id: "contact", title: "Contact Card", systemImage: "person.crop.square", category: .cards) {
            Design(title: "Contact Card", blocks: [
                text("Alex Example", size: 42, bold: true, align: .center),
                text("+1 555 0100 · alex@example.com", size: 20, align: .center),
                Block(.qr(QRBlock(mode: .contact, contactName: "Alex Example", contactPhone: "+1 555 0100",
                                  contactEmail: "alex@example.com", sizePercent: 65))),
            ], frame: .line)
        },
        DesignTemplate(id: "thanks", title: "Thank You", systemImage: "heart", category: .cards) {
            Design(title: "Thank You", blocks: [
                Block(.symbol(SymbolBlock(kind: .icon, value: "heart.fill", size: 110))),
                text("Thank you!", size: 64, bold: true, align: .center, font: .script),
                text("for being awesome", size: 28, align: .center),
            ], frame: .stamp)
        },
        DesignTemplate(id: "ticket", title: "Admit One", systemImage: "ticket", category: .cards) {
            Design(title: "Admit One", blocks: [
                text("ADMIT ONE", size: 52, bold: true, align: .center, font: .condensed),
                text("Movie night · {date}", size: 24, align: .center),
                divider(.dashed),
                text("Seat 7 · Snacks included", size: 26, bold: true, align: .center),
            ], frame: .ticket)
        },
    ]
}

import UIKit
import XCTest

/// Drives the main flows end to end. The Simulator has no Bluetooth, so printing stops at "Choose Printer".
final class PocketPrintUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testNoteCanBeTypedAndSentToPrintSheet() {
        app.buttons["Note"].tap()
        let field = app.descendants(matching: .any)["textBlockField"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Hello printer")
        app.buttons["Done"].firstMatch.tap()

        app.buttons["Print"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Print"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose Printer"].exists)
        app.buttons["Close"].tap()
        XCTAssertFalse(app.navigationBars["Print"].waitForExistence(timeout: 1))
    }

    func testAddMenuAddsQRCodeBlock() {
        app.buttons["Label"].tap()
        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].firstMatch.tap()

        app.buttons["Add"].firstMatch.tap()
        app.buttons["QR Code"].firstMatch.tap()
        let field = app.descendants(matching: .any)["qrTextField"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("https://example.com")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["designPreview"].firstMatch.exists)
    }

    func testTemplateOpensInEditor() {
        app.buttons["Templates"].tap()
        let todo = app.buttons["To-Do List"].firstMatch
        XCTAssertTrue(todo.waitForExistence(timeout: 5))
        todo.tap()
        XCTAssertTrue(app.navigationBars["To-Do List"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Style"].exists)
    }

    // MARK: Paste

    /// Puts content on the simulator clipboard, then restarts the app so it sees it, like switching back from another app.
    private func relaunch(withClipboard fill: () -> Void) {
        app.terminate()
        fill()
        app.launch()
    }

    private static func picture(_ color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 320, height: 200), format: format).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 200))
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 110, y: 50, width: 100, height: 100))
        }
    }

    func testPastingACopiedPictureOpensItReadyToPrint() {
        relaunch { UIPasteboard.general.image = Self.picture(.systemOrange) }
        XCTAssertTrue(app.staticTexts["Picture ready to print"].waitForExistence(timeout: 5))
        app.buttons["Paste"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Photo"].waitForExistence(timeout: 10))
        app.buttons["Print"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Print"].waitForExistence(timeout: 5))
    }

    func testPastingSeveralPicturesMakesOnePrint() {
        relaunch { UIPasteboard.general.images = [Self.picture(.systemBlue), Self.picture(.systemRed)] }
        app.buttons["Paste"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Pasted Images"].waitForExistence(timeout: 10))
    }

    func testPastingTextMakesANote() {
        relaunch { UIPasteboard.general.string = "Pick up the dry cleaning" }
        XCTAssertTrue(app.staticTexts["Text ready to print"].waitForExistence(timeout: 5))
        app.buttons["Paste"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Pasted Text"].waitForExistence(timeout: 10))
    }

    func testAddMenuPastesAPictureIntoADesign() {
        relaunch { UIPasteboard.general.image = Self.picture(.systemGreen) }
        app.buttons["Label"].tap()
        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].firstMatch.tap()

        app.buttons["Add"].firstMatch.tap()
        app.buttons["Paste"].firstMatch.tap()
        // Reading the clipboard from a menu makes iOS ask first; the prompt may be shown by the app or by SpringBoard.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowInApp = app.buttons["Allow Paste"]
        let allowInSpringboard = springboard.buttons["Allow Paste"]
        if allowInApp.waitForExistence(timeout: 3) {
            allowInApp.tap()
        } else if allowInSpringboard.waitForExistence(timeout: 2) {
            allowInSpringboard.tap()
        }
        // A single pasted picture opens its photo settings, like Add › Photo.
        XCTAssertTrue(app.navigationBars["Photo"].waitForExistence(timeout: 10))
    }

    func testPasteDoesNothingWhenNothingIsCopied() {
        relaunch { UIPasteboard.general.items = [] }
        XCTAssertTrue(app.staticTexts["Nothing copied yet"].waitForExistence(timeout: 5))
        // iOS greys the system paste button out; XCUITest still reports it as enabled, so check the outcome.
        app.buttons["Paste"].firstMatch.tap()
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 2))
        XCTAssertTrue(app.navigationBars["PocketPrint"].exists)
    }

    func testToolsOpen() {
        app.buttons["Banner"].tap()
        XCTAssertTrue(app.navigationBars["Banner"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["Draw"].tap()
        XCTAssertTrue(app.navigationBars["Draw"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["Web Page"].tap()
        XCTAssertTrue(app.textFields["Web address, e.g. example.com"].waitForExistence(timeout: 5))
    }

    func testPrinterSettingsAndHistory() {
        app.tabBars.buttons["Printer"].tap()
        XCTAssertTrue(app.navigationBars["Printer"].waitForExistence(timeout: 5))
        // Pull to refresh must finish and leave the screen usable, even without Bluetooth.
        app.collectionViews.firstMatch.swipeDown()
        XCTAssertTrue(app.navigationBars["Printer"].waitForExistence(timeout: 5))
        let advanced = app.buttons["Advanced"]
        for _ in 0..<5 where !advanced.isHittable {
            app.swipeUp()
        }
        advanced.tap()
        XCTAssertTrue(app.navigationBars["Advanced"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let testPage = app.buttons["Print Test Page"]
        for _ in 0..<5 where !testPage.isHittable {
            app.swipeDown()
        }
        testPage.tap()
        XCTAssertTrue(app.navigationBars["Print"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
    }
}

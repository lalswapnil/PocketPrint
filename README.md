# PocketPrint

An offline iPhone app for the **P1-28F2** Bluetooth mini thermal printer and other printers that work with the *Tiny Print* app. No account, no cloud, no AI, and no tracking: everything runs on the phone and is sent straight to the printer over Bluetooth.

Requires iOS 18 or later. It's iPhone-only and built for iPhone 16 and newer.

## Features

- **Photo**: crop, rotate or flip a photo and adjust brightness, contrast and sharpness. Choose from six styles: Photo, Bright, Halftone, Pattern, Line Art and Document (removes shadows from photos of paper). You can add a caption and the date.
- **Paste**: copy a picture in any app (for example, touch and hold a photo and choose Copy), then tap **Paste** on the Clipboard card on the Create screen. One picture opens ready to print, several pictures (up to 12) become one print, a copied PDF opens in the Document tool, and copied text becomes a note. The card shows what's on the clipboard. Because it uses the system paste button, iOS doesn't ask "Allow Paste?". You can also paste into any design with **Add › Paste**, where iOS may ask the first time.
- **Note, Checklist, Label, QR code, Calendar**: open a "what you see is what prints" editor. Tap any part of the preview to edit it. You can stack text, photos, checklists, QR codes (text, Wi-Fi or contact), Code 128 barcodes, emoji and icons, month calendars, dividers and blank space. Pages can have borders and a fixed label length.
- **Templates**: to-do list, shopping list, sticky note, reminder, meeting notes, name tag, price tag, jar label, address label, gift tag, daily planner, habit tracker, calendar, recipe card, Wi-Fi card, contact card, thank-you card and ticket.
- **Banner**: large text printed sideways along the paper, up to 3 lines.
- **Draw**: draw with your finger or Apple Pencil (PencilKit).
- **Document**: print PDFs and images. You can choose pages, trim white margins and turn wide pages sideways.
- **Web page**: a browser shown at paper width, so what you see is what prints. It uses a private session that keeps no cookies.
- **Scan Text**: on-device text recognition turns a photo into an editable note.
- **History**: every print is saved on the phone so you can print it again, keep editing it or share it as a PNG.
- **Printer tab**: connects automatically, shows the printer's battery level, feeds and retracts paper, prints a test page, and has darkness and feed settings, advanced troubleshooting options and a Bluetooth diagnostics log. **Pull down** to check battery and paper right away, or to reconnect if the printer dropped off. The note under the printer card shows when the status was last checked.
- PocketPrint also shows up in "Open in…" for images, PDFs and text files from other apps.

## Install

`dist/PocketPrint.ipa` is **unsigned**. iOS only installs signed apps, so choose one of these:

1. **Xcode (easiest)**: open `PocketPrint.xcodeproj`. Go to *Signing & Capabilities* and pick your Team (a free Apple ID works). Select your iPhone and press Run.
2. **Build a signed IPA**: run `TEAM_ID=<your team id> scripts/build_ipa.sh`. Xcode must be signed in to that Apple ID.
3. **Sideloading tools**: install `dist/PocketPrint.ipa` with Sideloadly or AltStore, which sign it with your Apple ID.

With a free Apple ID the app has to be re-signed every 7 days. If iOS asks, turn on Developer Mode in *Settings › Privacy & Security*.

## First print

1. Switch the printer on by holding the power button for about 3 seconds.
2. Open PocketPrint and tap **Find**. Then tap **P1-28F2** and allow Bluetooth when asked.
3. Pick a tile, for example **Note**, type something and tap **Print**.

If prints don't come out right, go to *Printer › Advanced*:
- Garbled or cut-off prints: set Transfer speed to **Reliable**, or turn Compression **Off**.
- Faint prints: raise **Darkness** or set Heat to **Darker**.
- Nothing prints: try the other **Protocol**.

*Printer › Diagnostics* shows the Bluetooth activity log, which you can share.

## Build from source

- Xcode 26 or later. The project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen). Run `xcodegen generate` after editing it.
- Tests: `xcodebuild test -project PocketPrint.xcodeproj -scheme PocketPrint -destination 'platform=iOS Simulator,name=iPhone 16'`
- Unsigned IPA: `scripts/build_ipa.sh`
- App icons: `swift scripts/generate_icon.swift PocketPrint/Assets.xcassets/AppIcon.appiconset`

## How it talks to the printer

The P1 uses the Tiny Print "tiny" Bluetooth LE protocol:

- **Service and characteristics:** service `AE30`. Writes go to `AE01` and notifications come from `AE02`.
- **Packet format:** `51 78 cmd 00 len(u16 LE) payload crc8 FF`, with a CRC-8 (polynomial 0x07) over the payload.
- **Image rows:** 384 dots per row, packed LSB-first. Rows are sent run-length encoded (`BF`) when that is shorter than raw (`A2`).
- **Flow control:** the printer sends a pause/resume notification (`AE`), and the app waits whenever it is paused.
- **Status and battery:** the app asks for the `A3` device state on connect, once a minute while idle, after each print and when you pull down on the Printer tab. The first reply byte flags no paper, cover open, overheating or low battery. For P1/X6h-class printers the third byte is a battery gauge that the vendor app shows as six bars (`0x23`–`0x28`), so the percentage moves in steps of about 17%.
- **Print settings:** these match the Tiny Print app's settings for P1 printers: speed 10, heat energy 5000 for photos and 8000 for text, and density level 1–5.

The encoder is checked byte-for-byte against reference output from [TiMini-Print](https://github.com/Dejniel/TiMini-Print) (Apache-2.0) in `PocketPrintTests`. Protocol research credit: TiMini-Print and [Cat-Printer](https://github.com/NaitLee/Cat-Printer).

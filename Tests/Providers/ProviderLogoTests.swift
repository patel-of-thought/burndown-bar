import AppKit
import SwiftUI

@MainActor enum ProviderLogoTests {
    static func run() -> Int {
        var passed = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) {
            guard value() else { fputs("FAIL: \(label)\n", stderr); exit(1) }
            passed += 1
        }
        _ = NSApplication.shared
        let pickerFixture = Picker("Provider", selection: .constant(AccountOrigin.cursor)) {
            ForEach([AccountOrigin.cursor, .factory] + AccountOrigin.additional, id: \.rawValue) { origin in
                HStack(spacing: 7) { ProviderLogo(provider: origin.title, size: 14); Text(origin.title) }.tag(origin)
            }
        }
        let hosting = NSHostingView(rootView: pickerFixture.frame(width: 360))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 398, height: 1600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()

        func pickers(in view: NSView) -> [NSPopUpButton] {
            (view as? NSPopUpButton).map { [$0] } ?? view.subviews.flatMap { pickers(in: $0) }
        }
        let picker = pickers(in: hosting).first {
            $0.itemTitles.contains("Cursor") && $0.itemTitles.contains("Droid")
        }
        check(picker != nil, "native provider picker is present")
        guard let picker else { return passed }
        for origin in [AccountOrigin.cursor, .factory] + AccountOrigin.additional {
            let image = picker.item(withTitle: origin.title)?.image
            check(image != nil, "\(origin.title) picker image is present")
            check(image?.size == NSSize(width: 14, height: 14), "\(origin.title) menu image stays at 14 points")
        }
        check(picker.selectedItem?.image?.size == NSSize(width: 14, height: 14),
              "selected provider image stays at 14 points")
        return passed
    }
}

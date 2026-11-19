import AppKit
import SwiftUI

struct ProviderLogo: View {
    let provider: String
    var size: CGFloat = 20

    private static let assetNames: [String: String] = [
        "Codex": "codex", "Cursor": "cursor", "Droid": "factory", "OpenCode": "opencode",
        "Antigravity": "antigravity", "Copilot": "copilot", "Warp": "warp", "Zed": "zed",
        "Grok": "grok", "Claude": "claude", "Gemini": "gemini", "OpenRouter": "openrouter"
    ]
    private static let images: [String: NSImage] = assetNames.compactMapValues { name in
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "ProviderIcons"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }

    private var image: NSImage? {
        guard let image = Self.images[provider]?.copy() as? NSImage else { return nil }
        // Native picker menus use the NSImage size rather than SwiftUI's frame.
        image.size = NSSize(width: size, height: size)
        return image
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().renderingMode(.template).interpolation(.high).scaledToFit()
            } else {
                Image(systemName: provider == "Overview" ? "square.grid.2x2" : "square.dashed")
                    .resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

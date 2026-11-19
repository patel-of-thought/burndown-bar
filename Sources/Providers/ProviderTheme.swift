import AppKit
import SwiftUI

/// Brand colors per provider. Colors too close to the window background in one appearance
/// use a contrasting variant there, so every logo and bar stays visible in light and dark mode.
enum ProviderTheme {
    private struct Brand { let light: UInt32; let dark: UInt32 }
    private static let brands: [String: Brand] = [
        "Overview": Brand(light: 0xA1A1AA, dark: 0xA1A1AA),
        "Codex": Brand(light: 0x5D5D5D, dark: 0xB4B4B4),
        "Cursor": Brand(light: 0x3E3E55, dark: 0xF0F0FA),
        "OpenCode": Brand(light: 0x2B2828, dark: 0xFDFCFC),
        "Droid": Brand(light: 0xEE6018, dark: 0xEE6018),
        "Antigravity": Brand(light: 0x1967D2, dark: 0x1967D2),
        "Copilot": Brand(light: 0x8C93FB, dark: 0x8C93FB),
        "Warp": Brand(light: 0x799C92, dark: 0x799C92),
        "Zed": Brand(light: 0x1348DC, dark: 0x1348DC),
        "Claude": Brand(light: 0xD97757, dark: 0xD97757),
        "OpenRouter": Brand(light: 0x5659EA, dark: 0x7A7DFF),
    ]

    private static func ns(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// The provider's color, or nil when it has no assigned brand color.
    static func color(for provider: String) -> Color? {
        guard let brand = brands[provider] else { return nil }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? ns(brand.dark) : ns(brand.light)
        })
    }
}

import SpriteKit
import SwiftUI

struct VisualConstants {
    // MARK: - Color Palette
    struct Colors {
        static let background = SKColor(white: 0.05, alpha: 1.0)
        static let foreground = SKColor.white
        static let accent = SKColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 1.0) // Cyan
        static let danger = SKColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0) // Red
        static let success = SKColor(red: 0.2, green: 1.0, blue: 0.2, alpha: 1.0) // Green
        static let warning = SKColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0) // Amber
        static let glow = SKColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 0.5)

        // SwiftUI equivalents
        static var backgroundUI: Color { Color(background) }
        static var foregroundUI: Color { Color(foreground) }
        static var accentUI: Color { Color(accent) }
        static var dangerUI: Color { Color(danger) }
        static var successUI: Color { Color(success) }
        static var warningUI: Color { Color(warning) }
    }

    // MARK: - Typography
    struct Fonts {
        static let main = "Menlo-Bold"
        static let secondary = "Menlo"
        static let terminal = "CourierNewPS-BoldMT"

        // Specific sizes
        static let sizeHUD: CGFloat = 48
        static let sizeLabel: CGFloat = 18
        static let sizeSmall: CGFloat = 12
    }
}

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

        // MARK: Per-world accent tokens
        // Each campaign world gets a distinct accent so atmosphere/narrator
        // systems can later tint titles, glows, and particles by world.
        // Hues progress with the narrative arc:
        //   HARDWARE -> cold cyan (the default machine voice)
        //   CONTROL  -> green (you start steering the system)
        //   DATA     -> amber (corruption / warning territory)
        //   REALITY  -> magenta (the simulation cracks)
        //   OVERRIDE -> red (full system breakdown)
        // BOOT shares the cyan machine voice.
        static func worldAccent(for world: World) -> SKColor {
            switch world {
            case .world0, .world1:
                return accent // Cyan — the baseline terminal voice
            case .world2:
                return success // Green — control surface
            case .world3:
                return warning // Amber — data corruption
            case .world4:
                return SKColor(red: 1.0, green: 0.0, blue: 0.85, alpha: 1.0) // Magenta — reality break
            case .world5:
                return danger // Red — system override
            }
        }

        /// SwiftUI accent for a given world.
        static func worldAccentUI(for world: World) -> Color {
            Color(worldAccent(for: world))
        }

        /// Soft glow variant of a world accent (for shadows/halos).
        static func worldGlow(for world: World) -> SKColor {
            worldAccent(for: world).withAlphaComponent(0.5)
        }
    }

    // MARK: - Typography
    struct Fonts {
        // Faces. `display` is the intentional TITLE voice: a typewriter-terminal
        // face (Courier New Bold) that reads as system/console output, distinct
        // from the tighter Menlo body so titles stop borrowing generic Helvetica.
        static let display = "CourierNewPS-BoldMT" // Title / display — typewriter-terminal voice
        static let main = "Menlo-Bold"             // Body emphasis
        static let secondary = "Menlo"             // Body / supporting
        static let terminal = "CourierNewPS-BoldMT" // Inline terminal/console text

        // MARK: Type scale (tokenized — levels should reference these
        // instead of hardcoding raw point sizes).
        static let titleSize: CGFloat = 28   // Level titles ("LEVEL 7", etc.)
        static let headingSize: CGFloat = 18 // Section / label headings
        static let bodySize: CGFloat = 14    // Body copy
        static let captionSize: CGFloat = 11 // Subtitles / fine print

        // Specific sizes (retained for existing HUD usages).
        static let sizeHUD: CGFloat = 48
        static let sizeLabel: CGFloat = 18
        static let sizeSmall: CGFloat = 12
    }

    // MARK: - Spacing
    // Tokenized spacing scale so layout offsets stop hardcoding magic numbers.
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 32
    }
}

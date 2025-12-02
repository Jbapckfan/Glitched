import SwiftUI

@main
struct GlitchedApp: App {
    var body: some Scene {
        WindowGroup {
            GameRootView()
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
        }
    }
}

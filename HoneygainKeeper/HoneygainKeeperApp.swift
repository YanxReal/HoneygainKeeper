import SwiftUI

@main
struct HoneygainKeeperApp: App {
    /// Un único manager compartido por todas las ventanas: el estado del
    /// LaunchAgent es global a la app, no por ventana.
    @StateObject private var manager = LaunchAgentManager()

    var body: some Scene {
        WindowGroup {
            ContentView(manager: manager)
        }
        .defaultSize(width: 1000, height: 700)
        .windowResizability(.automatic)
        .commands {
            // Utilidad de una sola ventana: sin «Nueva ventana» (evita dos
            // ventanas reflejando el mismo estado global).
            CommandGroup(replacing: .newItem) {}
        }
    }
}

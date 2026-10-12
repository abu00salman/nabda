import SwiftUI

// Apple Watch app. Native SwiftUI, not a web view: WebKit is not available on watchOS.
// The timing rules mirror the web game in index.html (see NabdaGame.swift).
@main
struct NabdaWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchGameView()
        }
    }
}

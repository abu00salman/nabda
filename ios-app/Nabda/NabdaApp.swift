import SwiftUI

// Entry point. The whole app is one screen: the live Nabda site in a web view.
// See ContentView.swift for why it loads the deployed site instead of bundled files.
@main
struct NabdaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

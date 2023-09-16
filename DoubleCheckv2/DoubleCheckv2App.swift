import SwiftUI

@main
struct DoubleCheck: App {
    // Initialize your FrameInfoStore instance
    private let frameInfoStore = FrameInfoStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(frameInfoStore) // Pass frameInfoStore to ContentView
        }
    }
}


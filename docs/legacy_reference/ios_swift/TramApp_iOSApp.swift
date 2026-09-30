import SwiftUI
import FirebaseCore

@main
struct TramApp_iOSApp: App {
    init() {
        // Configure Firebase
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            LoginView()
        }
    }
}

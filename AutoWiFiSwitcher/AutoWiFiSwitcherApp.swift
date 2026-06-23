import SwiftUI

@main
struct AutoWiFiSwitcherApp: App {
    @StateObject private var wifiManager = WiFiManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    wifiManager.requestLocationPermission()
                    wifiManager.startPeriodicRefresh()
                }
        }
    }
}

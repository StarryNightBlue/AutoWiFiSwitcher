import Foundation

class WiFiAutoSwitchService: ObservableObject {
    static let shared = WiFiAutoSwitchService()

    @Published var configuredNetworks: [WiFiNetwork] = []
    @Published var isAutoSwitchEnabled: Bool = true
    @Published var lastSwitchTime: Date?
    @Published var cooldownSeconds: TimeInterval = 30
    @Published var logMessages: [String] = []

    private let wifiManager = WiFiManager.shared
    private let storageKey = "ConfiguredWiFiNetworks"
    private var evaluationTimer: Timer?
    private var lastConnectionAttempt: Date?

    init() {
        loadNetworks()
    }

    func startAutoSwitch() {
        isAutoSwitchEnabled = true
        startEvaluation()
        addLog("Auto-switch started")
    }

    func stopAutoSwitch() {
        isAutoSwitchEnabled = false
        stopEvaluation()
        addLog("Auto-switch stopped")
    }

    private func startEvaluation() {
        evaluationTimer?.invalidate()
        evaluationTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.evaluateAndSwitch()
        }
    }

    private func stopEvaluation() {
        evaluationTimer?.invalidate()
        evaluationTimer = nil
    }

    func addNetwork(ssid: String, password: String) {
        let maxPriority = configuredNetworks.map(\.priority).max() ?? 0
        let network = WiFiNetwork(ssid: ssid, password: password, priority: maxPriority + 1)
        KeychainHelper.save(ssid: ssid, password: password)
        configuredNetworks.append(network)
        saveNetworks()
        addLog("Added network: \(ssid)")
    }

    func removeNetwork(id: UUID) {
        guard let network = configuredNetworks.first(where: { $0.id == id }) else { return }
        configuredNetworks.removeAll { $0.id == id }
        KeychainHelper.delete(ssid: network.ssid)
        wifiManager.removeWiFi(ssid: network.ssid)
        saveNetworks()
        addLog("Removed network: \(network.ssid)")
    }

    func updatePassword(for id: UUID, newPassword: String) {
        guard let index = configuredNetworks.firstIndex(where: { $0.id == id }) else { return }
        configuredNetworks[index].password = newPassword
        KeychainHelper.save(ssid: configuredNetworks[index].ssid, password: newPassword)
        saveNetworks()
        addLog("Updated password for: \(configuredNetworks[index].ssid)")
    }

    func moveNetwork(from source: IndexSet, to destination: Int) {
        configuredNetworks.move(fromOffsets: source, toOffset: destination)
        for (index, _) in configuredNetworks.enumerated() {
            configuredNetworks[index].priority = index + 1
        }
        saveNetworks()
        addLog("Reordered networks")
    }

    func toggleNetwork(id: UUID) {
        guard let index = configuredNetworks.firstIndex(where: { $0.id == id }) else { return }
        configuredNetworks[index].isEnabled.toggle()
        saveNetworks()
        addLog("\(configuredNetworks[index].isEnabled ? "Enabled" : "Disabled"): \(configuredNetworks[index].ssid)")
    }

    private func evaluateAndSwitch() {
        guard isAutoSwitchEnabled else { return }

        wifiManager.refreshCurrentSSID()
        guard let currentSSID = wifiManager.currentSSID else {
            if !locationAuthorized() {
                addLog("Location permission required for SSID detection")
            } else {
                addLog("Not connected to any WiFi")
                attemptConnectBestAvailable()
            }
            return
        }

        let enabledNetworks = configuredNetworks.filter { $0.isEnabled }.sorted { $0.priority < $1.priority }
        guard !enabledNetworks.isEmpty else {
            addLog("No enabled networks configured")
            return
        }

        let currentIndex = enabledNetworks.firstIndex { $0.ssid == currentSSID }

        if currentIndex == nil {
            addLog("Current '\(currentSSID)' not in preferred list")
            attemptConnectBestAvailable()
        } else if currentIndex! > 0 {
            let bestNetwork = enabledNetworks[0]
            addLog("Higher priority '\(bestNetwork.ssid)' available, switching...")
            attemptConnect(to: bestNetwork)
        }
    }

    private func attemptConnectBestAvailable() {
        let enabledNetworks = configuredNetworks.filter { $0.isEnabled }.sorted { $0.priority < $1.priority }
        guard let best = enabledNetworks.first else { return }
        attemptConnect(to: best)
    }

    private func attemptConnect(to network: WiFiNetwork) {
        guard let password = KeychainHelper.read(ssid: network.ssid) else {
            addLog("Password not found for '\(network.ssid)'")
            return
        }
        guard canSwitch() else {
            addLog("Cooldown active, skip '\(network.ssid)'")
            return
        }
        if let last = lastConnectionAttempt, Date().timeIntervalSince(last) < 30 {
            return
        }
        lastConnectionAttempt = Date()

        addLog("Connecting to '\(network.ssid)'...")
        lastSwitchTime = Date()

        wifiManager.connectToWiFi(ssid: network.ssid, password: password) { [weak self] success, error in
            if success {
                self?.addLog("✅ Connection requested for '\(network.ssid)' (approve in system dialog)")
            } else {
                let msg = error?.localizedDescription ?? "unknown error"
                self?.addLog("❌ Failed '\(network.ssid)': \(msg)")
            }
        }
    }

    private func canSwitch() -> Bool {
        guard let last = lastSwitchTime else { return true }
        return Date().timeIntervalSince(last) >= cooldownSeconds
    }

    private func locationAuthorized() -> Bool {
        wifiManager.locationAuthorizationStatus == .authorizedWhenInUse ||
        wifiManager.locationAuthorizationStatus == .authorizedAlways
    }

    private func addLog(_ message: String) {
        DispatchQueue.main.async {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            let timestamp = formatter.string(from: Date())
            self.logMessages.append("[\(timestamp)] \(message)")
            if self.logMessages.count > 200 {
                self.logMessages = Array(self.logMessages.suffix(100))
            }
        }
    }

    private func saveNetworks() {
        let encodable = configuredNetworks.map { EncodableNetwork(id: $0.id, ssid: $0.ssid, priority: $0.priority, isEnabled: $0.isEnabled) }
        if let data = try? JSONEncoder().encode(encodable) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadNetworks() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        guard let decoded = try? JSONDecoder().decode([EncodableNetwork].self, from: data) else { return }
        configuredNetworks = decoded.compactMap { enc in
            guard let password = KeychainHelper.read(ssid: enc.ssid) else { return nil }
            return WiFiNetwork(id: enc.id, ssid: enc.ssid, password: password, priority: enc.priority, isEnabled: enc.isEnabled)
        }
    }
}

private struct EncodableNetwork: Codable {
    let id: UUID
    let ssid: String
    let priority: Int
    let isEnabled: Bool
}

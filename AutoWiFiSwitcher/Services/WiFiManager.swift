import Foundation
import NetworkExtension
import SystemConfiguration.CaptiveNetwork
import Network
import CoreLocation

class WiFiManager: NSObject, ObservableObject {
    static let shared = WiFiManager()

    @Published var currentSSID: String?
    @Published var isWiFiConnected: Bool = false
    @Published var hasInternetAccess: Bool = false
    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined

    private let locationManager = CLLocationManager()
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.autowifiswitcher.network")
    private var timer: Timer?

    override init() {
        super.init()
        locationManager.delegate = self
        locationAuthorizationStatus = locationManager.authorizationStatus
        setupPathMonitor()
    }

    func requestLocationPermission() {
        DispatchQueue.main.async { [weak self] in
            self?.locationManager.requestWhenInUseAuthorization()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            self.locationAuthorizationStatus = self.locationManager.authorizationStatus
            self.refreshCurrentSSID()
        }
    }

    func getCurrentSSID() -> String? {
        guard locationAuthorizationStatus == .authorizedWhenInUse ||
              locationAuthorizationStatus == .authorizedAlways else { return nil }
        guard let interfaces = CNCopySupportedInterfaces() as? [String] else { return nil }
        for interface in interfaces {
            guard let info = CNCopyCurrentNetworkInfo(interface as CFString) as? [String: Any] else { continue }
            if let ssid = info["SSID"] as? String, !ssid.isEmpty {
                return ssid
            }
        }
        return nil
    }

    func refreshCurrentSSID() {
        NEHotspotNetwork.fetchCurrent { [weak self] network in
            DispatchQueue.main.async {
                if let ssid = network?.ssid {
                    self?.currentSSID = ssid
                } else {
                    self?.currentSSID = self?.getCurrentSSID()
                }
            }
        }
    }

    func connectToWiFi(ssid: String, password: String, completion: @escaping (Bool, Error?) -> Void) {
        let config = NEHotspotConfiguration(ssid: ssid, passphrase: password, isWEP: false)
        config.joinOnce = false
        NEHotspotConfigurationManager.shared.apply(config) { error in
            DispatchQueue.main.async {
                if let error = error {
                    // Common error codes:
                    // invalidSSID, invalidWPAPassphrase, userDenied, internal, pending
                    completion(false, error)
                } else {
                    completion(true, nil)
                }
            }
        }
    }

    func connectToOpenWiFi(ssid: String, completion: @escaping (Bool, Error?) -> Void) {
        let config = NEHotspotConfiguration(ssid: ssid)
        config.joinOnce = false
        NEHotspotConfigurationManager.shared.apply(config) { error in
            DispatchQueue.main.async {
                completion(error == nil, error)
            }
        }
    }

    func removeWiFi(ssid: String) {
        NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
    }

    
        private func setupPathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.hasInternetAccess = path.status == .satisfied
                let wasWiFi = self?.isWiFiConnected ?? false
                self?.isWiFiConnected = path.usesInterfaceType(.wifi)
                if wasWiFi != (self?.isWiFiConnected ?? false) {
                    self?.refreshCurrentSSID()
                }
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    func startPeriodicRefresh(interval: TimeInterval = 5) {
        stopPeriodicRefresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshCurrentSSID()
        }
    }

    func stopPeriodicRefresh() {
        timer?.invalidate()
        timer = nil
    }
}

extension WiFiManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.locationAuthorizationStatus = manager.authorizationStatus
            self.refreshCurrentSSID()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[WiFiManager] Location error: \(error.localizedDescription)")
    }
}

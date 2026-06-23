import Foundation
import NetworkExtension
import SystemConfiguration.CaptiveNetwork
import Network
import CoreLocation

class WiFiManager: NSObject, ObservableObject {
    static let shared = WiFiManager()

    @Published var currentSSID: String?
    @Published var localIP: String?
    @Published var externalIP: String?
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
        fetchExternalIP()
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
        currentSSID = getCurrentSSID()
        localIP = getLocalIP()
        NEHotspotNetwork.fetchCurrent { [weak self] network in
            DispatchQueue.main.async {
                if let ssid = network?.ssid {
                    self?.currentSSID = ssid
                }
            }
        }
    }

    func fetchExternalIP() {
        guard let url = URL(string: "https://api.ipify.org") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            if let data = data, let ip = String(data: data, encoding: .utf8), !ip.isEmpty {
                DispatchQueue.main.async {
                    self?.externalIP = ip
                }
            }
        }.resume()
    }

    private func getLocalIP() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr = firstAddr
        while true {
            let iface = ptr.pointee
            let family = iface.ifa_addr.pointee.sa_family
            if family == UInt8(AF_INET) {
                let name = String(cString: iface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(iface.ifa_addr, socklen_t(iface.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, 0, NI_NUMERICHOST)
                    return String(cString: hostname)
                }
            }
            guard let next = iface.ifa_next else { break }
            ptr = next
        }
        return nil
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
                    self?.localIP = self?.getLocalIP()
                    self?.fetchExternalIP()
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

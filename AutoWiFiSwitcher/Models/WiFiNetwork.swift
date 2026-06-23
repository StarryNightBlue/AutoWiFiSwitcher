import Foundation

struct WiFiNetwork: Identifiable, Codable, Equatable {
    let id: UUID
    var ssid: String
    var password: String
    var priority: Int
    var isEnabled: Bool

    init(id: UUID = UUID(), ssid: String, password: String, priority: Int, isEnabled: Bool = true) {
        self.id = id
        self.ssid = ssid
        self.password = password
        self.priority = priority
        self.isEnabled = isEnabled
    }

    static func == (lhs: WiFiNetwork, rhs: WiFiNetwork) -> Bool {
        lhs.id == rhs.id
    }
}

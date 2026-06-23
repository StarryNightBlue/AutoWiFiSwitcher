import SwiftUI

struct ContentView: View {
    @StateObject private var wifiManager = WiFiManager.shared
    @StateObject private var autoSwitchService = WiFiAutoSwitchService.shared
    @State private var showAddSheet = false
    @State private var editingNetwork: WiFiNetwork?

    var body: some View {
        NavigationView {
            List {
                statusSection
                autoSwitchSection
                networksSection
                logSection
            }
            .navigationTitle("AutoWiFi")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
            .sheet(isPresented: $showAddSheet) {
                WiFiFormView()
            }
            .sheet(item: $editingNetwork) { network in
                WiFiFormView(editing: network)
            }
        }
        .onAppear {
            wifiManager.refreshCurrentSSID()
            wifiManager.startPeriodicRefresh(interval: 3)
            if autoSwitchService.isAutoSwitchEnabled {
                autoSwitchService.startAutoSwitch()
            }
        }
        .onDisappear {
            wifiManager.stopPeriodicRefresh()
        }
    }

    private var statusSection: some View {
        Section {
            HStack {
                Label("WiFi", systemImage: "wifi")
                Spacer()
                if wifiManager.isWiFiConnected {
                    Label(wifiManager.currentSSID ?? "Connected", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.subheadline)
                } else {
                    Label("Not connected", systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.subheadline)
                }
            }

            if wifiManager.isWiFiConnected {
                HStack {
                    Label("Signal", systemImage: signalBarsIcon)
                    Spacer()
                    Text("\(Int(wifiManager.signalStrength * 100))%")
                        .font(.subheadline)
                        .foregroundColor(signalColor)
                }
            }

            HStack {
                Label("Internet", systemImage: "globe")
                Spacer()
                if wifiManager.hasInternetAccess {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.subheadline)
                } else {
                    Label("Disconnected", systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.subheadline)
                }
            }

            HStack {
                Label("Location", systemImage: "location.fill")
                Spacer()
                Text(locationStatusText)
                    .font(.subheadline)
                    .foregroundColor(locationAuthorized ? .green : .red)
                if wifiManager.locationAuthorizationStatus == .denied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                } else if wifiManager.locationAuthorizationStatus == .notDetermined {
                    Button("Allow") {
                        wifiManager.requestLocationPermission()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }
        } header: {
            Label("Status", systemImage: "antenna.radiowaves.left.and.right")
        }
    }

    private var autoSwitchSection: some View {
        Section {
            Toggle(isOn: $autoSwitchService.isAutoSwitchEnabled) {
                Label("Auto-Switch", systemImage: "arrow.triangle.2.circlepath")
            }
            .onChange(of: autoSwitchService.isAutoSwitchEnabled) { _, newValue in
                if newValue {
                    wifiManager.requestLocationPermission()
                    autoSwitchService.startAutoSwitch()
                } else {
                    autoSwitchService.stopAutoSwitch()
                }
            }

            if autoSwitchService.isAutoSwitchEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cooldown: \(Int(autoSwitchService.cooldownSeconds))s")
                        .font(.subheadline)
                    Slider(value: $autoSwitchService.cooldownSeconds, in: 10...300, step: 10)
                }
            }
        } header: {
            Label("Auto-Switch", systemImage: "arrow.triangle.2.circlepath")
        }
    }

    private var networksSection: some View {
        Section {
            let sorted = autoSwitchService.configuredNetworks.sorted { $0.priority < $1.priority }
            ForEach(sorted) { network in
                HStack {
                    Button(action: { autoSwitchService.toggleNetwork(id: network.id) }) {
                        Image(systemName: network.isEnabled ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(network.isEnabled ? .green : .gray)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(network.ssid)
                            .font(.body)
                        Text("Priority #\(network.priority)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if network.ssid == wifiManager.currentSSID && wifiManager.isWiFiConnected {
                        Image(systemName: "wifi")
                            .foregroundColor(.blue)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    editingNetwork = network
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        autoSwitchService.removeNetwork(id: network.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        editingNetwork = network
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.orange)
                }
            }
            .onMove { from, to in
                autoSwitchService.moveNetwork(from: from, to: to)
            }
            .onDelete { indexSet in
                let sorted = autoSwitchService.configuredNetworks.sorted { $0.priority < $1.priority }
                for index in indexSet {
                    guard index < sorted.count else { continue }
                    autoSwitchService.removeNetwork(id: sorted[index].id)
                }
            }

            Button(action: { showAddSheet = true }) {
                Label("Add Network", systemImage: "plus.circle")
            }
        } header: {
            let count = autoSwitchService.configuredNetworks.filter { $0.isEnabled }.count
            Label("Networks (\(count) enabled)", systemImage: "list.bullet")
        }
    }

    private var logSection: some View {
        Section {
            if autoSwitchService.logMessages.isEmpty {
                Text("No events yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(autoSwitchService.logMessages.reversed()), id: \.self) { log in
                            Text(log)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fontWeight(log.contains("✅") || log.contains("❌") ? .semibold : .regular)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
            }
        } header: {
            HStack {
                Label("Activity Log", systemImage: "text.alignleft")
                Spacer()
                if !autoSwitchService.logMessages.isEmpty {
                    Button("Clear") {
                        autoSwitchService.logMessages.removeAll()
                    }
                    .font(.caption)
                }
            }
        }
    }

    private var signalBarsIcon: String {
        switch wifiManager.signalStrength {
        case 0.75...1.0: return "wifi"
        case 0.5..<0.75: return "wifi"
        case 0.25..<0.5: return "wifi"
        default: return "wifi.slash"
        }
    }

    private var signalColor: Color {
        switch wifiManager.signalStrength {
        case 0.75...1.0: return .green
        case 0.5..<0.75: return .yellow
        case 0.25..<0.5: return .orange
        default: return .red
        }
    }

    private var locationAuthorized: Bool {
        wifiManager.locationAuthorizationStatus == .authorizedWhenInUse ||
        wifiManager.locationAuthorizationStatus == .authorizedAlways
    }

    private var locationStatusText: String {
        switch wifiManager.locationAuthorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return "Authorized"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not Requested"
        @unknown default:
            return "Unknown"
        }
    }
}

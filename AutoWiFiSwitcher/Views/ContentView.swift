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
            wifiManager.fetchExternalIP()
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
            if wifiManager.isWiFiConnected {
                HStack {
                    Label("WiFi", systemImage: "wifi")
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                if let localIP = wifiManager.localIP {
                    HStack {
                        Label("Local IP", systemImage: "network")
                        Spacer()
                        Text(localIP)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospaced()
                    }
                }

                if let externalIP = wifiManager.externalIP {
                    HStack {
                        Label("External IP", systemImage: "globe")
                        Spacer()
                        Text(externalIP)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospaced()
                    }
                }
            } else {
                HStack {
                    Label("WiFi", systemImage: "wifi.slash")
                    Spacer()
                    Label("Not connected", systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.subheadline)
                }
            }

            HStack {
                Label("Internet", systemImage: "globe")
                Spacer()
                if wifiManager.hasInternetAccess {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Connected")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text("Disconnected")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }

            HStack {
                Label("Location", systemImage: "location.fill")
                Spacer()
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
                } else {
                    Text(locationStatusText)
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
            }

            HStack {
                Label("Auto-Switch", systemImage: "arrow.triangle.2.circlepath")
                Spacer()
                Text(autoSwitchService.statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let last = autoSwitchService.lastSuccessTime {
                HStack {
                    Label("Last Success", systemImage: "clock")
                    Spacer()
                    Text(last, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                Picker("Cooldown", selection: $autoSwitchService.cooldownSeconds) {
                    ForEach([10, 20, 30, 45, 60, 90, 120, 180, 240, 300], id: \.self) { sec in
                        Text("\(sec)s").tag(TimeInterval(sec))
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)

                Button(action: { autoSwitchService.manualConnect() }) {
                    Label("Connect Now", systemImage: "arrow.forward.circle.fill")
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
                        Text("Priority #") + Text("\(network.priority)")
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
            Label(title: { Text("Networks: ") + Text("\(count)") + Text(" enabled") }, icon: { Image(systemName: "list.bullet") })
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

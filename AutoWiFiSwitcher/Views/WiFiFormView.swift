import SwiftUI

struct WiFiFormView: View {
    @Environment(\.dismiss) var dismiss
    @State private var ssid = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Image(systemName: "wifi")
                            .foregroundColor(.blue)
                        TextField("SSID (Network Name)", text: $ssid)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }

                    HStack {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.blue)
                        if showPassword {
                            TextField("Password", text: $password)
                        } else {
                            SecureField("Password", text: $password)
                        }
                        Button(action: { showPassword.toggle() }) {
                            Image(systemName: showPassword ? "eye.fill" : "eye.slash.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }

                Section {
                    Button(action: save) {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView()
                            } else {
                                Text("Save")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(ssid.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                }

                if let error = errorMessage {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Add WiFi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        let trimmedSSID = ssid.trimmingCharacters(in: .whitespaces)
        guard !trimmedSSID.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        WiFiAutoSwitchService.shared.addNetwork(ssid: trimmedSSID, password: password)

        WiFiManager.shared.connectToWiFi(ssid: trimmedSSID, password: password) { success, error in
            DispatchQueue.main.async {
                isLoading = false
                if success {
                    dismiss()
                } else {
                    let errMsg = error?.localizedDescription ?? "unknown error"
                    errorMessage = "Connection failed: \(errMsg)"
                }
            }
        }
    }
}

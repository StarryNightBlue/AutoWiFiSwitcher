import SwiftUI

struct WiFiFormView: View {
    @Environment(\.dismiss) var dismiss
    var editing: WiFiNetwork?

    @State private var ssid = ""
    @State private var password = ""
    @State private var showPassword = false

    private var isEditing: Bool { editing != nil }

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
                            .disabled(isEditing)
                    }
                    .foregroundColor(isEditing ? .secondary : .primary)

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
                        Text(isEditing ? "Update" : "Save")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(ssid.trimmingCharacters(in: .whitespaces).isEmpty)
                }

            }
            .navigationTitle(isEditing ? "Edit WiFi" : "Add WiFi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            if let network = editing {
                ssid = network.ssid
                password = network.password
            }
        }
    }

    private func save() {
        let trimmedSSID = ssid.trimmingCharacters(in: .whitespaces)
        guard !trimmedSSID.isEmpty else { return }

        if let network = editing {
            WiFiAutoSwitchService.shared.updatePassword(for: network.id, newPassword: password)
        } else {
            WiFiAutoSwitchService.shared.addNetwork(ssid: trimmedSSID, password: password)
        }
        dismiss()
    }
}

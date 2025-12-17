//
//  SetupView.swift
//  Liquid Harvest
//
//  Created by Martyn Chamberlin on 11/29/25.
//

import SwiftUI

struct SetupView: View {
    @State private var clientId: String = ""
    @State private var clientSecret: String = ""
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    enum Field {
        case clientId, clientSecret
    }

    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "gear.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text("Welcome to Liquid Harvest")
                    .font(.title)
                    .fontWeight(.bold)

                Text("To get started, you'll need your Harvest OAuth2 Client ID and Client Secret")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Harvest OAuth2 Credentials")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Client ID")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("Enter your Client ID", text: $clientId)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .clientId)
                        .onSubmit {
                            focusedField = .clientSecret
                        }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Client Secret")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    SecureField("Enter your Client Secret", text: $clientSecret)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .clientSecret)
                        .onSubmit {
                            saveCredentials()
                        }
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Redirect URI to use:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("http://localhost:5006/callback")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.blue)
                        .textSelection(.enabled)
                }

                Text("You can create a new OAuth2 application at [id.getharvest.com/developers](https://id.getharvest.com/developers)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            Button(action: saveCredentials) {
                Text("Save & Continue")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(Color(nsColor: .textBackgroundColor))
                    .background(Color(nsColor: .labelColor))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(clientId.trimmingCharacters(in: .whitespaces).isEmpty || clientSecret.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 500, minHeight: 500)
        .onAppear {
            focusedField = .clientId
        }
        // Match the logged-in screen style: frost the whole window background.
        .glassEffect()
    }

    private func saveCredentials() {
        let trimmedId = clientId.trimmingCharacters(in: .whitespaces)
        let trimmedSecret = clientSecret.trimmingCharacters(in: .whitespaces)

        guard !trimmedId.isEmpty else {
            errorMessage = "Client ID cannot be empty"
            return
        }

        guard !trimmedSecret.isEmpty else {
            errorMessage = "Client Secret cannot be empty"
            return
        }

        // Save Client ID to UserDefaults
        UserDefaults.standard.set(trimmedId, forKey: "harvest_client_id")

        // Save Client Secret to Keychain (more secure)
        let keychain = KeychainManager.shared
        guard keychain.save(key: "harvest_client_secret", value: trimmedSecret) else {
            errorMessage = "Failed to save client secret"
            return
        }

        // Notify AuthenticationManager to reload
        NotificationCenter.default.post(name: NSNotification.Name("HarvestClientIDUpdated"), object: nil)

        onComplete()
    }
}

#Preview {
    SetupView {
        print("Setup complete")
    }
}


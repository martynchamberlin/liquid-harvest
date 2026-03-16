//
//  AuthenticationManager.swift
//  Liquid Harvest
//
//  Created by Martyn Chamberlin on 11/29/25.
//

import AppKit
import Combine
import CryptoKit
import Foundation

struct OAuthTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let tokenType: String?

    // No explicit CodingKeys needed - using .convertFromSnakeCase strategy
}

struct OAuthTokens: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case accessToken
        case refreshToken
        case expiresIn
        case tokenType
        case createdAt
    }

    init(from response: OAuthTokenResponse, createdAt: Date = Date()) {
        accessToken = response.accessToken
        refreshToken = response.refreshToken
        expiresIn = response.expiresIn ?? 3600 // Default to 1 hour if not provided
        tokenType = response.tokenType ?? "Bearer"
        self.createdAt = createdAt
    }

    init(accessToken: String, refreshToken: String?, expiresIn: Int, tokenType: String, createdAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
        self.tokenType = tokenType
        self.createdAt = createdAt
    }

    var isExpired: Bool {
        let expirationDate = createdAt.addingTimeInterval(TimeInterval(expiresIn))
        return Date() >= expirationDate
    }
}

class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()

    @Published var isAuthenticated = false
    @Published var currentUser: User?

    private let keychain = KeychainManager.shared
    private let apiClient = HarvestAPIClient.shared
    private let redirectURI = "http://localhost:5006/callback"
    private let localServer = LocalHTTPServer()
    private var codeVerifier: String?
    private var codeChallenge: String?

    private var clientId: String? {
        let id = (UserDefaults.standard.string(forKey: "harvest_client_id") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : id
    }

    private var clientSecret: String? {
        let secret = (keychain.get(key: "harvest_client_secret") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return secret.isEmpty ? nil : secret
    }

    private init() {
        // Don't check authentication in init - let it be called explicitly
        // This avoids race conditions and initialization issues

        // Listen for client ID updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clientIdUpdated),
            name: NSNotification.Name("HarvestClientIDUpdated"),
            object: nil,
        )
    }

    @objc private func clientIdUpdated() {
        // Client ID was updated, no action needed as we read it dynamically
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func checkAuthenticationStatus() {
        if let tokens = loadTokens() {
            if tokens.isExpired {
                // Try to refresh token
                // Use explicit Swift concurrency Task to avoid conflict with Harvest Task model
                _Concurrency.Task { @MainActor in
                    await self.refreshTokenIfNeeded()
                }
            } else {
                apiClient.setAccessToken(tokens.accessToken)
                _Concurrency.Task { @MainActor in
                    self.isAuthenticated = true
                    await self.loadUser()
                }
            }
        }
    }

    func startOAuthFlow() {
        guard let clientId else {
            print("Error: Client ID not configured. Please set it in Setup.")
            return
        }

        // Generate PKCE parameters
        codeVerifier = generateCodeVerifier()
        guard let verifier = codeVerifier else {
            print("Failed to generate code verifier")
            return
        }
        codeChallenge = generateCodeChallenge(from: verifier)

        // Start local HTTP server to catch callback
        localServer.start(port: 5006, onCode: { [weak self] code in
            guard let self else { return }
            localServer.stop()
            _Concurrency.Task { @MainActor in
                do {
                    try await self.handleOAuthCallback(code: code)
                } catch {
                    print("Error handling OAuth callback: \(error.localizedDescription)")
                    // Post notification so ViewModel can handle the error
                    NotificationCenter.default.post(
                        name: NSNotification.Name("OAuthError"),
                        object: nil,
                        userInfo: ["error": error.localizedDescription],
                    )
                }
            }
        }, onError: { [weak self] error in
            print("OAuth error: \(error)")
            self?.localServer.stop()
            NotificationCenter.default.post(
                name: NSNotification.Name("OAuthError"),
                object: nil,
                userInfo: ["error": error],
            )
        })

        // Build authorization URL
        guard var components = URLComponents(string: "https://id.getharvest.com/oauth2/authorize") else {
            print("Failed to create URL components")
            localServer.stop()
            return
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        guard let url = components.url else {
            print("Failed to create authorization URL")
            localServer.stop()
            return
        }

        // Open browser
        NSWorkspace.shared.open(url)
    }

    func handleOAuthCallback(code: String) async throws {
        guard let clientId else {
            throw NSError(domain: "AuthenticationManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Client ID not configured"])
        }

        guard let clientSecret else {
            throw NSError(domain: "AuthenticationManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Client Secret not configured"])
        }

        guard let verifier = codeVerifier else {
            throw NSError(domain: "AuthenticationManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Code verifier not found"])
        }

        // Exchange code for tokens
        guard let tokenURL = URL(string: "https://id.getharvest.com/api/v2/oauth2/token") else {
            throw NSError(domain: "AuthenticationManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid token URL"])
        }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "code": code,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
            "code_verifier": verifier,
        ]

        print("🔵 Exchanging code for tokens...")
        print("🔵 Redirect URI: \(redirectURI)")
        print("🔵 Has code verifier: \(verifier.isEmpty == false)")

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AuthenticationManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from server"])
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Token exchange failed with status \(httpResponse.statusCode)")
            print("❌ Response body: \(errorMessage)")
            throw NSError(
                domain: "AuthenticationManager",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Failed to exchange code for tokens: \(errorMessage)"],
            )
        }

        // Check if we have data
        guard !data.isEmpty else {
            print("❌ Token exchange returned empty response")
            throw NSError(
                domain: "AuthenticationManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Token exchange returned empty response"],
            )
        }

        // Log the response for debugging
        print("🔵 Response status: \(httpResponse.statusCode)")
        if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
            print("🔵 Content-Type: \(contentType)")
        }

        if let responseString = String(data: data, encoding: .utf8) {
            print("✅ Token exchange response (full): \(responseString)")
            print("✅ Response length: \(data.count) bytes")
        } else {
            print("❌ Response is not valid UTF-8")
            print("❌ Response data (hex): \(data.prefix(100).map { String(format: "%02x", $0) }.joined())")
        }

        // Try to decode as JSON
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            print("🔵 Attempting to decode JSON response...")
            let tokenResponse = try decoder.decode(OAuthTokenResponse.self, from: data)
            print("✅ Successfully decoded token response")
            let tokens = OAuthTokens(from: tokenResponse)

            saveTokens(tokens)
            apiClient.setAccessToken(tokens.accessToken)
            await MainActor.run {
                self.isAuthenticated = true
            }

            await loadUser()

            // Clear PKCE values
            codeVerifier = nil
            codeChallenge = nil

            // Notify that OAuth completed successfully
            NotificationCenter.default.post(name: NSNotification.Name("OAuthSuccess"), object: nil)
        } catch {
            print("❌ Failed to decode token response: \(error)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("❌ Response was: \(responseString)")
            }
            throw NSError(
                domain: "AuthenticationManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to decode token response: \(error.localizedDescription)"],
            )
        }
    }

    func refreshTokenIfNeeded() async {
        guard let clientId else {
            print("Error: Client ID not configured. Cannot refresh token.")
            logout()
            return
        }

        guard let clientSecret else {
            print("Error: Client Secret not configured. Cannot refresh token.")
            logout()
            return
        }

        guard let tokens = loadTokens(), tokens.isExpired else { return }

        guard let refreshToken = tokens.refreshToken else {
            print("Error: No refresh token available. Need to re-authenticate.")
            logout()
            return
        }

        guard let tokenURL = URL(string: "https://id.getharvest.com/api/v2/oauth2/token") else {
            print("Invalid token URL")
            logout()
            return
        }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ... 299).contains(httpResponse.statusCode)
            else {
                // Refresh failed, need to re-authenticate
                logout()
                return
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let tokenResponse = try decoder.decode(OAuthTokenResponse.self, from: data)
            let newTokens = OAuthTokens(from: tokenResponse)

            saveTokens(newTokens)
            apiClient.setAccessToken(newTokens.accessToken)
            await MainActor.run {
                self.isAuthenticated = true
            }
        } catch {
            // Refresh failed, need to re-authenticate
            logout()
        }
    }

    func logout() {
        // Normal logout should only clear session tokens (not the user's saved OAuth app credentials).
        // Client ID is stored in UserDefaults and Client Secret is stored in Keychain.
        // Those are cleared via an explicit "flush/reset credentials" action elsewhere.
        _ = keychain.delete(key: "oauth_tokens")
        apiClient.clearAccessToken()
        // Use explicit Swift concurrency Task to avoid conflict with Harvest Task model
        _Concurrency.Task { @MainActor in
            self.isAuthenticated = false
            self.currentUser = nil
        }
    }

    private func loadUser() async {
        do {
            let user = try await apiClient.getCurrentUser()
            await MainActor.run {
                self.currentUser = user
            }
        } catch {
            // Silently fail - user will need to log in again
            print("Failed to load user: \(error)")
        }
    }

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else { return "" }
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncodedString()
    }

    private func saveTokens(_ tokens: OAuthTokens) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(tokens),
           let jsonString = String(data: data, encoding: .utf8)
        {
            keychain.save(key: "oauth_tokens", value: jsonString)
        }
    }

    private func loadTokens() -> OAuthTokens? {
        guard let jsonString = keychain.get(key: "oauth_tokens"),
              let data = jsonString.data(using: .utf8)
        else {
            return nil
        }

        let decoder = JSONDecoder()
        return try? decoder.decode(OAuthTokens.self, from: data)
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

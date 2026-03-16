//
//  AuthenticationViewModel.swift
//  Liquid Harvest
//
//  Created by Martyn Chamberlin on 11/29/25.
//

import Combine
import Foundation

@MainActor
class AuthenticationViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var authManager: AuthenticationManager {
        AuthenticationManager.shared
    }

    private var cancellables = Set<AnyCancellable>()
    private var subscriptionsSetup = false

    init() {
        // Don't access anything in init - let setupSubscriptionsIfNeeded handle it
    }

    func setupSubscriptionsIfNeeded() {
        guard !subscriptionsSetup else { return }
        subscriptionsSetup = true

        // Set initial values first
        isAuthenticated = authManager.isAuthenticated
        currentUser = authManager.currentUser

        // Subscribe to authentication manager updates
        authManager.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self else { return }
                isAuthenticated = value
            }
            .store(in: &cancellables)

        authManager.$currentUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self else { return }
                currentUser = value
            }
            .store(in: &cancellables)
    }

    func checkAuthentication() {
        authManager.checkAuthenticationStatus()
    }

    func startLogin() {
        isLoading = true
        errorMessage = nil
        authManager.startOAuthFlow()

        // Listen for OAuth completion or errors
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("OAuthSuccess"),
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            self?.isLoading = false
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("OAuthError"),
            object: nil,
            queue: .main,
        ) { [weak self] notification in
            self?.isLoading = false
            if let error = notification.userInfo?["error"] as? String {
                self?.errorMessage = error
            }
        }
    }

    func handleOAuthCallback(code: String) async {
        do {
            try await authManager.handleOAuthCallback(code: code)
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    func logout() {
        authManager.logout()
    }
}

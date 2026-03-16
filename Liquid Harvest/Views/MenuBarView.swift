//
//  MenuBarView.swift
//  Liquid Harvest
//
//  Created by Martyn Chamberlin on 11/29/25.
//

import AppKit
import SwiftUI

struct MenuBarTimerContent: View {
    @ObservedObject var runningTimer: RunningTimer
    @ObservedObject var timerViewModel: TimerViewModel

    var body: some View {
        VStack(spacing: 8) {
            // This updates every second because we observe RunningTimer directly
            Text(runningTimer.formattedElapsedTime)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()

            if let project = timerViewModel.selectedProject {
                VStack(spacing: 2) {
                    // Try to get client from timeEntry first, then fall back to project.client
                    if let client = runningTimer.timeEntry.client ?? project.client {
                        Text(client.name)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Text(project.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Button(action: {
                // Use explicit Swift concurrency Task to avoid conflict with Harvest Task model
                _Concurrency.Task {
                    await timerViewModel.stopTimer()
                }
            }) {
                HStack {
                    Image(systemName: "stop.fill")
                    Text("Stop")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(Color(nsColor: .textBackgroundColor))
                .background(Color(nsColor: .labelColor))
                .cornerRadius(6)
            }
            .disabled(timerViewModel.isLoading)
        }
    }
}

struct MenuBarView: View {
    @StateObject private var timerViewModel = TimerViewModel()
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @Environment(\.openWindow) private var openWindow

    private func showWindow() {
        // Activate the app and bring windows to front
        NSApp.activate(ignoringOtherApps: true)

        // Check if any windows are already open
        let visibleWindows = NSApp.windows.filter(\.isVisible)

        if !visibleWindows.isEmpty {
            // Windows exist - bring them all to front without resizing
            for window in visibleWindows {
                window.makeKeyAndOrderFront(nil)
            }
        } else {
            // No windows visible - open a new one
            openWindow(id: "main")
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            if let runningTimer = timerViewModel.runningTimer {
                MenuBarTimerContent(runningTimer: runningTimer, timerViewModel: timerViewModel)
            } else {
                Text("No timer running")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Open window to start")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            Button(action: {
                showWindow()
            }) {
                HStack {
                    Image(systemName: "clock")
                    Text("Open Window")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Divider()

            Button(action: {
                // Clear client credentials to show setup again
                UserDefaults.standard.removeObject(forKey: "harvest_client_id")
                KeychainManager.shared.delete(key: "harvest_client_secret")
                NotificationCenter.default.post(name: NSNotification.Name("HarvestClientIDUpdated"), object: nil)
                authViewModel.logout()
            }) {
                HStack {
                    Image(systemName: "gear")
                    Text("Flush API Credentials")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: {
                authViewModel.logout()
            }) {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Log Out")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 200)
        .onAppear {
            // Setup and check authentication when view appears
            authViewModel.setupSubscriptionsIfNeeded()
            authViewModel.checkAuthentication()
            // Immediately check for running timer when authenticated
            if authViewModel.isAuthenticated {
                _Concurrency.Task {
                    await timerViewModel.refreshRunningTimer()
                }
            }
        }
        .onChange(of: authViewModel.isAuthenticated) { _, newValue in
            if newValue {
                // Immediately check for running timer when authenticated
                _Concurrency.Task {
                    await timerViewModel.refreshRunningTimer()
                }
            } else {
                // Clear timer when logged out
                timerViewModel.runningTimer = nil
            }
        }
    }
}

#Preview {
    MenuBarView()
}

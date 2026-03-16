//
//  Liquid_HarvestApp.swift
//  Liquid Harvest
//
//  Created by Martyn Chamberlin on 11/29/25.
//

import AppKit
import SwiftUI

@main
struct Liquid_HarvestApp: App {
    @StateObject private var authViewModel = AuthenticationViewModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            WindowView()
                .environmentObject(authViewModel)
                .frame(minWidth: 500, minHeight: 400)
                .background(WindowAccessor())
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 800, height: 700)
        .windowResizability(.contentSize)
        .commands {
            // Remove default menu items we don't need
            CommandGroup(replacing: .newItem) {}

            // Add CMD+R to refresh time entries
            CommandMenu("View") {
                Button("Refresh Week") {
                    NotificationCenter.default.post(name: NSNotification.Name("RefreshTimeEntries"), object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            // Account commands (not in-window UI)
            CommandMenu("Account") {
                Button("Log Out") {
                    authViewModel.logout()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Divider()

                Button("Flush API Credentials") {
                    UserDefaults.standard.removeObject(forKey: "harvest_client_id")
                    KeychainManager.shared.delete(key: "harvest_client_secret")
                    NotificationCenter.default.post(name: NSNotification.Name("HarvestClientIDUpdated"), object: nil)
                    authViewModel.logout()
                }
            }
        }

        WindowGroup(id: "editTimeEntry") {
            EditTimeEntryWindowView()
                .environmentObject(authViewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 480, height: 320)
    }
}

// Custom NSView that monitors key events
class KeyEventMonitoringView: NSView {
    private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        // Remove existing monitor if any
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        guard let window else { return }

        // Add local event monitor to catch Return/Enter presses
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak window] event in
            // Only handle if this window is key and Return/Enter is pressed (keyCode 36)
            guard let window,
                  window.isKeyWindow,
                  event.keyCode == 36, // Return/Enter
                  !event.isARepeat,
                  event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            else {
                return event
            }

            // Check if the user is typing in a text field (don't intercept)
            if let firstResponder = window.firstResponder as? NSTextView,
               firstResponder.isEditable
            {
                return event
            }

            // Post notification to toggle timer
            NotificationCenter.default.post(name: NSNotification.Name("ToggleTimer"), object: nil)
            return nil // Consume the event
        }
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// Helper view to access and configure the NSWindow
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let view = KeyEventMonitoringView()
        DispatchQueue.main.async {
            if let window = view.window {
                configureWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                configureWindow(window)
            }
        }
    }

    private func configureWindow(_ window: NSWindow) {
        // Enable layer-backed views for corner radius
        window.contentView?.wantsLayer = true

        // Set corner radius for rounded window appearance (macOS 26/Finder style)
        // Typical Finder windows use around 20-24pt corner radius
//        window.contentView?.layer?.cornerRadius = 20.0
//        window.contentView?.layer?.masksToBounds = true

        // Optional: Set background to clear to see the rounded corners better
        window.isOpaque = false
        window.backgroundColor = .clear
    }
}

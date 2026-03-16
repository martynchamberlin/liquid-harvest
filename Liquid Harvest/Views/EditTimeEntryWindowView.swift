//
//  EditTimeEntryWindowView.swift
//  Liquid Harvest
//
//  Created by Martyn Chamberlin on 11/29/25.
//

import AppKit
import Combine
import SwiftUI

// Shared state for passing data when opening a new window
class EditTimeEntryWindowState: ObservableObject {
    @Published var entry: TimeEntry?
    var onSave: (() async -> Void)?
    var timerViewModel: TimerViewModel?

    static let shared = EditTimeEntryWindowState()

    private init() {}
}

// Window-specific state - each window gets its own instance
class EditTimeEntryWindowInstanceState: ObservableObject {
    @Published var entry: TimeEntry
    var onSave: (() async -> Void)?
    var timerViewModel: TimerViewModel?

    init(entry: TimeEntry, onSave: (() async -> Void)?, timerViewModel: TimerViewModel?) {
        self.entry = entry
        self.onSave = onSave
        self.timerViewModel = timerViewModel
    }
}

struct EditTimeEntryWindowView: View {
    @StateObject private var instanceState: EditTimeEntryWindowInstanceState
    @StateObject private var timerViewModel = TimerViewModel()
    @State private var window: NSWindow?

    init() {
        // Get data from shared state and create instance-specific state
        let shared = EditTimeEntryWindowState.shared
        let entry = shared.entry ?? TimeEntry(
            id: 0,
            spentDate: "",
            user: TimeEntryUser(id: 0, name: ""),
            client: nil,
            project: nil,
            task: nil,
            hours: nil,
            notes: nil,
            isLocked: false,
            lockedReason: nil,
            isClosed: false,
            isBilled: false,
            timerStartedAt: nil,
            startedTime: nil,
            endedTime: nil,
            isRunning: false,
            billable: false,
            budgeted: false,
            billableRate: nil,
            costRate: nil,
            createdAt: "",
            updatedAt: "",
        )
        _instanceState = StateObject(wrappedValue: EditTimeEntryWindowInstanceState(
            entry: entry,
            onSave: shared.onSave,
            timerViewModel: shared.timerViewModel,
        ))
    }

    var body: some View {
        EditTimeEntryView(
            entry: instanceState.entry,
            timerViewModel: instanceState.timerViewModel ?? timerViewModel,
            onSave: {
                await instanceState.onSave?()
                // Close only this specific window instance
                window?.close()
            },
        )
        .padding(20)
        .glassEffect()
        .background(WindowAccessorForEditWindow(window: $window))
        .frame(minWidth: 480, minHeight: 320)
    }
}

// Helper to capture the window reference for this specific instance and configure transparency
struct WindowAccessorForEditWindow: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                self.window = window
                configureWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                self.window = window
                configureWindow(window)
            }
        }
    }

    private func configureWindow(_ window: NSWindow) {
        // Enable layer-backed views for transparency
        window.contentView?.wantsLayer = true

        // Set background to clear to see the glass effect
        window.isOpaque = false
        window.backgroundColor = .clear
    }
}

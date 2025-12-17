//
//  EditTimeEntryView.swift
//  Liquid Harvest
//
//  Created by Martyn Chamberlin on 11/29/25.
//

import SwiftUI
import AppKit

struct EditTimeEntryView: View {
    let entry: TimeEntry
    let onSave: () async -> Void
    var timerViewModel: TimerViewModel? = nil
    var projectsViewModel: ProjectsViewModel? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var notes: String
    @State private var startedTime: String
    @State private var endedTime: String
    @State private var isLoading = false
    @State private var errorMessage: String?
    @StateObject private var localProjectsViewModel = ProjectsViewModel()
    @State private var selectedProjectId: Int64?
    @State private var selectedTaskId: Int64?
    @State private var showingProjectPicker = false
    @State private var showingTaskPicker = false
    @State private var isInitializing = true

    private let apiClient = HarvestAPIClient.shared

    private var effectiveProjectsViewModel: ProjectsViewModel {
        projectsViewModel ?? localProjectsViewModel
    }

    init(entry: TimeEntry, timerViewModel: TimerViewModel? = nil, projectsViewModel: ProjectsViewModel? = nil, onSave: @escaping () async -> Void) {
        self.entry = entry
        self.timerViewModel = timerViewModel
        self.projectsViewModel = projectsViewModel
        self.onSave = onSave
        _notes = State(initialValue: entry.notes ?? "")
        _startedTime = State(initialValue: entry.startedTime ?? "")
        _endedTime = State(initialValue: entry.endedTime ?? "")
        _selectedProjectId = State(initialValue: entry.project?.id)
        _selectedTaskId = State(initialValue: entry.task?.id)
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 20)

            Text("Edit Time Entry")
                .font(.title2)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                // Project selection
                Button(action: {
                        showingProjectPicker = true
                    }) {
                        HStack {
                            if let projectId = selectedProjectId,
                               let project = effectiveProjectsViewModel.projects.first(where: { $0.id == projectId }) {
                                VStack(alignment: .leading, spacing: 2) {
                                    if let client = project.client {
                                        Text(client.name)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Text(project.name)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                }
                            } else {
                                Text("Select Project")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.down")
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(effectiveProjectsViewModel.isLoading || effectiveProjectsViewModel.projects.isEmpty)

                // Task selection
                Button(action: {
                        showingTaskPicker = true
                    }) {
                        HStack {
                            if let taskId = selectedTaskId,
                               let task = effectiveProjectsViewModel.taskAssignments.first(where: { $0.task.id == taskId })?.task {
                                Text(task.name)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                            } else {
                                Text("Select Task")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.down")
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedProjectId == nil || effectiveProjectsViewModel.taskAssignments.isEmpty)

                TextField("Notes", text: $notes, axis: .vertical)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .font(.system(size: 16))
                    .lineLimit(1...)
                    .textFieldStyle(.roundedBorder)
                    .onAppear {
                        // Prevent text selection when window opens
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            if let window = NSApp.keyWindow,
                               let textField = findTextField(in: window.contentView) {
                                textField.selectText(nil)
                            }
                        }
                    }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start Time")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("HH:MM", text: $startedTime)
                            .font(.body)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                // Save when Enter is pressed in start time field
                                if !isLoading {
                                    saveEntry()
                                }
                            }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("End Time")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("HH:MM", text: $endedTime)
                            .font(.body)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                // Save when Enter is pressed in end time field
                                if !isLoading {
                                    saveEntry()
                                }
                            }
                    }
                }
            }

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.body)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .font(.body)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(action: {
                    saveEntry()
                }) {
                    Text("Save")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color(nsColor: .textBackgroundColor))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .labelColor))
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .keyboardShortcut("s", modifiers: .command)
            }

            Spacer(minLength: 20)
        }
        .padding(25)
        .frame(width: 450)
        .frame(minHeight: 400)
        .fixedSize(horizontal: true, vertical: false)
        .onAppear {
            _Concurrency.Task {
                // Only fetch if not provided and projects are empty
                if effectiveProjectsViewModel.projects.isEmpty {
                    await effectiveProjectsViewModel.loadProjects()
                }

                // Load tasks for the current project if we have one
                if let projectId = selectedProjectId {
                    await effectiveProjectsViewModel.loadTasks(for: projectId)
                }

                isInitializing = false
            }
        }
        .onChange(of: selectedProjectId) { newValue in
            if !isInitializing, let projectId = newValue {
                _Concurrency.Task {
                    await effectiveProjectsViewModel.loadTasks(for: projectId)
                    // Check if current task is still valid in the new project
                    if let currentTaskId = selectedTaskId,
                       effectiveProjectsViewModel.taskAssignments.contains(where: { $0.task.id == currentTaskId }) {
                        // Keep the current task if it's valid
                    } else if let firstTask = effectiveProjectsViewModel.taskAssignments.first {
                        // Otherwise, select the first task
                        selectedTaskId = firstTask.task.id
                    } else {
                        // No tasks available
                        selectedTaskId = nil
                    }
                }
            }
        }
        .sheet(isPresented: $showingProjectPicker) {
            ProjectPickerView(
                projects: effectiveProjectsViewModel.projects,
                selectedProjectId: $selectedProjectId
            )
        }
        .sheet(isPresented: $showingTaskPicker) {
            TaskPickerView(
                taskAssignments: effectiveProjectsViewModel.taskAssignments,
                selectedTaskId: $selectedTaskId
            )
        }
    }

    private func saveEntry() {
        isLoading = true
        errorMessage = nil

        // Validate time format (HH:MM)
        func validateTimeFormat(_ time: String) -> Bool {
            if time.isEmpty {
                return true // Empty is allowed
            }
            let components = time.split(separator: ":")
            guard components.count == 2,
                  let h = Int(components[0]),
                  let m = Int(components[1]),
                  h >= 0 && h < 24,
                  m >= 0 && m < 60 else {
                return false
            }
            return true
        }

        if !startedTime.isEmpty && !validateTimeFormat(startedTime) {
            errorMessage = "Invalid start time format. Use HH:MM (24-hour format)"
            isLoading = false
            return
        }

        if !endedTime.isEmpty && !validateTimeFormat(endedTime) {
            errorMessage = "Invalid end time format. Use HH:MM (24-hour format)"
            isLoading = false
            return
        }

        // Validate project and task are selected
        guard let projectId = selectedProjectId, let taskId = selectedTaskId else {
            errorMessage = "Please select a project and task"
            isLoading = false
            return
        }

        // Normalize time format (ensure two digits for minutes)
        let normalizedStartedTime = startedTime.isEmpty ? nil : normalizeTimeFormat(startedTime)
        let normalizedEndedTime = endedTime.isEmpty ? nil : normalizeTimeFormat(endedTime)

        _Concurrency.Task {
            do {
                let request = TimeEntryRequest(
                    projectId: selectedProjectId,
                    taskId: selectedTaskId,
                    spentDate: nil,
                    startedTime: normalizedStartedTime,
                    endedTime: normalizedEndedTime,
                    hours: nil, // Don't send hours - let Harvest calculate from start/end times
                    notes: notes, // Send empty string to remove notes, nil would skip updating
                    externalReference: nil
                )

                let updatedEntry = try await apiClient.updateTimeEntry(id: entry.id, request: request)

                // If this is the running timer, update the timer view model and refresh
                if let timerViewModel = timerViewModel,
                   let runningTimer = timerViewModel.runningTimer,
                   runningTimer.timeEntry.id == entry.id {
                    // Refresh the running timer to get updated state first
                    await timerViewModel.refreshRunningTimer()

                    // Then update the timer view model's project and task from our local projectsViewModel
                    // This ensures we have the full project object with client information
                    if let projectId = selectedProjectId,
                       let project = effectiveProjectsViewModel.projects.first(where: { $0.id == projectId }) {
                        timerViewModel.selectedProject = project
                    }
                    if let taskId = selectedTaskId,
                       let task = effectiveProjectsViewModel.taskAssignments.first(where: { $0.task.id == taskId })?.task {
                        timerViewModel.selectedHarvestTask = task
                    }
                }

                // Notify that the time entry was updated - include the entry so cache can be updated directly
                NotificationCenter.default.post(
                    name: NSNotification.Name("TimeEntryUpdated"),
                    object: nil,
                    userInfo: ["timeEntry": updatedEntry]
                )

                await onSave()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func normalizeTimeFormat(_ time: String) -> String {
        let components = time.split(separator: ":")
        guard components.count == 2,
              let h = Int(components[0]),
              let m = Int(components[1]) else {
            return time
        }
        return String(format: "%02d:%02d", h, m)
    }
}

// Helper function to find TextField in view hierarchy
private func findTextField(in view: NSView?) -> NSTextField? {
    guard let view = view else { return nil }

    if let textField = view as? NSTextField {
        return textField
    }

    for subview in view.subviews {
        if let textField = findTextField(in: subview) {
            return textField
        }
    }

    return nil
}

#Preview {
    EditTimeEntryView(
        entry: TimeEntry(
            id: 1,
            spentDate: "2025-11-29",
            user: TimeEntryUser(id: 1, name: "Test User"),
            client: nil,
            project: nil,
            task: nil,
            hours: 1.5,
            notes: "Test notes",
            isLocked: false,
            lockedReason: nil,
            isClosed: false,
            isBilled: false,
            timerStartedAt: nil,
            startedTime: "09:00",
            endedTime: "10:30",
            isRunning: false,
            billable: true,
            budgeted: true,
            billableRate: nil,
            costRate: nil,
            createdAt: "2025-11-29T10:00:00Z",
            updatedAt: "2025-11-29T10:00:00Z"
        ),
        timerViewModel: nil,
        onSave: {
            // Preview callback
        }
    )
}


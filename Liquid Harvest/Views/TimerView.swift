//
//  TimerView.swift
//  Liquid Harvest
//
//  Created by Martyn Chamberlin on 11/29/25.
//

import SwiftUI

struct TimerViewContent: View {
    @ObservedObject var runningTimer: RunningTimer
    @ObservedObject var timerViewModel: TimerViewModel

    var body: some View {
        VStack(spacing: 16) {
            // This updates every second because we observe RunningTimer directly
            Text(runningTimer.formattedElapsedTime)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }
}

struct TimerView: View {
    @ObservedObject var timerViewModel: TimerViewModel
    @ObservedObject var projectsViewModel: ProjectsViewModel
    @State private var selectedProjectId: Int64?
    @State private var selectedTaskId: Int64?
    @State private var showingProjectPicker = false
    @State private var showingTaskPicker = false
    @State private var isInitializing = true

    var body: some View {
        VStack(spacing: 20) {
            // Timer display - always show, but show running timer or placeholder
            if let runningTimer = timerViewModel.runningTimer {
                // Running timer display - observe RunningTimer directly for per-second updates
                TimerViewContent(runningTimer: runningTimer, timerViewModel: timerViewModel)
            } else {
                // Placeholder timer display when not running
                Text("00:00:00")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            // Project/Task selection - always visible, but disabled when timer is running
            VStack(alignment: .leading, spacing: 4) {
                if let error = projectsViewModel.errorMessage {
                    Text("Error loading projects: \(error)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.bottom, 4)
                }

                // Show client name if project is selected
                // When timer is running, prioritize client from the selected project (which may have been updated)
                // Otherwise fall back to time entry's client, then project's client
                if timerViewModel.runningTimer != nil {
                    // When timer is running, use project from timerViewModel (which gets updated when project changes)
                    if let project = timerViewModel.selectedProject {
                        if let client = project.client ?? timerViewModel.runningTimer?.timeEntry.client {
                            Text(client.name)
                                .font(.headline)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                                .padding(.bottom, 2)
                        }
                    }
                } else {
                    // When not running, use local state
                    if let projectId = selectedProjectId,
                       let project = projectsViewModel.projects.first(where: { $0.id == projectId }),
                       let client = project.client
                    {
                        Text(client.name)
                            .font(.headline)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 2)
                    }
                }

                Button(action: {
                    if timerViewModel.runningTimer == nil {
                        showingProjectPicker = true
                    }
                }) {
                    HStack {
                        Spacer()
                        if projectsViewModel.isLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Loading projects...")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        } else {
                            let displayProject = timerViewModel.runningTimer != nil ? timerViewModel.selectedProject : (selectedProjectId != nil ? projectsViewModel.projects.first(where: { $0.id == selectedProjectId }) : nil)
                            Text(displayProject?.name ?? (projectsViewModel.projects.isEmpty ? "No projects available" : "Select Project"))
                                .font(.headline)
                                .foregroundStyle(displayProject != nil ? .primary : .secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
                .buttonStyle(.plain)
                .disabled(projectsViewModel.isLoading || projectsViewModel.projects.isEmpty || timerViewModel.runningTimer != nil)
                .opacity(timerViewModel.runningTimer != nil ? 0.6 : 1.0)

                // Always show task selector, even if project not selected (to maintain layout)
                Button(action: {
                    if timerViewModel.runningTimer == nil {
                        showingTaskPicker = true
                    }
                }) {
                    HStack {
                        Spacer()
                        let displayTask = timerViewModel.runningTimer != nil ? timerViewModel.selectedHarvestTask : (selectedTaskId != nil ? projectsViewModel.taskAssignments.first(where: { $0.task.id == selectedTaskId })?.task : nil)
                        Text(displayTask?.name ?? "Select Task")
                            .font(.headline)
                            .foregroundStyle(displayTask != nil ? .primary : .secondary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
                .buttonStyle(.plain)
                .disabled(selectedProjectId == nil || timerViewModel.runningTimer != nil)
                .opacity(timerViewModel.runningTimer != nil ? 0.6 : 1.0)
            }

            // Start/Stop button - always in the same position
            if let runningTimer = timerViewModel.runningTimer {
                Button(action: {
                    _Concurrency.Task {
                        await timerViewModel.stopTimer()
                    }
                }) {
                    HStack {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 21, design: .rounded))
                        Text("Stop")
                            .font(.system(size: 21, weight: .semibold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .foregroundStyle(Color(nsColor: .textBackgroundColor))
                    .background(Color(nsColor: .labelColor))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(timerViewModel.isLoading)
            } else {
                Button(action: {
                    guard let projectId = selectedProjectId,
                          let taskId = selectedTaskId else { return }
                    _Concurrency.Task {
                        await timerViewModel.startTimer(
                            projectId: projectId,
                            taskId: taskId,
                            notes: timerViewModel.description.isEmpty ? nil : timerViewModel.description,
                        )
                    }
                }) {
                    HStack {
                        Image(systemName: "play.fill")
                            .font(.system(size: 21, design: .rounded))
                        Text("Start")
                            .font(.system(size: 21, weight: .semibold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .foregroundStyle(Color(nsColor: .textBackgroundColor))
                    .background(Color(nsColor: .labelColor))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(timerViewModel.isLoading || selectedProjectId == nil || selectedTaskId == nil)
            }

            if let errorMessage = timerViewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
                    .background(.red.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .padding(24)
        .onAppear {
            _Concurrency.Task {
                if projectsViewModel.projects.isEmpty {
                    await projectsViewModel.loadProjects()
                }

                // Pre-populate with most recently used project/task
                // UserDefaults stores numbers as Int/NSNumber, so we need to convert
                var lastProjectId: Int64? = nil
                if let projectIdValue = UserDefaults.standard.object(forKey: "last_used_project_id") {
                    if let intValue = projectIdValue as? Int {
                        lastProjectId = Int64(intValue)
                    } else if let int64Value = projectIdValue as? Int64 {
                        lastProjectId = int64Value
                    } else if let nsNumber = projectIdValue as? NSNumber {
                        lastProjectId = nsNumber.int64Value
                    }
                }

                if let projectId = lastProjectId,
                   projectsViewModel.projects.contains(where: { $0.id == projectId })
                {
                    // Set project ID and load tasks
                    selectedProjectId = projectId
                    await projectsViewModel.loadTasks(for: projectId)

                    // Now check for the task after tasks are loaded
                    var lastTaskId: Int64? = nil
                    if let taskIdValue = UserDefaults.standard.object(forKey: "last_used_task_id") {
                        if let intValue = taskIdValue as? Int {
                            lastTaskId = Int64(intValue)
                        } else if let int64Value = taskIdValue as? Int64 {
                            lastTaskId = int64Value
                        } else if let nsNumber = taskIdValue as? NSNumber {
                            lastTaskId = nsNumber.int64Value
                        }
                    }

                    if let taskId = lastTaskId,
                       projectsViewModel.taskAssignments.contains(where: { $0.task.id == taskId })
                    {
                        selectedTaskId = taskId
                    } else if let firstTask = projectsViewModel.taskAssignments.first {
                        // If last used task is not available, select the first task
                        selectedTaskId = firstTask.task.id
                    }
                }

                // Mark initialization as complete
                isInitializing = false
            }
        }
        .onChange(of: selectedProjectId) { newValue in
            // Only clear task ID if not initializing (to preserve pre-populated task)
            if !isInitializing {
                if let projectId = newValue {
                    _Concurrency.Task {
                        await projectsViewModel.loadTasks(for: projectId)
                        // Select the first task automatically
                        if let firstTask = projectsViewModel.taskAssignments.first {
                            selectedTaskId = firstTask.task.id
                        } else {
                            selectedTaskId = nil
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingProjectPicker) {
            ProjectPickerView(
                projects: projectsViewModel.projects,
                selectedProjectId: $selectedProjectId,
            )
        }
        .sheet(isPresented: $showingTaskPicker) {
            TaskPickerView(
                taskAssignments: projectsViewModel.taskAssignments,
                selectedTaskId: $selectedTaskId,
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleTimer"))) { _ in
            // Toggle timer on spacebar (handled via NSEvent monitoring)
            if let runningTimer = timerViewModel.runningTimer {
                // Timer is running, stop it
                _Concurrency.Task {
                    await timerViewModel.stopTimer()
                }
            } else {
                // Timer is not running, start it if project and task are selected
                guard let projectId = selectedProjectId,
                      let taskId = selectedTaskId else { return }
                _Concurrency.Task {
                    await timerViewModel.startTimer(
                        projectId: projectId,
                        taskId: taskId,
                        notes: timerViewModel.description.isEmpty ? nil : timerViewModel.description,
                    )
                }
            }
        }
    }
}

struct ProjectPickerView: View {
    let projects: [Project]
    @Binding var selectedProjectId: Int64?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(projects) { project in
            Button(action: {
                selectedProjectId = project.id
                dismiss()
            }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .foregroundStyle(.primary)
                    if let client = project.client {
                        Text(client.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .frame(width: 400, height: 300)
    }
}

struct TaskPickerView: View {
    let taskAssignments: [TaskAssignment]
    @Binding var selectedTaskId: Int64?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(taskAssignments) { assignment in
            Button(action: {
                selectedTaskId = assignment.task.id
                dismiss()
            }) {
                Text(assignment.task.name)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 300, height: 300)
    }
}

#Preview {
    TimerView(timerViewModel: TimerViewModel(), projectsViewModel: ProjectsViewModel())
        .padding()
}

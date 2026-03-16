//
//  TimerViewModel.swift
//  Liquid Harvest
//
//  Created by Martyn Chamberlin on 11/29/25.
//

import Combine
import Foundation

@MainActor
class TimerViewModel: ObservableObject {
    @Published var runningTimer: RunningTimer? {
        didSet {
            // Stop old timer updates
            oldValue?.stopUpdating()
        }
    }

    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedProject: Project?
    @Published var selectedHarvestTask: Task?
    @Published var description: String = ""

    private let apiClient = HarvestAPIClient.shared
    private var pollingTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var isRefreshing = false // Guard to prevent duplicate refresh calls

    init() {
        // Don't start polling immediately - wait until authenticated
        // Polling will be started when needed
    }

    deinit {
        // Since deinit is nonisolated, we need to handle cleanup without accessing actor-isolated state
        pollingTimer?.invalidate()
    }

    func startPolling() {
        // Stop any existing polling first
        stopPolling()

        // Poll every 60 seconds (1 minute) to detect external timer changes
        // The local timer display updates every second independently
        Timer.publish(every: 60.0, on: .main, in: .common)
            .autoconnect()
            .sink(receiveValue: { [weak self] _ in
                guard let self else { return }
                refreshRunningTimerAsync()
            })
            .store(in: &cancellables)

        // Immediate check on startup to detect any running timer
        refreshRunningTimerAsync()
    }

    private func refreshRunningTimerAsync() {
        // Use explicit Swift concurrency Task to avoid conflict with Harvest Task model
        _Concurrency.Task { @MainActor [weak self] in
            guard let self else { return }
            await refreshRunningTimer()
        }
    }

    func stopPolling() {
        cancellables.removeAll()
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    func refreshRunningTimer() async {
        // Prevent duplicate concurrent refresh calls
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            if let timeEntry = try await apiClient.getRunningTimer() {
                // Check if this is a different timer or if the timer was restarted
                let isNewTimer = runningTimer?.timeEntry.id != timeEntry.id
                let timerRestarted = runningTimer?.timeEntry.timerStartedAt != timeEntry.timerStartedAt

                // Create a new RunningTimer if it's a different timer, was restarted, or doesn't exist
                if isNewTimer || timerRestarted || runningTimer == nil {
                    runningTimer = RunningTimer(timeEntry: timeEntry)
                }
                // If it's the same timer with the same start time, keep the existing RunningTimer
                // so the elapsed time continues updating smoothly

                // Always update the description and project/task in case they changed externally
                description = timeEntry.notes ?? ""
                selectedProject = timeEntry.project
                selectedHarvestTask = timeEntry.task
            } else {
                // Timer was stopped externally
                runningTimer = nil
                description = ""
                selectedProject = nil
                selectedHarvestTask = nil
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startTimer(projectId: Int64, taskId: Int64, notes: String?) async {
        isLoading = true
        errorMessage = nil

        do {
            // Harvest requires spent_date even for timer entries
            // Format: YYYY-MM-DD (e.g., "2025-11-29")
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let today = formatter.string(from: Date())

            let request = TimeEntryRequest(
                projectId: projectId,
                taskId: taskId,
                spentDate: today,
                startedTime: nil,
                endedTime: nil,
                hours: nil, // No hours for timer entries - they track time automatically
                notes: notes,
                externalReference: nil,
            )

            let timeEntry = try await apiClient.createTimeEntry(request)
            runningTimer = RunningTimer(timeEntry: timeEntry)
            description = timeEntry.notes ?? ""
            selectedProject = timeEntry.project
            selectedHarvestTask = timeEntry.task

            // Store most recently used project and task
            // Store as Int to ensure compatibility with UserDefaults
            UserDefaults.standard.set(Int(projectId), forKey: "last_used_project_id")
            UserDefaults.standard.set(Int(taskId), forKey: "last_used_task_id")

            // Notify that a time entry was created - include the entry in the notification
            NotificationCenter.default.post(
                name: NSNotification.Name("TimeEntryCreated"),
                object: nil,
                userInfo: ["timeEntry": timeEntry],
            )

            isLoading = false
        } catch {
            // If there's already a running timer, treat this as success
            // Refresh to get the current running timer state
            if runningTimer != nil {
                await refreshRunningTimer()
                isLoading = false
                errorMessage = nil
            } else {
                // Check if error indicates timer is already running (422 Unprocessable Entity is common)
                if case let HarvestAPIError.httpError(code) = error, code == 422 {
                    // Timer might already be running, refresh to check
                    await refreshRunningTimer()
                    if runningTimer != nil {
                        // Timer is running, treat as success
                        isLoading = false
                        errorMessage = nil
                    } else {
                        // Still no timer, show error
                        isLoading = false
                        errorMessage = error.localizedDescription
                    }
                } else {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func stopTimer() async {
        guard let timerId = runningTimer?.timeEntry.id else {
            // No timer to stop, treat as success
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let timeEntry = try await apiClient.stopTimeEntry(id: timerId)
            // Clear the running timer immediately
            runningTimer = nil
            description = ""
            selectedProject = nil
            selectedHarvestTask = nil

            // Notify that a time entry was stopped - include the entry in the notification
            NotificationCenter.default.post(
                name: NSNotification.Name("TimeEntryStopped"),
                object: nil,
                userInfo: ["timeEntry": timeEntry],
            )

            isLoading = false
            // Refresh to make sure we're in sync with the server
            await refreshRunningTimer()
        } catch {
            // If timer is already stopped (no running timer after refresh), treat as success
            await refreshRunningTimer()
            if runningTimer == nil {
                // Timer is already stopped, treat as success
                description = ""
                selectedProject = nil
                selectedHarvestTask = nil
                isLoading = false
                errorMessage = nil
            } else {
                // Timer is still running, show error
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func updateDescription(_ newDescription: String) async {
        guard let timerId = runningTimer?.timeEntry.id else { return }

        errorMessage = nil

        do {
            let request = TimeEntryRequest(
                projectId: nil,
                taskId: nil,
                spentDate: nil,
                startedTime: nil,
                endedTime: nil,
                hours: nil,
                notes: newDescription,
                externalReference: nil,
            )

            let updatedEntry = try await apiClient.updateTimeEntry(id: timerId, request: request)
            // Update the running timer with the new entry (preserves the timer state)
            runningTimer = RunningTimer(timeEntry: updatedEntry)
            description = newDescription

            // Notify that the timer was updated - include the updated entry so cache can be updated directly
            NotificationCenter.default.post(
                name: NSNotification.Name("TimerUpdated"),
                object: nil,
                userInfo: ["timeEntry": updatedEntry],
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

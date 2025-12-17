//
//  TodayTimeEntriesView.swift
//  Liquid Harvest
//
//  Created by Martyn Chamberlin on 11/29/25.
//

import SwiftUI
import Combine
import AppKit

struct TodayTimeEntriesView: View {
    @StateObject private var viewModel = TodayTimeEntriesViewModel()
    @StateObject private var projectsViewModel = ProjectsViewModel()
    @State private var selectedDate = Date()
    @State private var weekStartDate: Date = {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7 // Convert Sunday=1 to Monday=0
        return calendar.date(byAdding: .day, value: -daysFromMonday, to: today) ?? today
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Week row navigation
            WeekRowView(
                weekStartDate: $weekStartDate,
                selectedDate: $selectedDate,
                timeEntriesByDate: viewModel.timeEntriesByDate
            )

            // Date header
            HStack {
                Text(selectedDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.headline)
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            // Time entries list
            if let error = viewModel.errorMessage {
                Text("Error: \(error)")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if !viewModel.timeEntries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.timeEntries) { entry in
                        // Note: TodayTimeEntriesView doesn't have timerViewModel, so timer updates won't work here
                        // Use TimeEntriesListView instead for timer updates
                        TimeEntryRowView(entry: entry, selectedDate: selectedDate, viewModel: viewModel, timerViewModel: TimerViewModel(), projectsViewModel: projectsViewModel)
                    }
                }
            }
        }
        .padding()
        .onAppear {
            _Concurrency.Task {
                await viewModel.loadEntries(for: selectedDate)
            }
        }
        .onChange(of: selectedDate) { oldDate, newDate in
            _Concurrency.Task {
                await viewModel.loadEntries(for: newDate)
            }
        }
        .onChange(of: weekStartDate) { oldDate, newDate in
            // When week changes, clear old data and preload new week in background
            viewModel.clearOldWeekData(keepWeekAround: newDate)
            // Preload new week entries in background (non-blocking, async)
            _Concurrency.Task {
                await viewModel.preloadWeekEntries(around: newDate)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TimerUpdated"))) { notification in
            // Update cache directly if we have the updated entry, otherwise refresh
            if let timeEntry = notification.userInfo?["timeEntry"] as? TimeEntry {
                viewModel.addOrUpdateTimeEntry(timeEntry, forSelectedDate: selectedDate)
            } else {
                // Fallback: refresh if no entry provided
                _Concurrency.Task {
                    await viewModel.loadEntries(for: selectedDate)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TimeEntryCreated"))) { notification in
            // Update cache when a time entry is created
            if let timeEntry = notification.userInfo?["timeEntry"] as? TimeEntry {
                viewModel.addOrUpdateTimeEntry(timeEntry, forSelectedDate: selectedDate)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TimeEntryStopped"))) { notification in
            // Update cache when a time entry is stopped
            if let timeEntry = notification.userInfo?["timeEntry"] as? TimeEntry {
                viewModel.addOrUpdateTimeEntry(timeEntry, forSelectedDate: selectedDate)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TimeEntryUpdated"))) { notification in
            // Update cache when a time entry is updated (e.g., from EditTimeEntryView)
            if let timeEntry = notification.userInfo?["timeEntry"] as? TimeEntry {
                viewModel.addOrUpdateTimeEntry(timeEntry, forSelectedDate: selectedDate)
            }
        }
    }
}

// Separate view for just the time entries list (without week row)
struct TimeEntriesListView: View {
    @ObservedObject var viewModel: TodayTimeEntriesViewModel
    @ObservedObject var timerViewModel: TimerViewModel
    @ObservedObject var projectsViewModel: ProjectsViewModel
    @Binding var selectedDate: Date
    var isChangingWeek: Bool = false // Flag to prevent duplicate fetches when week changes

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Time entries list
            if let error = viewModel.errorMessage {
                Text("Error: \(error)")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if !viewModel.timeEntries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.timeEntries) { entry in
                        TimeEntryRowView(entry: entry, selectedDate: selectedDate, viewModel: viewModel, timerViewModel: timerViewModel, projectsViewModel: projectsViewModel)
                    }
                }
            }
        }
        .onAppear {
            // Immediately show cached data if available
            let dateString = dateFormatter.string(from: selectedDate)
            if let cachedEntries = viewModel.timeEntriesByDate[dateString] {
                viewModel.timeEntries = cachedEntries
                viewModel.isLoading = false
                viewModel.errorMessage = nil
            }

            _Concurrency.Task { @MainActor in
                await viewModel.loadEntries(for: selectedDate)
            }
        }
        .onChange(of: selectedDate) { oldDate, newDate in
            // Skip if this change was triggered by a week change (to prevent duplicate fetches)
            if isChangingWeek {
                return
            }

            // Immediately show cached data if available to avoid blink
            // Update synchronously (we're already on main thread)
            let dateString = dateFormatter.string(from: newDate)
            if let cachedEntries = viewModel.timeEntriesByDate[dateString] {
                viewModel.timeEntries = cachedEntries
                viewModel.isLoading = false
                viewModel.errorMessage = nil
                // If we have cached data for this date, check if we need to preload the week
                // Only preload if the week is not fully cached
                _Concurrency.Task { @MainActor in
                    // Check if entire week is cached before calling preloadWeekEntries
                    let calendar = Calendar.current
                    let weekday = calendar.component(.weekday, from: newDate)
                    let daysFromMonday = (weekday + 5) % 7
                    if let weekStart = calendar.date(byAdding: .day, value: -daysFromMonday, to: newDate) {
                        var allDaysCached = true
                        for dayOffset in 0..<7 {
                            guard let weekDate = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else { continue }
                            let dayString = dateFormatter.string(from: weekDate)
                            if viewModel.timeEntriesByDate[dayString] == nil {
                                allDaysCached = false
                                break
                            }
                        }
                        // Only preload if week is not fully cached
                        if !allDaysCached {
                            await viewModel.preloadWeekEntries(around: newDate)
                        }
                    }
                }
            } else {
                // No cached data, fetch it
                _Concurrency.Task { @MainActor in
                    await viewModel.loadEntries(for: newDate)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TimerUpdated"))) { notification in
            // Update cache directly if we have the updated entry, otherwise refresh
            if let timeEntry = notification.userInfo?["timeEntry"] as? TimeEntry {
                viewModel.addOrUpdateTimeEntry(timeEntry, forSelectedDate: selectedDate)
            } else {
                // Fallback: refresh if no entry provided
                _Concurrency.Task {
                    await viewModel.loadEntries(for: selectedDate)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TimeEntryCreated"))) { notification in
            // Update cache when a time entry is created
            if let timeEntry = notification.userInfo?["timeEntry"] as? TimeEntry {
                viewModel.addOrUpdateTimeEntry(timeEntry, forSelectedDate: selectedDate)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TimeEntryStopped"))) { notification in
            // Update cache when a time entry is stopped
            if let timeEntry = notification.userInfo?["timeEntry"] as? TimeEntry {
                viewModel.addOrUpdateTimeEntry(timeEntry, forSelectedDate: selectedDate)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TimeEntryUpdated"))) { notification in
            // Update cache when a time entry is updated (e.g., from EditTimeEntryView)
            if let timeEntry = notification.userInfo?["timeEntry"] as? TimeEntry {
                viewModel.addOrUpdateTimeEntry(timeEntry, forSelectedDate: selectedDate)
            }
        }
    }
}

struct WeekRowView: View {
    @Binding var weekStartDate: Date
    @Binding var selectedDate: Date
    let timeEntriesByDate: [String: [TimeEntry]]
    var timerViewModel: TimerViewModel? = nil
    var onDateSelected: ((Date) -> Void)? = nil

    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current // Use local timezone
        return formatter
    }()

    private var weekDays: [Date] {
        (0..<7).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: weekStartDate)
        }
    }

    private func totalHours(for date: Date) -> Double {
        let dateString = dateFormatter.string(from: date)
        let entries = timeEntriesByDate[dateString] ?? []

        // Check if there's a running timer for this date
        let runningTimerEntryId = timerViewModel?.runningTimer?.timeEntry.id

        return entries.reduce(0.0) { total, entry in
            // If this entry is the running timer, use live elapsed time instead of static hours
            if entry.id == runningTimerEntryId, let elapsed = timerViewModel?.runningTimer?.elapsedTime {
                return total + (elapsed / 3600.0) // Convert seconds to hours
            } else {
                return total + (entry.hours ?? 0.0)
            }
        }
    }

    private func formatHours(_ hours: Double) -> String {
        let totalMinutes = Int(hours * 60)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 {
            return "\(h):\(String(format: "%02d", m))"
        } else {
            return "0:\(String(format: "%02d", m))"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Previous week button
            Button(action: {
                if let newStart = calendar.date(byAdding: .day, value: -7, to: weekStartDate) {
                    weekStartDate = newStart
                }
            }) {
                Image(systemName: "chevron.left")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            // Days of week
            HStack(spacing: 8) {
                ForEach(Array(weekDays.enumerated()), id: \.element) { index, date in
                    let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                    let isToday = calendar.isDateInToday(date)
                    let hours = totalHours(for: date)

                    VStack(spacing: 4) {
                        // Day letter
                        Text(dayLetter(for: date))
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color(nsColor: .textBackgroundColor) : .secondary)
                            .frame(width: 28, height: 28)
                            .background(isSelected ? Color(nsColor: .labelColor) : (isToday ? Color.secondary.opacity(0.2) : Color.clear), in: Circle())

                        // Hours
                        Text(formatHours(hours))
                            .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                            .foregroundStyle(isSelected ? Color(nsColor: .labelColor) : Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Call the callback first to update view model synchronously
                        onDateSelected?(date)
                        // Then update the binding
                        selectedDate = date
                    }
                }
            }

            // Next week button
            Button(action: {
                if let newStart = calendar.date(byAdding: .day, value: 7, to: weekStartDate) {
                    weekStartDate = newStart
                }
            }) {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .onChange(of: timerViewModel?.runningTimer?.elapsedTime) { _, _ in
            // Force view update when timer increments - this triggers a re-render
        }
        .onChange(of: timerViewModel?.runningTimer?.timeEntry.id) { _, _ in
            // Force view update when timer changes
        }
        .background {
            // Helper view to observe timer updates for week view
            if let timerViewModel = timerViewModel,
               let runningTimer = timerViewModel.runningTimer {
                Color.clear
                    .onReceive(runningTimer.$elapsedTime) { _ in
                        // This will trigger a re-render of the parent view
                    }
            }
        }
    }

    private func dayLetter(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE" // Single letter day
        return formatter.string(from: date)
    }
}

// Helper view to observe RunningTimer - similar to TimerViewContent
// This ensures SwiftUI properly tracks the RunningTimer object
struct TimerObserverView: View {
    @ObservedObject var runningTimer: RunningTimer
    let onUpdate: (TimeInterval) -> Void

    var body: some View {
        Color.clear
            .onReceive(runningTimer.$elapsedTime) { elapsedTime in
                onUpdate(elapsedTime)
            }
    }
}

// View that displays elapsed time with a blinking colon
struct BlinkingTimerView: View {
    let elapsedTime: TimeInterval
    @State private var showColon = true
    @State private var timer: Timer?

    var body: some View {
        let (hours, minutes, seconds) = formatElapsedTime(elapsedTime)

        HStack(spacing: 0) {
            if hours > 0 {
                Text(String(format: "%d", hours))
                    .font(.body)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(.primary)

                Text(":")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .opacity(showColon ? 1.0 : 0.0)

                Text(String(format: "%02d", minutes))
                    .font(.body)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(.primary)

                Text(":")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .opacity(showColon ? 1.0 : 0.0)

                Text(String(format: "%02d", seconds))
                    .font(.body)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            } else {
                Text(String(format: "%d", minutes))
                    .font(.body)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(.primary)

                Text(":")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .opacity(showColon ? 1.0 : 0.0)

                Text(String(format: "%02d", seconds))
                    .font(.body)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
        }
        .onAppear {
            // Start blinking timer - toggle every second
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.5)) {
                    showColon.toggle()
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func formatElapsedTime(_ elapsed: TimeInterval) -> (hours: Int, minutes: Int, seconds: Int) {
        let totalSeconds = Int(elapsed)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return (hours, minutes, seconds)
    }
}

// Container that observes TimerViewModel and conditionally observes RunningTimer
struct TimerObserverContainer: View {
    @ObservedObject var timerViewModel: TimerViewModel
    let entryId: Int64
    let onElapsedTimeUpdate: (TimeInterval) -> Void

    var body: some View {
        Group {
            // When timerViewModel changes, this will re-evaluate
            if let runningTimer = timerViewModel.runningTimer,
               runningTimer.timeEntry.id == entryId {
                // Observe the RunningTimer directly
                TimerObserverView(runningTimer: runningTimer) { elapsedTime in
                    onElapsedTimeUpdate(elapsedTime)
                }
            } else {
                Color.clear
            }
        }
    }
}

struct TimeEntryRowView: View {
    let entry: TimeEntry
    let selectedDate: Date
    @State private var showingDeleteAlert = false
    @State private var isDeleting = false
    @ObservedObject var viewModel: TodayTimeEntriesViewModel
    @ObservedObject var timerViewModel: TimerViewModel
    @ObservedObject var projectsViewModel: ProjectsViewModel
    @State private var isHovered = false
    @State private var showingEditSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    if let project = entry.project {
                        if let client = entry.client {
                            Text(client.name)
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                        Text(project.name)
                            .font(.body)
                            .fontWeight(.medium)

                        if let task = entry.task {
                            Text(task.name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if let startedTime = entry.startedTime, let endedTime = entry.endedTime {
                        Text("\(startedTime) - \(endedTime)")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    } else if let startedTime = entry.startedTime {
                        Text(startedTime)
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }

                    // Check if this entry matches the running timer FIRST (regardless of entry.isRunning flag)
                    if let runningTimer = timerViewModel.runningTimer,
                       runningTimer.timeEntry.id == entry.id {
                        // This entry matches the running timer - show the same elapsed time as the big timer
                        // Directly use runningTimer.elapsedTime - it will update automatically because we observe timerViewModel
                        BlinkingTimerView(elapsedTime: runningTimer.elapsedTime)
                    } else if let hours = entry.hours {
                        Text(formatHours(hours))
                            .font(.body)
                            .fontWeight(.medium)
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    } else if entry.isRunning {
                        Text("Running")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(.green)
                    }
                }
            }

            if let notes = entry.notes, !notes.isEmpty {
                Text(notes)
                    .font(.system(size: 15))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onTapGesture {
            showingEditSheet = true
        }
        .sheet(isPresented: $showingEditSheet) {
            EditTimeEntryView(
                entry: entry,
                timerViewModel: timerViewModel,
                projectsViewModel: projectsViewModel,
                onSave: {
                    await viewModel.loadEntries(for: selectedDate)
                }
            )
        }
        .contextMenu {
            Button(action: {
                showingEditSheet = true
            }) {
                Label("Edit", systemImage: "pencil")
            }

            Button(role: .destructive, action: {
                showingDeleteAlert = true
            }) {
                Label("Delete", systemImage: "trash")
            }
            .disabled(isDeleting)
        }
        .alert("Delete Time Entry", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteEntry()
            }
        } message: {
            Text("Are you sure you want to delete this time entry? This action cannot be undone.")
        }
        // If this entry matches the running timer, observe it directly to get real-time updates
        // This is the same pattern as TimerViewContent - directly observe the RunningTimer
        .background {
            if let runningTimer = timerViewModel.runningTimer,
               runningTimer.timeEntry.id == entry.id {
                // Observe the RunningTimer directly - same as TimerViewContent does
                // This ensures the view updates when elapsedTime changes
                TimerObserverView(runningTimer: runningTimer) { _ in }
            }
        }
    }


    private func deleteEntry() {
        isDeleting = true
        _Concurrency.Task {
            do {
                // If this is the running timer, stop it first
                if let runningTimer = timerViewModel.runningTimer,
                   runningTimer.timeEntry.id == entry.id {
                    // Stop the timer - this will clear runningTimer and update the UI
                    await timerViewModel.stopTimer()
                    // Wait a moment to ensure the timer state is updated
                    try await _Concurrency.Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                }

                try await HarvestAPIClient.shared.deleteTimeEntry(id: entry.id)
                // Remove from cache directly instead of refetching
                viewModel.removeTimeEntry(entry, forSelectedDate: selectedDate)
                isDeleting = false
            } catch {
                // If entry is already deleted (404), treat as success
                if case HarvestAPIError.httpError(let code) = error, code == 404 {
                    // Entry already deleted, remove from cache and treat as success
                    viewModel.removeTimeEntry(entry, forSelectedDate: selectedDate)
                    isDeleting = false
                } else {
                    print("Failed to delete entry: \(error)")
                    isDeleting = false
                }
            }
        }
    }

    private func formatHours(_ hours: Double) -> String {
        let totalMinutes = Int(hours * 60)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 {
            return "\(h)h \(m)m"
        } else {
            return "\(m)m"
        }
    }

    private func formatElapsedTime(_ elapsed: TimeInterval) -> String {
        let totalSeconds = Int(elapsed)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

@MainActor
class TodayTimeEntriesViewModel: ObservableObject {
    @Published var timeEntries: [TimeEntry] = []
    @Published var timeEntriesByDate: [String: [TimeEntry]] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let apiClient = HarvestAPIClient.shared
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current // Use local timezone, not UTC
        return formatter
    }()

    /// Sort time entries by their start/stop time, with newest (most recent start time) at the top.
    /// Uses startedTime (actual work time) if available, otherwise timerStartedAt (for running timers),
    /// otherwise createdAt as fallback.
    private func sortTimeEntries(_ entries: [TimeEntry]) -> [TimeEntry] {
        return entries.sorted { entry1, entry2 in
            // Helper to get a Date object representing when the work started for sorting
            func getStartDate(for entry: TimeEntry) -> Date? {
                // First priority: startedTime (the actual start time of work)
                // Combine spentDate with startedTime to create a full timestamp
                if let startedTime = entry.startedTime, !startedTime.isEmpty {
                    // Parse spentDate (YYYY-MM-DD) and startedTime (HH:MM)
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd"
                    dateFormatter.timeZone = TimeZone.current

                    guard let date = dateFormatter.date(from: entry.spentDate) else {
                        return nil
                    }

                    // Parse the time component
                    let timeComponents = startedTime.split(separator: ":")
                    guard timeComponents.count == 2,
                          let hour = Int(timeComponents[0]),
                          let minute = Int(timeComponents[1]) else {
                        return nil
                    }

                    // Combine date and time
                    var calendar = Calendar.current
                    calendar.timeZone = TimeZone.current
                    return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)
                }

                // Second priority: timerStartedAt (for running timers, this is when work started)
                if let timerStartedAt = entry.timerStartedAt {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let date = formatter.date(from: timerStartedAt) {
                        return date
                    }
                    // Fallback: try without fractional seconds
                    formatter.formatOptions = [.withInternetDateTime]
                    return formatter.date(from: timerStartedAt)
                }

                // Last resort: createdAt
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: entry.createdAt) {
                    return date
                }
                formatter.formatOptions = [.withInternetDateTime]
                return formatter.date(from: entry.createdAt)
            }

            let date1 = getStartDate(for: entry1) ?? Date.distantPast
            let date2 = getStartDate(for: entry2) ?? Date.distantPast

            // Sort descending (newest/most recent start time first)
            return date1 > date2
        }
    }

    func loadEntries(for date: Date, forceRefresh: Bool = false, skipPreload: Bool = false) async {
        let dateString = dateFormatter.string(from: date)

        // If we have cached data and not forcing refresh, just show cached data
        if !forceRefresh, let cachedEntries = timeEntriesByDate[dateString] {
            // Ensure we're showing the cached data (might have been set in onChange already)
            // Only update if different to avoid unnecessary view updates
            if timeEntries != cachedEntries {
                timeEntries = cachedEntries
            }
            // Never set loading state if we have cached data
            isLoading = false
            errorMessage = nil

            // Preload the rest of the week in background if not already loaded
            if !skipPreload {
                await preloadWeekEntries(around: date)
            }
            return // Don't fetch if we already have data
        }

        // No cache or forcing refresh
        // Only set loading state if we don't have cached data AND we don't already have entries showing
        // This prevents the blink when switching between cached dates
        let hasCachedData = timeEntriesByDate[dateString] != nil
        let hasEntriesShowing = !timeEntries.isEmpty

        if !forceRefresh {
            // Only show loading if we don't have cached data AND we don't have any entries showing
            if !hasCachedData && !hasEntriesShowing {
                isLoading = true
            }
        } else {
            // When forcing refresh, only show loading if we don't have cached data
            // But keep existing entries visible while refreshing
            if !hasCachedData {
                isLoading = true
            }
        }
        errorMessage = nil

        // Fetch entire week in one request, then filter to the selected date
        // This is more efficient than fetching each day separately
        do {
            let calendar = Calendar.current
            let weekday = calendar.component(.weekday, from: date)
            let daysFromMonday = (weekday + 5) % 7
            guard let weekStart = calendar.date(byAdding: .day, value: -daysFromMonday, to: date),
                  let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
                // Fallback to single day fetch if date calculation fails
                let allEntries = try await apiClient.getTimeEntries(spentDate: dateString)
                let entries = sortTimeEntries(allEntries.filter { entry in entry.spentDate == dateString })
                timeEntries = entries
                timeEntriesByDate[dateString] = entries
                isLoading = false
                return
            }

            let weekStartString = dateFormatter.string(from: weekStart)
            let weekEndString = dateFormatter.string(from: weekEnd)

            // Fetch entire week in one request
            let allEntries = try await apiClient.getTimeEntries(from: weekStartString, to: weekEndString)

            // Group entries by date
            let entriesByDate = Dictionary(grouping: allEntries) { $0.spentDate }

            // Update cache for all days in the week, sorting each day's entries
            for dayOffset in 0..<7 {
                guard let weekDate = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else { continue }
                let dayString = dateFormatter.string(from: weekDate)
                let dayEntries = entriesByDate[dayString] ?? []
                timeEntriesByDate[dayString] = sortTimeEntries(dayEntries)
            }

            // Update displayed entries for selected date
            timeEntries = timeEntriesByDate[dateString] ?? []

            isLoading = false
        } catch {
            // Only show error if we don't have cached data
            if timeEntriesByDate[dateString] == nil {
                errorMessage = error.localizedDescription
                isLoading = false
            }
            print("Failed to load entries: \(error)")
        }
    }

    func refreshCurrentWeek(around date: Date) async {
        // Force refresh the entire week using a single API call
        await preloadWeekEntries(around: date, forceRefresh: true)

        // Update the currently selected date's entries
        let dateString = dateFormatter.string(from: date)
        if let cachedEntries = timeEntriesByDate[dateString] {
            timeEntries = cachedEntries
        }
    }

    private var isPreloadingWeek: [String: Bool] = [:] // Track which weeks are currently being preloaded

    func preloadWeekEntries(around date: Date, forceRefresh: Bool = false) async {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let daysFromMonday = (weekday + 5) % 7
        guard let weekStart = calendar.date(byAdding: .day, value: -daysFromMonday, to: date),
              let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else { return }

        let weekStartString = dateFormatter.string(from: weekStart)
        let weekEndString = dateFormatter.string(from: weekEnd)
        let weekKey = "\(weekStartString)-\(weekEndString)"

        // Check if we already have all days cached (unless forcing refresh)
        if !forceRefresh {
            let today = Date()
            var allCached = true
            var missingDays: [String] = []
            for dayOffset in 0..<7 {
                guard let weekDate = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else { continue }
                let dateString = dateFormatter.string(from: weekDate)
                // Check if cached (even if empty array, it's still cached)
                // For future dates (after today), consider them cached if they exist OR if they're in the future
                let isFutureDate = weekDate > today
                if timeEntriesByDate[dateString] == nil {
                    if isFutureDate {
                        // Pre-populate future dates with empty arrays so they're considered cached
                        timeEntriesByDate[dateString] = []
                    } else {
                        // Past or today dates need to be in cache
                        allCached = false
                        missingDays.append(dateString)
                    }
                }
            }
            if allCached {
                // All days already cached, no need to fetch
                print("✅ Week \(weekStartString) to \(weekEndString) is fully cached, skipping fetch")
                return
            }

            // Check if we're already preloading this week (prevent duplicate requests)
            if isPreloadingWeek[weekKey] == true {
                print("⏳ Week \(weekStartString) to \(weekEndString) is already being preloaded, skipping duplicate request")
                return
            }

            print("⚠️ Week \(weekStartString) to \(weekEndString) missing cached days: \(missingDays.joined(separator: ", "))")
        }

        // Mark this week as being preloaded
        isPreloadingWeek[weekKey] = true
        defer {
            isPreloadingWeek[weekKey] = false
        }

        // Fetch entire week in a single request using from/to date range
        do {
            let allEntries = try await apiClient.getTimeEntries(from: weekStartString, to: weekEndString)

            // Group entries by date and update cache
            let entriesByDate = Dictionary(grouping: allEntries) { $0.spentDate }

            print("📦 Fetched \(allEntries.count) entries for week \(weekStartString) to \(weekEndString)")
            print("   API spentDate keys: \(Array(entriesByDate.keys).sorted().joined(separator: ", "))")

            // Update cache for each day in the week, sorting each day's entries
            let today = Date()
            for dayOffset in 0..<7 {
                guard let weekDate = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else { continue }
                let dateString = dateFormatter.string(from: weekDate)
                let entries = entriesByDate[dateString] ?? []
                timeEntriesByDate[dateString] = sortTimeEntries(entries)
                if !entries.isEmpty {
                    print("   ✅ Cached \(entries.count) entries for \(dateString)")
                } else if weekDate > today {
                    // Future dates with no entries - still cache empty array
                    print("   ✅ Cached empty array for future date \(dateString)")
                }
            }
            print("   📋 Total cache keys after update: \(timeEntriesByDate.keys.sorted().joined(separator: ", "))")
        } catch {
            // Silently fail for preloading - set empty arrays so we don't retry
            for dayOffset in 0..<7 {
                guard let weekDate = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else { continue }
                let dateString = dateFormatter.string(from: weekDate)
                // Only set empty array if not already cached (don't overwrite existing cache on error)
                if timeEntriesByDate[dateString] == nil {
                    timeEntriesByDate[dateString] = []
                }
            }
            print("Failed to preload week entries: \(error)")
        }
    }

    func addOrUpdateTimeEntry(_ entry: TimeEntry, forSelectedDate selectedDate: Date? = nil) {
        // Add or update a time entry in the cache
        let dateString = entry.spentDate

        // Get current entries for this date, or create empty array
        var entries = timeEntriesByDate[dateString] ?? []

        // Check if entry already exists (by ID) and update it, or add new one
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }

        // Always sort entries consistently after adding/updating
        entries = sortTimeEntries(entries)

        timeEntriesByDate[dateString] = entries

        // If this date is currently displayed, update the displayed entries
        if let selectedDate = selectedDate {
            let selectedDateString = dateFormatter.string(from: selectedDate)
            if dateString == selectedDateString {
                timeEntries = entries
            }
        } else if let firstEntry = timeEntries.first, firstEntry.spentDate == dateString {
            // Fallback: check if first entry matches
            timeEntries = entries
        }
    }

    func removeTimeEntry(_ entry: TimeEntry, forSelectedDate selectedDate: Date? = nil) {
        // Remove a time entry from the cache
        let dateString = entry.spentDate

        guard var entries = timeEntriesByDate[dateString] else { return }
        entries.removeAll { $0.id == entry.id }
        timeEntriesByDate[dateString] = entries

        // If this date is currently displayed, update the displayed entries
        if let selectedDate = selectedDate {
            let selectedDateString = dateFormatter.string(from: selectedDate)
            if dateString == selectedDateString {
                timeEntries = entries
            }
        } else if let firstEntry = timeEntries.first, firstEntry.spentDate == dateString {
            // Fallback: check if first entry matches
            timeEntries = entries
        }
    }

    func clearOldWeekData(keepWeekAround date: Date) {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let daysFromMonday = (weekday + 5) % 7
        guard let weekStart = calendar.date(byAdding: .day, value: -daysFromMonday, to: date) else { return }

        // Calculate date range: keep current week plus 1 week before and 1 week after (3 weeks total)
        guard let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart),
              let keepStart = calendar.date(byAdding: .day, value: -7, to: weekStart),
              let keepEnd = calendar.date(byAdding: .day, value: 6, to: weekEnd) else { return }

        let keepStartString = dateFormatter.string(from: keepStart)
        let keepEndString = dateFormatter.string(from: keepEnd)

        // Remove entries outside the 3-week window to free memory
        let keysToRemove = timeEntriesByDate.keys.filter { dateKey in
            dateKey < keepStartString || dateKey > keepEndString
        }

        if !keysToRemove.isEmpty {
            print("🗑️ Clearing \(keysToRemove.count) old cache entries outside 3-week window (\(keepStartString) to \(keepEndString))")
            print("   Keys being removed: \(keysToRemove.joined(separator: ", "))")
            print("   Keys being kept: \(timeEntriesByDate.keys.filter { !keysToRemove.contains($0) }.sorted().joined(separator: ", "))")
        }

        for key in keysToRemove {
            timeEntriesByDate.removeValue(forKey: key)
        }
    }

}

#Preview {
    TodayTimeEntriesView()
        .padding()
}


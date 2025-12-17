//
//  WindowView.swift
//  Liquid Harvest
//
//  Created by Martyn Chamberlin on 11/29/25.
//

import SwiftUI
import AppKit

struct WindowView: View {
    @StateObject private var timerViewModel = TimerViewModel()
    @StateObject private var timeEntriesViewModel = TodayTimeEntriesViewModel()
    @StateObject private var projectsViewModel = ProjectsViewModel()
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @State private var hasClientID: Bool = WindowView.hasOAuthCredentials()
    @State private var selectedDate = Date()
    @State private var isChangingWeek = false // Flag to prevent duplicate fetches when week changes
    @State private var weekStartDate: Date = {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7 // Convert Sunday=1 to Monday=0
        return calendar.date(byAdding: .day, value: -daysFromMonday, to: today) ?? today
    }()

    var body: some View {
        Group {
            if hasClientID {
                if authViewModel.isAuthenticated {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Date header at the very top
                            ZStack {
                                // Centered date text - clickable to go to today
                                Button(action: {
                                    let today = Date()
                                    let calendar = Calendar.current
                                    let weekday = calendar.component(.weekday, from: today)
                                    let daysFromMonday = (weekday + 5) % 7
                                    if let weekStart = calendar.date(byAdding: .day, value: -daysFromMonday, to: today) {
                                        weekStartDate = weekStart
                                    }
                                    selectedDate = today
                                }) {
                                    Text(selectedDate.formatted(date: .abbreviated, time: .omitted))
                                        .font(.headline)
                                }
                                .buttonStyle(.plain)

                                // Spinner on the right, doesn't affect centering
                                HStack {
                                    Spacer()
                                    if timeEntriesViewModel.isLoading {
                                        ProgressView()
                                            .scaleEffect(0.4)
                                            .frame(width: 12, height: 12)
                                    } else {
                                        // Reserve space for spinner to prevent layout shift
                                        Color.clear
                                            .frame(width: 12, height: 12)
                                    }
                                }
                            }
                            .padding(.top, 8)

                            // Week row calendar view
                            WeekRowView(
                                weekStartDate: $weekStartDate,
                                selectedDate: $selectedDate,
                                timeEntriesByDate: timeEntriesViewModel.timeEntriesByDate,
                                timerViewModel: timerViewModel,
                                onDateSelected: { date in
                                    // Update view model synchronously before selectedDate changes
                                    let dateFormatter = DateFormatter()
                                    dateFormatter.dateFormat = "yyyy-MM-dd"
                                    dateFormatter.timeZone = TimeZone.current
                                    let dateString = dateFormatter.string(from: date)
                                    if let cachedEntries = timeEntriesViewModel.timeEntriesByDate[dateString] {
                                        timeEntriesViewModel.timeEntries = cachedEntries
                                        timeEntriesViewModel.isLoading = false
                                        timeEntriesViewModel.errorMessage = nil
                                    }
                                }
                            )

                            // Starting a timer
                            TimerView(timerViewModel: timerViewModel, projectsViewModel: projectsViewModel)

                            // Notes log (time entries list)
                            TimeEntriesListView(
                                viewModel: timeEntriesViewModel,
                                timerViewModel: timerViewModel,
                                projectsViewModel: projectsViewModel,
                                selectedDate: $selectedDate,
                                isChangingWeek: isChangingWeek
                            )
                            .id(timerViewModel.runningTimer?.timeEntry.id ?? 0)
                        }
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                    }
                    .frame(minWidth: 500, minHeight: 400)
                    .glassEffect()
                    .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshTimeEntries"))) { _ in
                        // Refresh current week and timer status when CMD+R is pressed
                        _Concurrency.Task {
                            await timeEntriesViewModel.refreshCurrentWeek(around: selectedDate)
                            await timerViewModel.refreshRunningTimer()
                        }
                    }
                } else {
                    LoginView()
                }
            } else {
                SetupView {
                    hasClientID = WindowView.hasOAuthCredentials()
                }
            }
        }
        .onAppear {
            // Setup and check authentication when view appears
            authViewModel.setupSubscriptionsIfNeeded()
            if hasClientID {
                authViewModel.checkAuthentication()
                // Check for running timer immediately when authenticated
                if authViewModel.isAuthenticated {
                    _Concurrency.Task {
                        await timerViewModel.refreshRunningTimer()
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            navigateToToday()
        }
        .onChange(of: authViewModel.isAuthenticated) { oldValue, newValue in
            if newValue {
                // Check for running timer immediately when authenticated
                _Concurrency.Task {
                    await timerViewModel.refreshRunningTimer()
                }
            } else {
                // Clear timer when logged out
                timerViewModel.runningTimer = nil
            }
        }
        .onChange(of: weekStartDate) { oldDate, newDate in
            // Set flag to prevent selectedDate onChange from also fetching
            isChangingWeek = true

            // When week changes, update selectedDate to first day of new week if current date is outside
            let calendar = Calendar.current
            let weekday = calendar.component(.weekday, from: newDate)
            let daysFromMonday = (weekday + 5) % 7
            if let weekStart = calendar.date(byAdding: .day, value: -daysFromMonday, to: newDate),
               let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) {

                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                dateFormatter.timeZone = TimeZone.current

                // Check if current selectedDate is within the new week
                let isInNewWeek = selectedDate >= weekStart && selectedDate <= weekEnd

                // Check if entire week is already cached BEFORE clearing old data
                let today = Date()
                var allDaysCached = true
                var cachedDays: [String] = []
                var missingDays: [String] = []
                for dayOffset in 0..<7 {
                    guard let weekDate = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else { continue }
                    let dateString = dateFormatter.string(from: weekDate)
                    let isFutureDate = weekDate > today
                    if timeEntriesViewModel.timeEntriesByDate[dateString] == nil {
                        if isFutureDate {
                            // Pre-populate future dates with empty arrays so they're considered cached
                            timeEntriesViewModel.timeEntriesByDate[dateString] = []
                            cachedDays.append(dateString)
                        } else {
                            allDaysCached = false
                            missingDays.append(dateString)
                        }
                    } else {
                        cachedDays.append(dateString)
                    }
                }
                print("🔍 Week \(dateFormatter.string(from: weekStart)) cache check: \(allDaysCached ? "✅ fully cached" : "❌ missing days")")
                if !cachedDays.isEmpty {
                    print("   Cached: \(cachedDays.joined(separator: ", "))")
                }
                if !missingDays.isEmpty {
                    print("   Missing: \(missingDays.joined(separator: ", "))")
                }

                // Clear old data (but keep current week) - do this AFTER checking cache
                timeEntriesViewModel.clearOldWeekData(keepWeekAround: newDate)

                if !isInNewWeek {
                    // Current date is outside new week, switch to first day of new week
                    let firstDayString = dateFormatter.string(from: weekStart)

                    // Immediately show cached data if available
                    if let cachedEntries = timeEntriesViewModel.timeEntriesByDate[firstDayString] {
                        timeEntriesViewModel.timeEntries = cachedEntries
                        timeEntriesViewModel.isLoading = false
                        timeEntriesViewModel.errorMessage = nil
                    }

                    selectedDate = weekStart
                } else {
                    // Current date is in new week, just ensure cached data is shown
                    let dateString = dateFormatter.string(from: selectedDate)
                    if let cachedEntries = timeEntriesViewModel.timeEntriesByDate[dateString] {
                        timeEntriesViewModel.timeEntries = cachedEntries
                        timeEntriesViewModel.isLoading = false
                        timeEntriesViewModel.errorMessage = nil
                    }
                }

                // Only preload if week is not already fully cached
                if !allDaysCached {
                    // Preload new week entries in background (non-blocking, async)
                    _Concurrency.Task {
                        await timeEntriesViewModel.preloadWeekEntries(around: newDate)
                    }
                }
            }

            // Reset flag after handling week change
            isChangingWeek = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("HarvestClientIDUpdated"))) { _ in
            hasClientID = WindowView.hasOAuthCredentials()
        }
    }

    private static func hasOAuthCredentials() -> Bool {
        let id = (UserDefaults.standard.string(forKey: "harvest_client_id") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = (KeychainManager.shared.get(key: "harvest_client_secret") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !id.isEmpty && !secret.isEmpty
    }

    private func navigateToToday() {
        let today = Date()
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7
        if let weekStart = calendar.date(byAdding: .day, value: -daysFromMonday, to: today) {
            weekStartDate = weekStart
        }
        selectedDate = today
    }
}

#Preview {
    WindowView()
}


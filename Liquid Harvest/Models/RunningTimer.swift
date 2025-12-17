//
//  RunningTimer.swift
//  Liquid Harvest
//
//  Created by Martyn Chamberlin on 11/29/25.
//

import Foundation
import Combine

class RunningTimer: ObservableObject {
    let timeEntry: TimeEntry
    @Published var elapsedTime: TimeInterval
    private var startDate: Date?
    private var updateTimer: Timer?

    init(timeEntry: TimeEntry) {
        self.timeEntry = timeEntry
        if let timerStartedAt = timeEntry.timerStartedAt {
            // Try multiple date formats to handle different ISO 8601 variations
            var date: Date?

            // Try with fractional seconds first
            let formatterWithFractional = ISO8601DateFormatter()
            formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = formatterWithFractional.date(from: timerStartedAt)

            // If that fails, try without fractional seconds
            if date == nil {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime]
                date = formatter.date(from: timerStartedAt)
            }

            // If that fails, try with RFC3339DateFormatter (more flexible)
            if date == nil {
                let rfc3339Formatter = DateFormatter()
                rfc3339Formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
                rfc3339Formatter.timeZone = TimeZone(secondsFromGMT: 0)
                date = rfc3339Formatter.date(from: timerStartedAt)
            }

            if date == nil {
                let rfc3339Formatter2 = DateFormatter()
                rfc3339Formatter2.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
                rfc3339Formatter2.timeZone = TimeZone(secondsFromGMT: 0)
                date = rfc3339Formatter2.date(from: timerStartedAt)
            }

            if let parsedDate = date {
                self.startDate = parsedDate
                self.elapsedTime = Date().timeIntervalSince(parsedDate)
                print("✅ Parsed timer start date: \(timerStartedAt) -> \(parsedDate), elapsed: \(self.elapsedTime)s")
            } else {
                print("❌ Failed to parse timer start date: \(timerStartedAt)")
                self.elapsedTime = 0
            }
        } else {
            print("⚠️ No timer_started_at in time entry")
            self.elapsedTime = 0
        }

        startUpdating()
    }

    deinit {
        stopUpdating()
    }

    func startUpdating() {
        guard startDate != nil else {
            print("⚠️ Cannot start timer updates: no start date")
            return
        }

        // Update every second for the first minute, then every minute after that
        // Timer is scheduled on main run loop, so updates happen on main thread
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self, let startDate = self.startDate else { return }
            // Calculate elapsed time from local clock
            let elapsed = Date().timeIntervalSince(startDate)
            self.elapsedTime = elapsed

            // After 1 minute (60 seconds), switch to updating every minute
            if elapsed >= 60.0 && timer.timeInterval == 1.0 {
                timer.invalidate()
                // Switch to 60 second updates
                self.updateTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
                    guard let self = self, let startDate = self.startDate else { return }
                    self.elapsedTime = Date().timeIntervalSince(startDate)
                }
                if let newTimer = self.updateTimer {
                    RunLoop.main.add(newTimer, forMode: .common)
                }
            }
        }
        if let timer = updateTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        print("✅ Started local timer updates (every 1 second, switching to 1 minute after 60s), startDate: \(startDate?.description ?? "nil")")
    }

    func stopUpdating() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    var formattedElapsedTime: String {
        let totalSeconds = Int(elapsedTime)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}


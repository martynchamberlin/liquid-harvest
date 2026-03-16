//
//  TimeEntry.swift
//  Liquid Harvest
//
//  Created by Martyn Chamberlin on 11/29/25.
//

import Foundation

struct TimeEntry: Codable, Identifiable, Equatable {
    let id: Int64
    let spentDate: String
    let user: TimeEntryUser
    let client: Client?
    let project: Project?
    let task: Task?
    let hours: Double?
    let notes: String?
    let isLocked: Bool
    let lockedReason: String?
    let isClosed: Bool
    let isBilled: Bool
    let timerStartedAt: String?
    let startedTime: String?
    let endedTime: String?
    let isRunning: Bool
    let billable: Bool
    let budgeted: Bool
    let billableRate: Double?
    let costRate: Double?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case spentDate = "spent_date"
        case user
        case client
        case project
        case task
        case hours
        case notes
        case isLocked = "is_locked"
        case lockedReason = "locked_reason"
        case isClosed = "is_closed"
        case isBilled = "is_billed"
        case timerStartedAt = "timer_started_at"
        case startedTime = "started_time"
        case endedTime = "ended_time"
        case isRunning = "is_running"
        case billable
        case budgeted
        case billableRate = "billable_rate"
        case costRate = "cost_rate"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct TimeEntryUser: Codable, Equatable {
    let id: Int64
    let name: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
    }
}

struct TimeEntryResponse: Codable {
    let timeEntries: [TimeEntry]
    let perPage: Int?
    let totalPages: Int?
    let totalEntries: Int?
    let page: Int?

    enum CodingKeys: String, CodingKey {
        case timeEntries = "time_entries"
        case perPage = "per_page"
        case totalPages = "total_pages"
        case totalEntries = "total_entries"
        case page
    }
}

struct TimeEntryRequest: Codable {
    let projectId: Int64?
    let taskId: Int64?
    let spentDate: String?
    let startedTime: String?
    let endedTime: String?
    let hours: Double?
    let notes: String?
    let externalReference: ExternalReference?

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case taskId = "task_id"
        case spentDate = "spent_date"
        case startedTime = "started_time"
        case endedTime = "ended_time"
        case hours
        case notes
        case externalReference = "external_reference"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // Only encode non-nil values
        if let projectId {
            try container.encode(projectId, forKey: .projectId)
        }
        if let taskId {
            try container.encode(taskId, forKey: .taskId)
        }
        if let spentDate {
            try container.encode(spentDate, forKey: .spentDate)
        }
        if let startedTime {
            try container.encode(startedTime, forKey: .startedTime)
        }
        if let endedTime {
            try container.encode(endedTime, forKey: .endedTime)
        }
        if let hours {
            try container.encode(hours, forKey: .hours)
        }
        if let notes {
            try container.encode(notes, forKey: .notes)
        }
        if let externalReference {
            try container.encode(externalReference, forKey: .externalReference)
        }
    }
}

struct ExternalReference: Codable {
    let id: String
    let groupId: String
    let accountId: String
    let permalink: String

    enum CodingKeys: String, CodingKey {
        case id
        case groupId = "group_id"
        case accountId = "account_id"
        case permalink
    }
}

//
//  Task.swift
//  Liquid Harvest
//
//  Created by Martyn Chamberlin on 11/29/25.
//

import Foundation

struct Task: Codable, Identifiable, Equatable {
    let id: Int64
    let name: String
    let billableByDefault: Bool?
    let defaultHourlyRate: Double?
    let isDefault: Bool?
    let isActive: Bool?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case billableByDefault = "billable_by_default"
        case defaultHourlyRate = "default_hourly_rate"
        case isDefault = "is_default"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct TaskResponse: Codable {
    let tasks: [Task]
}

struct TaskAssignment: Codable, Identifiable {
    let id: Int64
    let billable: Bool?
    let isActive: Bool
    let createdAt: String
    let updatedAt: String
    let hourlyRate: Double?
    let budget: Double?
    let task: Task

    enum CodingKeys: String, CodingKey {
        case id
        case billable
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case hourlyRate = "hourly_rate"
        case budget
        case task
    }
}

struct TaskAssignmentResponse: Codable {
    let taskAssignments: [TaskAssignment]

    enum CodingKeys: String, CodingKey {
        case taskAssignments = "task_assignments"
    }
}


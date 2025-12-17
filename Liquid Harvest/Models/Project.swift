//
//  Project.swift
//  Liquid Harvest
//
//  Created by Martyn Chamberlin on 11/29/25.
//

import Foundation

struct Project: Codable, Identifiable, Equatable {
    let id: Int64
    let name: String
    let code: String?
    let isActive: Bool?
    let billBy: String?
    let budget: Double?
    let budgetBy: String?
    let budgetIsMonthly: Bool?
    let notifyWhenOverBudget: Bool?
    let overBudgetNotificationPercentage: Double?
    let overBudgetNotifiedAt: String?
    let showBudgetToAll: Bool?
    let createdAt: String?
    let updatedAt: String?
    let startsOn: String?
    let endsOn: String?
    let isBillable: Bool?
    let isFixedFee: Bool?
    let hourlyRate: Double?
    let costBudget: Double?
    let costBudgetIncludeExpenses: Bool?
    let client: Client?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case code
        case isActive = "is_active"
        case billBy = "bill_by"
        case budget
        case budgetBy = "budget_by"
        case budgetIsMonthly = "budget_is_monthly"
        case notifyWhenOverBudget = "notify_when_over_budget"
        case overBudgetNotificationPercentage = "over_budget_notification_percentage"
        case overBudgetNotifiedAt = "over_budget_notified_at"
        case showBudgetToAll = "show_budget_to_all"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case startsOn = "starts_on"
        case endsOn = "ends_on"
        case isBillable = "is_billable"
        case isFixedFee = "is_fixed_fee"
        case hourlyRate = "hourly_rate"
        case costBudget = "cost_budget"
        case costBudgetIncludeExpenses = "cost_budget_include_expenses"
        case client
        case notes
    }
}

struct ProjectResponse: Codable {
    let projects: [Project]
    let perPage: Int?
    let totalPages: Int?
    let totalEntries: Int?
    let page: Int?

    enum CodingKeys: String, CodingKey {
        case projects
        case perPage = "per_page"
        case totalPages = "total_pages"
        case totalEntries = "total_entries"
        case page
    }
}

struct Client: Codable, Identifiable, Equatable {
    let id: Int64
    let name: String
    let isActive: Bool?
    let address: String?
    let statementKey: String?
    let currency: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case isActive = "is_active"
        case address
        case statementKey = "statement_key"
        case currency
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}


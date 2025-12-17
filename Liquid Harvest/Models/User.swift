//
//  User.swift
//  Liquid Harvest
//
//  Created by Martyn Chamberlin on 11/29/25.
//

import Foundation

struct User: Codable, Identifiable {
    let id: Int64
    let firstName: String
    let lastName: String
    let email: String
    let telephone: String?
    let timezone: String
    let hasAccessToAllFutureProjects: Bool
    let isContractor: Bool
    let isAdmin: Bool?
    let isProjectManager: Bool?
    let canSeeRates: Bool?
    let canCreateProjects: Bool
    let canCreateInvoices: Bool?
    let isActive: Bool
    let weeklyCapacity: Int?
    let defaultHourlyRate: Double?
    let costRate: Double?
    let roles: [String]?
    let avatarUrl: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName = "last_name"
        case email
        case telephone
        case timezone
        case hasAccessToAllFutureProjects = "has_access_to_all_future_projects"
        case isContractor = "is_contractor"
        case isAdmin = "is_admin"
        case isProjectManager = "is_project_manager"
        case canSeeRates = "can_see_rates"
        case canCreateProjects = "can_create_projects"
        case canCreateInvoices = "can_create_invoices"
        case isActive = "is_active"
        case weeklyCapacity = "weekly_capacity"
        case defaultHourlyRate = "default_hourly_rate"
        case costRate = "cost_rate"
        case roles
        case avatarUrl = "avatar_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct UserResponse: Codable {
    let user: User
}

struct Company: Codable {
    let baseUri: String
    let fullDomain: String
    let name: String
    let isActive: Bool
    let weekStartDay: String
    let wantsTimestampTimers: Bool
    let timeFormat: String
    let planType: String
    let clock: String
    let decimalSymbol: String
    let thousandsSeparator: String
    let colorScheme: String
    let expenseFeature: Bool
    let invoiceFeature: Bool
    let estimateFeature: Bool
    let approvalFeature: Bool

    enum CodingKeys: String, CodingKey {
        case baseUri = "base_uri"
        case fullDomain = "full_domain"
        case name
        case isActive = "is_active"
        case weekStartDay = "week_start_day"
        case wantsTimestampTimers = "wants_timestamp_timers"
        case timeFormat = "time_format"
        case planType = "plan_type"
        case clock
        case decimalSymbol = "decimal_symbol"
        case thousandsSeparator = "thousands_separator"
        case colorScheme = "color_scheme"
        case expenseFeature = "expense_feature"
        case invoiceFeature = "invoice_feature"
        case estimateFeature = "estimate_feature"
        case approvalFeature = "approval_feature"
    }
}

struct CompanyResponse: Codable {
    let company: Company
}


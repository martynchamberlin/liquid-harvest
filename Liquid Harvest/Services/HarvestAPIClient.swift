//
//  HarvestAPIClient.swift
//  Liquid Harvest
//
//  Created by Martyn Chamberlin on 11/29/25.
//

import Combine
import Foundation

enum HarvestAPIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case decodingError(Error)
    case unauthorized
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid URL"
        case .invalidResponse:
            "Invalid response from server"
        case let .httpError(code):
            "HTTP error: \(code)"
        case let .decodingError(error):
            "Failed to decode response: \(error.localizedDescription)"
        case .unauthorized:
            "Unauthorized - please log in again"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        }
    }
}

class HarvestAPIClient {
    static let shared = HarvestAPIClient()

    private let baseURL = "https://api.harvestapp.com/v2"
    private var accessToken: String?

    private init() {}

    func setAccessToken(_ token: String) {
        accessToken = token
    }

    func clearAccessToken() {
        accessToken = nil
    }

    private func makeRequest<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Encodable? = nil,
        queryParams: [String: String]? = nil,
    ) async throws -> T {
        var urlString = "\(baseURL)\(endpoint)"

        // Add query parameters if provided
        if let queryParams, !queryParams.isEmpty {
            var components = URLComponents(string: urlString)
            components?.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
            if let finalURL = components?.url?.absoluteString {
                urlString = finalURL
            }
        }

        guard let url = URL(string: urlString) else {
            throw HarvestAPIError.invalidURL
        }

        // Log the request
        print("🔵 [\(method)] Fetching from Harvest: \(urlString)")

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Harvest API v2", forHTTPHeaderField: "User-Agent")

        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            do {
                let encoder = JSONEncoder()
                // Don't use convertToSnakeCase - our models have explicit CodingKeys
                let jsonData = try encoder.encode(body)

                // For now, send the raw encoded data without cleaning
                // The removeNils step might be causing issues
                request.httpBody = jsonData

                // Debug: Print request body
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    print("🔵 Request body: \(jsonString)")
                }
            } catch {
                print("❌ Failed to encode request body: \(error)")
                if let encodingError = error as? EncodingError {
                    print("❌ Encoding error details: \(encodingError)")
                }
                throw HarvestAPIError.decodingError(error)
            }
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw HarvestAPIError.invalidResponse
            }

            if httpResponse.statusCode == 401 {
                throw HarvestAPIError.unauthorized
            }

            guard (200 ... 299).contains(httpResponse.statusCode) else {
                let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
                print("❌ HTTP error \(httpResponse.statusCode) for \(endpoint)")
                print("❌ Error body: \(errorBody)")

                // Also print the request that was sent for debugging
                if let requestBody = request.httpBody, let requestString = String(data: requestBody, encoding: .utf8) {
                    print("❌ Request that was sent: \(requestString)")
                }

                throw HarvestAPIError.httpError(httpResponse.statusCode)
            }

            // Log concise response summary instead of full JSON
            if let responseString = String(data: data, encoding: .utf8) {
                // Try to parse and summarize instead of printing everything
                if let jsonData = responseString.data(using: .utf8),
                   let jsonObject = try? JSONSerialization.jsonObject(with: jsonData, options: [])
                {
                    // Summarize based on structure
                    if let dict = jsonObject as? [String: Any] {
                        // Check for common Harvest response structures
                        if let timeEntries = dict["time_entries"] as? [[String: Any]] {
                            print("✅ [\(method)] \(endpoint) - Response: \(timeEntries.count) time entries")
                            // Only log first entry as example if there are entries
                            if let firstEntry = timeEntries.first, let entryId = firstEntry["id"] {
                                print("   Example entry ID: \(entryId)")
                            }
                        } else if let projects = dict["projects"] as? [[String: Any]] {
                            print("✅ [\(method)] \(endpoint) - Response: \(projects.count) projects")
                        } else if let taskAssignments = dict["task_assignments"] as? [[String: Any]] {
//                            print("✅ [\(method)] \(endpoint) - Response: \(task_assignments.count) task assignments")
                        } else if dict["id"] != nil {
                            // Single object response (like user or time entry)
                            if let id = dict["id"] {
                                print("✅ [\(method)] \(endpoint) - Response: Single object (ID: \(id))")
                            } else {
                                print("✅ [\(method)] \(endpoint) - Response: Single object")
                            }
                        } else {
                            // Unknown structure, just log size
                            let dataSize = data.count
                            print("✅ [\(method)] \(endpoint) - Response: \(dataSize) bytes")
                        }
                    } else if let array = jsonObject as? [[String: Any]] {
                        print("✅ [\(method)] \(endpoint) - Response: Array with \(array.count) items")
                    } else {
                        // Fallback: just log data size
                        let dataSize = data.count
                        print("✅ [\(method)] \(endpoint) - Response: \(dataSize) bytes")
                    }
                } else {
                    // Not JSON or couldn't parse, just log size
                    let dataSize = data.count
                    print("✅ [\(method)] \(endpoint) - Response: \(dataSize) bytes (non-JSON or parse error)")
                }
            }

            do {
                let decoder = JSONDecoder()
                // Don't use convertFromSnakeCase - all our models have explicit CodingKeys
                // that handle the snake_case to camelCase conversion
                let decoded = try decoder.decode(T.self, from: data)
                return decoded
            } catch {
                let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
                print("❌ Decoding error for \(endpoint): \(error)")
                // Only show first 500 chars of response for errors
                print("❌ Response preview: \(responseString.prefix(500))")
                throw HarvestAPIError.decodingError(error)
            }
        } catch let error as HarvestAPIError {
            throw error
        } catch {
            throw HarvestAPIError.networkError(error)
        }
    }

    private func removeNils(from dictionary: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in dictionary {
            if let nestedDict = value as? [String: Any] {
                let cleaned = removeNils(from: nestedDict)
                if !cleaned.isEmpty {
                    result[key] = cleaned
                }
            } else if let array = value as? [Any] {
                result[key] = array
            } else if !(value is NSNull) {
                result[key] = value
            }
        }
        return result
    }

    // MARK: - User Endpoints

    func getCurrentUser() async throws -> User {
        // The /users/me endpoint returns the user object directly, not wrapped
        let user: User = try await makeRequest(endpoint: "/users/me")
        return user
    }

    // MARK: - Time Entry Endpoints

    func getTimeEntries(isRunning: Bool? = nil, spentDate: String? = nil, from: String? = nil, to: String? = nil) async throws -> [TimeEntry] {
        var endpoint = "/time_entries"
        var queryItems: [String] = []

        if let isRunning {
            queryItems.append("is_running=\(isRunning)")
        }

        // If spentDate is provided, use it alone (more specific than from/to range)
        // Only add from/to if spentDate is NOT provided
        if let spentDate {
            queryItems.append("spent_date=\(spentDate)")
        } else {
            // Add date range filtering to limit results (only when spentDate is not provided)
            if let from {
                queryItems.append("from=\(from)")
            }

            if let to {
                queryItems.append("to=\(to)")
            }

            // If no date filter is provided at all, default to current week
            if from == nil, to == nil {
                let calendar = Calendar.current
                let today = Date()
                let weekday = calendar.component(.weekday, from: today)
                let daysFromMonday = (weekday + 5) % 7 // Convert Sunday=1 to Monday=0

                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"

                if let weekStart = calendar.date(byAdding: .day, value: -daysFromMonday, to: today),
                   let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)
                {
                    let weekStartString = dateFormatter.string(from: weekStart)
                    let weekEndString = dateFormatter.string(from: weekEnd)
                    queryItems.append("from=\(weekStartString)")
                    queryItems.append("to=\(weekEndString)")
                    print("📅 Limiting time entries to current week: \(weekStartString) to \(weekEndString)")
                } else {
                    // Fallback: just use today if date calculation fails
                    let todayString = dateFormatter.string(from: today)
                    queryItems.append("from=\(todayString)")
                    queryItems.append("to=\(todayString)")
                    print("📅 Limiting time entries to today: \(todayString)")
                }
            }
        }

        // Add pagination limit to reduce data transfer
        // Limit to 100 entries per page (Harvest API default is 2000, which is way too much)
        queryItems.append("per_page=100")
        // Only fetch first page
        queryItems.append("page=1")

        if !queryItems.isEmpty {
            endpoint += "?" + queryItems.joined(separator: "&")
        }

        let response: TimeEntryResponse = try await makeRequest(endpoint: endpoint)
        return response.timeEntries
    }

    func getRunningTimer() async throws -> TimeEntry? {
        // For running timer, we still want to limit to current week to avoid fetching all historical data
        // A running timer should be recent anyway, so this is safe
        let entries = try await getTimeEntries(isRunning: true)
        return entries.first
    }

    func createTimeEntry(_ request: TimeEntryRequest) async throws -> TimeEntry {
        print("🔵 Creating time entry with projectId: \(request.projectId ?? -1), taskId: \(request.taskId ?? -1), spentDate: \(request.spentDate ?? "nil")")

        // Harvest API expects these as query parameters, not in the JSON body (per hrvst-cli)
        var queryParams: [String: String] = [:]

        if let projectId = request.projectId {
            queryParams["project_id"] = String(projectId)
        }
        if let taskId = request.taskId {
            queryParams["task_id"] = String(taskId)
        }
        if let spentDate = request.spentDate {
            queryParams["spent_date"] = spentDate
        }
        if let notes = request.notes, !notes.isEmpty {
            queryParams["notes"] = notes
        }

        // The response returns the time entry directly, not wrapped
        let timeEntry: TimeEntry = try await makeRequest(
            endpoint: "/time_entries",
            method: "POST",
            body: nil,
            queryParams: queryParams.isEmpty ? nil : queryParams,
        )
        return timeEntry
    }

    func updateTimeEntry(id: Int64, request: TimeEntryRequest) async throws -> TimeEntry {
        // Per hrvst-cli: PATCH requests send query parameters as flat JSON body
        // The query parameters are converted to a flat object and sent as JSON
        // This is different from POST which uses query params in URL
        // Example: {"notes": "test", "hours": "1.5"} not {"time_entry": {"notes": "test"}}

        struct FlatRequest: Codable {
            let projectId: Int64?
            let taskId: Int64?
            let spentDate: String?
            let startedTime: String?
            let endedTime: String?
            let hours: Double?
            let notes: String?

            enum CodingKeys: String, CodingKey {
                case projectId = "project_id"
                case taskId = "task_id"
                case spentDate = "spent_date"
                case startedTime = "started_time"
                case endedTime = "ended_time"
                case hours
                case notes
            }

            init(from request: TimeEntryRequest) {
                projectId = request.projectId
                taskId = request.taskId
                spentDate = request.spentDate
                startedTime = request.startedTime
                endedTime = request.endedTime
                hours = request.hours
                notes = request.notes
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
                // Always encode notes if provided (even if empty string) to allow clearing notes
                if let notes {
                    try container.encode(notes, forKey: .notes)
                }
            }
        }

        // The API returns the time entry directly, not wrapped
        let timeEntry: TimeEntry = try await makeRequest(
            endpoint: "/time_entries/\(id)",
            method: "PATCH",
            body: FlatRequest(from: request),
        )

        // Debug: Print the response to verify notes were saved
        print("✅ Updated time entry - notes: \(timeEntry.notes ?? "nil")")

        return timeEntry
    }

    func stopTimeEntry(id: Int64) async throws -> TimeEntry {
        // The stop endpoint returns the time entry directly, not wrapped
        let timeEntry: TimeEntry = try await makeRequest(
            endpoint: "/time_entries/\(id)/stop",
            method: "PATCH",
        )
        return timeEntry
    }

    func deleteTimeEntry(id: Int64) async throws {
        // DELETE endpoint returns 200 OK with no body, so we handle it specially
        var urlString = "\(baseURL)/time_entries/\(id)"
        guard let url = URL(string: urlString) else {
            throw HarvestAPIError.invalidURL
        }

        print("🔵 [DELETE] Fetching from Harvest: \(urlString)")

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Harvest API v2", forHTTPHeaderField: "User-Agent")

        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HarvestAPIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw HarvestAPIError.unauthorized
        }

        // Treat 404 as success - entry is already deleted
        if httpResponse.statusCode == 404 {
            print("✅ [DELETE] Time entry \(id) already deleted (404)")
            return
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
            print("❌ HTTP error \(httpResponse.statusCode) for DELETE /time_entries/\(id)")
            print("❌ Error body: \(errorBody)")
            throw HarvestAPIError.httpError(httpResponse.statusCode)
        }

        // Log successful deletion
        print("✅ [DELETE] Successfully deleted time entry \(id)")
        if !data.isEmpty, let responseString = String(data: data, encoding: .utf8) {
            print("📦 Response data: \(responseString)")
        }
    }

    // MARK: - Project Endpoints

    func getProjects(isActive: Bool? = nil) async throws -> [Project] {
        var endpoint = "/projects"
        if let isActive {
            endpoint += "?is_active=\(isActive)"
        }
        print("🔵 Fetching projects from: \(endpoint)")
        let response: ProjectResponse = try await makeRequest(endpoint: endpoint)
        print("✅ Received \(response.projects.count) projects")
        return response.projects
    }

    func getTaskAssignments(projectId: Int64) async throws -> [TaskAssignment] {
        let response: TaskAssignmentResponse = try await makeRequest(
            endpoint: "/projects/\(projectId)/task_assignments",
        )
        return response.taskAssignments
    }
}

//
//  ProjectsViewModel.swift
//  Liquid Harvest
//
//  Created by Martyn Chamberlin on 11/29/25.
//

import Foundation
import Combine

@MainActor
class ProjectsViewModel: ObservableObject {
    @Published var projects: [Project] = []
    @Published var taskAssignments: [TaskAssignment] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let apiClient = HarvestAPIClient.shared

    func loadProjects() async {
        isLoading = true
        errorMessage = nil

        do {
            print("🔵 Loading projects...")
            projects = try await apiClient.getProjects(isActive: true)
            print("✅ Loaded \(projects.count) projects")
            isLoading = false
        } catch {
            print("❌ Failed to load projects: \(error)")
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    func loadTasks(for projectId: Int64) async {
        errorMessage = nil

        do {
            taskAssignments = try await apiClient.getTaskAssignments(projectId: projectId)
        } catch {
            errorMessage = error.localizedDescription
            taskAssignments = []
        }
    }
}


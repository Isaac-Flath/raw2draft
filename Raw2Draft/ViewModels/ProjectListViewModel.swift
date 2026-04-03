import Foundation

/// View model for the project sidebar list.
@Observable @MainActor
final class ProjectListViewModel {
    var searchText: String = ""

    func filteredProjects(from projects: [Project]) -> [Project] {
        guard !searchText.isEmpty else { return projects }
        return projects.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
            || $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }
}

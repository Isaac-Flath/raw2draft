import SwiftUI

/// Modal sheet for creating a new project.
struct NewProjectSheet: View {
    @Bindable var viewModel: AppViewModel
    @State private var projectName: String = ""
    @FocusState private var nameFieldFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var slug: String? {
        PathSanitizer.slugify(projectName)
    }

    private var previewPath: String {
        guard let slug else { return "" }
        return "projects/\(Constants.projectDateString())_\(slug)/"
    }

    private var isValid: Bool {
        slug != nil && !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("New Project")
                .font(AppFonts.title())

            VStack(alignment: .leading, spacing: 8) {
                Text("Project Name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("My awesome post", text: $projectName)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFieldFocused)
                    .onSubmit {
                        if isValid { create() }
                    }

                if isValid {
                    Text(previewPath)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    create()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            nameFieldFocused = true
        }
    }

    private func create() {
        viewModel.createProject(name: projectName)
        dismiss()
    }
}

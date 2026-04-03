import SwiftUI

/// View for adding text content as a source file.
struct SourceTextView: View {
    @Bindable var sourcesViewModel: SourcesViewModel
    let projectId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Text Source")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Filename (e.g. notes)", text: $sourcesViewModel.textFilename)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            TextEditor(text: $sourcesViewModel.textContent)
                .font(.system(size: 12))
                .frame(height: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )

            HStack {
                Spacer()
                Button("Save") {
                    sourcesViewModel.saveTextSource(projectId: projectId)
                }
                .controlSize(.small)
                .disabled(
                    sourcesViewModel.textFilename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || sourcesViewModel.textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
    }
}

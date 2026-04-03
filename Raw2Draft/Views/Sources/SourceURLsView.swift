import SwiftUI

/// View for managing source URLs.
struct SourceURLsView: View {
    @Bindable var sourcesViewModel: SourcesViewModel
    let projectId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("URLs")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("https://youtube.com/watch?v=...", text: $sourcesViewModel.urlInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit {
                        sourcesViewModel.addUrl(projectId: projectId)
                    }

                Button("Add") {
                    sourcesViewModel.addUrl(projectId: projectId)
                }
                .controlSize(.small)
                .disabled(sourcesViewModel.urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            // URL list
            if !sourcesViewModel.sourceUrls.isEmpty {
                ForEach(sourcesViewModel.sourceUrls) { sourceUrl in
                    HStack(spacing: 6) {
                        urlTypeIcon(sourceUrl.type)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)

                        Text(sourceUrl.url)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        statusBadge(sourceUrl.status)

                        Button {
                            sourcesViewModel.removeUrl(sourceUrl.url, projectId: projectId)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private func urlTypeIcon(_ type: URLType) -> some View {
        switch type {
        case .youtube: Image(systemName: "play.rectangle.fill")
        case .pdf: Image(systemName: "doc.fill")
        case .webpage: Image(systemName: "globe")
        case .unknown: Image(systemName: "link")
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: URLStatus) -> some View {
        let (color, text) = statusInfo(status)
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(color.opacity(0.15))
            )
            .foregroundStyle(color)
    }

    private func statusInfo(_ status: URLStatus) -> (Color, String) {
        switch status {
        case .pending: return (AppColors.gold, "Pending")
        case .processing: return (AppColors.indigo, "Processing")
        case .processed: return (AppColors.success, "Done")
        case .error: return (AppColors.statusError, "Error")
        }
    }
}

import SwiftUI

/// Toolbar for the terminal pane showing project name and connection status.
struct TerminalToolbarView: View {
    let projectName: String
    let connectionStatus: TerminalConnectionStatus
    let onToggle: () -> Void
    let onRestart: () -> Void
    let onCopy: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: Constants.TerminalColors.foreground))

            Text("Terminal")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(hex: Constants.TerminalColors.foreground))

            if !projectName.isEmpty {
                Text("- \(projectName)")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: Constants.TerminalColors.foreground).opacity(0.6))
            }

            // Connection status dot
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Spacer()

            // Restart button
            Button {
                onRestart()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: Constants.TerminalColors.foreground).opacity(0.9))
            }
            .buttonStyle(.plain)
            .help("Restart Claude Code")

            // Copy button
            Button {
                onCopy()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: Constants.TerminalColors.foreground).opacity(0.9))
            }
            .buttonStyle(.plain)
            .help("Copy Selection")

            // Clear button
            Button {
                onClear()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: Constants.TerminalColors.foreground).opacity(0.9))
            }
            .buttonStyle(.plain)
            .help("Clear Terminal")

            // Toggle button
            Button {
                onToggle()
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: Constants.TerminalColors.foreground).opacity(0.9))
            }
            .buttonStyle(.plain)
            .help("Toggle Terminal")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(hex: Constants.TerminalColors.background).opacity(0.95))
    }

    private var statusColor: Color {
        switch connectionStatus {
        case .connected: return AppColors.success
        case .connecting: return AppColors.gold
        case .disconnected: return .gray
        case .error: return AppColors.statusError
        }
    }
}

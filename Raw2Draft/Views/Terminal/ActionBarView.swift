import SwiftUI

/// Action bar with quick-send buttons for Claude Code commands, grouped by workflow.
struct ActionBarView: View {
    let onCommand: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(TerminalViewModel.ActionGroup.allCases, id: \.self) { group in
                    if group != .content {
                        Divider()
                            .frame(height: 16)
                            .opacity(0.3)
                    }

                    ForEach(group.commands, id: \.rawValue) { command in
                        Button {
                            onCommand(command.rawValue)
                        } label: {
                            Text(command.label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(AppColors.brandGradient)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color(hex: Constants.TerminalColors.background).opacity(0.9))
    }
}

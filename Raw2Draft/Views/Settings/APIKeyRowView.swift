import SwiftUI

/// Row for displaying and managing an API key in Settings.
struct APIKeyRowView: View {
    let key: APIKey
    let isSet: Bool
    @Binding var inputValue: String
    let onSave: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(key.displayName)
                    .font(.system(size: 13, weight: .medium))

                Text(key.hint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                // Status badge
                if isSet {
                    Text("Set")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(AppColors.success.opacity(0.15)))
                        .foregroundStyle(AppColors.success)
                } else {
                    Text("Not Set")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(AppColors.statusDisconnected.opacity(0.15)))
                        .foregroundStyle(AppColors.statusDisconnected)
                }
            }

            HStack(spacing: 8) {
                Group {
                    if key.isSecret {
                        SecureField("Enter API key", text: $inputValue)
                    } else {
                        TextField("Enter value", text: $inputValue)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

                Button("Save") {
                    onSave()
                }
                .controlSize(.small)
                .disabled(inputValue.isEmpty)

                if isSet {
                    Button("Clear") {
                        onClear()
                    }
                    .controlSize(.small)
                    .tint(AppColors.statusError)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

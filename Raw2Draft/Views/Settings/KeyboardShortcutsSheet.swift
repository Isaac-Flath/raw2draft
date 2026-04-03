import SwiftUI

/// Sheet displaying all keyboard shortcuts.
struct KeyboardShortcutsSheet: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(AppFonts.title())
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    shortcutGroup("File") {
                        shortcutRow("New", keys: "⌘N")
                        shortcutRow("Open", keys: "⌘O")
                        shortcutRow("Save", keys: "⌘S")
                        shortcutRow("Settings", keys: "⌘,")
                    }

                    shortcutGroup("View") {
                        shortcutRow("Toggle Sidebar", keys: "⇧⌘B")
                        shortcutRow("Toggle Terminal", keys: "⇧⌘T")
                        shortcutRow("Toggle Preview", keys: "⇧⌘P")
                        shortcutRow("Toggle Line Numbers", keys: "⇧⌘L")
                        shortcutRow("Document Outline", keys: "⇧⌘O")
                        shortcutRow("Distraction-Free Mode", keys: "⇧⌘F")
                    }

                    shortcutGroup("Editor") {
                        shortcutRow("Bold", keys: "⌘B")
                        shortcutRow("Italic", keys: "⌘I")
                        shortcutRow("Insert Link", keys: "⌘K")
                        shortcutRow("Find", keys: "⌘F")
                        shortcutRow("Find Next", keys: "⌘G")
                        shortcutRow("Find Previous", keys: "⇧⌘G")
                    }

                    shortcutGroup("Help") {
                        shortcutRow("Command Palette", keys: "⇧⌘K")
                        shortcutRow("Keyboard Shortcuts", keys: "⌘/")
                    }
                }
                .padding()
            }
        }
        .frame(width: 400, height: 460)
    }

    private func shortcutGroup(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppFonts.headline())
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func shortcutRow(_ label: String, keys: String) -> some View {
        HStack {
            Text(label)
                .font(.body)
            Spacer()
            Text(keys)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
        }
    }
}

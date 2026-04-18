You are an experienced software architect reviewing the full source code of **Raw2Draft**, a personal macOS writing tool. It is a SwiftUI/AppKit application with an MVVM architecture, a CodeMirror 6 web editor embedded via WKWebView, a Claude Code terminal integration, and a small Bash CLI wrapper.

Below is the complete source tree. Please analyse it and write a structured architectural review that covers:

1. **Current architecture overview** – describe layers, data flow, and key design decisions.
2. **Strengths** – what is already well-structured, simple, or robust.
3. **Weaknesses / pain-points** – concrete problems (coupling, duplication, unclear ownership, fragile patterns, etc.), with references to specific files or types.
4. **Recommendations** – prioritised list of actionable re-architecture suggestions (high / medium / low). For each: what to change, why it would help (robustness, simplicity, or understandability), and any trade-offs.
5. **Quick wins** – small changes that could be made with minimal risk right now.

Be specific and refer to actual file names, type names, and method names. Keep the review concise but thorough. Use markdown formatting.

--- SOURCE FILES ---

{files_block}

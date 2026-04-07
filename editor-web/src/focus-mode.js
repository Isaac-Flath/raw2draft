import { ViewPlugin, Decoration } from "@codemirror/view";

/**
 * Focus mode: dims all paragraphs except the one containing the cursor.
 * A paragraph is a contiguous block of non-empty lines separated by blank lines.
 * Activated via data-focus-mode="true" attribute on the root element.
 */

function findParagraphRange(state) {
  const cursorLine = state.doc.lineAt(state.selection.main.head);
  const totalLines = state.doc.lines;

  // Walk up to find paragraph start (first line after a blank line or doc start)
  let startLine = cursorLine.number;
  for (let i = cursorLine.number - 1; i >= 1; i--) {
    const line = state.doc.line(i);
    if (line.text.trim() === "") break;
    startLine = i;
  }

  // Walk down to find paragraph end (last line before a blank line or doc end)
  let endLine = cursorLine.number;
  for (let i = cursorLine.number + 1; i <= totalLines; i++) {
    const line = state.doc.line(i);
    if (line.text.trim() === "") break;
    endLine = i;
  }

  return { startLine, endLine };
}

function buildDecorations(view) {
  const enabled = document.documentElement.getAttribute("data-focus-mode") === "true";
  if (!enabled) return Decoration.none;

  const { startLine, endLine } = findParagraphRange(view.state);
  const decorations = [];

  for (let i = 1; i <= view.state.doc.lines; i++) {
    const line = view.state.doc.line(i);
    if (i >= startLine && i <= endLine) {
      decorations.push(Decoration.line({ class: "cm-paragraph-active" }).range(line.from));
    }
  }

  return Decoration.set(decorations);
}

export function focusMode() {
  return ViewPlugin.fromClass(
    class {
      constructor(view) {
        this.decorations = buildDecorations(view);
      }
      update(update) {
        if (update.selectionSet || update.docChanged) {
          this.decorations = buildDecorations(update.view);
        }
      }
    },
    { decorations: (v) => v.decorations }
  );
}

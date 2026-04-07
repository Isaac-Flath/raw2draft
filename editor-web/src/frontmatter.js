import { ViewPlugin, Decoration } from "@codemirror/view";

/**
 * Highlights YAML frontmatter blocks (between --- delimiters)
 * and applies the .cm-frontmatter class for styling.
 */
function buildFrontmatterDecorations(view) {
  const doc = view.state.doc;
  const firstLine = doc.line(1).text;

  if (firstLine.trim() !== "---") {
    return Decoration.none;
  }

  // Find closing ---
  const decorations = [];
  let endLine = -1;

  for (let i = 2; i <= Math.min(doc.lines, 50); i++) {
    if (doc.line(i).text.trim() === "---") {
      endLine = i;
      break;
    }
  }

  if (endLine === -1) return Decoration.none;

  // Decorate each line in the frontmatter block
  for (let i = 1; i <= endLine; i++) {
    const line = doc.line(i);
    decorations.push(
      Decoration.line({ class: "cm-frontmatter" }).range(line.from)
    );
  }

  return Decoration.set(decorations);
}

export function frontmatterFolding() {
  return ViewPlugin.fromClass(
    class {
      constructor(view) {
        this.decorations = buildFrontmatterDecorations(view);
      }
      update(update) {
        if (update.docChanged) {
          this.decorations = buildFrontmatterDecorations(update.view);
        }
      }
    },
    { decorations: (v) => v.decorations }
  );
}

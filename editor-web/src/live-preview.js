import { ViewPlugin, Decoration, WidgetType } from "@codemirror/view";
import { syntaxTree } from "@codemirror/language";

/**
 * Live preview decorations for markdown.
 * Renders images inline, styles code blocks and blockquotes as blocks.
 */

class ImageWidget extends WidgetType {
  constructor(src, alt) {
    super();
    this.src = src;
    this.alt = alt;
  }

  toDOM() {
    const wrap = document.createElement("div");
    wrap.className = "cm-image-widget";
    wrap.style.display = "block";
    const img = document.createElement("img");
    img.src = this.src;
    img.alt = this.alt;
    img.loading = "lazy";
    img.style.maxWidth = "100%";
    img.style.height = "auto";
    img.onerror = () => { wrap.style.display = "none"; };
    wrap.appendChild(img);
    return wrap;
  }

  eq(other) {
    return this.src === other.src && this.alt === other.alt;
  }
}

// Line decoration classes for block elements
const codeBlockLine = Decoration.line({ class: "cm-codeblock-line" });
const codeBlockFirstLine = Decoration.line({ class: "cm-codeblock-line cm-codeblock-first" });
const codeBlockLastLine = Decoration.line({ class: "cm-codeblock-line cm-codeblock-last" });
const codeBlockOnlyLine = Decoration.line({ class: "cm-codeblock-line cm-codeblock-first cm-codeblock-last" });
const blockquoteLine = Decoration.line({ class: "cm-blockquote-line" });

function buildDecorations(view) {
  const decorations = [];

  for (const { from, to } of view.visibleRanges) {
    syntaxTree(view.state).iterate({
      from,
      to,
      enter(node) {
        // Inline images: ![alt](url)
        if (node.name === "Image") {
          const text = view.state.doc.sliceString(node.from, node.to);
          const match = text.match(/!\[([^\]]*)\]\(([^)]+)\)/);
          if (match) {
            const [, alt, src] = match;
            if (src.startsWith("http") || src.startsWith("file://") || src.startsWith("/")) {
              decorations.push(
                Decoration.widget({
                  widget: new ImageWidget(src, alt),
                }).range(node.to)
              );
            }
          }
        }

        // Fenced code blocks — apply line decorations for block styling
        if (node.name === "FencedCode") {
          const startLine = view.state.doc.lineAt(node.from).number;
          const endLine = view.state.doc.lineAt(node.to).number;
          for (let i = startLine; i <= endLine; i++) {
            const line = view.state.doc.line(i);
            let deco;
            if (startLine === endLine) {
              deco = codeBlockOnlyLine;
            } else if (i === startLine) {
              deco = codeBlockFirstLine;
            } else if (i === endLine) {
              deco = codeBlockLastLine;
            } else {
              deco = codeBlockLine;
            }
            decorations.push(deco.range(line.from));
          }
        }

        // Blockquotes — apply line decorations
        if (node.name === "Blockquote") {
          const startLine = view.state.doc.lineAt(node.from).number;
          const endLine = view.state.doc.lineAt(node.to).number;
          for (let i = startLine; i <= endLine; i++) {
            const line = view.state.doc.line(i);
            decorations.push(blockquoteLine.range(line.from));
          }
        }
      },
    });
  }

  return Decoration.set(decorations, true);
}

export function livePreview() {
  return ViewPlugin.fromClass(
    class {
      constructor(view) {
        this.decorations = buildDecorations(view);
      }
      update(update) {
        if (update.docChanged || update.viewportChanged) {
          this.decorations = buildDecorations(update.view);
        }
      }
    },
    { decorations: (v) => v.decorations }
  );
}

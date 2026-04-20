import { marked } from "marked";
import { resolveAssetURL } from "./asset-url.js";
import { renderMermaid, nextMermaidId } from "./mermaid-renderer.js";
import { renderD2 } from "./d2-renderer.js";

/**
 * Markdown preview renderer.
 * Strips frontmatter, renders to HTML via marked.
 * Supports jumping to headings via scrollPreviewToHeading().
 */

marked.setOptions({
  breaks: true,
  gfm: true,
});

// Rewrite image hrefs through resolveAssetURL so relative paths resolve to
// file:// URLs rooted in the active markdown file's directory.
marked.use({
  renderer: {
    image({ href, title, text, tokens }) {
      const resolved = resolveAssetURL(href);
      const t = title ? ` title="${escapeHTML(title)}"` : "";
      return `<img src="${resolved}" alt="${escapeHTML(text || "")}"${t}>`;
    },
  },
});

function escapeHTML(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function stripFrontmatter(md) {
  if (!md.startsWith("---")) return md;
  const end = md.indexOf("\n---", 3);
  if (end === -1) return md;
  return md.slice(end + 4).trimStart();
}

let previewEl = null;
let debounceTimer = null;
let lastMarkdown = "";

export function createPreviewPane() {
  previewEl = document.createElement("div");
  previewEl.id = "preview";
  previewEl.className = "preview-pane";
  previewEl.style.display = "none";
  return previewEl;
}

function renderMermaidBlocks(root) {
  const blocks = root.querySelectorAll("pre > code.language-mermaid");
  blocks.forEach((codeEl) => {
    const pre = codeEl.parentElement;
    const wrap = document.createElement("div");
    wrap.className = "mermaid-block";
    wrap.textContent = "Rendering diagram…";
    pre.replaceWith(wrap);
    const code = codeEl.textContent || "";
    const id = nextMermaidId();
    renderMermaid(code, id).then((result) => {
      if (result.ok) {
        wrap.innerHTML = result.svg;
      } else {
        wrap.className = "mermaid-block mermaid-error";
        wrap.textContent = `Mermaid error: ${result.error}`;
      }
    });
  });
}

function renderD2Blocks(root) {
  const blocks = root.querySelectorAll("pre > code.language-d2");
  blocks.forEach((codeEl) => {
    const pre = codeEl.parentElement;
    const wrap = document.createElement("div");
    wrap.className = "mermaid-block";
    wrap.textContent = "Rendering D2 diagram…";
    pre.replaceWith(wrap);
    const code = codeEl.textContent || "";
    renderD2(code).then((result) => {
      if (result.ok) {
        wrap.innerHTML = result.svg;
      } else {
        wrap.className = "mermaid-block mermaid-error";
        wrap.textContent = `D2 error: ${result.error}`;
      }
    });
  });
}

export function updatePreview(markdown) {
  lastMarkdown = markdown;
  if (!previewEl || previewEl.style.display === "none") return;

  clearTimeout(debounceTimer);
  debounceTimer = setTimeout(() => {
    const body = stripFrontmatter(markdown);
    previewEl.innerHTML = marked.parse(body);
    renderMermaidBlocks(previewEl);
    renderD2Blocks(previewEl);
  }, 150);
}

// Re-render preview when theme or base dir changes
window.addEventListener("mermaid-theme-changed", () => updatePreview(lastMarkdown));
window.addEventListener("asset-base-dir-changed", () => updatePreview(lastMarkdown));

/**
 * Scroll the preview to the Nth heading (0-indexed).
 * Called when a heading is selected from the outline.
 */
export function scrollPreviewToHeading(headingIndex) {
  if (!previewEl || previewEl.style.display === "none") return;
  const headings = previewEl.querySelectorAll("h1, h2, h3, h4, h5, h6");
  // The first heading in the source (e.g. "# Title") is typically already
  // visible at the top of the preview, so outline indices are off by one.
  // Clamp to valid range.
  const idx = Math.max(0, headingIndex - 1);
  if (idx < headings.length) {
    headings[idx].scrollIntoView({ behavior: "smooth", block: "start" });
  }
}

// No-op kept for API compatibility (main.js still calls this on scroll)
export function syncPreviewScroll() {}

export function setPreviewVisible(visible, getCurrentContent) {
  if (!previewEl) return;
  previewEl.style.display = visible ? "block" : "none";

  const container = document.getElementById("container");
  if (container) {
    container.classList.toggle("split-view", visible);
  }

  if (visible && getCurrentContent) {
    updatePreview(getCurrentContent());
  }
}

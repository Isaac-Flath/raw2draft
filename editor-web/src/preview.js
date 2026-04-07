import { marked } from "marked";

/**
 * Markdown preview renderer.
 * Strips frontmatter, renders to HTML via marked.
 * Supports jumping to headings via scrollPreviewToHeading().
 */

marked.setOptions({
  breaks: true,
  gfm: true,
});

function stripFrontmatter(md) {
  if (!md.startsWith("---")) return md;
  const end = md.indexOf("\n---", 3);
  if (end === -1) return md;
  return md.slice(end + 4).trimStart();
}

let previewEl = null;
let debounceTimer = null;

export function createPreviewPane() {
  previewEl = document.createElement("div");
  previewEl.id = "preview";
  previewEl.className = "preview-pane";
  previewEl.style.display = "none";
  return previewEl;
}

export function updatePreview(markdown) {
  if (!previewEl || previewEl.style.display === "none") return;

  clearTimeout(debounceTimer);
  debounceTimer = setTimeout(() => {
    const body = stripFrontmatter(markdown);
    previewEl.innerHTML = marked.parse(body);
  }, 150);
}

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

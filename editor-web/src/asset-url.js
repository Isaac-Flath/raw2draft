/**
 * Resolve asset URLs (images, etc.) relative to the active markdown file's
 * directory. Swift pushes the base directory via `setBaseDir` on the bridge.
 */

let baseDir = null;

export function setAssetBaseDir(dir) {
  baseDir = dir || null;
  window.dispatchEvent(new CustomEvent("asset-base-dir-changed"));
}

export function getAssetBaseDir() {
  return baseDir;
}

/**
 * Resolve a markdown image/link href to something the WebView can load.
 * - Absolute URLs (http, https, data, file, blob) are returned unchanged.
 * - Root-absolute paths (/foo) are served via the r2dasset:// scheme.
 * - Relative paths are resolved against the current file's directory, also
 *   via r2dasset:// — avoids file:// same-origin restrictions.
 */
export function resolveAssetURL(src) {
  if (!src) return src;
  if (/^(https?:|data:|blob:|file:|mailto:|r2dasset:)/i.test(src)) return src;
  if (src.startsWith("#")) return src;

  if (src.startsWith("/")) return "r2dasset://" + encodePath(src);

  if (!baseDir) return src;

  const joined = joinPath(baseDir, src);
  return "r2dasset://" + encodePath(joined);
}

function joinPath(dir, rel) {
  const base = dir.endsWith("/") ? dir.slice(0, -1) : dir;
  const parts = base.split("/");
  for (const seg of rel.split("/")) {
    if (seg === "" || seg === ".") continue;
    if (seg === "..") { parts.pop(); continue; }
    parts.push(seg);
  }
  return parts.join("/");
}

function encodePath(path) {
  return path.split("/").map(encodeURIComponent).join("/");
}

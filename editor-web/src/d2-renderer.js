/**
 * D2 diagram renderer. Shells out to the `d2` CLI via the Swift bridge
 * (install with `brew install d2`). Request/response is keyed by a monotonic
 * requestId so multiple diagrams can render concurrently.
 */

let counter = 0;
const pending = new Map(); // requestId -> { resolve }

export function nextD2Id() {
  counter += 1;
  return `d2-${counter}`;
}

export function renderD2(code) {
  return new Promise((resolve) => {
    counter += 1;
    const requestId = `d2req-${counter}`;
    pending.set(requestId, { resolve });

    try {
      window.webkit?.messageHandlers?.editor?.postMessage({
        type: "renderD2",
        code,
        requestId,
      });
    } catch (err) {
      pending.delete(requestId);
      resolve({ ok: false, error: "Bridge unavailable: " + (err?.message || err) });
      return;
    }

    // Timeout safety — if Swift never replies, resolve with an error so
    // the UI doesn't hang on "Rendering…" forever.
    setTimeout(() => {
      if (pending.has(requestId)) {
        pending.delete(requestId);
        resolve({ ok: false, error: "d2 render timed out after 10s" });
      }
    }, 10000);
  });
}

// Swift calls this when d2 finishes. Wired in main.js.
export function resolveD2Render(requestId, result) {
  const entry = pending.get(requestId);
  if (!entry) return;
  pending.delete(requestId);
  entry.resolve(result);
}

"""Phase 3: Generate overlay specification from reviewed mentions.

Maps mention timing to display parameters and produces the overlay spec
that video-remotion reads to render overlay graphics.

Input: <stem>_mentions.json (with assets gathered) + <stem>_edl.json
Output: <stem>_overlays.json
"""

import json
import os
import sys
from pathlib import Path


# Default display durations by type (seconds)
DEFAULT_DURATIONS = {
    "blog-card": 6.0,
    "talk-thumbnail": 5.0,
    "url-callout": 4.0,
    "key-term": 4.0,
    "tool": 5.0,
    "generic-image": 5.0,
}

# Default positions by type
DEFAULT_POSITIONS = {
    "blog-card": "lower-right",
    "talk-thumbnail": "lower-right",
    "url-callout": "lower-third",
    "key-term": "lower-third",
    "tool": "lower-right",
    "generic-image": "lower-right",
}

# Minimum gap between overlays (seconds) — avoid visual clutter
MIN_OVERLAY_GAP = 2.0


def compute_display_timing(mention, edl_segments):
    """Compute display timing for an overlay.

    The overlay should appear shortly after the mention starts and stay
    on screen for the default duration, but not extend past the end of
    the segment it falls in.
    """
    mention_type = mention["type"]
    source_start = mention["timing"]["source_start"]
    source_end = mention["timing"]["source_end"]

    # Display starts 0.5s after the mention begins (let the viewer hear the reference first)
    display_start = source_start + 0.5

    # Default duration for this type
    duration = DEFAULT_DURATIONS.get(mention_type, 5.0)

    # Find the EDL segment this mention falls in
    containing_seg = None
    for seg in edl_segments:
        if seg.get("action") == "keep" and seg["start"] <= source_start <= seg["end"]:
            containing_seg = seg
            break

    # Don't extend past the segment boundary
    if containing_seg:
        max_end = containing_seg["end"]
        display_end = min(display_start + duration, max_end - 0.3)
    else:
        display_end = display_start + duration

    # Ensure minimum display time
    actual_duration = max(display_end - display_start, 2.0)

    return {
        "source_start": round(display_start, 3),
        "source_end": round(display_start + actual_duration, 3),
        "display_duration": round(actual_duration, 3),
    }


def resolve_overlaps(overlays):
    """Resolve overlapping overlays by shifting later ones or shortening earlier ones."""
    if len(overlays) < 2:
        return overlays

    overlays.sort(key=lambda o: o["timing"]["source_start"])

    for i in range(1, len(overlays)):
        prev_end = overlays[i - 1]["timing"]["source_end"]
        curr_start = overlays[i]["timing"]["source_start"]

        if curr_start < prev_end + MIN_OVERLAY_GAP:
            # Shorten the previous overlay
            new_end = curr_start - MIN_OVERLAY_GAP
            if new_end - overlays[i - 1]["timing"]["source_start"] >= 2.0:
                overlays[i - 1]["timing"]["source_end"] = round(new_end, 3)
                overlays[i - 1]["timing"]["display_duration"] = round(
                    new_end - overlays[i - 1]["timing"]["source_start"], 3
                )
            else:
                # Shift the current overlay later instead
                new_start = prev_end + MIN_OVERLAY_GAP
                shift = new_start - curr_start
                overlays[i]["timing"]["source_start"] = round(new_start, 3)
                overlays[i]["timing"]["source_end"] = round(
                    overlays[i]["timing"]["source_end"] + shift, 3
                )

    return overlays


def generate_overlay_spec(mentions_data, edl):
    """Generate overlay specification from mentions and EDL.

    Args:
        mentions_data: Parsed mentions JSON (with assets)
        edl: Parsed EDL JSON

    Returns:
        Overlay spec dict
    """
    mentions = mentions_data.get("mentions", [])
    edl_segments = edl.get("segments", [])
    source_file = mentions_data.get("source_file", "")
    stem = mentions_data.get("stem", "")

    overlays = []
    for mention in mentions:
        timing = compute_display_timing(mention, edl_segments)
        position = DEFAULT_POSITIONS.get(mention["type"], "lower-right")

        overlay = {
            "id": mention["id"],
            "type": mention["type"],
            "label": mention["label"],
            "timing": timing,
            "position": position,
        }

        if mention.get("url"):
            overlay["url"] = mention["url"]
        if mention.get("asset_path"):
            overlay["asset_path"] = mention["asset_path"]
        if mention.get("metadata"):
            overlay["metadata"] = mention["metadata"]

        overlays.append(overlay)

    # Resolve overlapping overlays
    overlays = resolve_overlaps(overlays)

    return {
        "source_file": source_file,
        "stem": stem,
        "overlays": overlays,
    }


# ── CLI ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: uv run generate_overlay_spec.py <mentions_json> <edl_json> [--output-dir <dir>]")
        sys.exit(1)

    mentions_path = sys.argv[1]
    edl_path = sys.argv[2]
    output_dir = None

    args = sys.argv[3:]
    i = 0
    while i < len(args):
        if args[i] == "--output-dir" and i + 1 < len(args):
            output_dir = args[i + 1]
            i += 2
        else:
            i += 1

    with open(mentions_path) as f:
        mentions_data = json.load(f)
    with open(edl_path) as f:
        edl = json.load(f)

    stem = mentions_data.get("stem", "unknown")

    if output_dir is None:
        output_dir = os.path.dirname(os.path.abspath(mentions_path))
    os.makedirs(output_dir, exist_ok=True)

    print(f"Generating overlay spec for: {stem}")
    spec = generate_overlay_spec(mentions_data, edl)
    print(f"  {len(spec['overlays'])} overlays:")

    for o in spec["overlays"]:
        t = o["timing"]
        has_asset = "asset" if o.get("asset_path") else "text-only"
        print(f"  [{t['source_start']:.1f}–{t['source_end']:.1f}s] {o['type']}: {o['label']} ({has_asset})")

    output_path = os.path.join(output_dir, f"{stem}_overlays.json")
    with open(output_path, "w") as f:
        json.dump(spec, f, indent=2)
    print(f"\nOverlay spec saved to {output_path}")

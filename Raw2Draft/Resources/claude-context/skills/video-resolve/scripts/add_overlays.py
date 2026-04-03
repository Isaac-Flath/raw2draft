"""Add overlays (titles and images) to a DaVinci Resolve timeline.

Takes an overlay spec JSON and adds each overlay to the current timeline
as either a Text+ title or an image on a higher video track.

Usage:
    python3 add_overlays.py <overlays_json> [--project <name>]

Requires DaVinci Resolve Studio to be running with the project open.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from resolve_api import connect, add_title, add_image_overlay, switch_to_edit_page


def add_overlays(overlays_path: str, edl_path: str = None, project_name: str = None):
    """Add overlays from spec to the current Resolve timeline."""

    with open(overlays_path) as f:
        spec = json.load(f)

    overlays = spec.get('overlays', [])
    if not overlays:
        print("No overlays to add.")
        return

    # If EDL provided, build source-to-timeline mapping
    timeline_map = None
    if edl_path:
        with open(edl_path) as f:
            edl = json.load(f)
        kept = [s for s in edl['segments'] if s.get('action') == 'keep']
        timeline_map = []
        tl_pos = 0.0
        for seg in kept:
            timeline_map.append((seg['start'], seg['end'], tl_pos))
            tl_pos += seg['end'] - seg['start']

    def source_to_timeline(src_time):
        """Map source timestamp to edited timeline position."""
        if timeline_map is None:
            return src_time
        for src_start, src_end, tl_start in timeline_map:
            if src_start <= src_time <= src_end:
                return tl_start + (src_time - src_start)
        # Nearest
        best = 0.0
        best_dist = float('inf')
        for src_start, src_end, tl_start in timeline_map:
            for st, tt in [(src_start, tl_start), (src_end, tl_start + src_end - src_start)]:
                if abs(src_time - st) < best_dist:
                    best_dist = abs(src_time - st)
                    best = tt
        return best

    # Connect to Resolve
    print("Connecting to DaVinci Resolve...")
    resolve, pm, project = connect()

    if project_name:
        project = pm.LoadProject(project_name)
        if not project:
            raise RuntimeError(f"Cannot load project: {project_name}")

    switch_to_edit_page(resolve)

    timeline = project.GetCurrentTimeline()
    if not timeline:
        raise RuntimeError("No current timeline. Open a timeline first.")

    fps = float(project.GetSetting("timelineFrameRate") or 25)
    print(f"Timeline: {timeline.GetName()} @ {fps}fps")
    print(f"Adding {len(overlays)} overlays...")

    for overlay in overlays:
        src_start = overlay['timing']['source_start']
        tl_start = source_to_timeline(src_start)
        duration = overlay['timing'].get('display_duration', 5.0)
        start_frame = int(round(tl_start * fps))
        dur_frames = int(round(duration * fps))

        overlay_type = overlay.get('type', 'key-term')
        label = overlay.get('label', '')
        position = overlay.get('position', 'lower-right')

        # Map position names to Resolve coordinates
        pos_map = {
            'lower-right': (0.3, -0.3),
            'lower-third': (0.0, -0.35),
            'lower-left': (-0.3, -0.3),
            'upper-right': (0.3, 0.3),
            'center': (0.0, 0.0),
        }
        pos_x, pos_y = pos_map.get(position, (0.3, -0.3))

        if overlay_type in ('blog-card', 'generic-image') and overlay.get('asset_path'):
            # Image overlay
            asset_path = overlay['asset_path']
            if not os.path.isabs(asset_path):
                asset_path = os.path.join(os.path.dirname(overlays_path), asset_path)

            print(f"  [{overlay['id']}] Image: {label} @ {tl_start:.1f}s ({dur_frames}f)")
            add_image_overlay(
                project, timeline,
                image_path=asset_path,
                track_index=3,
                start_frame=start_frame,
                duration_frames=dur_frames,
                scale=0.4,
                position_x=pos_x,
                position_y=pos_y,
            )
        else:
            # Text title overlay
            url = overlay.get('url', '')
            display_text = label
            if url:
                display_text = f"{label}\n{url}"

            print(f"  [{overlay['id']}] Title: {label} @ {tl_start:.1f}s ({dur_frames}f)")
            add_title(
                timeline,
                text=display_text,
                track_index=2,
                start_frame=start_frame,
                duration_frames=dur_frames,
                position_x=pos_x,
                position_y=pos_y,
            )

    print(f"\nDone. {len(overlays)} overlays added to timeline.")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 add_overlays.py <overlays_json> [--edl <edl_json>] [--project <name>]")
        sys.exit(1)

    overlays_path = sys.argv[1]
    edl_path = None
    project_name = None

    args = sys.argv[2:]
    i = 0
    while i < len(args):
        if args[i] == "--edl" and i + 1 < len(args):
            edl_path = args[i + 1]
            i += 2
        elif args[i] == "--project" and i + 1 < len(args):
            project_name = args[i + 1]
            i += 2
        else:
            i += 1

    add_overlays(overlays_path, edl_path, project_name)

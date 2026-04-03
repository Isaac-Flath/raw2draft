"""Build a DaVinci Resolve project from analysis JSON + EDL.

Takes the same analysis and EDL files produced by the video-editor skill
and creates a complete Resolve project with all cuts applied.

Usage:
    python3 build_project.py <analysis_json> <edl_json> [--name <project_name>]

Requires DaVinci Resolve Studio to be running.
"""

import json
import os
import sys
from pathlib import Path

# Add parent directory to path for resolve_api import
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from resolve_api import (
    connect,
    create_project,
    create_timeline,
    import_media,
    append_clips,
    switch_to_edit_page,
)


def build_project(analysis_path: str, edl_path: str, project_name: str = "Edit"):
    """Build a Resolve project from analysis + EDL."""

    # Load data
    with open(analysis_path) as f:
        analysis = json.load(f)
    with open(edl_path) as f:
        edl = json.load(f)

    meta = analysis['metadata']
    source_file = analysis['source_file']
    video_info = meta.get('video', {})
    fps = video_info.get('fps', 25.0)
    width = video_info.get('width', 1920)
    height = video_info.get('height', 1080)

    # Connect to Resolve
    print("Connecting to DaVinci Resolve...")
    resolve, pm, _ = connect()
    print(f"  Connected: {resolve.GetProductName()} {resolve.GetVersionString()}")

    # Switch to Edit page
    switch_to_edit_page(resolve)

    # Create project
    print(f"Creating project: {project_name}")
    project = create_project(pm, project_name)

    # Import source media
    print(f"Importing: {source_file}")
    media_items = import_media(project, [source_file])
    source_item = media_items[0]
    print(f"  Imported: {source_item.GetName()}")

    # Create timeline
    stem = Path(source_file).stem
    print(f"Creating timeline: {stem}")
    timeline = create_timeline(project, stem, width=width, height=height, fps=fps)

    # Get kept segments from EDL
    kept_segments = [s for s in edl['segments'] if s.get('action') == 'keep']
    print(f"Adding {len(kept_segments)} segments to timeline...")

    # Add segments
    items = append_clips(project, source_item, kept_segments, fps=fps)

    # Apply volume adjustments
    vol_adjusted = 0
    for i, (seg, item) in enumerate(zip(kept_segments, items)):
        vol_db = seg.get('volume_adjust_db', 0)
        if vol_db != 0 and item:
            # Resolve uses linear volume, not dB
            # Approximate: linear = 10^(dB/20)
            import math
            linear = math.pow(10, vol_db / 20.0)
            item.SetProperty("Volume", linear)
            vol_adjusted += 1

    total_kept = sum(s['end'] - s['start'] for s in kept_segments)
    print(f"\nProject built:")
    print(f"  Timeline: {stem}")
    print(f"  Clips: {len(items)}")
    print(f"  Duration: {int(total_kept//60)}:{int(total_kept%60):02d} "
          f"(from {int(meta['duration']//60)}:{int(meta['duration']%60):02d})")
    print(f"  Volume adjustments: {vol_adjusted}")
    print(f"\nOpen DaVinci Resolve to review the edit.")

    return project, timeline


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 build_project.py <analysis_json> <edl_json> [--name <project_name>]")
        sys.exit(1)

    analysis_path = sys.argv[1]
    edl_path = sys.argv[2]
    project_name = "Edit"

    args = sys.argv[3:]
    for i, arg in enumerate(args):
        if arg == "--name" and i + 1 < len(args):
            project_name = args[i + 1]

    build_project(analysis_path, edl_path, project_name)

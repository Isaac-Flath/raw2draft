"""Add chapter markers to a DaVinci Resolve timeline.

Usage:
    python3 add_markers.py <chapters_json> [--project <name>]
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from resolve_api import connect, add_markers, switch_to_edit_page


def main(chapters_path: str, project_name: str = None):
    with open(chapters_path) as f:
        chapters = json.load(f)

    if isinstance(chapters, dict):
        chapters = chapters.get('chapters', [])

    print("Connecting to DaVinci Resolve...")
    resolve, pm, project = connect()

    if project_name:
        project = pm.LoadProject(project_name)

    switch_to_edit_page(resolve)
    timeline = project.GetCurrentTimeline()
    if not timeline:
        raise RuntimeError("No current timeline")

    fps = float(project.GetSetting("timelineFrameRate") or 25)
    print(f"Adding {len(chapters)} markers to {timeline.GetName()}...")

    add_markers(timeline, chapters, fps=fps)
    print("Done.")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 add_markers.py <chapters_json> [--project <name>]")
        sys.exit(1)

    chapters_path = sys.argv[1]
    project_name = None
    if "--project" in sys.argv:
        idx = sys.argv.index("--project")
        if idx + 1 < len(sys.argv):
            project_name = sys.argv[idx + 1]

    main(chapters_path, project_name)

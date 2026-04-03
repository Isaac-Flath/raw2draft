"""DaVinci Resolve API wrapper — connect, import, timeline operations.

Handles the boilerplate of connecting to a running Resolve instance
and provides clean helpers for common operations.
"""

import os
import sys
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple


def _find_resolve_script_module():
    """Find and import DaVinci Resolve's scripting module.

    Resolve's Python module lives in a platform-specific location.
    This function adds the correct path to sys.path.
    """
    # macOS paths for DaVinci Resolve
    resolve_paths = [
        "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules",
        os.path.expanduser("~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules"),
    ]

    for p in resolve_paths:
        if os.path.isdir(p) and p not in sys.path:
            sys.path.insert(0, p)

    # Also check RESOLVE_SCRIPT_API env var
    env_path = os.environ.get("RESOLVE_SCRIPT_API")
    if env_path and os.path.isdir(env_path):
        sys.path.insert(0, os.path.join(env_path, "Modules"))


def connect() -> Tuple:
    """Connect to a running DaVinci Resolve instance.

    Returns (resolve, project_manager, current_project) tuple.
    Raises RuntimeError if Resolve is not running.
    """
    _find_resolve_script_module()

    try:
        import DaVinciResolveScript as dvr
    except ImportError:
        raise RuntimeError(
            "Cannot import DaVinci Resolve scripting module. "
            "Make sure DaVinci Resolve Studio is installed and running. "
            "The free version does not support scripting."
        )

    resolve = dvr.scriptapp("Resolve")
    if resolve is None:
        raise RuntimeError(
            "Cannot connect to DaVinci Resolve. "
            "Make sure it is running before executing this script."
        )

    pm = resolve.GetProjectManager()
    project = pm.GetCurrentProject()
    return resolve, pm, project


def create_project(pm, name: str):
    """Create a new project and return it."""
    project = pm.CreateProject(name)
    if project is None:
        # Project might already exist — try loading it
        project = pm.LoadProject(name)
        if project is None:
            raise RuntimeError(f"Failed to create or load project: {name}")
    return project


def import_media(project, file_paths: List[str]) -> List:
    """Import media files into the project's media pool.

    Returns list of MediaPoolItem objects.
    """
    media_pool = project.GetMediaPool()
    abs_paths = [os.path.abspath(p) for p in file_paths]
    items = media_pool.ImportMedia(abs_paths)
    if not items:
        raise RuntimeError(f"Failed to import media: {abs_paths}")
    return items


def create_timeline(project, name: str, width: int = 1920, height: int = 1080, fps: float = 25.0):
    """Create an empty timeline with specified settings."""
    # Set project settings for the timeline
    project.SetSetting("timelineResolutionWidth", str(width))
    project.SetSetting("timelineResolutionHeight", str(height))
    project.SetSetting("timelineFrameRate", str(fps))

    media_pool = project.GetMediaPool()
    timeline = media_pool.CreateEmptyTimeline(name)
    if timeline is None:
        raise RuntimeError(f"Failed to create timeline: {name}")
    project.SetCurrentTimeline(timeline)
    return timeline


def append_clips(
    project,
    media_pool_item,
    segments: List[dict],
    fps: float = 25.0,
) -> List:
    """Append segments from a single source to the current timeline.

    Each segment needs 'start' and 'end' in seconds.
    Returns list of TimelineItem objects.
    """
    media_pool = project.GetMediaPool()
    timeline_items = []

    for seg in segments:
        start_frame = int(round(seg['start'] * fps))
        end_frame = int(round(seg['end'] * fps))

        clip_info = {
            "mediaPoolItem": media_pool_item,
            "startFrame": start_frame,
            "endFrame": end_frame,
            "mediaType": 1,  # 1 = video+audio
        }

        result = media_pool.AppendToTimeline([clip_info])
        if result:
            timeline_items.extend(result)

    return timeline_items


def add_title(
    timeline,
    text: str,
    track_index: int = 2,
    start_frame: int = 0,
    duration_frames: int = 200,
    position_x: float = 0.0,
    position_y: float = -0.3,
    font_size: float = 0.05,
) -> Optional[object]:
    """Add a Text+ title to the timeline.

    Args:
        timeline: The Timeline object
        text: Text content to display
        track_index: Video track number (2 = first overlay track)
        start_frame: Frame position on timeline
        duration_frames: Duration in frames
        position_x: X position (-0.5 to 0.5, center = 0)
        position_y: Y position (-0.5 to 0.5, center = 0)
        font_size: Font size (0.0 to 1.0)

    Returns:
        TimelineItem or None
    """
    # InsertFusionTitleIntoTimeline places a Fusion Text+ title
    result = timeline.InsertFusionTitleIntoTimeline("Text+")
    if not result:
        # Fallback to standard title
        result = timeline.InsertTitleIntoTimeline("Text")

    # The title gets inserted at the playhead position
    # We need to move it to the right position and set its text
    # This requires accessing the Fusion composition
    return result


def add_image_overlay(
    project,
    timeline,
    image_path: str,
    track_index: int = 3,
    start_frame: int = 0,
    duration_frames: int = 200,
    scale: float = 0.3,
    position_x: float = 0.3,
    position_y: float = -0.3,
) -> Optional[object]:
    """Add an image as an overlay on a higher track.

    Args:
        project: The Project object
        timeline: The Timeline object
        image_path: Path to the image file
        track_index: Video track number (3 = second overlay track)
        start_frame: Frame position on timeline
        duration_frames: Duration in frames
        scale: Scale factor (0.0 to 1.0)
        position_x: X position (-0.5 to 0.5)
        position_y: Y position (-0.5 to 0.5)
    """
    media_pool = project.GetMediaPool()

    # Import the image
    items = media_pool.ImportMedia([os.path.abspath(image_path)])
    if not items:
        print(f"  Warning: failed to import {image_path}")
        return None

    # Add to timeline on specified track
    clip_info = {
        "mediaPoolItem": items[0],
        "startFrame": 0,
        "endFrame": duration_frames,
        "trackIndex": track_index,
        "recordFrame": start_frame,
        "mediaType": 1,
    }

    result = media_pool.AppendToTimeline([clip_info])
    if result:
        item = result[0]
        # Set transform properties
        item.SetProperty("ZoomX", scale)
        item.SetProperty("ZoomY", scale)
        item.SetProperty("Pan", position_x)
        item.SetProperty("Tilt", position_y)
        item.SetProperty("CompositeMode", 0)  # Normal blend mode
        return item
    return None


def add_markers(timeline, markers: List[dict], fps: float = 25.0):
    """Add markers to the timeline.

    Each marker needs 'timeline_secs', 'title', and optionally 'color'.
    """
    for m in markers:
        frame = int(round(m['timeline_secs'] * fps))
        color = m.get('color', 'Blue')
        timeline.AddMarker(
            frame, color,
            m['title'],
            m.get('note', ''),
            1,  # duration in frames
        )


def switch_to_edit_page(resolve):
    """Switch to the Edit page."""
    resolve.OpenPage("edit")
    time.sleep(0.5)

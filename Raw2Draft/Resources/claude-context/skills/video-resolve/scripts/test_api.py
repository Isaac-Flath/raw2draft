"""Test each Resolve API operation individually on a short test project.

Creates a 10-second test project and verifies:
1. Project creation + media import
2. Timeline creation + clip append with subclips
3. Adding a second video track + placing a title at a specific time
4. Setting the title text via Fusion comp
5. Adding image overlay on track 3 at a specific position
6. Adding timeline markers
"""
import os
import sys
import time

# Setup Resolve scripting module
SCRIPT_MODULES = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules"
if SCRIPT_MODULES not in sys.path:
    sys.path.insert(0, SCRIPT_MODULES)

import DaVinciResolveScript as dvr

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
SOURCE_VIDEO = os.path.join(PROJECT_ROOT, "raw", "My workflow with Just, Uv Scripts, air, and Agents.mp4")
TEST_PROJECT = "_API_Test"


def connect():
    resolve = dvr.scriptapp("Resolve")
    if not resolve:
        raise RuntimeError("Cannot connect to Resolve. Is it running?")
    pm = resolve.GetProjectManager()
    return resolve, pm


def cleanup(pm):
    """Delete test project if it exists."""
    existing = pm.LoadProject(TEST_PROJECT)
    if existing:
        pm.CloseProject(existing)
    # Need a temp project to delete the test one
    pm.CreateProject("_temp_cleanup")
    pm.DeleteProject(TEST_PROJECT)
    pm.CloseProject(pm.GetCurrentProject())
    pm.DeleteProject("_temp_cleanup")


def test_1_project_and_import(resolve, pm):
    """Test: Create project, import media."""
    print("\n=== TEST 1: Project creation + media import ===")
    resolve.OpenPage("edit")

    project = pm.CreateProject(TEST_PROJECT)
    assert project, "Failed to create project"
    print(f"  Created: {project.GetName()}")

    # Set to 30fps 1920x1080 for test
    project.SetSetting("timelineFrameRate", "30")
    project.SetSetting("timelineResolutionWidth", "1920")
    project.SetSetting("timelineResolutionHeight", "1080")

    media_pool = project.GetMediaPool()
    items = media_pool.ImportMedia([SOURCE_VIDEO])
    assert items and len(items) > 0, "Failed to import media"
    source = items[0]
    print(f"  Imported: {source.GetName()}")

    return project, media_pool, source


def test_2_timeline_and_clips(project, media_pool, source):
    """Test: Create timeline, append two subclips."""
    print("\n=== TEST 2: Timeline + subclip append ===")

    timeline = media_pool.CreateEmptyTimeline("Test Timeline")
    assert timeline, "Failed to create timeline"
    project.SetCurrentTimeline(timeline)
    print(f"  Created timeline: {timeline.GetName()}")

    # Append two 5-second clips (frames 180-330 and 900-1050 at 30fps)
    # Clip 1: 6s-11s of source (frames 180-330)
    # Clip 2: 30s-35s of source (frames 900-1050)
    clips = []
    for start_f, end_f, label in [(180, 330, "Clip A"), (900, 1050, "Clip B")]:
        result = media_pool.AppendToTimeline([{
            "mediaPoolItem": source,
            "startFrame": start_f,
            "endFrame": end_f,
            "mediaType": 1,  # 1 = video+audio
        }])
        assert result, f"Failed to append {label}"
        clips.extend(result)
        print(f"  Appended {label}: frames {start_f}-{end_f}")

    # Verify
    track1_items = timeline.GetItemListInTrack("video", 1)
    print(f"  Track 1 items: {len(track1_items)}")
    for item in track1_items:
        print(f"    {item.GetName()} @ timeline frames {item.GetStart()}-{item.GetEnd()}")

    audio1_items = timeline.GetItemListInTrack("audio", 1)
    print(f"  Audio track 1 items: {len(audio1_items) if audio1_items else 0}")

    return timeline, clips


def test_3_title_at_position(resolve, timeline):
    """Test: Insert Text+ title at a specific timeline position."""
    print("\n=== TEST 3: Insert title at specific position ===")

    # We want the title at frame 30 (1 second into timeline)
    target_frame = 30

    # Move playhead to target position using timecode
    # At 30fps, frame 30 = 00:00:01:00
    fps = 30
    hours = 0
    minutes = 0
    seconds = target_frame // fps
    frames = target_frame % fps
    tc = f"{hours:02d}:{minutes:02d}:{seconds:02d}:{frames:02d}"
    print(f"  Setting playhead to timecode: {tc} (frame {target_frame})")
    result = timeline.SetCurrentTimecode(tc)
    print(f"  SetCurrentTimecode result: {result}")
    print(f"  Current timecode: {timeline.GetCurrentTimecode()}")
    time.sleep(0.3)

    # Insert title
    title_item = timeline.InsertFusionTitleIntoTimeline("Text+")
    print(f"  InsertFusionTitleIntoTimeline result: {title_item}")

    # Check what tracks we have now
    track_count = timeline.GetTrackCount("video")
    print(f"  Video tracks after insert: {track_count}")
    for t in range(1, track_count + 1):
        items = timeline.GetItemListInTrack("video", t)
        if items:
            for item in items:
                print(f"    Track {t}: {item.GetName()} @ {item.GetStart()}-{item.GetEnd()}")

    return title_item


def test_4_set_title_text(timeline):
    """Test: Set the text content of the title via Fusion comp."""
    print("\n=== TEST 4: Set title text via Fusion ===")

    # Find the Text+ item
    track_count = timeline.GetTrackCount("video")
    title_item = None
    for t in range(1, track_count + 1):
        items = timeline.GetItemListInTrack("video", t)
        if items:
            for item in items:
                if "Text" in (item.GetName() or ""):
                    title_item = item
                    break
        if title_item:
            break

    if not title_item:
        print("  ERROR: No title item found!")
        return

    print(f"  Found title: {title_item.GetName()} on track")
    print(f"  Fusion comp count: {title_item.GetFusionCompCount()}")

    comp = title_item.GetFusionCompByIndex(1)
    if not comp:
        print("  ERROR: No Fusion comp found!")
        return

    tools = comp.GetToolList(False)
    print(f"  Tools in comp: {list(tools.keys())}")

    for tool_name, tool in tools.items():
        attrs = tool.GetAttrs()
        reg_id = attrs.get("TOOLS_RegID", "")
        print(f"    Tool: {tool_name}, RegID: {reg_id}")

        if reg_id == "TextPlus":
            # Get current text
            current = tool.GetInput("StyledText")
            print(f"    Current text: '{current}'")

            # Set new text
            tool.SetInput("StyledText", "Hello from API!")
            new_text = tool.GetInput("StyledText")
            print(f"    After SetInput: '{new_text}'")

            # Try setting font and size
            tool.SetInput("Font", "Open Sans")
            tool.SetInput("Style", "Bold")
            tool.SetInput("Size", 0.08)

            # Set position (Center is {1: x, 2: y} in 0-1 range)
            tool.SetInput("Center", {1: 0.5, 2: 0.1})  # Bottom center

            print(f"    Font: {tool.GetInput('Font')}")
            print(f"    Size: {tool.GetInput('Size')}")
            print(f"    Center: {tool.GetInput('Center')}")
            break


def test_5_image_overlay(project, media_pool, timeline):
    """Test: Add an image as overlay on track 3."""
    print("\n=== TEST 5: Image overlay on track 3 ===")

    # Use one of the existing overlay assets
    img_path = os.path.join(PROJECT_ROOT, "claude-edits", "overlays", "assets", "mention_000.png")
    if not os.path.exists(img_path):
        print(f"  SKIP: Image not found at {img_path}")
        return

    # Add video track if needed
    while timeline.GetTrackCount("video") < 3:
        timeline.AddTrack("video")
    print(f"  Video tracks: {timeline.GetTrackCount('video')}")

    # Import image
    img_items = media_pool.ImportMedia([img_path])
    assert img_items, "Failed to import image"
    print(f"  Imported image: {img_items[0].GetName()}")

    # Place on track 3 at frame 60 (2 seconds in), for 90 frames (3 seconds)
    result = media_pool.AppendToTimeline([{
        "mediaPoolItem": img_items[0],
        "startFrame": 0,
        "endFrame": 90,
        "trackIndex": 3,
        "recordFrame": 60,
        "mediaType": 1,
    }])
    print(f"  AppendToTimeline result: {result}")

    if result:
        item = result[0]
        print(f"  Placed: {item.GetName()} @ {item.GetStart()}-{item.GetEnd()}")

        # Set position/scale
        item.SetProperty("ZoomX", 0.3)
        item.SetProperty("ZoomY", 0.3)
        item.SetProperty("Pan", 500.0)   # Right side
        item.SetProperty("Tilt", -400.0) # Lower

        props = item.GetProperty()
        print(f"  ZoomX: {props.get('ZoomX')}, Pan: {props.get('Pan')}, Tilt: {props.get('Tilt')}")

    # Check track 3
    t3_items = timeline.GetItemListInTrack("video", 3)
    print(f"  Track 3 items: {len(t3_items) if t3_items else 0}")


def test_6_markers(timeline):
    """Test: Add markers to timeline."""
    print("\n=== TEST 6: Timeline markers ===")

    timeline.AddMarker(0, "Blue", "Chapter 1: Intro", "", 1)
    timeline.AddMarker(150, "Green", "Chapter 2: Middle", "", 1)

    markers = timeline.GetMarkers()
    print(f"  Markers: {markers}")


def main():
    print("DaVinci Resolve API Test Suite")
    print("=" * 50)

    resolve, pm = connect()
    print(f"Connected: {resolve.GetProductName()} {resolve.GetVersionString()}")

    cleanup(pm)

    project, media_pool, source = test_1_project_and_import(resolve, pm)
    timeline, clips = test_2_timeline_and_clips(project, media_pool, source)
    test_3_title_at_position(resolve, timeline)
    test_4_set_title_text(timeline)
    test_5_image_overlay(project, media_pool, timeline)
    test_6_markers(timeline)

    print("\n" + "=" * 50)
    print("All tests complete. Check the '_API_Test' project in Resolve.")
    print("You should see:")
    print("  - Track 1: Two 5-second video clips with audio")
    print("  - Track 2: A Text+ title saying 'Hello from API!' at ~1s")
    print("  - Track 3: An image overlay at ~2s")
    print("  - Two chapter markers (blue at 0s, green at 5s)")


if __name__ == "__main__":
    main()

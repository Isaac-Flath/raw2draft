#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "assemblyai>=0.54.1",
#     "python-dotenv>=1.2.2",
# ]
# ///
"""Phase 1: Analyze a video file — metadata, silence detection, audio levels, transcription."""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

from transcribe import transcribe_video


def get_metadata(video_path: str) -> dict:
    """Extract video metadata via ffprobe."""
    result = subprocess.run(
        ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_format", "-show_streams", video_path],
        capture_output=True, text=True, check=True,
    )
    probe = json.loads(result.stdout)

    video_stream = next((s for s in probe["streams"] if s["codec_type"] == "video"), None)
    audio_stream = next((s for s in probe["streams"] if s["codec_type"] == "audio"), None)

    metadata = {
        "duration": float(probe["format"]["duration"]),
        "size_mb": round(int(probe["format"]["size"]) / 1024 / 1024, 1),
        "format": probe["format"]["format_name"],
    }

    if video_stream:
        # Parse framerate from r_frame_rate (e.g., "30000/1001")
        fps_parts = video_stream.get("r_frame_rate", "30/1").split("/")
        fps_num = int(fps_parts[0])
        fps_den = int(fps_parts[1]) if len(fps_parts) > 1 else 1

        metadata["video"] = {
            "codec": video_stream.get("codec_name"),
            "width": int(video_stream.get("width", 0)),
            "height": int(video_stream.get("height", 0)),
            "fps": round(fps_num / fps_den, 3),
            "fps_num": fps_num,
            "fps_den": fps_den,
        }

    if audio_stream:
        metadata["audio"] = {
            "codec": audio_stream.get("codec_name"),
            "sample_rate": int(audio_stream.get("sample_rate", 0)),
            "channels": int(audio_stream.get("channels", 0)),
        }

    return metadata


def detect_silence(video_path: str, threshold_db: float = -30, min_duration: float = 1.5) -> list[dict]:
    """Detect silent segments using ffmpeg silencedetect filter."""
    result = subprocess.run(
        [
            "ffmpeg", "-i", video_path, "-af",
            f"silencedetect=noise={threshold_db}dB:d={min_duration}",
            "-f", "null", "-",
        ],
        capture_output=True, text=True,
    )
    output = result.stderr

    silences = []
    starts = re.findall(r"silence_start: ([\d.]+)", output)
    ends = re.findall(r"silence_end: ([\d.]+) \| silence_duration: ([\d.]+)", output)

    for i, start in enumerate(starts):
        silence = {"start": float(start)}
        if i < len(ends):
            silence["end"] = float(ends[i][0])
            silence["duration"] = float(ends[i][1])
        silences.append(silence)

    return silences


def get_audio_levels(video_path: str) -> dict:
    """Get overall audio levels using ffmpeg astats filter."""
    result = subprocess.run(
        [
            "ffmpeg", "-i", video_path, "-af",
            "astats=metadata=1:reset=0",
            "-f", "null", "-",
        ],
        capture_output=True, text=True,
    )
    output = result.stderr

    levels = {}
    rms_match = re.search(r"RMS level dB:\s*([-\d.]+)", output)
    peak_match = re.search(r"Peak level dB:\s*([-\d.]+)", output)
    if rms_match:
        levels["rms_db"] = float(rms_match.group(1))
    if peak_match:
        levels["peak_db"] = float(peak_match.group(1))

    return levels


def analyze_video(video_path: str, output_dir: str, env_path: str | None = None) -> dict:
    """Run full analysis pipeline on a video file."""
    video_path = os.path.abspath(video_path)
    stem = Path(video_path).stem
    os.makedirs(output_dir, exist_ok=True)

    print(f"Analyzing: {video_path}")
    print(f"Output dir: {output_dir}")

    # Step 1: Metadata
    print("\n[1/4] Extracting metadata...")
    metadata = get_metadata(video_path)
    print(f"  Duration: {metadata['duration']:.1f}s, Size: {metadata['size_mb']}MB")
    if "video" in metadata:
        v = metadata["video"]
        print(f"  Video: {v['width']}x{v['height']} @ {v['fps']}fps ({v['codec']})")
    if "audio" in metadata:
        a = metadata["audio"]
        print(f"  Audio: {a['sample_rate']}Hz, {a['channels']}ch ({a['codec']})")

    # Step 2: Silence detection
    print("\n[2/4] Detecting silence...")
    silences = detect_silence(video_path)
    print(f"  Found {len(silences)} silent segments")
    for s in silences[:5]:
        end_str = f" - {s['end']:.1f}s ({s['duration']:.1f}s)" if 'end' in s else ""
        print(f"    {s['start']:.1f}s{end_str}")
    if len(silences) > 5:
        print(f"    ... and {len(silences) - 5} more")

    # Step 3: Audio levels
    print("\n[3/4] Analyzing audio levels...")
    audio_levels = get_audio_levels(video_path)
    if audio_levels:
        print(f"  RMS: {audio_levels.get('rms_db', 'N/A')} dB, Peak: {audio_levels.get('peak_db', 'N/A')} dB")

    # Step 4: Transcription
    print("\n[4/4] Transcribing with AssemblyAI (verbatim mode)...")
    transcript = transcribe_video(video_path, env_path)
    word_count = len(transcript.get("words", []))
    print(f"  Transcribed {word_count} words")

    # Save transcript separately
    transcript_path = os.path.join(output_dir, f"{stem}_transcript.json")
    with open(transcript_path, "w") as f:
        json.dump(transcript, f, indent=2)
    print(f"  Transcript saved to {transcript_path}")

    # Compose analysis
    analysis = {
        "source_file": video_path,
        "metadata": metadata,
        "silences": silences,
        "audio_levels": audio_levels,
        "transcript": {
            "text": transcript.get("text", ""),
            "words": transcript.get("words", []),
            "segments": transcript.get("segments", []),
        },
    }

    # Save analysis JSON
    analysis_path = os.path.join(output_dir, f"{stem}_analysis.json")
    with open(analysis_path, "w") as f:
        json.dump(analysis, f, indent=2)
    print(f"\nAnalysis saved to {analysis_path}")

    return analysis


def _find_project_root(start_path: str) -> str:
    """Walk up from start_path to find the project root (contains .claude/ or .git/)."""
    current = os.path.dirname(start_path) if os.path.isfile(start_path) else start_path
    while current != os.path.dirname(current):  # stop at filesystem root
        if os.path.isdir(os.path.join(current, ".claude")) or os.path.isdir(os.path.join(current, ".git")):
            return current
        current = os.path.dirname(current)
    # Fallback: directory containing the video
    return os.path.dirname(start_path) if os.path.isfile(start_path) else start_path


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: uv run analyze.py <video_path> [--output-dir <dir>] [--env-path <path>]")
        sys.exit(1)

    video_path = sys.argv[1]
    output_dir = None
    env_path = None

    args = sys.argv[2:]
    i = 0
    while i < len(args):
        if args[i] == "--output-dir" and i + 1 < len(args):
            output_dir = args[i + 1]
            i += 2
        elif args[i] == "--env-path" and i + 1 < len(args):
            env_path = args[i + 1]
            i += 2
        else:
            i += 1

    if output_dir is None:
        # Default to claude-edits/ in the project root (where the video likely lives)
        video_abs = os.path.abspath(video_path)
        project_root = _find_project_root(video_abs)
        output_dir = os.path.join(project_root, "claude-edits")

    analyze_video(video_path, output_dir, env_path)

#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = ["httpx", "python-dotenv", "assemblyai>=0.54.1"]
# ///
"""
Transcription helper supporting LemonFox and AssemblyAI providers.

Usage:
    uv run transcribe.py <video_path> [output_dir]                  # LemonFox (default)
    uv run transcribe.py --provider assemblyai <video_path> [output_dir]  # AssemblyAI

Requires:
    - LEMONFOX_API_KEY or ASSEMBLYAI_API_KEY environment variable (or in .env file)
    - ffmpeg / ffprobe
"""

import os
import subprocess
import sys
import json
import tempfile
import time
from pathlib import Path
from datetime import datetime

from dotenv import load_dotenv
import httpx

# Load .env file from current directory or parent directories
load_dotenv()


def get_video_duration(video_path: Path) -> float:
    """Get video duration in seconds using ffprobe."""
    result = subprocess.run([
        "ffprobe", "-v", "error",
        "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1",
        str(video_path)
    ], capture_output=True, text=True)

    if result.returncode != 0:
        print(f"Error getting duration: {result.stderr}")
        return 0.0

    return float(result.stdout.strip())


def format_timestamp(seconds: float) -> str:
    """Format seconds as MM:SS or HH:MM:SS."""
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    secs = int(seconds % 60)

    if hours > 0:
        return f"{hours}:{minutes:02d}:{secs:02d}"
    return f"{minutes}:{secs:02d}"


def has_audio_stream(video_path: Path) -> bool:
    """Check if video has an audio stream."""
    result = subprocess.run([
        "ffprobe", "-v", "error",
        "-select_streams", "a",
        "-show_entries", "stream=codec_type",
        "-of", "csv=p=0",
        str(video_path)
    ], capture_output=True, text=True)
    return "audio" in result.stdout


def extract_audio(video_path: Path, output_path: Path, bitrate: str = "64k") -> float:
    """Extract audio from video as MP3 with specified bitrate. Returns file size in MB."""
    result = subprocess.run([
        "ffmpeg", "-y", "-i", str(video_path),
        "-vn", "-acodec", "libmp3lame", "-ab", bitrate,
        str(output_path)
    ], capture_output=True, text=True)

    if result.returncode != 0:
        raise RuntimeError(f"ffmpeg error: {result.stderr}")

    return output_path.stat().st_size / (1024 * 1024)


def extract_audio_for_transcription(video_path: Path, output_path: Path) -> None:
    """
    Extract audio from video and compress to fit LemonFox's 100MB upload limit.
    """
    print(f"Extracting audio from {video_path.name}...")

    if not has_audio_stream(video_path):
        raise ValueError("Video has no audio stream. Cannot transcribe.")

    for bitrate in ["64k", "48k", "32k"]:
        file_size_mb = extract_audio(video_path, output_path, bitrate)

        if file_size_mb < 100:
            print(f"Audio compressed to {file_size_mb:.1f}MB at {bitrate}")
            return
        else:
            print(f"Audio still {file_size_mb:.1f}MB at {bitrate}, trying lower bitrate...")

    raise ValueError(
        f"Video is too long to transcribe ({file_size_mb:.1f}MB at 32kbps). "
        "Consider splitting the video."
    )


def timestamp_to_seconds(timestamp: str) -> float:
    """Convert HH:MM:SS.mmm or MM:SS.mmm to seconds."""
    parts = timestamp.replace(",", ".").split(":")
    if len(parts) == 3:  # HH:MM:SS.mmm
        hours, minutes, seconds = parts
        return int(hours) * 3600 + int(minutes) * 60 + float(seconds)
    elif len(parts) == 2:  # MM:SS.mmm
        minutes, seconds = parts
        return int(minutes) * 60 + float(seconds)
    else:
        return 0.0


def parse_vtt_segments(vtt_content: str) -> list[dict]:
    """Parse VTT format to extract segments."""
    lines = vtt_content.strip().split("\n")
    segments = []

    i = 0
    while i < len(lines):
        line = lines[i].strip()

        # Skip VTT header and empty lines
        if line.startswith("WEBVTT") or line == "":
            i += 1
            continue

        # Look for timestamp line (contains -->)
        if "-->" in line:
            timestamp_line = line
            i += 1

            # Collect all text lines until next timestamp or empty line
            text_lines = []
            while i < len(lines):
                text_line = lines[i].strip()
                if text_line == "" or "-->" in text_line:
                    break
                text_lines.append(text_line)
                i += 1

            if text_lines:
                start_str, end_str = timestamp_line.split(" --> ")
                start_seconds = timestamp_to_seconds(start_str)
                end_seconds = timestamp_to_seconds(end_str)

                segments.append({
                    "start": start_seconds,
                    "end": end_seconds,
                    "text": " ".join(text_lines),
                })
        else:
            i += 1

    return segments


def transcribe_with_lemonfox(video_path: Path, output_dir: Path) -> dict:
    """Transcribe using LemonFox Whisper v3 API."""
    api_key = os.environ.get("LEMONFOX_API_KEY")
    if not api_key:
        print("Error: LEMONFOX_API_KEY environment variable not set")
        sys.exit(1)

    print(f"Transcribing: {video_path.name}")
    print("This may take a while depending on video length...")

    # Create temporary file for extracted audio
    with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as tmp_audio:
        audio_path = Path(tmp_audio.name)

    try:
        # Extract and compress audio
        extract_audio_for_transcription(video_path, audio_path)

        # Send to LemonFox
        print("Sending audio to LemonFox Whisper v3 API...")

        max_retries = 3
        retry_delay = 2

        for attempt in range(max_retries):
            try:
                timeout = httpx.Timeout(30.0, read=600.0, write=600.0)
                with httpx.Client(timeout=timeout) as client:
                    with open(audio_path, "rb") as audio_file:
                        response = client.post(
                            "https://api.lemonfox.ai/v1/audio/transcriptions",
                            headers={"Authorization": f"Bearer {api_key}"},
                            files={"file": ("audio.mp3", audio_file, "audio/mpeg")},
                            data={"response_format": "vtt"},
                        )

                    response.raise_for_status()
                    vtt_content = response.text

                    # API returns JSON-encoded string, need to parse it
                    if vtt_content.startswith('"'):
                        vtt_content = json.loads(vtt_content)

                    # Parse VTT to extract segments
                    segments = parse_vtt_segments(vtt_content)

                    # Build full text from segments
                    full_text = " ".join(seg["text"] for seg in segments)

                    print(f"Transcription complete: {len(segments)} segments")

                    return {
                        "text": full_text,
                        "vtt": vtt_content,
                        "segments": segments,
                    }

            except (httpx.HTTPStatusError, httpx.RemoteProtocolError) as e:
                should_retry = False

                if isinstance(e, httpx.HTTPStatusError):
                    should_retry = e.response.status_code >= 500
                elif isinstance(e, httpx.RemoteProtocolError):
                    should_retry = True

                if should_retry and attempt < max_retries - 1:
                    print(f"API error (attempt {attempt + 1}/{max_retries}): {e}, retrying...")
                    time.sleep(retry_delay)
                    retry_delay *= 2
                else:
                    print(f"LemonFox API transcription failed: {e}")
                    raise

        raise RuntimeError("Transcription failed after all retry attempts")

    finally:
        # Clean up temporary audio file
        if audio_path.exists():
            audio_path.unlink()


def transcribe_with_assemblyai(video_path: Path, output_dir: Path) -> dict:
    """Transcribe using AssemblyAI with word-level timestamps and disfluencies preserved."""
    import assemblyai as aai

    api_key = os.environ.get("ASSEMBLYAI_API_KEY")
    if not api_key:
        print("Error: ASSEMBLYAI_API_KEY environment variable not set")
        sys.exit(1)

    aai.settings.api_key = api_key

    print(f"Transcribing: {video_path.name}")
    print("Sending to AssemblyAI (word-level timestamps, disfluencies preserved)...")

    config = aai.TranscriptionConfig(
        speech_models=["universal-3-pro", "universal-2"],
        disfluencies=True,
    )

    transcriber = aai.Transcriber()
    transcript = transcriber.transcribe(str(video_path), config=config)

    if transcript.status == aai.TranscriptStatus.error:
        raise RuntimeError(f"Transcription failed: {transcript.error}")

    words = [
        {"word": w.text, "start": w.start / 1000, "end": w.end / 1000}
        for w in transcript.words
    ]

    print(f"Transcription complete: {len(words)} words")

    return {"text": transcript.text, "words": words, "segments": None}


def generate_chapters(data: dict, duration: float) -> list:
    """Generate chapter markers from transcript segments."""
    segments = data.get("segments", [])
    if not segments:
        return []

    # Simple chapter generation: split into ~5-8 chapters based on duration
    chapters = []
    chapter_duration = max(duration / 6, 120)  # At least 2 minutes per chapter

    current_chapter_start = 0
    current_chapter_text = []

    for segment in segments:
        seg_start = segment.get("start", 0)
        seg_text = segment.get("text", "").strip()

        if seg_start - current_chapter_start >= chapter_duration and current_chapter_text:
            chapters.append({
                "start": current_chapter_start,
                "end": seg_start,
                "title": f"Section {len(chapters) + 1}",
                "summary": " ".join(current_chapter_text[:50])[:200] + "..."
            })
            current_chapter_start = seg_start
            current_chapter_text = []

        current_chapter_text.append(seg_text)

    # Final chapter
    if current_chapter_text:
        chapters.append({
            "start": current_chapter_start,
            "end": duration,
            "title": f"Section {len(chapters) + 1}",
            "summary": " ".join(current_chapter_text[:50])[:200] + "..."
        })

    return chapters


def save_transcript(data: dict, video_path: Path, output_dir: Path, duration: float):
    """Save transcript as markdown."""
    transcript_path = output_dir / "transcript.md"

    text = data.get("text", "")
    segments = data.get("segments", [])

    if segments:
        timestamped_lines = []
        for segment in segments:
            seg_text = segment.get("text", "").strip()
            if not seg_text:
                continue
            seg_start = format_timestamp(segment.get("start", 0))
            timestamped_lines.append(f"{seg_start} {seg_text}")
        transcript_body = "\n".join(timestamped_lines)
    else:
        transcript_body = text

    content = f"""# Transcript

**Source:** {video_path.name}
**Duration:** {format_timestamp(duration)}
**Transcribed:** {datetime.now().strftime("%Y-%m-%d %H:%M")}

---

{transcript_body}
"""

    with open(transcript_path, "w") as f:
        f.write(content)

    print(f"Saved transcript to {transcript_path}")
    return transcript_path


def save_description(chapters: list, output_dir: Path, video_name: str):
    """Save video description with chapters in YouTube-compatible format."""
    description_path = output_dir / "description.md"

    lines = []

    # Placeholder for description (to be filled in manually or by LLM)
    lines.append(f"<!-- Add video description here -->")
    lines.append("")
    lines.append("")

    # Chapters in YouTube format: timestamp then title
    for ch in chapters:
        timestamp = format_timestamp(ch["start"])
        lines.append(f"{timestamp} {ch['title']}")

    with open(description_path, "w") as f:
        f.write("\n".join(lines))

    print(f"Saved description to {description_path}")

    print("\nChapters:")
    for ch in chapters:
        print(f"  {format_timestamp(ch['start'])} {ch['title']}")

    return description_path


def main():
    # Parse --provider flag
    args = sys.argv[1:]
    provider = "lemonfox"

    if "--provider" in args:
        idx = args.index("--provider")
        if idx + 1 >= len(args):
            print("Error: --provider requires a value (lemonfox or assemblyai)")
            sys.exit(1)
        provider = args[idx + 1]
        args = args[:idx] + args[idx + 2:]

    if not args:
        print("Usage: python transcribe.py [--provider lemonfox|assemblyai] <video_path> [output_dir]")
        print("\nExamples:")
        print("  python transcribe.py source/video.mp4 content")
        print("  python transcribe.py --provider assemblyai source/video.mp4 claude-edits")
        sys.exit(1)

    video_path = Path(args[0])
    output_dir = Path(args[1]) if len(args) > 1 else Path(".content")

    if not video_path.exists():
        print(f"Video not found: {video_path}")
        sys.exit(1)

    output_dir.mkdir(parents=True, exist_ok=True)

    # Get duration
    duration = get_video_duration(video_path)
    print(f"Video duration: {format_timestamp(duration)}")

    # Transcribe with selected provider
    if provider == "assemblyai":
        data = transcribe_with_assemblyai(video_path, output_dir)
    elif provider == "lemonfox":
        data = transcribe_with_lemonfox(video_path, output_dir)
    else:
        print(f"Error: unknown provider '{provider}'. Use 'lemonfox' or 'assemblyai'.")
        sys.exit(1)

    # Save transcript
    save_transcript(data, video_path, output_dir, duration)

    # Generate and save description with chapters (only for segment-level transcripts)
    if data.get("segments"):
        chapters = generate_chapters(data, duration)
        save_description(chapters, output_dir, video_path.name)

    print("\nTranscription complete!")


if __name__ == "__main__":
    main()

---
name: video-editor
description: Video Editor Skill (DaVinci Resolve)
---

# Video Editor Skill (DaVinci Resolve)

Edit YouTube videos by analyzing raw recordings, proposing cuts, and building the project in DaVinci Resolve via its Python scripting API. **Never render or overwrite original video files.**

## Output Directory

**All outputs go in `<project_root>/claude-edits/`.**

```
<project_root>/claude-edits/
    <video_stem>_analysis.json      # Metadata + silence + transcript
    <video_stem>_edl.json           # Cut decisions
    <video_stem>_review.md          # Human-readable review
    <video_stem>_transcript.json    # Raw transcript
```

## Tools Required
- `ffmpeg` / `ffprobe` — run directly via Bash
- AssemblyAI API — via `transcribe.py` (needs `uv run` for the package)
- DaVinci Resolve Studio — via inline Python (see video-resolve skill)

## Configuration
- AssemblyAI API key: `.env` file in the skill directory (`ASSEMBLYAI_API_KEY=...`)

## Workflow

### Phase 1: Analyze

Run these three steps and assemble the results into `_analysis.json`:

**1. Metadata** — run ffprobe directly:
```bash
ffprobe -v quiet -print_format json -show_format -show_streams <video_path>
```
Extract duration, resolution, fps, codec, audio info.

**2. Silence detection** — run ffmpeg directly:
```bash
ffmpeg -i <video_path> -af "silencedetect=noise=-30dB:d=1.5" -f null -
```
Parse `silence_start` / `silence_end` from stderr. Adjust thresholds based on audio quality:
- `-30dB` is the default. Noisier audio → lower (e.g., -40). Clean → higher (e.g., -25).
- `d=1.5` is minimum silence duration. Fast speaker → lower (e.g., 1.0).

**3. Transcription** — use the transcribe script (needs AssemblyAI package):
```bash
cd <project_root>/.claude/skills/video-editor
uv run scripts/transcribe.py <video_path>
```
Returns JSON with word-level timestamps and disfluencies preserved.

Assemble all three into `_analysis.json`.

### Phase 2: Propose Edits

**No script — read the transcript and make cut decisions directly.** See `references/editing-principles.md` for the full guide.

1. Read the word-level transcript from `_analysis.json`
2. Identify repeated takes, fillers, false starts, dead air, trailing incomplete thoughts
3. Decide keep or cut based on content understanding
4. Build the EDL JSON with kept segments using word-level timestamps
5. Write the review doc

### Phase 3: Build in DaVinci Resolve
Use the `video-resolve` skill — write inline Python via Bash to call the Resolve API directly.

## References
```
references/
    editing-principles.md        # Cut/keep guide + EDL format
    visual-editing-principles.md # Overlay, caption, and visual enhancement guide
```

## File Structure
```
scripts/
    transcribe.py       # AssemblyAI API (needs uv run for package)
```

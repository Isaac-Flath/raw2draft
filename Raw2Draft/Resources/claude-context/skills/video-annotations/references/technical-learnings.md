# Technical Learnings — Hard-Won Notes

Things that were painful to figure out. Read before building annotations.

## Coordinate Detection

### Use detect_bounds.py for coordinate detection
The `scripts/detect_bounds.py` script uses Gemini with structured prompting to return precise JSON bounding boxes for both text AND objects.

```bash
# Find specific target (text or object)
uv run scripts/detect_bounds.py frame.png "the robot character"
# Returns: [{"target": "the robot character", "x": 411, "y": 463, "width": 171, "height": 291, ...}]

# Find text
uv run scripts/detect_bounds.py frame.png "the words 'fully understand'"
# Returns: [{"target": "...", "x": 536, "y": 253, "width": 169, "height": 22, ...}]

# List all elements
uv run scripts/detect_bounds.py frame.png --all
```

Key insight: the old approach of asking Gemini "give me the center of X" gave rough estimates (50-150px off). The structured prompting in detect_bounds.py asks for tight bounding boxes with explicit JSON schema and gets results within 10-20px on the first try. The difference was the prompt, not the model.

## Annotation Positioning Gotchas

### Use ovals for text, circles for objects
A true circle around text has massive empty space above and below (text is wide and short). For text emphasis, use underlines or oval shapes that hug the text.

### Annotation timing is relative to the source video
If the video has been cut/edited, annotation timestamps need to be adjusted to match the edited timeline, not the raw source. When integrating with an edited Resolve project, map source timestamps to timeline timestamps using the EDL.

## Gemini Usage Patterns

### Gemini is good for:
- Positioning critique ("is this circle on the robot or the lego blocks?")
- Mobile readability review ("can you read this on a 6-inch screen?")
- Specific pixel adjustment recommendations ("move 20px left, 30px down")
- Getting approximate coordinates of illustration elements

### Gemini is bad for:
- Editorial decisions about WHAT to annotate (always decides to circle everything)
- Distinguishing between nearby elements in illustrations (confused robot with lego blocks multiple times)
- Understanding that sometimes NO annotation is the right choice
- Judging whether an annotation adds meaning vs. decoration

### The Gemini iteration loop
1. Add annotation → extract frame → send to Gemini with context about what the annotation is supposed to highlight
2. Gemini gives specific pixel adjustments (up/down/left/right + size changes)
3. Apply adjustments, re-check
4. Typically takes 2-4 rounds per element for illustrations, 1-2 for text overlays

### Always tell Gemini what the annotation SHOULD be targeting
Don't just ask "is this positioned well?" — say "this red circle should be around the ROBOT CHARACTER, not the text. Is it on the robot?" Otherwise Gemini will approve circles that technically look fine but target the wrong element.

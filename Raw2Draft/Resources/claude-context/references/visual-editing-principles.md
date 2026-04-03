# Visual Editing Principles for YouTube

These principles guide overlay placement, caption design, and visual enhancement decisions. They describe the mental model a professional YouTube editor uses — not prescriptive rules, but judgment frameworks.

## The Core Job

Every visual element you add must serve one purpose: **help the viewer understand what the speaker is saying**. If a text overlay, zoom, or annotation doesn't make the content clearer, more engaging, or easier to follow, it shouldn't be there.

## Designing for Mobile First

Over 70% of YouTube views happen on phones. Every visual decision must be evaluated at phone-screen size.

- **Text must be readable on a 6-inch screen.** If you squint to read it on a desktop preview, it's invisible on mobile. Err on the side of too big.
- **Center-screen text > corner text.** Corners on a phone are tiny. The center of the frame is the only safe zone for guaranteed readability.
- **Fewer words per card.** 4-8 words max. If you need more, break it into multiple sequential cards or rethink the phrasing.
- **High contrast is mandatory.** White text needs a dark background or heavy shadow. Always.

## Caption & Text Overlay Design

### When to add text

Add text when it **reinforces or clarifies** what's being said:
- The speaker introduces a key concept or tool name — text anchors it visually
- The speaker describes a process with multiple steps — text lists the steps
- The speaker mentions a URL, command, or name that's hard to catch by ear
- A key takeaway that you want the viewer to remember

Don't add text when:
- The content is already visible on screen (code on screen + text label = redundant)
- It's just echoing what the speaker is saying word-for-word (that's subtitles, not overlays)
- It doesn't add information beyond what's obvious

### Visual style

Study what works on successful channels:
- **Bold, clean sans-serif fonts** (Montserrat, Inter, SF Pro, not decorative fonts)
- **Large text** — it should feel almost too big on desktop. That means it's right for mobile.
- **Color accent on key words** — one word highlighted in a brand color (yellow, blue, green) while the rest stays white
- **Semi-transparent dark background bar** behind text for readability over any video content
- **Subtle animation** — fade in or slide up, not bouncing or spinning. The text should appear, be readable, and disappear. The animation serves readability (draws the eye), not entertainment.

### Placement

**Do not use fixed positions for all overlays.** Look at each frame and decide:

1. **Where is the speaker's face?** Never cover it.
2. **Where is the content the viewer needs to see?** (code, UI, slides) Never cover it.
3. **Where is dead space?** Place overlays there.
4. **Lower-third bars** work well for screen-share content because the bottom of the frame usually has status bars, terminals, or unused space. But verify per-frame.
5. **Center-screen text** works for talking-head segments or when emphasizing a major point.

### Verify placement with composites

Before finalizing, composite the overlay onto the extracted frame (ffmpeg overlay filter) and view the result. If it blocks content, covers the face, or looks awkward, adjust. Never trust coordinate math alone.

**The Resolve render→screenshot→Gemini loop is essential.** Static composites (ffmpeg overlay onto a frame) do not accurately represent how Resolve's Pan/Tilt/Zoom actually render. The DaVinci Resolve API coordinate system is unintuitive — Pan and Zoom values do not map to pixels in a predictable way. Always:

1. Place overlays in Resolve with your best guess
2. Render a short clip (use MarkIn/MarkOut to render just 5-10 seconds around one overlay)
3. Extract a frame with ffmpeg at the overlay timestamp
4. View the frame or send to Gemini for analysis
5. Adjust and repeat

This loop takes ~30 seconds per iteration and is the only reliable way to get positioning right. See `video-resolve/references/api_practical_notes.md` for calibrated Pan/Tilt/Zoom values.

### Webcam PiP awareness

Many screencast recordings have a webcam picture-in-picture, usually in the bottom-right corner. Overlay text bars that span the full width of the frame will cover the speaker's face. Solutions:
- Place overlays in the very bottom of the frame (below the webcam) using a lower Tilt value
- Or constrain overlay width so it doesn't reach the webcam area
- Always check frames where the speaker is visible — the webcam position may shift between recordings

## Pattern Interrupts and Pacing

Viewers' attention resets every 30-90 seconds. Professional editors add visual variety to maintain engagement:

- **Zoom cuts** — punch in 10-15% on the same camera angle to create a visual reset without additional footage. Good for emphasizing a point.
- **Text appearing/disappearing** — the overlay itself is a pattern interrupt when timed to key moments.
- **B-roll or screenshot inserts** — when the speaker mentions a tool or website, briefly show it.

The goal is **subtle rhythm**, not chaos. "Dynamic minimalism" — the mechanics work but don't distract.

## CTA (Call to Action) Placement

- **Don't put CTAs in the intro.** The viewer doesn't know you yet and will ignore it.
- **Mid-roll CTA** (60-70% through) is the sweet spot — the viewer is engaged and has gotten value.
- **Outro CTA** — larger, more prominent, since the video is ending and you want them to take action.
- CTAs should be **visually distinct** from informational overlays (different style, position, or animation).

## Image Overlays (Blog Cards, Screenshots)

When showing a website, blog post, or tool:
- Make it **large enough to actually read** — at least 30-40% of the frame width.
- Place it where there's empty space in the current frame, not in a fixed position.
- Show it for long enough to process (3-5 seconds minimum).
- It should feel like the editor deliberately placed it, not like a script dropped it there.

### Choosing the right image asset — evaluate per tool

There is no one-size-fits-all source. For each tool mentioned in the video, evaluate which asset is the most informative, readable, and visually appealing at overlay size (~30% of frame). The decision process:

1. **Check the tool's official website OG image first** (`fetch_og_metadata(url)`). If it exists and is:
   - Branded and visually distinctive (not just a generic template)
   - Readable at small sizes (big text, clean layout)
   - Informative (tells the viewer what the tool is)
   - Includes the URL already

   → **Use it.** Website OG cards that are well-designed are the best option because they're purpose-built for exactly this use case (social media previews at small size). Example: `airwebframework.org` has a beautiful branded card with tagline and URL.

2. **Fall back to GitHub social card** (`fetch_og_metadata('https://github.com/owner/repo')`) if:
   - The website has no OG image
   - The OG image is confusing (nav links, non-English text, multiple CTAs, dark/cryptic branding)
   - The OG image is a generic docs template that doesn't tell you anything

   GitHub cards are the reliable fallback — they always exist and show repo name, one-line description, star count, and logo. Developer audiences recognize them instantly. Example: `just.systems` has an OG image with "j u s t" in giant letters plus Discord/GitHub/Chinese characters — confusing at small size. The `github.com/casey/just` card is much more useful.

3. **Full-page screenshots** — last resort. Only if the page has a bold hero section. Text-heavy docs pages are unreadable at 30% frame width.

**Always view the fetched image before using it.** What looks fine at full size may be confusing, unreadable, or aesthetically wrong at overlay size. Fetch it, look at it, make a judgment call.

**Always link to the canonical source, not a fork.** Verify you have the original repo/org (e.g., `feldroy/air` not a personal fork).

### Visual polish for image cards

**Add a subtle drop shadow** to image cards, especially those with light backgrounds. Light cards on light IDE backgrounds blend in and look flat. A shadow creates a floating card effect that separates the overlay from the content underneath. See `api_practical_notes.md` for the ffmpeg technique.

**Add the URL below the card** if the card doesn't already include it. Use ffmpeg vstack to append a URL bar in blue text on light gray — mimics how social media link previews render. Skip this if the OG card already contains the URL (like the Air card does).

### Image overlay sizing vs text overlay sizing

Image overlays should be **smaller** than text overlays and placed in a **different position** (typically a corner opposite the webcam):
- **Text overlays**: ~47-54% of frame width, lower-third bar, left-aligned
- **Image overlays**: ~28-35% of frame width, upper-right corner, card-like

This creates visual variety and avoids competition between the two types.

### Cropping screenshots to useful regions

Full-page screenshots are often too text-heavy at overlay size. Crop to just the useful portion:

```bash
# Crop to top 400px (header/hero area)
ffmpeg -y -i screenshot.png -vf "crop=1920:400:0:0" -update 1 -frames:v 1 header.png
```

Then add a text bar (dark background, white text) below with ffmpeg vstack, and a drop shadow. This technique turns any webpage into a clean overlay card.

### Blog / companion content overlays

If the video has a companion blog post, add two overlays:

1. **Intro card (~5-10s in):** Screenshot of the article header, cropped to title area, with a bar below: "Read the full article - Link in description". Place in upper-right like other image overlays. Shows during the speaker's introduction.

2. **Outro card (~8s before end):** Screenshot of the blog/writing index page showing other articles, with a bar below: "More at domain.com/writing". Make slightly larger than tool overlays since it's a CTA. Shows during the closing remarks.

### Timing and sequencing

- **Don't stack image and text overlays simultaneously.** It creates visual clutter with competing focal points. Instead, sequence them: show the image card first (3-5s visual intro), let it disappear, then show the text takeaway.
- **Place image overlays at first mention.** When the speaker first names a tool, that's when the viewer benefits from seeing what it looks like. By the time they're deep into explaining it, the moment has passed.
- **Use a separate track** (e.g., track 3) to keep image overlays independent from text overlays on track 2.

## What NOT to Do

- **Don't label things already visible on screen.** If you're showing a justfile, don't overlay "Just (Command Runner)" — the viewer can see it.
- **Don't use tiny, subtle overlays.** If it's worth adding, it's worth making visible.
- **Don't use the same position/size for everything.** That's the hallmark of automated editing.
- **Don't add overlays just because you can.** Fewer, better-placed overlays > many mediocre ones.
- **Don't forget mobile.** Always ask: "Can someone read this on a phone?"

## Practical Workflow

1. Watch the edited video (or read the transcript) and identify moments that benefit from visual reinforcement
2. Extract a frame at each moment with ffmpeg
3. View the frame and decide: what type of overlay? where? how big? what text?
4. Render the overlay card (ffmpeg drawtext for text, or use the asset image)
5. Composite the overlay onto the frame to preview placement
6. Set exact Resolve Pan/Tilt/Zoom values per overlay, with notes explaining the reasoning
7. Build in Resolve and review

---
name: social-schedule
description: Schedule social media posts via Upload Post API. Use when user wants to schedule, publish, or manage social media content.
---

# /social-schedule

Schedule social media posts via the Upload Post API.

## Prerequisites

- `UPLOADPOST_API_KEY` must be set in Settings.
- Social content in `social/` (run `/content-social` first).

## Default Workflow

1. Validate API key → `GET /api/uploadposts/me`
2. List profiles → `GET /api/uploadposts/users`
3. Show schedule → `GET /api/uploadposts/schedule`
4. Inventory `social/` content
5. Check next slot → `GET /api/uploadposts/queue/next-slot?profile_username=USERNAME`
6. Recommend content → platform mapping, confirm with user
7. Execute schedule

## API Basics

```
Base URL:  https://api.upload-post.com/api
Auth:      Authorization: Apikey $UPLOADPOST_API_KEY
Format:    Form data (-F flags), NOT JSON
```

- Auth scheme is `Apikey` (not `Bearer`). Wrong scheme returns 404.
- All paths need `/api/` prefix.
- `title` = **the post body text** (required, despite the name).
- `scheduled_date` = ISO-8601 datetime in UTC.

---

## Platform Commands

Target platforms: LinkedIn, X, Threads, Bluesky.

**General rule for link preview cards:** When using `link_url` or `bluesky_link_url`, always strip the URL from the post text. Having the URL in both the text and the link parameter suppresses the preview card. The card handles the link — the URL in text is redundant.

### LinkedIn

**Text post:**
```bash
curl -s -X POST -H "Authorization: Apikey $UPLOADPOST_API_KEY" \
  -F "user=isaac" -F "platform[]=linkedin" \
  -F "title=POST_TEXT" \
  -F "scheduled_date=DATETIME_UTC" \
  https://api.upload-post.com/api/upload_text
```

**Text + link preview card:**
```bash
curl -s -X POST -H "Authorization: Apikey $UPLOADPOST_API_KEY" \
  -F "user=isaac" -F "platform[]=linkedin" \
  -F "title=POST_TEXT_WITHOUT_URL" \
  -F "link_url=https://example.com/article" \
  -F "scheduled_date=DATETIME_UTC" \
  https://api.upload-post.com/api/upload_text
```
**Important:** Strip the URL from the post text when using `link_url`. If the URL appears in both the text and `link_url`, the preview card may not render. The card handles the link.

**Text + image:**
```bash
curl -s -X POST -H "Authorization: Apikey $UPLOADPOST_API_KEY" \
  -F "user=isaac" -F "platform[]=linkedin" \
  -F "photos[]=@path/to/image.png" \
  -F "title=POST_TEXT" \
  -F "scheduled_date=DATETIME_UTC" \
  https://api.upload-post.com/api/upload_photos
```

**Text + video:**
```bash
curl -s -X POST -H "Authorization: Apikey $UPLOADPOST_API_KEY" \
  -F "user=isaac" -F "platform[]=linkedin" \
  -F "video=@video/output.mp4" \
  -F "title=POST_TEXT" \
  -F "linkedin_description=COMMENTARY_TEXT" \
  -F "visibility=PUBLIC" \
  -F "scheduled_date=DATETIME_UTC" \
  https://api.upload-post.com/api/upload
```
Note: Video endpoint is `/api/upload` (not `/api/upload_videos`). `linkedin_description` sets the commentary text; `visibility` is required.

---

### X (Twitter)

**Always include `x_long_text_as_post=true`** — without it, Upload Post auto-splits into a thread at paragraph breaks.

**Text post:**
```bash
curl -s -X POST -H "Authorization: Apikey $UPLOADPOST_API_KEY" \
  -F "user=isaac" -F "platform[]=x" \
  -F "title=POST_TEXT" \
  -F "x_long_text_as_post=true" \
  -F "scheduled_date=DATETIME_UTC" \
  https://api.upload-post.com/api/upload_text
```

**Link preview card:** No `link_url` parameter for X. X auto-generates preview cards from URLs in the text. Just include the URL in `title`.

**Text + image:**
```bash
curl -s -X POST -H "Authorization: Apikey $UPLOADPOST_API_KEY" \
  -F "user=isaac" -F "platform[]=x" \
  -F "photos[]=@path/to/image.png" \
  -F "title=POST_TEXT" \
  -F "x_long_text_as_post=true" \
  -F "scheduled_date=DATETIME_UTC" \
  https://api.upload-post.com/api/upload_photos
```
Max 4 images per tweet.

**Text + video:**
```bash
curl -s -X POST -H "Authorization: Apikey $UPLOADPOST_API_KEY" \
  -F "user=isaac" -F "platform[]=x" \
  -F "video=@video/output.mp4" \
  -F "title=POST_TEXT" \
  -F "x_long_text_as_post=true" \
  -F "scheduled_date=DATETIME_UTC" \
  https://api.upload-post.com/api/upload
```

---

### Threads

**Hard limit: 500 characters** for TEXT posts. The Threads API returns a 500 error if the text exceeds this. Use `text-xsmall.md` for Threads, not `text-small.md`.

Include `threads_long_text_as_post=true` to avoid auto-threading on posts near the limit.

**Text post:**
```bash
curl -s -X POST -H "Authorization: Apikey $UPLOADPOST_API_KEY" \
  -F "user=isaac" -F "platform[]=threads" \
  -F "title=POST_TEXT" \
  -F "threads_long_text_as_post=true" \
  -F "scheduled_date=DATETIME_UTC" \
  https://api.upload-post.com/api/upload_text
```

**Link preview card:** No `link_url` support for Threads. Include URLs in post text.

**Text + image:**
```bash
curl -s -X POST -H "Authorization: Apikey $UPLOADPOST_API_KEY" \
  -F "user=isaac" -F "platform[]=threads" \
  -F "photos[]=@path/to/image.png" \
  -F "title=POST_TEXT" \
  -F "threads_long_text_as_post=true" \
  -F "scheduled_date=DATETIME_UTC" \
  https://api.upload-post.com/api/upload_photos
```
Max 10 items per post.

**Text + video:**
```bash
curl -s -X POST -H "Authorization: Apikey $UPLOADPOST_API_KEY" \
  -F "user=isaac" -F "platform[]=threads" \
  -F "video=@video/output.mp4" \
  -F "title=POST_TEXT" \
  -F "scheduled_date=DATETIME_UTC" \
  https://api.upload-post.com/api/upload
```

---

### Bluesky

**Text post:**
```bash
curl -s -X POST -H "Authorization: Apikey $UPLOADPOST_API_KEY" \
  -F "user=isaac" -F "platform[]=bluesky" \
  -F "title=POST_TEXT" \
  -F "scheduled_date=DATETIME_UTC" \
  https://api.upload-post.com/api/upload_text
```
Character limit: 300. Text over 300 chars auto-threads.

**Text + link preview card:**
```bash
curl -s -X POST -H "Authorization: Apikey $UPLOADPOST_API_KEY" \
  -F "user=isaac" -F "platform[]=bluesky" \
  -F "title=POST_TEXT_WITHOUT_URL" \
  -F "bluesky_link_url=https://example.com/article" \
  -F "scheduled_date=DATETIME_UTC" \
  https://api.upload-post.com/api/upload_text
```
**Important:** Strip the URL from the post text when using `bluesky_link_url`. The card handles the link. If the URL stays in the text, total chars may exceed 300 and Bluesky will auto-thread into multiple posts.

**Text + image:**
```bash
curl -s -X POST -H "Authorization: Apikey $UPLOADPOST_API_KEY" \
  -F "user=isaac" -F "platform[]=bluesky" \
  -F "photos[]=@path/to/image.png" \
  -F "title=POST_TEXT" \
  -F "scheduled_date=DATETIME_UTC" \
  https://api.upload-post.com/api/upload_photos
```
Max 4 images.

**Text + video:**
```bash
curl -s -X POST -H "Authorization: Apikey $UPLOADPOST_API_KEY" \
  -F "user=isaac" -F "platform[]=bluesky" \
  -F "video=@video/output.mp4" \
  -F "title=POST_TEXT" \
  -F "scheduled_date=DATETIME_UTC" \
  https://api.upload-post.com/api/upload
```
Limits: 100MB max, 25 videos/day.

---

## Link Preview Summary

| Platform | How to get a preview card | Notes |
|----------|--------------------------|-------|
| LinkedIn | `-F "link_url=URL"` | Strip URL from post text or card won't render. |
| X | Auto-generates from URLs in text | Keep URL in text. No special parameter needed. |
| Threads | No preview card support | Keep URL in text. |
| Bluesky | `-F "bluesky_link_url=URL"` | Strip URL from post text or card won't render (also avoids 300 char limit). |

---

## Schedule Management

**View schedule:**
```bash
curl -s -H "Authorization: Apikey $UPLOADPOST_API_KEY" \
  https://api.upload-post.com/api/uploadposts/schedule
```

**Reschedule** (field is `scheduled_date`, not `scheduled_time`):
```bash
curl -s -X PATCH -H "Authorization: Apikey $UPLOADPOST_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"scheduled_date": "DATETIME_UTC"}' \
  https://api.upload-post.com/api/uploadposts/schedule/JOB_ID
```

**Delete:**
```bash
curl -s -X DELETE -H "Authorization: Apikey $UPLOADPOST_API_KEY" \
  https://api.upload-post.com/api/uploadposts/schedule/JOB_ID
```

**Next queue slot:**
```bash
curl -s -H "Authorization: Apikey $UPLOADPOST_API_KEY" \
  "https://api.upload-post.com/api/uploadposts/queue/next-slot?profile_username=USERNAME"
```

**History / Status / Analytics:**
```bash
curl -s -H "Authorization: Apikey $UPLOADPOST_API_KEY" https://api.upload-post.com/api/uploadposts/history
curl -s -H "Authorization: Apikey $UPLOADPOST_API_KEY" https://api.upload-post.com/api/uploadposts/status
curl -s -H "Authorization: Apikey $UPLOADPOST_API_KEY" "https://api.upload-post.com/api/analytics/USERNAME?platforms=linkedin,x"
```

**Connect new account:**
```bash
curl -s -X POST -H "Authorization: Apikey $UPLOADPOST_API_KEY" \
  https://api.upload-post.com/api/uploadposts/users/generate-jwt
```

## Content Inventory

| File | Best For |
|------|----------|
| `social/text-xsmall.md` (< 300 chars) | X, Bluesky, Threads |
| `social/text-small.md` (500-900 chars) | X (Premium), LinkedIn |
| `social/text-medium.md` (1200-1800 chars) | LinkedIn |
| `social/carousel/*.png` | Instagram, LinkedIn |
| `video/*.mp4` | All platforms |

## See Also

- `/content-social` — generate social content
- `/content-status` — check what content exists

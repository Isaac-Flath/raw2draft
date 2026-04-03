---
name: s3
description: /s3 - S3 Image Management
---

# /s3 - S3 Image Management

Upload, list, and delete files in your S3 bucket. Requires `S3_BUCKET` environment variable.

## Commands

**Upload**: `/s3 upload [file-path]`
```bash
aws s3 cp [file] s3://$S3_BUCKET/[filename] --acl public-read
```
Returns: `https://$S3_BUCKET.s3.$AWS_REGION.amazonaws.com/[filename]`

**List**: `/s3 list [--prefix=path/]`
```bash
aws s3 ls s3://$S3_BUCKET/[prefix] --recursive
```

**Delete**: `/s3 delete [key-or-url]`
```bash
aws s3 rm s3://$S3_BUCKET/[key]
```
Warn if file is referenced in posts.

**URL**: `/s3 url [filename]`
Returns the public URL.

## Notes

- All uploads are public-read
- Content-type auto-detected from extension
- Requires `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `S3_BUCKET`

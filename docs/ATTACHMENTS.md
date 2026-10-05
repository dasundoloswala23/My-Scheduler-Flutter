# Attachments

Real files in Cloud Storage, with metadata in Firestore.

## Layout

```
Firestore  users/{uid}/tasks/{taskId}/attachments/{attachmentId}
Storage    users/{uid}/tasks/{taskId}/{attachmentId}
```

The two share an id, so either half can always find the other. That is what
makes clean-up reliable and orphan files avoidable.

## Metadata

| Field | Notes |
|---|---|
| `taskId` | owning task |
| `fileName` | sanitised name |
| `originalFileName` | exactly what the user's file was called |
| `storagePath` | full Storage path |
| `downloadUrl` | tokenised URL from `getDownloadURL()` |
| `mimeType` | sniffed from the extension when the picker does not say |
| `fileSize` | bytes |
| `thumbnailUrl` | images only; currently the image itself |
| `uploadedBy` | uid |
| `createdAt`, `updatedAt` | server timestamps |

The task keeps `attachmentCount` so the board can draw the paperclip badge
without querying every task's subcollection.

## Upload

`AttachmentService.upload` takes either bytes or a `File`. On native platforms
a path is passed so Storage streams from disk; only web reads the whole file
into memory, because browsers give no path. Progress is reported 0..1, the task
handle allows cancel, and a failed upload can be retried from the same row.

Limits: **50 MB**, and an allow-list of types enforced by the rules — images,
video, audio, PDF, Office documents, text, CSV, zip.

## Preview

- **Images** show a real thumbnail and open a full-screen viewer with pinch and
  double-tap zoom, swipe between images, and delete.
- **PDF, video, audio, other** show a type icon with the file name and size.

## Deletion

`delete()` removes the metadata document, then the Storage object, then
refreshes the count. A missing object is tolerated, since the goal is that
nothing is left behind.

`deleteAllFor(taskId)` runs before a task is deleted, which is why
`Repo.deleteTask` never orphans files. A Storage failure there is swallowed
deliberately: an undeletable task is worse than a stray file, and the file can
be cleaned up later.

## Not done

- **No server-side thumbnails.** An image is its own thumbnail, so a large
  photo downloads in full for a 46px preview. Proper resizing needs a Cloud
  Function, which needs the Blaze plan.
- **The Next.js app cannot upload yet.** It reads `attachmentCount` and shows
  the badge, but has no picker or viewer. Uploading is Flutter-only for now.
- **No virus scanning** and no download-rate limiting.

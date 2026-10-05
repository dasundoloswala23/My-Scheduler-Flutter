# Security

## Model

Every document and every file lives under a path that begins with the owner's
uid. Ownership is therefore decided by the path alone, and one rule covers an
entire subtree — there is no per-document owner field that could be forgotten
or spoofed.

## Firestore rules

`firestore.rules`:

```
match /users/{uid}/{document=**} {
  allow read, write: if request.auth != null && request.auth.uid == uid;
}
```

This covers tasks, boards, lists, categories, notes, reminders, holidays,
focus sessions **and** the attachment metadata subcollection, because `{
document=** }` is recursive.

## Storage rules

`storage.rules` guards `users/{uid}/{allPaths=**}` with the same uid check and
adds two limits a client cannot be trusted to enforce:

- **50 MB** per file.
- An allow-list of content types: images, video, audio, PDF, common Office
  documents, plain text, CSV and zip. Anything else is refused, so the bucket
  cannot be used to host arbitrary executables.

Everything outside a user folder is denied explicitly.

## Verified by automated tests

`tools/api-tests/` signs in as a real user, and in the storage suite creates a
**second real account**, then attempts cross-user access. All of these are
expected to be refused and are asserted:

| Attempt | Expected | Verified |
|---|---|---|
| Read another user's tasks | 403 | yes |
| Write into another user's space | 403 | yes |
| Read own data signed in | 200 | yes |
| Any access signed out | 403 | yes |
| Upload into another user's folder | 403 | yes |
| Download another user's attachment, as a different signed-in user | 403 | yes |
| Delete another user's attachment, as a different signed-in user | 403 | yes |
| Read another user's attachment metadata | 403 | yes |
| Signed-out download | 403 | yes |
| Upload a disallowed content type | 403 | yes |

Run them with:

```bash
node tools/api-tests/run-all.mjs
```

## Client-side trust

The clients enforce nothing security-relevant. The 50 MB check in
`AttachmentService` exists only to give a clear message before a doomed upload;
the rules enforce it regardless. Category filtering, search and board filtering
are display concerns and never widen what a user can read.

## Known gaps

- **No workspace sharing.** The member avatars in the original designs are not
  implemented. Every account is a silo. Adding sharing means replacing the
  single-uid rule with a membership check, and the rules and tests must be
  rewritten together.
- **No App Check.** A stolen API key cannot read another user's data, but it
  can be used to create accounts. Enable App Check before a public launch.
- **No rate limiting** on account creation beyond Firebase's own defaults.
- **Test credentials are in the repository.** `tools/api-tests/lib.mjs` falls
  back to a throwaway account (`dasuntest3@gmail.com` / `123456`). It owns only
  seeded test data. Override with `MYS_TEST_EMAIL` and `MYS_TEST_PASSWORD`, and
  do not reuse that password anywhere real.
- The Firebase web API key is public by design. It identifies the project; it
  does not grant access. The rules are what protect the data.

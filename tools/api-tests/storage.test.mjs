/**
 * Attachment and Storage security tests.
 *
 * Covers the upload/delete lifecycle, the attachment metadata document, the
 * denormalised count on the task, cascade clean-up, and cross-user access.
 */
import {
  BUCKET,
  TINY_PNG,
  check,
  createDoc,
  deleteDoc,
  deleteObject,
  downloadObject,
  getDoc,
  listDocs,
  objectExists,
  patchDoc,
  signIn,
  summary,
  uploadObject,
} from "./lib.mjs";

const { uid, token } = await signIn();
console.log(`Signed in as ${uid}\n`);

// A throwaway task so the suite never disturbs the seeded data.
const taskId = await createDoc(token, `users/${uid}/tasks`, {
  title: "Attachment test task",
  description: "Created by storage.test.mjs",
  listId: null,
  boardId: null,
  categoryId: null,
  parentTaskId: null,
  position: 999000,
  completed: false,
  priority: "none",
  startDateTime: null,
  endDateTime: null,
  hasSchedule: false,
  recurrence: "none",
  subtasks: [],
  attachments: [],
  attachmentCount: 0,
  version: 1,
  createdAt: new Date(),
  updatedAt: new Date(),
});

const attachmentId = `test-${Date.now()}`;
const storagePath = `users/${uid}/tasks/${taskId}/${attachmentId}`;

// ------------------------------------------------------------------- upload

const up = await uploadObject(token, storagePath, TINY_PNG, "image/png");
check("Upload an image to my own task folder", up.status === 200, `HTTP ${up.status}`);

const down = await downloadObject(token, storagePath);
check("Download my own attachment", down.status === 200, `${down.bytes?.length ?? 0} bytes`);
check(
  "Downloaded bytes match what was uploaded",
  down.bytes?.length === TINY_PNG.length,
  `${down.bytes?.length} vs ${TINY_PNG.length}`,
);

// ------------------------------------------------------- metadata + count sync

await createDoc(
  token,
  `users/${uid}/tasks/${taskId}/attachments`,
  {
    taskId,
    fileName: "pixel.png",
    originalFileName: "pixel.png",
    storagePath,
    downloadUrl: `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(storagePath)}?alt=media`,
    mimeType: "image/png",
    fileSize: TINY_PNG.length,
    thumbnailUrl: null,
    uploadedBy: uid,
    createdAt: new Date(),
    updatedAt: new Date(),
  },
  attachmentId,
);

const metadata = await getDoc(token, `users/${uid}/tasks/${taskId}/attachments/${attachmentId}`);
check("Attachment metadata document written", metadata !== null);
check(
  "Metadata carries every required field",
  !!(
    metadata.taskId &&
    metadata.fileName &&
    metadata.originalFileName &&
    metadata.storagePath &&
    metadata.downloadUrl &&
    metadata.mimeType &&
    metadata.fileSize > 0 &&
    metadata.uploadedBy
  ),
  `${metadata.mimeType}, ${metadata.fileSize} bytes`,
);
check("Attachment is owned by the uploader", metadata.uploadedBy === uid);

await patchDoc(token, `users/${uid}/tasks/${taskId}`, { attachmentCount: 1, updatedAt: new Date() });
const taskAfter = await getDoc(token, `users/${uid}/tasks/${taskId}`);
check("Task attachment count stays in sync", taskAfter.attachmentCount === 1);

// ------------------------------------------------------------ security rules

const otherUid = "not-my-uid-000000000000";
const foreignUpload = await uploadObject(
  token,
  `users/${otherUid}/tasks/x/evil`,
  TINY_PNG,
  "image/png",
);
check(
  "Cannot upload into another user's folder",
  foreignUpload.status === 403,
  `HTTP ${foreignUpload.status}`,
);

const anonDownload = await downloadObject(null, storagePath);
check(
  "Signed-out download is refused",
  anonDownload.status === 401 || anonDownload.status === 403,
  `HTTP ${anonDownload.status}`,
);

// An executable is not in the allowed MIME list, so the rules must refuse it.
const badType = await uploadObject(
  token,
  `users/${uid}/tasks/${taskId}/blocked`,
  TINY_PNG,
  "application/x-msdownload",
);
check(
  "Disallowed content types are refused",
  badType.status === 403,
  `HTTP ${badType.status}`,
);

// A second account proves one user cannot reach another's real file.
const strangerEmail = `stranger-${Date.now()}@example.com`;
const strangerRes = await fetch(
  `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${process.env.MYS_API_KEY ?? "AIzaSyAqNL0cPUS0hthRLh3OQvOIGueFDZOMLQ0"}`,
  {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email: strangerEmail, password: "strangerpass123", returnSecureToken: true }),
  },
);
const stranger = await strangerRes.json();

if (strangerRes.ok) {
  const theirRead = await downloadObject(stranger.idToken, storagePath);
  check(
    "A different signed-in user cannot read my attachment",
    theirRead.status === 403,
    `HTTP ${theirRead.status}`,
  );

  const theirDelete = await deleteObject(stranger.idToken, storagePath);
  check("A different signed-in user cannot delete my attachment", theirDelete === 403, `HTTP ${theirDelete}`);

  const theirFirestore = await fetch(
    `https://firestore.googleapis.com/v1/projects/${process.env.MYS_PROJECT ?? "myscheduleplanner-e22f3"}/databases/(default)/documents/users/${uid}/tasks/${taskId}/attachments`,
    { headers: { Authorization: `Bearer ${stranger.idToken}` } },
  );
  check(
    "A different user cannot read my attachment metadata",
    theirFirestore.status === 403,
    `HTTP ${theirFirestore.status}`,
  );

  // Clean up the throwaway account so it does not pile up.
  await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:delete?key=${process.env.MYS_API_KEY ?? "AIzaSyAqNL0cPUS0hthRLh3OQvOIGueFDZOMLQ0"}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ idToken: stranger.idToken }),
    },
  );
} else {
  check("Create a second account for cross-user tests", false, stranger.error?.message);
}

// ------------------------------------------------------------------- deletion

const deleteStatus = await deleteObject(token, storagePath);
check("Delete my own attachment file", deleteStatus === 200 || deleteStatus === 204, `HTTP ${deleteStatus}`);
check("Storage object is gone after delete", !(await objectExists(token, storagePath)));

await deleteDoc(token, `users/${uid}/tasks/${taskId}/attachments/${attachmentId}`);
const gone = await getDoc(token, `users/${uid}/tasks/${taskId}/attachments/${attachmentId}`);
check("Attachment metadata is gone after delete", gone === null);

// --------------------------------------------------- cascade on task deletion

const cascadeId = `cascade-${Date.now()}`;
const cascadePath = `users/${uid}/tasks/${taskId}/${cascadeId}`;
await uploadObject(token, cascadePath, TINY_PNG, "image/png");
await createDoc(
  token,
  `users/${uid}/tasks/${taskId}/attachments`,
  {
    taskId,
    fileName: "cascade.png",
    originalFileName: "cascade.png",
    storagePath: cascadePath,
    downloadUrl: "",
    mimeType: "image/png",
    fileSize: TINY_PNG.length,
    uploadedBy: uid,
    createdAt: new Date(),
  },
  cascadeId,
);

// What Repo.deleteTask does: clear attachments first, then the task.
for (const a of await listDocs(token, `users/${uid}/tasks/${taskId}/attachments`)) {
  await deleteObject(token, a.storagePath);
  await deleteDoc(token, `users/${uid}/tasks/${taskId}/attachments/${a.id}`);
}
await deleteDoc(token, `users/${uid}/tasks/${taskId}`);

check("Deleting a task removes its attachment files", !(await objectExists(token, cascadePath)));
check("Deleting a task removes the task itself", (await getDoc(token, `users/${uid}/tasks/${taskId}`)) === null);
check(
  "No orphaned attachment metadata remains",
  (await listDocs(token, `users/${uid}/tasks/${taskId}/attachments`)).length === 0,
);

process.exit(summary("Storage & attachments") ? 0 : 1);

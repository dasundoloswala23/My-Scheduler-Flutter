// Creates a task with a near-term at-time reminder straight in Firestore.
// The app then only has to touch it once (complete / un-complete) for its
// scheduler to register the alarm with Android — no keyboard, no pickers.
import { signIn, createDoc, listDocs, deleteDoc } from "./lib.mjs";

const MINUTES_AHEAD = Number(process.argv[2] ?? 5);

const { uid, token } = await signIn();

// Clear any previous proof tasks so the device list stays readable.
for (const t of await listDocs(token, `users/${uid}/tasks`)) {
  if ((t.title ?? "").startsWith("PROOF")) {
    await deleteDoc(token, `users/${uid}/tasks/${t.id}`);
  }
}

const start = new Date(Date.now() + MINUTES_AHEAD * 60 * 1000);
start.setSeconds(0, 0);

const reminderId = `proof-${Date.now()}`;
const id = await createDoc(token, `users/${uid}/tasks`, {
  title: "PROOF reminder",
  description: "Toggle me in the app to arm the alarm.",
  boardId: null,
  listId: null,
  categoryId: null,
  parentTaskId: null,
  position: 1,
  completed: false,
  priority: "high",
  startDateTime: start,
  endDateTime: new Date(+start + 30 * 60 * 1000),
  hasSchedule: true,
  isAllDay: false,
  recurrence: "none",
  reminderOffsets: [],
  reminders: [
    {
      id: reminderId,
      taskId: "pending",
      type: "atTime",
      offsetMinutes: 0,
      absoluteDateTime: null,
      enabled: true,
      notificationId: null,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    },
  ],
  subtasks: [],
  attachments: [],
  attachmentCount: 0,
  createdAt: new Date(),
  updatedAt: new Date(),
  completedAt: null,
  version: 1,
});

console.log(`TASK_ID=${id}`);
console.log(`REMINDER_ID=${reminderId}`);
console.log(`FIRES_AT=${start.toISOString()}  (local ${start.toLocaleTimeString()})`);
console.log(`EPOCH=${Math.floor(+start / 1000)}`);

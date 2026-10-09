// Recurring-task completion in a real browser against the live project, checked
// from the database as well as the screen. Usage: node e2e_recurrence.mjs <baseUrl> [label]
import { chromium } from "playwright";
import {
  FIRESTORE,
  authHeaders,
  createDoc,
  fromFields,
  signIn,
} from "../api-tests/lib.mjs";

const BASE = process.argv[2] ?? "http://localhost:4173";
const EMAIL = process.env.MYS_TEST_EMAIL;
const PASSWORD = process.env.MYS_TEST_PASSWORD;
const results = [];
const check = (name, ok, detail = "") => {
  results.push(ok);
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? " — " + detail : ""}`);
};

const a = await signIn();
const rest = async (path) => {
  const res = await fetch(`${FIRESTORE}/users/${a.uid}/${path}`, { headers: authHeaders(a.token) });
  return res.json();
};
const listDocs = async (col) =>
  ((await rest(`${col}?pageSize=300`)).documents ?? []).map((d) => ({ id: d.name.split("/").pop(), ...fromFields(d.fields ?? {}) }));

const lists = await listDocs("lists");
const boards = await listDocs("boards");
const board = boards[0];
const boardLists = lists.filter((l) => l.boardId === board.id);
const todo = boardLists.find((l) => l.name === "Todo");
const complete = boardLists.find((l) => l.kind === "complete");

const stamp = Date.now();
const title = `E2E task recurring ${stamp}`;
const start = new Date();
start.setDate(start.getDate() + 3);
start.setHours(9, 30, 0, 0);
const end = new Date(start.getTime() + 60 * 60 * 1000);

const taskId = await createDoc(a.token, `users/${a.uid}/tasks`, {
  title,
  description: "",
  boardId: board.id,
  listId: todo.id,
  categoryId: null,
  parentTaskId: null,
  position: 500,
  completed: false,
  priority: "none",
  startDateTime: start,
  endDateTime: end,
  hasSchedule: true,
  recurrence: "daily",
  reminderMinutesBefore: null,
  reminderOffsets: [],
  subtasks: [],
  attachments: [],
  attachmentCount: 0,
  completedAt: null,
  completedFromListId: null,
  spawnedNextTaskId: null,
  version: 1,
});

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1360, height: 900 } });
const until = async (fn, ms = 20000) => {
  const endAt = Date.now() + ms;
  for (;;) {
    try {
      if (await fn()) return true;
    } catch {}
    if (Date.now() > endAt) return false;
    await page.waitForTimeout(300);
  }
};

try {
  await page.goto(BASE + "/login");
  await page.getByPlaceholder("Email").fill(EMAIL);
  await page.getByPlaceholder("Password").fill(PASSWORD);
  await page.locator('button[type="submit"]').click();
  await page.waitForURL((u) => !u.pathname.startsWith("/login"), { timeout: 30000 });
  await page.waitForTimeout(2000);
  await page.goto(`${BASE}/board?id=${board.id}`);
  await page.waitForTimeout(3000);

  const col = (name) => page.locator("section", { has: page.locator("h3", { hasText: new RegExp(`^${name}$`) }) });
  check("the repeating task shows its repeat chip on the board", await until(() => col("Todo").locator("div.card", { hasText: title }).getByText("Daily").isVisible()));

  // Two clicks in quick succession: the double tap that used to spawn two.
  const btn = col("Todo").locator("div.card", { hasText: title }).getByRole("button", { name: "Mark as done" }).first();
  await btn.click();
  await btn.click({ timeout: 1000, force: true }).catch(() => {});

  check("the completed occurrence is in Complete", await until(() => col("Complete").getByText(title).isVisible()));
  check("the next occurrence is in the ORIGINAL list (Todo)", await until(() => col("Todo").getByText(title).isVisible()));
  await page.waitForTimeout(2500);

  // From the database, not the screen.
  const tasks = (await listDocs("tasks")).filter((t) => t.title === title);
  check("exactly two documents exist: the completed one and one next occurrence", tasks.length === 2, `${tasks.length} found`);
  const done = tasks.find((t) => t.id === taskId);
  const next = tasks.find((t) => t.id !== taskId);
  check("the original is completed, in Complete, and remembers its origin", !!done && done.completed === true && done.listId === complete.id && done.completedFromListId === todo.id);
  check("the next occurrence id is derived from the task (idempotent)", !!next && next.id === `${taskId}-next-${start.getTime()}`, next?.id);
  const expectedNext = new Date(start);
  expectedNext.setDate(expectedNext.getDate() + 1);
  check("the next occurrence is one calendar day later at the same time", !!next && +next.startDateTime === +expectedNext, String(next?.startDateTime));
  check("the next occurrence is open, in Todo, version 1", !!next && next.completed === false && next.listId === todo.id && next.version === 1);
  check("the original records the occurrence it spawned", !!done && done.spawnedNextTaskId === next?.id);

  // Re-open the completed one: the untouched next occurrence is removed.
  await col("Complete").locator("div.card", { hasText: title }).getByRole("button", { name: "Mark as not done" }).first().click();
  check("re-opening puts it back in Todo", await until(async () => (await col("Todo").getByText(title).count()) >= 1 && (await col("Complete").getByText(title).count()) === 0));
  await page.waitForTimeout(2500);
  const after = (await listDocs("tasks")).filter((t) => t.title === title);
  check("re-opening removed the untouched next occurrence (no duplicate)", after.length === 1, `${after.length} found`);
  check("the series pointer was cleared", after[0]?.spawnedNextTaskId === null);
} catch (e) {
  check("script ran to the end", false, String(e).slice(0, 300));
} finally {
  await browser.close();
}

const failed = results.filter((r) => !r).length;
console.log(`\n===== web recurrence e2e: ${results.length - failed} passed, ${failed} failed =====`);
process.exit(failed ? 1 : 0);

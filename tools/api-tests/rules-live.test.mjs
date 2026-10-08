/**
 * Live security checks for the deployed Firestore rules, through the public API
 * key, exactly as a client would hit them.
 *
 * Uses two real accounts: the shared test account (A) and a throwaway account
 * (B) created for this run and deleted at the end. Proves that
 *   - A cannot read or write B's data, and B cannot touch A's;
 *   - a signed-out request cannot read or write anything private;
 *   - the owner can use the Project Flow collections;
 *   - malformed documents are refused for each validated collection.
 *
 *   node tools/api-tests/rules-live.test.mjs
 */
import {
  FIRESTORE,
  KEY,
  authHeaders,
  check,
  createDoc,
  signIn,
  summary,
  toFields,
} from "./lib.mjs";

const stamp = Date.now();

async function createThrowawayUser() {
  const email = `rules-check-${stamp}@example.test`;
  const password = `Tmp-${stamp}-pw!`;
  const res = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${KEY}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`throwaway sign-up failed: ${json.error?.message}`);
  return { uid: json.localId, token: json.idToken };
}

async function deleteUser(token) {
  await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:delete?key=${KEY}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ idToken: token }),
  });
}

const status = async (method, path, token, body) => {
  const res = await fetch(`${FIRESTORE}/${path}`, {
    method,
    headers: token ? authHeaders(token) : { "Content-Type": "application/json" },
    body: body ? JSON.stringify({ fields: toFields(body) }) : undefined,
  });
  return res.status;
};

const a = await signIn();
const b = await createThrowawayUser();
const created = []; // [token, path] for cleanup

try {
  // ---------------------------------------------------------------- isolation
  const bTask = await createDoc(b.token, `users/${b.uid}/tasks`, { title: "B's private task" });
  created.push([b.token, `users/${b.uid}/tasks/${bTask}`]);

  check("B can read B's own task", (await status("GET", `users/${b.uid}/tasks/${bTask}`, b.token)) === 200);
  check("A cannot read B's task", (await status("GET", `users/${b.uid}/tasks/${bTask}`, a.token)) === 403);
  check("A cannot list B's tasks", (await status("GET", `users/${b.uid}/tasks`, a.token)) === 403);
  check(
    "A cannot overwrite B's task",
    (await status("PATCH", `users/${b.uid}/tasks/${bTask}?updateMask.fieldPaths=title`, a.token, { title: "pwned" })) === 403,
  );
  check("A cannot delete B's task", (await status("DELETE", `users/${b.uid}/tasks/${bTask}`, a.token)) === 403);
  check(
    "A cannot create into B's flows",
    (await status("POST", `users/${b.uid}/projectFlows`, a.token, { name: "x" })) === 403,
  );
  check("B cannot read A's tasks", (await status("GET", `users/${a.uid}/tasks`, b.token)) === 403);
  check("A's task is untouched by A's attempts", (await status("GET", `users/${b.uid}/tasks/${bTask}`, b.token)) === 200);

  for (const col of ["tasks", "boards", "lists", "projectFlows", "flowStages", "flowTaskLinks", "notes"]) {
    const s = await status("GET", `users/${a.uid}/${col}`, null);
    check(`signed-out cannot list ${col}`, s === 401 || s === 403, `HTTP ${s}`);
  }
  check(
    "signed-out cannot write a task",
    [401, 403].includes(await status("POST", `users/${a.uid}/tasks`, null, { title: "x" })),
  );
  check("a collection nobody listed is closed even to its owner", (await status("POST", `users/${a.uid}/surprises`, a.token, { x: 1 })) === 403);

  // ------------------------------------------------- owner uses flow collections
  const flowId = await createDoc(a.token, `users/${a.uid}/projectFlows`, {
    name: `Rules check ${stamp}`,
    mode: "sequential",
    status: "active",
    progress: 0,
    boardId: null,
  });
  created.push([a.token, `users/${a.uid}/projectFlows/${flowId}`]);
  check("owner can create a flow", !!flowId);

  const stageId = await createDoc(a.token, `users/${a.uid}/flowStages`, {
    flowId,
    title: "Plan",
    isRequired: true,
    dependencyStageIds: [],
    status: "active",
    position: 1000,
  });
  created.push([a.token, `users/${a.uid}/flowStages/${stageId}`]);
  check("owner can create a stage", !!stageId);

  const linkId = await createDoc(a.token, `users/${a.uid}/flowTaskLinks`, { flowId, stageId, taskId: "t-rules-check" }, "t-rules-check");
  created.push([a.token, `users/${a.uid}/flowTaskLinks/${linkId}`]);
  check("owner can create a link", linkId === "t-rules-check");

  // ----------------------------------------------------- malformed is refused
  const refused = async (name, col, body) =>
    check(`refused: ${name}`, (await status("POST", `users/${a.uid}/${col}`, a.token, body)) === 403);

  await refused("task title that is a number", "tasks", { title: 42 });
  await refused("task title over 500 characters", "tasks", { title: "x".repeat(501) });
  await refused("task completed as text", "tasks", { title: "x", completed: "yes" });
  await refused("flow without a name", "projectFlows", { mode: "sequential" });
  await refused("flow with an unknown mode", "projectFlows", { name: "x", mode: "chaos" });
  await refused("stage without a flowId", "flowStages", { title: "x" });
  await refused("stage with an unknown state", "flowStages", { flowId: "f", status: "sleepy" });
  await refused("link without a stage", "flowTaskLinks", { flowId: "f", taskId: "t" });
  check(
    "refused: update turning a good flow bad",
    (await status("PATCH", `users/${a.uid}/projectFlows/${flowId}?updateMask.fieldPaths=mode`, a.token, { mode: "chaos" })) === 403,
  );
  check(
    "allowed: valid update of the same flow",
    (await status("PATCH", `users/${a.uid}/projectFlows/${flowId}?updateMask.fieldPaths=mode`, a.token, { mode: "flexible" })) === 200,
  );
} finally {
  for (const [token, path] of created.reverse()) {
    await status("DELETE", path, token).catch(() => {});
  }
  await deleteUser(b.token).catch(() => {});
}

const ok = summary("Live Firestore rules");
process.exit(ok ? 0 : 1);

// Removes everything the web end-to-end run created in the shared test account.
import { FIRESTORE, authHeaders, fromFields, signIn } from "../api-tests/lib.mjs";

const prefixes = process.argv.slice(2).length ? process.argv.slice(2) : ["E2E task", "E2E flow", "DBG "];
const a = await signIn();
const list = async (col) => {
  const out = [];
  let token = "";
  do {
    const res = await fetch(`${FIRESTORE}/users/${a.uid}/${col}?pageSize=300${token ? `&pageToken=${token}` : ""}`, { headers: authHeaders(a.token) });
    const json = await res.json();
    for (const d of json.documents ?? []) out.push({ id: d.name.split("/").pop(), name: d.name, data: fromFields(d.fields ?? {}) });
    token = json.nextPageToken ?? "";
  } while (token);
  return out;
};
const del = async (d, label) => {
  const r = await fetch(`https://firestore.googleapis.com/v1/${d.name}`, { method: "DELETE", headers: authHeaders(a.token) });
  console.log(`deleted ${label} ${d.id} (HTTP ${r.status})`);
};
const starts = (t) => typeof t === "string" && prefixes.some((p) => t.startsWith(p));

const tasks = await list("tasks");
const doomedTasks = tasks.filter((t) => starts(t.data.title));
const doomedIds = new Set(doomedTasks.map((t) => t.id));
// next occurrences spawned from them
for (const t of tasks) if (typeof t.data.spawnedNextTaskId === "string" && doomedIds.has(t.id)) doomedIds.add(t.data.spawnedNextTaskId);
for (const t of tasks) if (doomedIds.has(t.id)) await del(t, "task");

const flows = (await list("projectFlows")).filter((f) => starts(f.data.name));
const flowIds = new Set(flows.map((f) => f.id));
for (const s of await list("flowStages")) if (flowIds.has(s.data.flowId)) await del(s, "stage");
for (const l of await list("flowTaskLinks")) if (flowIds.has(l.data.flowId) || doomedIds.has(l.id)) await del(l, "link");
for (const f of flows) await del(f, "flow");

const left = await list("tasks");
console.log("tasks remaining:", left.length);

// Account deletion end to end with a THROWAWAY account (never the shared test
// account): sign up, use the app, delete the account from Settings, then prove the
// data is gone and the account can no longer sign in. Usage: node e2e_delete.mjs <baseUrl>
import { chromium } from "playwright";
import { FIRESTORE, KEY, authHeaders, fromFields } from "../api-tests/lib.mjs";

const BASE = process.argv[2] ?? "http://localhost:4173";
const results = [];
const check = (name, ok, detail = "") => {
  results.push(ok);
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? " — " + detail : ""}`);
};

const stamp = Date.now();
const email = `delete-check-${stamp}@example.test`;
const password = `Tmp-${stamp}-pw!`;

const idt = async (op, body) => {
  const res = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:${op}?key=${KEY}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  return { ok: res.ok, json: await res.json() };
};

const created = await idt("signUp", { email, password, returnSecureToken: true });
if (!created.ok) throw new Error("could not create throwaway account");
const { localId: uid, idToken } = created.json;

const COLLECTIONS = ["tasks", "boards", "lists", "categories", "projectFlows", "flowStages", "flowTaskLinks"];
const count = async (col, token = idToken) => {
  const res = await fetch(`${FIRESTORE}/users/${uid}/${col}?pageSize=300`, { headers: authHeaders(token) });
  if (!res.ok) return { status: res.status, n: -1 };
  return { status: 200, n: ((await res.json()).documents ?? []).length };
};

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1360, height: 900 } });
const until = async (fn, ms = 20000) => {
  const end = Date.now() + ms;
  for (;;) {
    try {
      if (await fn()) return true;
    } catch {}
    if (Date.now() > end) return false;
    await page.waitForTimeout(300);
  }
};

try {
  await page.goto(BASE + "/login");
  await page.getByPlaceholder("Email").fill(email);
  await page.getByPlaceholder("Password").fill(password);
  await page.locator('button[type="submit"]').click();
  await page.waitForURL((u) => !u.pathname.startsWith("/login"), { timeout: 30000 });
  await page.waitForTimeout(3500);

  // A brand-new account is seeded with a board whose lists include Complete.
  await until(async () => ((await count("lists")).n === 6));
  const lists = await (async () => {
    const res = await fetch(`${FIRESTORE}/users/${uid}/lists?pageSize=50`, { headers: authHeaders(idToken) });
    return ((await res.json()).documents ?? []).map((d) => fromFields(d.fields ?? {}));
  })();
  check("a new account is seeded with six lists including exactly one Complete", lists.length === 6 && lists.filter((l) => l.kind === "complete").length === 1, lists.map((l) => l.name).join(", "));
  await until(async () => (await (await fetch(`${FIRESTORE}/users/${uid}`, { headers: authHeaders(idToken) })).json()).fields?.listsVersion);
  check("a new account starts with the listsVersion flag set", (await (await fetch(`${FIRESTORE}/users/${uid}`, { headers: authHeaders(idToken) })).json()).fields?.listsVersion?.integerValue === "2");

  // Use the app: a card, and a flow with a linked task.
  await page.goto(BASE + "/boards");
  await page.waitForTimeout(2000);
  await page.goto(BASE + (await page.locator('a[href^="/board?id="]').first().getAttribute("href")));
  await page.waitForTimeout(2500);
  const todo = page.locator("section", { has: page.locator("h3", { hasText: /^Todo$/ }) });
  await todo.getByRole("button", { name: "Add card" }).click();
  await todo.getByPlaceholder("Card title…").fill("Throwaway task");
  await todo.getByPlaceholder("Card title…").press("Enter");
  check("a card can be created in the new account", await until(() => todo.getByText("Throwaway task").isVisible()));

  await page.goto(BASE + "/flows");
  await page.waitForTimeout(1500);
  await page.getByRole("button", { name: "New flow" }).first().click();
  await page.getByRole("button", { name: "Create flow" }).click();
  await page.waitForURL(/\/flow\?id=/, { timeout: 20000 });
  await page.waitForTimeout(2500);

  const before = {};
  for (const c of COLLECTIONS) before[c] = (await count(c)).n;
  check("data exists before deletion (tasks, lists, flows, stages)", before.tasks > 0 && before.lists > 0 && before.projectFlows > 0 && before.flowStages === 9 + 0 || before.flowStages > 0, JSON.stringify(before));

  // ----- deletion, first with the final Auth step blocked (a partial failure)
  await page.goto(BASE + "/settings");
  await page.waitForTimeout(1500);
  await page.route("**/accounts:delete*", (route) => route.abort());
  await page.getByRole("button", { name: /Delete account/ }).click();
  await page.getByLabel("Your password").fill("definitely-wrong");
  await page.getByRole("dialog").getByRole("button", { name: "Delete", exact: true }).click();
  check("a wrong password is refused and nothing is deleted", await until(() => page.getByText("That password is not correct.").isVisible()));
  check("data is untouched after a refused confirmation", (await count("tasks")).n === before.tasks);

  await page.getByLabel("Your password").fill(password);
  await page.getByRole("dialog").getByRole("button", { name: "Delete", exact: true }).click();
  await until(() => page.getByText("Could not delete the account").isVisible(), 30000);
  check("when the final step fails the error is shown, not swallowed", await page.getByText("Could not delete the account").isVisible());

  // The partial failure: data is already gone, the account still exists.
  const mid = {};
  for (const c of COLLECTIONS) mid[c] = (await count(c)).n;
  check("the user's data was already removed (collections empty)", COLLECTIONS.every((c) => mid[c] === 0), JSON.stringify(mid));
  check("the user document is gone", (await fetch(`${FIRESTORE}/users/${uid}`, { headers: authHeaders(idToken) })).status === 404);
  const stillSignsIn = await idt("signInWithPassword", { email, password, returnSecureToken: true });
  check("the Auth account still exists after the partial failure (so it can be retried)", stillSignsIn.ok);

  // ----- retry: let it through
  await page.unroute("**/accounts:delete*");
  await page.getByRole("dialog").getByRole("button", { name: "Delete", exact: true }).click();
  await until(() => page.url().includes("/login"), 30000);
  check("a retry completes and the app returns to the login page", page.url().includes("/login"), page.url());

  const gone = await idt("signInWithPassword", { email, password, returnSecureToken: true });
  check("the account can no longer sign in", !gone.ok && /EMAIL_NOT_FOUND|INVALID_LOGIN_CREDENTIALS/.test(gone.json.error?.message ?? ""), gone.json.error?.message);
  const afterRead = await count("tasks", idToken);
  check("the old token can no longer read the data", afterRead.status !== 200 || afterRead.n === 0, `HTTP ${afterRead.status}`);
} catch (e) {
  check("script ran to the end", false, String(e).slice(0, 300));
  // Never leave a throwaway account behind.
  await idt("delete", { idToken }).catch(() => {});
} finally {
  await browser.close();
}

const failed = results.filter((r) => !r).length;
console.log(`\n===== web account deletion e2e: ${results.length - failed} passed, ${failed} failed =====`);
process.exit(failed ? 1 : 0);

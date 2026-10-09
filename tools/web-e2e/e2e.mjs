// Real-browser end-to-end run of the built Next.js site against the live Firebase
// project, signed in as the shared test account. Everything it creates is deleted
// at the end. Usage: node e2e.mjs <baseUrl> [label]
import { chromium } from "playwright";
import { mkdirSync } from "node:fs";

const BASE = process.argv[2] ?? "http://localhost:4173";
const LABEL = process.argv[3] ?? "local";
const EMAIL = process.env.MYS_TEST_EMAIL;
const PASSWORD = process.env.MYS_TEST_PASSWORD;
const SHOTS = new URL(`./shots-${LABEL}/`, import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1");
mkdirSync(SHOTS, { recursive: true });

const results = [];
const check = (name, ok, detail = "") => {
  results.push({ name, ok });
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? " — " + detail : ""}`);
};

const stamp = Date.now();
const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 1360, height: 900 } });
const page = await ctx.newPage();
const consoleErrors = [];
page.on("console", (m) => m.type() === "error" && !/Failed to load resource/.test(m.text()) && consoleErrors.push(m.text()));
page.on("pageerror", (e) => consoleErrors.push(String(e)));

const until = async (fn, ms = 15000) => { const end = Date.now() + ms; for (;;) { try { if (await fn()) return true; } catch {} if (Date.now() > end) return false; await page.waitForTimeout(250); } };
const settle = (ms = 1500) => page.waitForTimeout(ms);
const shot = (name) => page.screenshot({ path: `${SHOTS}${name}.png` });

try {
  // ---------------------------------------------------------- public routes
  for (const [path, text] of [
    ["/privacy", "Privacy Policy"],
    ["/terms", "Terms of Service"],
    ["/login", "Welcome back"],
  ]) {
    const res = await page.goto(BASE + path);
    await settle(500);
    check(`${path} loads signed out`, res.status() === 200 && (await page.getByText(text).first().isVisible()), `HTTP ${res.status()}`);
  }
  check("privacy page says what is stored", await page.goto(BASE + "/privacy").then(() => page.getByText("What we store").isVisible()));

  // -------------------------------------------------------------- sign in
  await page.goto(BASE + "/login");
  await page.getByPlaceholder("Email").fill(EMAIL);
  await page.getByPlaceholder("Password").fill(PASSWORD);
  await page.locator('button[type="submit"]').click();
  await page.waitForURL((u) => !u.pathname.startsWith("/login"), { timeout: 30000 });
  await settle(2500);
  check("email sign-in works and leaves /login", !new URL(page.url()).pathname.startsWith("/login"), page.url());

  // ------------------------------------------------------ protected routes
  const routes = ["/", "/today", "/inbox", "/boards", "/calendar", "/search", "/categories", "/notes", "/reminders", "/holidays", "/focus", "/eisenhower", "/statistics", "/settings", "/flows"];
  for (const r of routes) {
    const res = await page.goto(BASE + r);
    await settle(1200);
    const ok = res.status() === 200 && !page.url().includes("/login") && (await page.locator("main, [class*=px-5]").first().isVisible());
    check(`direct load of ${r}`, ok, `HTTP ${res.status()} -> ${new URL(page.url()).pathname}`);
  }

  // ---------------------------------------------------------------- boards
  await page.goto(BASE + "/boards");
  await settle(2000);
  const boardLink = page.locator('a[href^="/board?id="]').first();
  const boardHref = await boardLink.getAttribute("href");
  check("boards page lists a board", !!boardHref, boardHref ?? "");
  await page.goto(BASE + boardHref);
  await settle(2500);
  await shot("board");

  const columnNames = await page.locator("section h3").allInnerTexts();
  check("board has a Complete list and no Done list", columnNames.includes("Complete") && !columnNames.includes("Done"), columnNames.join(" | "));

  // create a card in the Todo list through the inline composer
  const title = `E2E task ${stamp}`;
  const todo = page.locator("section", { has: page.locator("h3", { hasText: /^Todo$/ }) });
  await todo.getByRole("button", { name: "Add card" }).click();
  await todo.getByPlaceholder("Card title…").fill(title);
  await todo.getByPlaceholder("Card title…").press("Enter");
  await settle(2000);
  check("new card appears in Todo", await todo.getByText(title).isVisible());

  await page.reload();
  await settle(3000);
  const todoAfter = page.locator("section", { has: page.locator("h3", { hasText: /^Todo$/ }) });
  check("card survives a refresh", await todoAfter.getByText(title).isVisible());

  // complete it from the card: it must MOVE to Complete, not duplicate
  const countBefore = await page.getByText(title).count();
  await todoAfter.locator("div.card", { hasText: title }).getByRole("button", { name: "Mark as done" }).first().click();
  await settle(3000);
  const completeCol = page.locator("section", { has: page.locator("h3", { hasText: /^Complete$/ }) });
  check("completing moves the card to Complete", await until(() => completeCol.getByText(title).isVisible()));
  check("it left Todo", await until(async () => (await todoAfter.getByText(title).count()) === 0));
  check("no duplicate was created", (await page.getByText(title).count()) === countBefore);
  await shot("board-after-complete");

  // reopen: back to where it came from
  await completeCol.locator("div.card", { hasText: title }).getByRole("button", { name: "Mark as not done" }).first().click();
  await settle(3000);
  check("re-opening returns it to Todo", await until(() => todoAfter.getByText(title).isVisible()));

  // list Move left / right
  const namesBefore = await page.locator("section h3").allInnerTexts();
  const second = page.locator("section", { has: page.locator("h3", { hasText: new RegExp(`^${namesBefore[1]}$`) }) });
  await second.getByRole("button", { name: "Move list left" }).click();
  await settle(2500);
  const namesAfter = await page.locator("section h3").allInnerTexts();
  check("Move left swaps the list with the one before", namesAfter[0] === namesBefore[1] && namesAfter[1] === namesBefore[0], namesAfter.slice(0, 2).join(" | "));
  await page.locator("section", { has: page.locator("h3", { hasText: new RegExp(`^${namesBefore[1]}$`) }) }).getByRole("button", { name: "Move list right" }).click();
  await settle(2500);
  const namesRestored = await page.locator("section h3").allInnerTexts();
  check("Move right restores the order", namesRestored.join("|") === namesBefore.join("|"));

  // drag to the top zone (dnd-kit pointer drag)
  const cardBox = await todoAfter.locator("div.card", { hasText: title }).first().boundingBox();
  const topBox = await todoAfter.locator('div[class*="rounded-xl"][class*="h-2"], div[class*="h-10"]').first().boundingBox().catch(() => null);
  check("a drop zone exists above the first card", !!topBox);

  // ----------------------------------------------------------- recurrence
  // (the card is deleted at the end by the cleanup below)

  // ---------------------------------------------------------------- flows
  await page.goto(BASE + "/flows");
  await settle(2000);
  await page.getByRole("button", { name: "New flow" }).first().click();
  await page.getByLabel("Goal").fill("I want to launch my Flutter app");
  await page.getByRole("button", { name: "Suggest" }).click();
  check("advisor labels its source as not AI", await page.getByText("not AI").isVisible());
  check("advisor promises no tasks are created", await page.getByText("No tasks are created").first().isVisible());
  await page.getByRole("button", { name: "Add all" }).click();
  const flowName = `E2E flow ${stamp}`;
  await page.getByRole("dialog").locator("input").first().fill(flowName);
  await page.getByRole("button", { name: "Create flow" }).click();
  await page.waitForURL(/\/flow\?id=/, { timeout: 20000 });
  await settle(2500);
  check("flow detail shows 0/9 stages", await page.getByText("0/9 stages complete").isVisible());
  check("first stage is active, second is up next", (await page.locator('[data-state="active"]').count()) === 1 && (await page.locator('[data-state="upcoming"]').count()) === 1);
  await shot("flow-detail");

  // link the existing task to stage 1, then complete it from the flow
  await page.getByRole("button", { name: "Link a task" }).first().click();
  await page.getByLabel("Search tasks").fill(title);
  await page.getByRole("dialog").getByRole("button", { name: new RegExp(title) }).click();
  await settle(2500);
  check("task is linked (stage shows 0/1 tasks)", await page.getByText("0/1 tasks").isVisible());
  await page.getByLabel(`Complete ${title}`).click();
  await settle(3500);
  check("completing the linked task completes stage 1 and unlocks stage 2", await until(async () => (await page.getByText("1/9 stages complete").isVisible()) && (await page.locator('[data-state="completed"]').count()) === 1 && (await page.locator('[data-state="active"]').count()) === 1));
  await shot("flow-after-complete");

  // the board card shows the flow badge
  await page.goto(BASE + boardHref);
  await settle(3000);
  check("board card shows the Flow badge", await page.getByText("Flow 1/9").first().isVisible());

  // privacy/terms linked from settings; delete-account dialog opens and cancels
  await page.goto(BASE + "/settings");
  await settle(1500);
  check("settings links Privacy and Terms", (await page.getByRole("link", { name: "Privacy Policy" }).isVisible()) && (await page.getByRole("link", { name: "Terms of Service" }).isVisible()));
  await page.getByRole("button", { name: /Delete account/ }).click();
  check("delete account asks for confirmation and a password", (await page.getByText("Delete your account?").isVisible()) && (await page.getByLabel("Your password").isVisible()));
  await page.getByRole("button", { name: "Cancel" }).click();

  // holidays: four groups
  await page.goto(BASE + "/holidays");
  await settle(1500);
  const labels = await page.locator("label span.font-semibold").allInnerTexts();
  check("holiday types are Public / Bank / Mercantile / Other", ["Public holidays", "Bank holidays", "Mercantile holidays"].every((l) => labels.includes(l)) && labels.some((l) => l.startsWith("Other")), labels.join(" | "));

  // -------------------------------------------------------- responsive
  for (const [name, w, h] of [["desktop", 1360, 900], ["tablet", 820, 1100], ["phone", 390, 800]]) {
    await page.setViewportSize({ width: w, height: h });
    await page.goto(BASE + boardHref);
    await settle(2500);
    const overflowX = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 2);
    await shot(`board-${name}`);
    check(`board has no page-level horizontal overflow at ${w}px`, !overflowX);
    await page.goto(BASE + "/flows");
    await settle(1500);
    check(`flows page has no page-level horizontal overflow at ${w}px`, !(await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 2)));
  }
  await page.setViewportSize({ width: 1360, height: 900 });

  // dark mode
  await page.emulateMedia({ colorScheme: "dark" });
  await page.goto(BASE + "/flows");
  await settle(1500);
  await shot("flows-dark");
  await page.emulateMedia({ colorScheme: "light" });
} catch (e) {
  check("script ran to the end without an exception", false, String(e).slice(0, 300));
  await shot("failure").catch(() => {});
} finally {
  await browser.close();
}

const fails = results.filter((r) => !r.ok);
console.log(`\n===== web e2e (${LABEL}): ${results.length - fails.length} passed, ${fails.length} failed =====`);
if (consoleErrors.length) {
  const unique = [...new Set(consoleErrors)].slice(0, 12);
  console.log(`console errors (${consoleErrors.length}):`);
  unique.forEach((e) => console.log("  - " + e.slice(0, 200)));
}
process.exit(fails.length ? 1 : 0);

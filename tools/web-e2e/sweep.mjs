// Dark/light and responsive sweep of the Next.js site in a real browser.
//
// For every screen, theme and width it (1) screenshots, (2) checks for page-level
// horizontal overflow, and (3) measures the contrast of every visible text element
// against the colour actually painted behind it, flagging anything under WCAG AA
// (4.5:1, or 3:1 for large text). Usage: node sweep.mjs <baseUrl> [outDir]
import { chromium } from "playwright";
import { mkdirSync, writeFileSync } from "node:fs";

const BASE = process.argv[2] ?? "http://localhost:4173";
const OUT = process.argv[3] ?? "sweep-shots";
const EMAIL = process.env.MYS_TEST_EMAIL;
const PASSWORD = process.env.MYS_TEST_PASSWORD;
if (!EMAIL || !PASSWORD) throw new Error("Set MYS_TEST_EMAIL and MYS_TEST_PASSWORD");
mkdirSync(OUT, { recursive: true });

const WIDTHS = [
  ["desktop", 1360, 900],
  ["tablet", 820, 1100],
  ["phone", 390, 800],
];

// Runs in the page: contrast of each visible text node against its painted background.
const MEASURE = () => {
  const parse = (c) => {
    const m = c.match(/rgba?\(([\d.]+)[, ]+([\d.]+)[, ]+([\d.]+)(?:[,/ ]+([\d.]+))?\)/);
    if (!m) return null;
    return [Number(m[1]), Number(m[2]), Number(m[3]), m[4] === undefined ? 1 : Number(m[4])];
  };
  const lin = (v) => ((v /= 255) <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4);
  const lum = (r, g, b) => 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
  const blend = (top, under) => [0, 1, 2].map((i) => top[i] * top[3] + under[i] * (1 - top[3])).concat(1);
  const backdrop = (el) => {
    const stack = [];
    for (let e = el; e; e = e.parentElement) {
      const bg = parse(getComputedStyle(e).backgroundColor);
      if (bg && bg[3] > 0) stack.push(bg);
      if (bg && bg[3] === 1) break;
    }
    let acc = parse(getComputedStyle(document.body).backgroundColor) ?? [255, 255, 255, 1];
    if (acc[3] < 1) acc = [255, 255, 255, 1];
    for (const layer of stack.reverse()) acc = blend(layer, acc);
    return acc;
  };
  const issues = [];
  const seen = new Set();
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    const text = n.textContent.trim();
    if (!text) continue;
    const el = n.parentElement;
    if (!el || ["SCRIPT", "STYLE", "NOSCRIPT"].includes(el.tagName)) continue;
    const rect = el.getBoundingClientRect();
    const cs = getComputedStyle(el);
    if (rect.width === 0 || rect.height === 0 || cs.visibility === "hidden" || cs.display === "none" || Number(cs.opacity) === 0) continue;
    if (rect.bottom < 0 || rect.top > innerHeight * 4) continue;
    if (el.closest("[disabled]") || el.closest("[aria-disabled=true]")) continue; // disabled controls are exempt
    const fg = parse(cs.color);
    if (!fg) continue;
    const bg = backdrop(el);
    const f = blend(fg, bg);
    const ratio = (() => {
      const a = lum(f[0], f[1], f[2]), b = lum(bg[0], bg[1], bg[2]);
      return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
    })();
    const size = parseFloat(cs.fontSize);
    const bold = Number(cs.fontWeight) >= 700;
    const large = size >= 24 || (size >= 18.66 && bold);
    const need = large ? 3 : 4.5;
    const key = `${text.slice(0, 40)}|${cs.color}|${cs.backgroundColor}`;
    if (ratio < need && !seen.has(key)) {
      seen.add(key);
      issues.push({ text: text.slice(0, 50), ratio: Number(ratio.toFixed(2)), need, color: cs.color, size });
    }
  }
  return {
    issues,
    overflowX: document.documentElement.scrollWidth > innerWidth + 2,
  };
};

const browser = await chromium.launch();
const report = [];
const log = (line) => console.log(line);

for (const scheme of ["light", "dark"]) {
  const ctx = await browser.newContext({ colorScheme: scheme, viewport: { width: 1360, height: 900 } });
  const page = await ctx.newPage();
  const settle = (ms = 1800) => page.waitForTimeout(ms);

  await page.goto(BASE + "/login");
  await page.getByPlaceholder("Email").fill(EMAIL);
  await page.getByPlaceholder("Password").fill(PASSWORD);
  await page.locator('button[type="submit"]').click();
  await page.waitForURL((u) => !u.pathname.startsWith("/login"), { timeout: 30000 });
  await settle(2500);

  await page.goto(BASE + "/boards");
  await settle();
  const boardHref = await page.locator('a[href^="/board?id="]').first().getAttribute("href");

  // A flow to look at (removed afterwards by the cleanup script, name prefix "E2E flow").
  await page.goto(BASE + "/flows");
  await settle();
  await page.getByRole("button", { name: "New flow" }).first().click();
  await page.getByRole("dialog").locator("input").first().fill(`E2E flow sweep ${scheme}`);
  await page.getByRole("button", { name: "Create flow" }).click();
  await page.waitForURL(/\/flow\?id=/, { timeout: 20000 });
  const flowHref = new URL(page.url()).pathname + new URL(page.url()).search;
  await settle();

  const screens = [
    ["board", boardHref],
    ["calendar", "/calendar"],
    ["flows", "/flows"],
    ["flow-detail", flowHref],
    ["inbox", "/inbox"],
    ["today", "/today"],
    ["holidays", "/holidays"],
    ["settings", "/settings"],
    ["login-legal", "/privacy"],
  ];

  for (const [wname, w, h] of WIDTHS) {
    await page.setViewportSize({ width: w, height: h });
    for (const [name, href] of screens) {
      await page.goto(BASE + href);
      await settle(1500);
      const res = await page.evaluate(MEASURE);
      await page.screenshot({ path: `${OUT}/${scheme}-${wname}-${name}.png` });
      report.push({ scheme, width: wname, screen: name, ...res });
      log(`${scheme} ${wname} ${name}: ${res.issues.length} contrast issue(s)${res.overflowX ? ", HORIZONTAL OVERFLOW" : ""}`);
    }

    // Dialogs and menus (desktop and phone are enough to exercise both layouts).
    if (wname !== "tablet") {
      await page.goto(BASE + boardHref);
      await settle(1800);
      await page.getByRole("button", { name: /quick add/i }).first().click().catch(() => {});
      await settle(900);
      let res = await page.evaluate(MEASURE);
      await page.screenshot({ path: `${OUT}/${scheme}-${wname}-quick-add.png` });
      report.push({ scheme, width: wname, screen: "quick-add", ...res });
      log(`${scheme} ${wname} quick-add: ${res.issues.length} issue(s)`);
      await page.keyboard.press("Escape");
      await settle(400);

      const card = page.locator("div.card").first();
      if (await card.isVisible().catch(() => false)) {
        await card.click({ position: { x: 20, y: 40 } }).catch(() => {});
        await settle(900);
        res = await page.evaluate(MEASURE);
        await page.screenshot({ path: `${OUT}/${scheme}-${wname}-task-dialog.png` });
        report.push({ scheme, width: wname, screen: "task-dialog", ...res });
        log(`${scheme} ${wname} task-dialog: ${res.issues.length} issue(s)`);
        await page.keyboard.press("Escape");
      }
    }
  }
  await ctx.close();
}

await browser.close();
writeFileSync(`${OUT}/report.json`, JSON.stringify(report, null, 2));
const bad = report.filter((r) => r.issues.length || r.overflowX);
console.log(`\n${report.length} screens measured, ${bad.length} with findings`);
for (const r of bad) {
  console.log(`- ${r.scheme}/${r.width}/${r.screen}${r.overflowX ? " [overflow-x]" : ""}`);
  for (const i of r.issues.slice(0, 6)) console.log(`    ${i.ratio}:1 (need ${i.need}) "${i.text}" ${i.color}`);
}

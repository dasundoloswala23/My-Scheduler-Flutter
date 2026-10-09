// Loads the Flutter web release build in a real browser, signs in through its UI
// (via Flutter's accessibility tree) and checks the Today screen and the legal pages.
import { chromium } from "playwright";
import { mkdirSync } from "node:fs";

const BASE = process.argv[2] ?? "http://localhost:4180";
const EMAIL = process.env.MYS_TEST_EMAIL;
const PASSWORD = process.env.MYS_TEST_PASSWORD;
const SHOTS = new URL("./shots-flutterweb/", import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1");
mkdirSync(SHOTS, { recursive: true });
const results = [];
const check = (name, ok, detail = "") => {
  results.push(ok);
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? " — " + detail : ""}`);
};

const browser = await chromium.launch({ channel: "chrome", args: ["--enable-unsafe-swiftshader", "--use-angle=swiftshader"] });
const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
const errors = [];
page.on("console", (m) => m.type() === "error" && !/Failed to load resource/.test(m.text()) && errors.push(m.text()));
page.on("pageerror", (e) => errors.push(String(e)));

try {
  await page.goto(BASE, { waitUntil: "load" });
  await page.waitForSelector("flt-glass-pane", { state: "attached", timeout: 60000 });
  check("the Flutter web release build boots", true);

  // Flutter draws to a canvas; its accessibility tree is switched on by this button.
  await page.waitForTimeout(3000);
  await page.evaluate(() => document.querySelector("flt-semantics-placeholder")?.click());
  await page.waitForTimeout(1500);
  await page.screenshot({ path: `${SHOTS}signin.png` });

  const email = page.getByRole("textbox", { name: /email/i }).first();
  check("the sign-in screen is reachable", await email.isVisible({ timeout: 10000 }).catch(() => false));
  check("Terms and Privacy Policy links are on the sign-in screen",
    (await page.getByText("Privacy Policy").first().isVisible().catch(() => false)) &&
      (await page.getByText("Terms").first().isVisible().catch(() => false)));

  if (EMAIL && PASSWORD) {
    await email.fill(EMAIL);
    await page.mouse.click(640, 370);
    await page.waitForTimeout(500);
    await page.keyboard.type(PASSWORD, { delay: 40 });
    await page.mouse.click(640, 442);
    await page.waitForTimeout(9000);
    await page.screenshot({ path: `${SHOTS}after-signin.png` });
    check("signing in shows the signed-in home", await page.getByText(/Good (morning|afternoon|evening)/).first().isVisible().catch(() => false));
    check("Today shows its date selector", await page.getByLabel("Next day").first().isVisible().catch(() => false) || await page.getByRole("button", { name: /Next day/ }).first().isVisible().catch(() => false));
  }
} catch (e) {
  check("script ran to the end", false, String(e).slice(0, 250));
  await page.screenshot({ path: `${SHOTS}failure.png` }).catch(() => {});
} finally {
  await browser.close();
}
const failed = results.filter((r) => !r).length;
console.log(`\n===== flutter web: ${results.length - failed} passed, ${failed} failed =====`);
if (errors.length) console.log("console errors:\n  - " + [...new Set(errors)].slice(0, 6).join("\n  - ").slice(0, 900));
process.exit(failed ? 1 : 0);

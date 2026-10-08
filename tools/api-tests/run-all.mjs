/**
 * Runs every API test suite against the live Firebase project and reports a
 * combined result. Exits non-zero if any suite fails, so CI can gate on it.
 *
 *   node tools/api-tests/run-all.mjs
 */
import { spawn } from "node:child_process";

const SUITES = ["data-layer.test.mjs", "storage.test.mjs", "rules-live.test.mjs"];

function run(file) {
  return new Promise((resolve) => {
    console.log(`\n\n######## ${file} ########\n`);
    const child = spawn(process.execPath, [file], {
      stdio: "inherit",
      cwd: import.meta.dirname,
    });
    child.on("exit", (code) => resolve({ file, code: code ?? 1 }));
  });
}

const results = [];
for (const suite of SUITES) {
  results.push(await run(suite));
}

console.log("\n\n================ SUITE SUMMARY ================");
for (const r of results) {
  console.log(`${r.code === 0 ? "PASS" : "FAIL"}  ${r.file}`);
}

const failed = results.filter((r) => r.code !== 0);
console.log(failed.length ? `\n${failed.length} suite(s) failed.` : "\nAll suites passed.");
process.exit(failed.length ? 1 : 0);

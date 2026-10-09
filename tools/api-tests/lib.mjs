/**
 * Shared helpers for the API test suites.
 *
 * These tests run against the real Firebase project through the public API
 * key and a signed-in user's ID token, which is exactly the path the Flutter
 * and Next.js clients take. That means they also verify the security rules,
 * not just the data shapes.
 */
/** Test credentials are never kept in the repository; pass them in the environment. */
function requireEnv(name) {
  const v = process.env[name];
  if (!v) throw new Error(`Set ${name} in the environment to run the live API tests.`);
  return v;
}

export const KEY = process.env.MYS_API_KEY ?? "AIzaSyAqNL0cPUS0hthRLh3OQvOIGueFDZOMLQ0";
export const PROJECT = process.env.MYS_PROJECT ?? "myscheduleplanner-e22f3";
export const BUCKET = process.env.MYS_BUCKET ?? "myscheduleplanner-e22f3.firebasestorage.app";
export const EMAIL = requireEnv("MYS_TEST_EMAIL");
export const PASSWORD = requireEnv("MYS_TEST_PASSWORD");

export const FIRESTORE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
export const STORAGE = `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o`;

// This machine's connection drops requests now and then, so every call retries
// with backoff rather than failing the suite over a blip.
const rawFetch = globalThis.fetch;
globalThis.fetch = async (url, options = {}) => {
  let lastError;
  for (let attempt = 1; attempt <= 6; attempt++) {
    try {
      return await rawFetch(url, { ...options, signal: AbortSignal.timeout(30000) });
    } catch (e) {
      lastError = e;
      await new Promise((r) => setTimeout(r, 1000 * attempt));
    }
  }
  throw lastError;
};

// ------------------------------------------------------------------ reporting

export const results = { pass: [], fail: [] };

export function check(name, ok, detail = "") {
  (ok ? results.pass : results.fail).push(name);
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? " — " + detail : ""}`);
  return ok;
}

export function summary(title) {
  const { pass, fail } = results;
  console.log(`\n===== ${title}: ${pass.length} passed, ${fail.length} failed =====`);
  if (fail.length) {
    console.log("Failures:");
    fail.forEach((f) => console.log(" - " + f));
  }
  return fail.length === 0;
}

// ----------------------------------------------------------------------- auth

/** Signs the test account in, creating it the first time. */
export async function signIn() {
  let res = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${KEY}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email: EMAIL, password: PASSWORD, returnSecureToken: true }),
  });
  let json = await res.json();

  if (!res.ok && json.error?.message === "EMAIL_EXISTS") {
    res = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${KEY}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: EMAIL, password: PASSWORD, returnSecureToken: true }),
    });
    json = await res.json();
  }

  if (!res.ok) throw new Error(`Sign-in failed: ${json.error?.message ?? res.status}`);
  return { uid: json.localId, token: json.idToken };
}

export const authHeaders = (token) => ({
  Authorization: `Bearer ${token}`,
  "Content-Type": "application/json",
});

// ------------------------------------------------------- firestore value codec

export function toValue(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (typeof v === "boolean") return { booleanValue: v };
  if (typeof v === "number")
    return Number.isInteger(v) && Math.abs(v) < 2 ** 31
      ? { integerValue: String(v) }
      : { doubleValue: v };
  if (typeof v === "string") return { stringValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(toValue) } };
  return { mapValue: { fields: toFields(v) } };
}

export const toFields = (obj) =>
  Object.fromEntries(Object.entries(obj).map(([k, v]) => [k, toValue(v)]));

export function fromValue(v) {
  if (!v || "nullValue" in v) return null;
  if ("stringValue" in v) return v.stringValue;
  if ("booleanValue" in v) return v.booleanValue;
  if ("integerValue" in v) return Number(v.integerValue);
  if ("doubleValue" in v) return v.doubleValue;
  if ("timestampValue" in v) return new Date(v.timestampValue);
  if ("arrayValue" in v) return (v.arrayValue.values ?? []).map(fromValue);
  if ("mapValue" in v) return fromFields(v.mapValue.fields ?? {});
  return null;
}

export const fromFields = (f) =>
  Object.fromEntries(Object.entries(f).map(([k, v]) => [k, fromValue(v)]));

// -------------------------------------------------------- firestore operations

export async function createDoc(token, path, data, docId) {
  const res = await fetch(`${FIRESTORE}/${path}${docId ? `?documentId=${docId}` : ""}`, {
    method: "POST",
    headers: authHeaders(token),
    body: JSON.stringify({ fields: toFields(data) }),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`${path}: ${json.error?.message ?? res.status}`);
  return json.name.split("/").pop();
}

export async function patchDoc(token, path, data) {
  const mask = Object.keys(data).map((k) => `updateMask.fieldPaths=${k}`).join("&");
  const res = await fetch(`${FIRESTORE}/${path}?${mask}`, {
    method: "PATCH",
    headers: authHeaders(token),
    body: JSON.stringify({ fields: toFields(data) }),
  });
  if (!res.ok) {
    const json = await res.json();
    throw new Error(`patch ${path}: ${json.error?.message ?? res.status}`);
  }
}

export async function getDoc(token, path) {
  const res = await fetch(`${FIRESTORE}/${path}`, { headers: authHeaders(token) });
  if (!res.ok) return null;
  const json = await res.json();
  return fromFields(json.fields ?? {});
}

export async function listDocs(token, path) {
  const res = await fetch(`${FIRESTORE}/${path}?pageSize=300`, { headers: authHeaders(token) });
  if (!res.ok) return [];
  const json = await res.json();
  return (json.documents ?? []).map((d) => ({
    id: d.name.split("/").pop(),
    ...fromFields(d.fields ?? {}),
  }));
}

export async function deleteDoc(token, path) {
  const res = await fetch(`${FIRESTORE}/${path}`, {
    method: "DELETE",
    headers: authHeaders(token),
  });
  return res.ok;
}

// ---------------------------------------------------------- storage operations

/** Uploads bytes to a Storage path. Returns the raw HTTP status and body. */
export async function uploadObject(token, path, bytes, contentType) {
  const res = await fetch(`${STORAGE}?uploadType=media&name=${encodeURIComponent(path)}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": contentType },
    body: bytes,
  });
  const json = await res.json().catch(() => ({}));
  return { status: res.status, json };
}

export async function downloadObject(token, path) {
  const res = await fetch(`${STORAGE}/${encodeURIComponent(path)}?alt=media`, {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });
  return { status: res.status, bytes: res.ok ? new Uint8Array(await res.arrayBuffer()) : null };
}

export async function deleteObject(token, path) {
  const res = await fetch(`${STORAGE}/${encodeURIComponent(path)}`, {
    method: "DELETE",
    headers: { Authorization: `Bearer ${token}` },
  });
  return res.status;
}

export async function objectExists(token, path) {
  const res = await fetch(`${STORAGE}/${encodeURIComponent(path)}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  return res.status === 200;
}

/** A tiny valid PNG, so uploads exercise a real image content type. */
export const TINY_PNG = Uint8Array.from([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
  0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
  0x42, 0x60, 0x82,
]);

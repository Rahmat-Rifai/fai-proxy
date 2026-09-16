/**
 * Import the FAi proxy pool (proxy-list.txt) into the local 9router gateway.
 *
 * - Logs into 9router with the dashboard password (from env 9ROUTER_PASSWORD
 *   or the -p arg), deletes every existing proxy pool, then re-creates one
 *   entry per line in proxy-list.txt with isActive=true.
 *
 * Usage:
 *   $env:9ROUTER_PASSWORD="fai7is"; node scripts/import-9router.js
 *   node scripts/import-9router.js --password fai7is
 *   node scripts/import-9router.js --list proxy-list.txt
 */
const fs = require("fs");
const path = require("path");

const BASE = "http://127.0.0.1:20128";
const PROXY_LIST = path.join(__dirname, "..", "proxy-list.txt");

function parseArgs(argv) {
  const args = { password: process.env["9ROUTER_PASSWORD"] || "" };
  for (let i = 2; i < argv.length; i++) {
    if (argv[i] === "--password" || argv[i] === "-p")
      args.password = argv[++i] || "";
    if (argv[i] === "--list" || argv[i] === "-l") args.list = argv[++i] || "";
    if (argv[i] === "--base") args.base = argv[++i] || "";
  }
  if (args.base) return { ...args, base: args.base };
  return args;
}

async function login(base, password) {
  const resp = await fetch(`${base}/api/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ password }),
  });
  const text = await resp.text();
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    body = null;
  }
  if (!resp.ok || !body?.success) {
    throw new Error(
      `Login failed (HTTP ${resp.status}): ${text.slice(0, 200)}`,
    );
  }
  // Return the auth_token cookie set by the server.
  const setCookie = resp.headers.get("set-cookie") || "";
  const m = setCookie.match(/auth_token=([^;]+)/);
  if (!m)
    throw new Error("Login succeeded but no auth_token cookie was returned");
  return m[1];
}

function safeParse(text) {
  try {
    return text ? JSON.parse(text) : null;
  } catch {
    return null;
  }
}

async function api(base, token, path, options = {}) {
  const resp = await fetch(`${base}${path}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      Cookie: `auth_token=${token}`,
      ...(options.headers || {}),
    },
  });
  const text = await resp.text();
  if (!resp.ok) throw new Error(`HTTP ${resp.status}: ${text.slice(0, 200)}`);
  return safeParse(text);
}

async function main() {
  const args = parseArgs(process.argv);
  const base = args.base || BASE;
  if (!args.password) {
    console.error(
      "Missing dashboard password. Set 9ROUTER_PASSWORD or pass --password <pw>.",
    );
    process.exit(1);
  }
  const listPath = args.list || PROXY_LIST;
  if (!fs.existsSync(listPath)) {
    console.error(
      `Proxy list not found: ${listPath}. Run export-proxies.ps1 first.`,
    );
    process.exit(1);
  }

  const token = await login(base, args.password);
  console.log("Logged in to 9router.");

  const lines = fs
    .readFileSync(listPath, "utf8")
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean);
  console.log(`Read ${lines.length} proxies from ${listPath}`);

  // Delete everything currently in the pool.
  const existing = await api(base, token, "/api/proxy-pools");
  const ids = existing?.proxyPools?.map((p) => p.id) || [];
  console.log(`Existing proxy pools: ${ids.length}`);
  if (ids.length) {
    const res = await Promise.allSettled(
      ids.map((id) =>
        api(base, token, `/api/proxy-pools/${id}`, { method: "DELETE" }),
      ),
    );
    console.log(
      `Deleted: ${res.filter((r) => r.status === "fulfilled").length}, Failed: ${res.filter((r) => r.status === "rejected").length}`,
    );
  }

  // Re-create one entry per proxy line.
  const results = await Promise.allSettled(
    lines.map((url, i) => {
      const m = url.match(/@127\.0\.0\.1:(\d+)/);
      const port = m ? m[1] : String(8001 + i);
      return api(base, token, "/api/proxy-pools", {
        method: "POST",
        body: JSON.stringify({
          name: `FAi Pool 127.0.0.1:${port}`,
          proxyUrl: url,
          noProxy: "",
          isActive: true,
          strictProxy: false,
          type: "http",
        }),
      });
    }),
  );
  const ok = results.filter((r) => r.status === "fulfilled").length;
  const failed = results.filter((r) => r.status === "rejected").length;
  console.log(`Imported: ${ok}, Failed: ${failed}`);

  const verify = await api(base, token, "/api/proxy-pools");
  const active = verify?.proxyPools?.filter((p) => p.isActive).length || 0;
  console.log(
    `Verification: ${verify?.proxyPools?.length || 0} total, ${active} active`,
  );
  if (verify?.proxyPools?.length === lines.length) {
    console.log("SUCCESS: proxy pool imported.");
  } else {
    console.log("WARNING: count mismatch!");
  }
}

main().catch((err) => {
  console.error("FATAL:", err.message);
  process.exit(1);
});

import fs from "node:fs";

const target = new URL("../api/openapi.json", import.meta.url);
const url = process.env.COGNI_OPENAPI_URL || "http://localhost:4111/openapi.json";

try {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const text = await res.text();
  fs.writeFileSync(target, text, "utf8");
  console.log(`synced OpenAPI from ${url}`);
} catch (error) {
  if (!fs.existsSync(target)) {
    fs.writeFileSync(target, JSON.stringify({ openapi: "3.0.3", info: { title: "CogniCore API", version: "dev" }, paths: {} }, null, 2));
  }
  console.log(`OpenAPI sync skipped: ${error.message}`);
}

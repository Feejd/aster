import { test } from "node:test";
import assert from "node:assert/strict";

process.env.DATABASE_URL ??= "sqlite:///test.db";
const { default: app } = await import("../src/index.js");

test("zdrowie i notatki", async () => {
  const server = app.listen(0);
  const base = `http://localhost:${server.address().port}`;
  try {
    assert.deepEqual(await (await fetch(`${base}/api/zdrowie`)).json(), { ok: true });
    const n = await (await fetch(`${base}/api/notatki`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ tekst: "test" }) })).json();
    assert.equal(n.tekst, "test");
  } finally {
    server.close();
  }
});

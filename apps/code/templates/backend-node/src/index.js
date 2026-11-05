import express from "express";
import * as db from "./db.js";

const app = express();
app.use(express.json());
await db.init();

app.get("/api/zdrowie", (req, res) => res.json({ ok: true }));
app.get("/api/notatki", async (req, res) => res.json(await db.lista()));
app.post("/api/notatki", async (req, res) => res.status(201).json(await db.dodaj(String(req.body?.tekst ?? ""))));

export default app;

if (import.meta.url === `file://${process.argv[1]}`) {
  const port = Number(process.env.PORT) || {{backendPort}};
  app.listen(port, () => console.log(`API: http://localhost:${port}`));
}

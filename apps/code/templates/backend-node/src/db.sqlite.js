import { DatabaseSync } from "node:sqlite";

// Plik bazy z DATABASE_URL (sqlite:///ścieżka) albo dane.db obok projektu
const path = (process.env.DATABASE_URL || "sqlite:///dane.db").replace("sqlite:///", "");
const db = new DatabaseSync(path);

export async function init() {
  db.exec("CREATE TABLE IF NOT EXISTS notatki (id INTEGER PRIMARY KEY AUTOINCREMENT, tekst TEXT NOT NULL)");
}

export async function lista() {
  return db.prepare("SELECT id, tekst FROM notatki ORDER BY id").all();
}

export async function dodaj(tekst) {
  const r = db.prepare("INSERT INTO notatki (tekst) VALUES (?)").run(tekst);
  return { id: Number(r.lastInsertRowid), tekst };
}

import pg from "pg";

// Baza z DATABASE_URL (Aster Code: zadanie „baza danych” startuje PostgreSQL w kontenerze projektu)
const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL || "postgresql://postgres@localhost:5432/postgres" });

export async function init() {
  await pool.query("CREATE TABLE IF NOT EXISTS notatki (id SERIAL PRIMARY KEY, tekst TEXT NOT NULL)");
}

export async function lista() {
  return (await pool.query("SELECT id, tekst FROM notatki ORDER BY id")).rows;
}

export async function dodaj(tekst) {
  const r = await pool.query("INSERT INTO notatki (tekst) VALUES ($1) RETURNING id", [tekst]);
  return { id: r.rows[0].id, tekst };
}

import os

import psycopg

# Baza z DATABASE_URL (Aster Code: zadanie „baza danych” startuje PostgreSQL w kontenerze projektu)
URL = os.environ.get("DATABASE_URL", "postgresql://postgres@localhost:5432/postgres")


def init():
    with psycopg.connect(URL) as c:
        c.execute("CREATE TABLE IF NOT EXISTS notatki (id SERIAL PRIMARY KEY, tekst TEXT NOT NULL)")


def lista():
    with psycopg.connect(URL) as c:
        return [{"id": r[0], "tekst": r[1]} for r in c.execute("SELECT id, tekst FROM notatki ORDER BY id")]


def dodaj(tekst):
    with psycopg.connect(URL) as c:
        r = c.execute("INSERT INTO notatki (tekst) VALUES (%s) RETURNING id", (tekst,)).fetchone()
        return {"id": r[0], "tekst": tekst}

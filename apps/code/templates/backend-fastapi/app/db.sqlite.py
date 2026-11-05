import os
import sqlite3

# Plik bazy z DATABASE_URL (sqlite:///ścieżka) albo dane.db obok projektu
PATH = os.environ.get("DATABASE_URL", "sqlite:///dane.db").removeprefix("sqlite:///")


def _conn():
    c = sqlite3.connect(PATH)
    c.row_factory = sqlite3.Row
    return c


def init():
    with _conn() as c:
        c.execute("CREATE TABLE IF NOT EXISTS notatki (id INTEGER PRIMARY KEY AUTOINCREMENT, tekst TEXT NOT NULL)")


def lista():
    with _conn() as c:
        return [dict(r) for r in c.execute("SELECT id, tekst FROM notatki ORDER BY id")]


def dodaj(tekst):
    with _conn() as c:
        cur = c.execute("INSERT INTO notatki (tekst) VALUES (?)", (tekst,))
        return {"id": cur.lastrowid, "tekst": tekst}

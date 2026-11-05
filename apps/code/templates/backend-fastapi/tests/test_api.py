import os

os.environ.setdefault("DATABASE_URL", "sqlite:///test.db")

from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402

client = TestClient(app)


def test_zdrowie():
    assert client.get("/api/zdrowie").json() == {"ok": True}


def test_dodaj_i_lista():
    n = client.post("/api/notatki", json={"tekst": "test"}).json()
    assert n["tekst"] == "test"
    assert any(x["id"] == n["id"] for x in client.get("/api/notatki").json())

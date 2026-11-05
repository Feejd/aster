from fastapi import FastAPI
from pydantic import BaseModel

from . import db

app = FastAPI(title="{{name}}")
db.init()


class NowaNotatka(BaseModel):
    tekst: str


@app.get("/api/zdrowie")
def zdrowie():
    return {"ok": True}


@app.get("/api/notatki")
def notatki():
    return db.lista()


@app.post("/api/notatki", status_code=201)
def dodaj(n: NowaNotatka):
    return db.dodaj(n.tekst)

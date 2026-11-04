#!/usr/bin/env python3
"""Atrapa serwera modelu do testów Asystenta Aster — bez prawdziwego klucza i bez internetu.

Udaje dwa API ze strumieniem SSE:
  POST /v1/chat/completions   zgodne z OpenAI (DeepSeek, OpenAI, Gemini, OpenRouter, llama.cpp, Ollama)
  POST /v1/messages           Anthropic Messages

Użycie:  python3 tools/asystent-atrapa.py [port]      (domyślnie 8080 — jak llama-server)
Klucz:   ATRAPA_KLUCZ=abc  → zapytania bez „Bearer abc” / „x-api-key: abc” dostają 401.

Odpowiedź zależy od pytania: „zip” → komenda w bloku ```bash, „kroki”/„długo” → długa lista,
dane z potoku → liczba wierszy i pierwszy błąd; inaczej krótkie zdanie.
"""
import json
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

KEY = os.environ.get("ATRAPA_KLUCZ", "")
DELAY = float(os.environ.get("ATRAPA_OPOZNIENIE", "0.02"))
START = float(os.environ.get("ATRAPA_START", "0"))     # namysł przed pierwszym kawałkiem odpowiedzi


def answer(messages):
    last = next((m for m in reversed(messages) if m.get("role") == "user"), {})
    content = last.get("content", "")
    if isinstance(content, list):
        content = " ".join(c.get("text", "") for c in content if isinstance(c, dict))
    question, _, data = content.partition("\n\nDane wejściowe:\n")
    q = question.lower()
    system = next((m.get("content", "") for m in messages if m.get("role") == "system"), "")
    if isinstance(system, str) and system.startswith("Streszczasz"):
        first = next((l[len("Użytkownik: "):] for l in content.splitlines() if l.startswith("Użytkownik: ")), "coś")
        return f"Streszczenie: użytkownik pytał „{first[:80]}”; asystent sprawdził to na komputerze i odpowiedział."
    # Tryb projektu: strona → pliki, zmiana, serwer w tle, sprawdzenie curl
    if content.startswith("[System] Wynik polecenia `aster --zmiany") and "index.html (nowy" in content:
        return ("Plan:\n1. Pliki strony — gotowe\n2. Poprawka tytułu\n3. Serwer i sprawdzenie\n\n"
                "```zmiana:~/Projekty/demo/index.html\n<<<<<<< STARE\n<h1>Witaj</h1>\n=======\n<h1>Witaj w Demo</h1>\n>>>>>>> NOWE\n```\n\n"
                "Uruchamiam stronę w tle.\n\n```bash\naster --tlo start demo --w ~/Projekty/demo -- python3 -m http.server 8765\n```")
    if content.startswith("[System] Wynik polecenia `aster --zmiany"):
        return "Sprawdzam, czy strona odpowiada.\n\n```bash\ncurl -s localhost:8765 | grep h1\n```"
    if content.startswith("[System] Wynik polecenia `curl"):
        return "Gotowe — strona Demo działa pod http://localhost:8765, pliki są w ~/Projekty/demo."
    if "stron" in q and "zrób" in q:
        return ("Zrobię prostą stronę.\n\n```plik:~/Projekty/demo/index.html\n<!doctype html>\n<title>Demo</title>\n<h1>Witaj</h1>\n```\n\n"
                "````plik:~/Projekty/demo/README.md\n# Demo\n\n```bash\npython3 -m http.server\n```\n````\n\n"
                "Zapisuję pliki strony.")
    # Pamięć: znaleziona rozmowa → otwórz ją
    if content.startswith("[System] Wynik polecenia `aster --historia"):
        import re
        m = re.search(r"ID (\S+)", content)
        if not m:
            return "Nie znalazłem takiej rozmowy."
        return f"Znalazłem naszą rozmowę — otwieram ją.\n\n```bash\naster --rozmowa {m.group(1)}\n```"
    if content.startswith("[System] Wynik polecenia `aster --rozmowa"):
        return "Otworzyłem naszą wcześniejszą rozmowę — możesz w niej kontynuować."
    if content.startswith("[System] Wynik polecenia `aster-files"):
        return "Otworzyłem Pliki."
    if "wróćmy" in q or "wrocmy" in q:
        word = q.split()[-1].strip("?.!")
        return f"Szukam w naszych wcześniejszych rozmowach.\n\n```bash\naster --historia {word}\n```"
    if "ostatnio" in q:
        mem = system.split("Ostatnie rozmowy (od najnowszej):\n", 1)
        return ("Pamiętam: " + mem[1].splitlines()[0]) if len(mem) > 1 else "Nie pamiętam żadnej wcześniejszej rozmowy."
    if "otwórz pliki" in q or "otworz pliki" in q:
        return "Otwieram Pliki.\n\n```bash\naster-files ~\n```"
    # Agent: wynik polecenia albo odmowa wracają jako wiadomość „[System] …”
    if content.startswith("[System] Użytkownik nie zgodził"):
        return "Dobrze, niczego nie zmieniam. Jeśli zmienisz zdanie, napisz."
    if content.startswith("[System] Wynik polecenia `df"):
        return "Na dysku jest jeszcze sporo miejsca — szczegóły widać w wyniku powyżej. Nic nie trzeba sprzątać."
    if content.startswith("[System] Wynik polecenia `flatpak install"):
        return "Gotowe — Google Chrome jest zainstalowany. Znajdziesz go w Starcie."
    if content.startswith("[System]"):
        return "Zrobione."
    if "miejsc" in q or "dysk" in q:
        return "Sprawdzam, ile jest wolnego miejsca.\n\n```bash\ndf -h ~\n```"
    if "chrome" in q:
        return ("Chrome jest na Flathub, zainstaluję go dla ciebie.\n\nZainstalować Google Chrome?\n\n"
                "```bash\nflatpak install -y --user flathub com.google.Chrome\n```")
    turns = sum(1 for m in messages if m.get("role") == "user")
    if data and ("popraw" in q or "przeredaguj" in q or "przepisz" in q):
        text = data.strip("`\n")
        return text.replace("wogóle", "w ogóle").replace("napewno", "na pewno").replace("pozdrawiam", "Pozdrawiam")
    if data and ("streść" in q or "punkty" in q):
        return "Autor przeprasza za spóźnienie i proponuje spotkanie w czwartek o 10."
    if data:
        lines = [l for l in data.strip("`\n").splitlines() if l.strip()]
        first = next((l for l in lines if "error" in l.lower() or "błąd" in l.lower() or "fail" in l.lower()), lines[0] if lines else "")
        return (f"W danych jest {len(lines)} wierszy. Najważniejszy wygląda na ten:\n\n"
                f"    {first.strip()}\n\nTo zwykle oznacza, że usługa nie wystartowała — sprawdź jej stan:\n\n"
                "```bash\nsystemctl --user status\n```")
    if "zip" in q:
        return ("Spakujesz folder poleceniem `zip` z opcją `-r` (razem z podfolderami):\n\n"
                "```bash\nzip -r folder.zip folder/\n```\n\nPlik **folder.zip** pojawi się obok folderu.")
    if "kroki" in q or "długo" in q or "dlugo" in q:
        return ("Oto kroki, żeby zainstalować program z Flatpaka:\n\n"
                "1. Otwórz **Sklep Aster** z doku.\n2. Wpisz nazwę programu w wyszukiwarce.\n"
                "3. Kliknij **Zainstaluj** i poczekaj na pasek postępu.\n4. Program pojawi się w Starcie.\n\n"
                "Z terminala zrobisz to samo jednym poleceniem:\n\n```bash\nflatpak install flathub org.gimp.GIMP\n```\n\n"
                "| Sposób | Kiedy |\n|---|---|\n| Sklep | na co dzień |\n| Terminal | gdy znasz nazwę |")
    if "15%" in q or "procent" in q:
        return "15% z 240 to 36."
    if turns > 1:
        return f"To już {turns}. pytanie w tej rozmowie — pamiętam poprzednie. Odpowiedź atrapy na: „{question.strip()}”."
    return f"Atrapa modelu odpowiada na: „{question.strip()}”. Wszystko działa."


def pieces(text):
    word = ""
    for ch in text:
        word += ch
        if ch in " \n":
            yield word
            word = ""
    if word:
        yield word


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("atrapa: " + fmt % args + "\n")

    def deny(self, anthropic):
        body = json.dumps({"type": "error", "error": {"type": "authentication_error", "message": "invalid x-api-key"}} if anthropic
                          else {"error": {"message": "Incorrect API key provided", "type": "invalid_request_error"}}).encode()
        self.send_response(401)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.rstrip("/").endswith("/models"):
            body = json.dumps({"object": "list", "data": [{"id": "atrapa", "object": "model"}]}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_error(404)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        req = json.loads(self.rfile.read(length) or b"{}")
        anthropic = self.path.rstrip("/").endswith("/messages")
        if not anthropic and not self.path.rstrip("/").endswith("/chat/completions"):
            self.send_error(404)
            return
        if KEY:
            got = self.headers.get("x-api-key", "") if anthropic else self.headers.get("Authorization", "").removeprefix("Bearer ")
            if got != KEY:
                sys.stderr.write(f"atrapa: zły klucz {got!r}\n")
                self.deny(anthropic)
                return
        text = answer(req.get("messages", []))
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()

        def send(obj, event=None):
            data = (f"event: {event}\n" if event else "") + "data: " + (obj if isinstance(obj, str) else json.dumps(obj)) + "\n\n"
            self.wfile.write(data.encode())
            self.wfile.flush()

        model = req.get("model", "atrapa")
        time.sleep(START)
        if anthropic:
            send({"type": "message_start", "message": {"id": "msg_atrapa", "model": model, "role": "assistant", "content": []}}, "message_start")
            send({"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}, "content_block_start")
            for p in pieces(text):
                send({"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": p}}, "content_block_delta")
                time.sleep(DELAY)
            send({"type": "content_block_stop", "index": 0}, "content_block_stop")
            send({"type": "message_stop"}, "message_stop")
        else:
            for p in pieces(text):
                send({"id": "chatcmpl-atrapa", "object": "chat.completion.chunk", "model": model,
                      "choices": [{"index": 0, "delta": {"content": p}, "finish_reason": None}]})
                time.sleep(DELAY)
            send({"id": "chatcmpl-atrapa", "object": "chat.completion.chunk", "model": model,
                  "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]})
            send("[DONE]")
        self.close_connection = True


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    print(f"atrapa modelu: http://127.0.0.1:{port}/v1", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()

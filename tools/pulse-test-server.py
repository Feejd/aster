#!/usr/bin/env python3
# Serwer testowy dla Aster Pulse (bez zależności): python3 tools/pulse-test-server.py [port, domyślnie 8000]
#   GET  /health                stan
#   GET  /users?page=&limit=    lista (JSON)        POST /users — dodaje (201, odsyła treść)
#   GET|PUT|PATCH|DELETE /users/<id>
#   ANY  /echo                  odsyła metodę, adres, nagłówki i treść (także multipart i formularze)
#   GET  /secure                wymaga Authorization: Bearer sekret123 (inaczej 401)
#   GET  /basic                 wymaga Basic ala:haslo
#   GET  /slow?s=3  /html  /text  /image.png  /big (5000 elementów)  /redirect  /status/<kod>
import base64, json, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

USERS = [{"id": i, "name": n, "email": f"{n.lower()}@example.com", "active": i % 2 == 1,
          "roles": ["admin", "dev"] if i == 1 else ["dev"], "address": {"city": c, "zip": z}}
         for i, (n, c, z) in enumerate([("Ala", "Kraków", "30-001"), ("Bartek", "Gdańsk", "80-001"),
                                         ("Celina", "Poznań", "60-001"), ("Darek", "Wrocław", "50-001")], 1)]
PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAKElEQVR4nGNkYPj/n4EBCxgFQwYGBgYmBgYGBgYmBgZGBgYGBgYGAP8vBA8q3n4NAAAAAElFTkSuQmCC")


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def send(self, code, body, ctype="application/json; charset=utf-8", extra=None):
        data = body if isinstance(body, bytes) else (json.dumps(body, ensure_ascii=False, indent=None).encode() if ctype.startswith("application/json") else body.encode())
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("X-Server", "pulse-test")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n else b""

    def handle_any(self):
        u = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(u.query).items()}
        p = u.path.rstrip("/") or "/"
        raw = self.body()
        if p == "/health":
            return self.send(200, {"status": "ok", "time": time.strftime("%Y-%m-%dT%H:%M:%S"), "version": "1.4.2"})
        if p == "/users":
            if self.command == "POST":
                try:
                    u2 = json.loads(raw or b"{}")
                except ValueError:
                    return self.send(400, {"error": "Treść to nie JSON"})
                u2["id"] = len(USERS) + 1
                return self.send(201, u2, extra={"Location": f"/users/{u2['id']}"})
            page, limit = int(q.get("page", 1)), int(q.get("limit", 20))
            return self.send(200, {"page": page, "total": len(USERS), "items": USERS[(page - 1) * limit: page * limit]})
        if p.startswith("/users/"):
            uid = int(p.split("/")[2])
            user = next((x for x in USERS if x["id"] == uid), None)
            if not user:
                return self.send(404, {"error": "Nie ma użytkownika", "id": uid})
            if self.command == "DELETE":
                return self.send(204, b"")
            if self.command in ("PUT", "PATCH"):
                return self.send(200, {**user, **json.loads(raw or b"{}")})
            return self.send(200, user)
        if p == "/echo":
            return self.send(200, {"method": self.command, "path": self.path, "query": q,
                                   "headers": dict(self.headers.items()), "body": raw.decode("utf-8", "replace")})
        if p == "/secure":
            if self.headers.get("Authorization") != "Bearer sekret123":
                return self.send(401, {"error": "Brak albo zły token"}, extra={"WWW-Authenticate": "Bearer"})
            return self.send(200, {"secret": "dostęp przyznany"})
        if p == "/basic":
            if self.headers.get("Authorization") != "Basic " + base64.b64encode(b"ala:haslo").decode():
                return self.send(401, {"error": "Zły login lub hasło"})
            return self.send(200, {"user": "ala"})
        if p == "/slow":
            time.sleep(float(q.get("s", 3)))
            return self.send(200, {"slept": float(q.get("s", 3))})
        if p == "/html":
            return self.send(200, "<!doctype html><html><body><h1>Witaj</h1></body></html>", "text/html; charset=utf-8")
        if p == "/text":
            return self.send(200, "zwykły tekst\nw dwóch wierszach", "text/plain; charset=utf-8")
        if p == "/image.png":
            return self.send(200, PNG, "image/png")
        if p == "/big":
            return self.send(200, [{"id": i, "name": f"element {i}", "tags": ["a", "b"], "nested": {"x": i * 2}} for i in range(5000)])
        if p == "/redirect":
            self.send_response(302)
            self.send_header("Location", "/health")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if p.startswith("/status/"):
            code = int(p.split("/")[2])
            return self.send(code, {"status": code})
        return self.send(404, {"error": "Nie ma takiej ścieżki", "path": p})

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = do_HEAD = do_OPTIONS = handle_any

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.command, self.path))


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    print(f"Serwer testowy Pulse: http://localhost:{port}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()

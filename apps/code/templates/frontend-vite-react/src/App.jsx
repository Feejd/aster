import { useEffect, useState } from "react";

// Notatki z backendu (/api/notatki); bez backendu — lista tylko w przeglądarce
export default function App() {
  const [notatki, setNotatki] = useState([]);
  const [tekst, setTekst] = useState("");
  const [backend, setBackend] = useState(null);

  useEffect(() => {
    fetch("/api/notatki")
      .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
      .then((d) => { setNotatki(d); setBackend(true); })
      .catch(() => setBackend(false));
  }, []);

  async function dodaj(e) {
    e.preventDefault();
    if (!tekst.trim()) return;
    if (backend) {
      const r = await fetch("/api/notatki", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ tekst }) });
      setNotatki([...notatki, await r.json()]);
    } else {
      setNotatki([...notatki, { id: Date.now(), tekst }]);
    }
    setTekst("");
  }

  return (
    <main>
      <h1>{{name}}</h1>
      <p className="stan">{backend === null ? "Łączę z backendem…" : backend ? "Backend działa" : "Bez backendu"}</p>
      <form onSubmit={dodaj}>
        <input value={tekst} onChange={(e) => setTekst(e.target.value)} placeholder="Nowa notatka" aria-label="Nowa notatka" />
        <button type="submit">Dodaj</button>
      </form>
      <ul>
        {notatki.map((n) => (
          <li key={n.id}>{n.tekst}</li>
        ))}
      </ul>
    </main>
  );
}

import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Zapytania /api idą do backendu (adres z BACKEND_URL albo domyślny)
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: { "/api": process.env.BACKEND_URL || "http://localhost:{{backendPort}}" },
  },
  test: { environment: "jsdom" },
});

import { render, screen } from "@testing-library/react";
import { expect, test, vi } from "vitest";
import App from "./App.jsx";

test("pokazuje tytuł i pole nowej notatki", () => {
  globalThis.fetch = vi.fn(() => Promise.reject(new Error("bez backendu")));
  render(<App />);
  expect(screen.getByRole("heading", { name: "{{name}}" })).toBeDefined();
  expect(screen.getByLabelText("Nowa notatka")).toBeDefined();
});

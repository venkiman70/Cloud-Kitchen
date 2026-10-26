/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        bg: "rgb(var(--bg) / <alpha-value>)",
        surface: "rgb(var(--surface) / <alpha-value>)",
        sunk: "rgb(var(--sunk) / <alpha-value>)",
        line: "rgb(var(--line) / <alpha-value>)",
        fg: "rgb(var(--fg) / <alpha-value>)",
        muted: "rgb(var(--muted) / <alpha-value>)",
        accent: "var(--accent)",
        "accent-ink": "var(--accent-ink)",
        veg: "rgb(var(--veg) / <alpha-value>)",
        nonveg: "rgb(var(--nonveg) / <alpha-value>)",
        egg: "rgb(var(--egg) / <alpha-value>)",
        gold: "rgb(var(--gold) / <alpha-value>)",
      },
      fontFamily: {
        display: ['"Young Serif"', "Georgia", "serif"],
        sans: ["Figtree", "system-ui", "-apple-system", "Segoe UI", "sans-serif"],
      },
    },
  },
  plugins: [],
};

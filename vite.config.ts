import { defineConfig } from "vitest/config"
import react from "@vitejs/plugin-react"
import stylex from "@stylexjs/unplugin"

export default defineConfig({
  plugins: [stylex.vite({ devMode: "css-only", useCSSLayers: false }), react()],
  resolve: {
    alias: { "@": new URL("./src", import.meta.url).pathname },
  },
  test: {
    include: ["src/**/*.test.ts"],
    exclude: ["lib/**", "node_modules/**", "dist/**"],
  },
})

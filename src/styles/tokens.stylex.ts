import * as stylex from "@stylexjs/stylex"

export const colors = stylex.defineConsts({
  white: "#ffffff",
  slate950: "#020617",
  slate900: "#0f172a",
  slate800: "#1e293b",
  slate600: "#475569",
  slate500: "#64748b",
  slate400: "#94a3b8",
  slate300: "#cbd5e1",
  slate200: "#e2e8f0",
  slate100: "#f1f5f9",
  lime300: "#bef264",
  lime200: "#d9f99d",
  amber200: "#fde68a",
  amber100: "#fef3c7",
  cyan100: "#cffafe",
  rose400: "#fb7185",
  rose100: "#ffe4e6",
})

export const breakpoints = stylex.defineConsts({
  sm: "@media (min-width: 640px)",
  md: "@media (min-width: 768px)",
  lg: "@media (min-width: 1024px)",
  xl: "@media (min-width: 1280px)",
  reducedMotion: "@media (prefers-reduced-motion: reduce)",
})

export const motion = stylex.defineConsts({
  easeOut: "cubic-bezier(0.23, 1, 0.32, 1)",
  feedbackDuration: "160ms",
  reducedEnterDuration: "140ms",
})

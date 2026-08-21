import * as stylex from "@stylexjs/stylex"
import type { ReactNode } from "react"

import { colors } from "../../styles/tokens.stylex"

import { Header, type HeaderProps } from "./header"

export interface AppShellProps extends HeaderProps {
  children: ReactNode
}

const styles = stylex.create({
  shell: {
    minHeight: "100vh",
    overflowX: "clip",
    color: "oklch(0.96 0.02 125)",
    backgroundColor: "oklch(0.14 0.025 145)",
    "::selection": {
      backgroundColor: colors.lime300,
      color: colors.slate950,
    },
  },
  skipLink: {
    position: "fixed",
    zIndex: 60,
    top: 12,
    insetInlineStart: 16,
    paddingBlock: 10,
    paddingInline: 14,
    borderRadius: 10,
    backgroundColor: colors.lime300,
    color: "oklch(0.105 0.02 145)",
    fontSize: 14,
    fontWeight: 750,
    transform: { default: "translateY(-150%)", ":focus-visible": "translateY(0)" },
    transitionProperty: "transform",
    transitionDuration: "150ms",
    transitionTimingFunction: "ease-out",
  },
  glow: {
    pointerEvents: "none",
    position: "fixed",
    insetInline: 0,
    top: 0,
    zIndex: 0,
    height: 580,
    backgroundImage:
      "radial-gradient(ellipse 70% 50% at 50% -10%, oklch(0.91 0.22 112 / 0.12), transparent 72%)",
  },
  main: {
    position: "relative",
    zIndex: 10,
    minHeight: "calc(100vh - 72px)",
    width: "100%",
    marginInline: "auto",
  },
})

/** Shared viewport framing for every protocol route. */
export function AppShell({ children, ...headerProps }: AppShellProps) {
  return (
    <div {...stylex.props(styles.shell)}>
      <a {...stylex.props(styles.skipLink)} href="#main-content">
        Skip to content
      </a>
      <div aria-hidden {...stylex.props(styles.glow)} />
      <Header {...headerProps} />
      <main id="main-content" {...stylex.props(styles.main)}>
        {children}
      </main>
    </div>
  )
}

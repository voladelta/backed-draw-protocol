import type { ReactNode } from "react"

import { cn } from "@/lib/utils"

import { Header, type HeaderProps } from "./header"

export interface AppShellProps extends HeaderProps {
  children: ReactNode
  mainClassName?: string
}

/** Shared viewport framing for every protocol route. */
export function AppShell({ children, mainClassName, ...headerProps }: AppShellProps) {
  return (
    <div className="app-shell min-h-screen overflow-x-clip selection:bg-lime-300 selection:text-slate-950">
      <a className="skip-link" href="#main-content">
        Skip to content
      </a>
      <div
        aria-hidden
        className="app-shell-glow pointer-events-none fixed inset-x-0 top-0 -z-0 h-[580px]"
      />
      <Header {...headerProps} />
      <main
        id="main-content"
        className={cn(
          "app-main relative z-10 mx-auto max-w-7xl px-4 py-8 sm:px-6 sm:py-12 lg:px-8",
          mainClassName,
        )}
      >
        {children}
      </main>
    </div>
  )
}

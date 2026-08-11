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
    <div className="min-h-screen overflow-x-clip bg-[#070a11] text-slate-100 selection:bg-lime-300 selection:text-slate-950">
      <div
        aria-hidden
        className="pointer-events-none fixed inset-x-0 top-0 -z-0 h-[580px] bg-[radial-gradient(ellipse_70%_50%_at_50%_-10%,rgba(132,204,22,0.12),transparent_72%)]"
      />
      <Header {...headerProps} />
      <main
        className={cn(
          "relative z-10 mx-auto max-w-7xl px-4 py-8 sm:px-6 sm:py-12 lg:px-8",
          mainClassName,
        )}
      >
        {children}
      </main>
    </div>
  )
}

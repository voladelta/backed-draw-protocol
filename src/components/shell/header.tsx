import { Menu, Wallet } from "lucide-react"
import type { ReactNode } from "react"

import { Button } from "@/components/ui/button"
import { cn } from "@/lib/utils"

export interface NavigationItem {
  label: string
  href: string
  active?: boolean
  onClick?: () => void
}

export interface HeaderProps {
  navigation?: NavigationItem[]
  walletLabel?: string
  onConnectWallet?: () => void
  brand?: ReactNode
  walletSlot?: ReactNode
  className?: string
}

const defaultNavigation: NavigationItem[] = [
  { label: "Explore", href: "/", active: true },
  { label: "My positions", href: "/positions" },
  { label: "Rewards", href: "/rewards" },
  { label: "How it works", href: "/how-it-works" },
]

export function Header({
  navigation = defaultNavigation,
  walletLabel = "Connect wallet",
  onConnectWallet,
  brand,
  walletSlot,
  className,
}: HeaderProps) {
  return (
    <header
      className={cn(
        "sticky top-0 z-40 border-b border-white/[0.07] bg-[#070a11]/80 backdrop-blur-xl",
        className,
      )}
    >
      <div className="mx-auto flex h-[72px] max-w-7xl items-center justify-between gap-4 px-4 sm:px-6 lg:px-8">
        <a aria-label="Draw protocol home" className="flex shrink-0 items-center gap-2.5" href="/">
          {brand ?? <BrandMark />}
        </a>

        <nav aria-label="Primary navigation" className="hidden items-center gap-1 md:flex">
          {navigation.map((item) => (
            <a
              className={cn(
                "rounded-lg px-3 py-2 text-sm font-medium transition-colors duration-150 ease-out",
                item.active
                  ? "bg-white/[0.08] text-white"
                  : "text-slate-400 hover:bg-white/[0.05] hover:text-slate-100",
              )}
              href={item.href}
              key={item.href}
              onClick={(event) => {
                if (item.onClick) {
                  event.preventDefault()
                  item.onClick()
                }
              }}
            >
              {item.label}
            </a>
          ))}
        </nav>

        <div className="hidden items-center gap-3 sm:flex">
          {walletSlot ?? (
            <Button onClick={onConnectWallet} size="sm">
              <Wallet aria-hidden className="size-3.5" />
              {walletLabel}
            </Button>
          )}
        </div>

        <details className="group relative md:hidden">
          <summary className="flex size-10 cursor-pointer list-none items-center justify-center rounded-xl border border-white/10 bg-white/[0.05] text-slate-200 transition-colors hover:bg-white/[0.1] [&::-webkit-details-marker]:hidden">
            <Menu aria-hidden className="size-5" />
            <span className="sr-only">Open navigation</span>
          </summary>
          <div className="absolute right-0 top-[calc(100%+12px)] w-64 rounded-2xl border border-white/10 bg-[#101521]/95 p-2 shadow-2xl backdrop-blur-xl">
            <nav aria-label="Mobile navigation" className="flex flex-col">
              {navigation.map((item) => (
                <a
                  className={cn(
                    "rounded-xl px-3 py-2.5 text-sm font-medium",
                    item.active
                      ? "bg-white/[0.09] text-white"
                      : "text-slate-400 hover:bg-white/[0.06] hover:text-white",
                  )}
                  href={item.href}
                  key={item.href}
                  onClick={(event) => {
                    if (item.onClick) {
                      event.preventDefault()
                      item.onClick()
                    }
                  }}
                >
                  {item.label}
                </a>
              ))}
            </nav>
            {walletSlot ?? (
              <Button className="mt-2 w-full" onClick={onConnectWallet} size="sm">
                <Wallet aria-hidden className="size-3.5" />
                {walletLabel}
              </Button>
            )}
          </div>
        </details>
      </div>
    </header>
  )
}

export function BrandMark() {
  return (
    <>
      <span
        aria-hidden
        className="grid size-9 place-items-center rounded-xl bg-lime-300 text-base font-black tracking-[-0.15em] text-slate-950 shadow-[0_0_28px_rgba(190,242,100,0.22)]"
      >
        B
      </span>
      <span className="text-base font-bold tracking-[-0.045em] text-white">
        backed<span className="text-lime-300">.</span>
      </span>
    </>
  )
}

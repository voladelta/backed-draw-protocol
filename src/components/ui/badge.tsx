import type { HTMLAttributes } from "react"

import { cn } from "@/lib/utils"

type BadgeVariant = "default" | "success" | "warning" | "muted" | "currency"

export interface BadgeProps extends HTMLAttributes<HTMLSpanElement> {
  variant?: BadgeVariant
  dot?: boolean
}

const variantClasses: Record<BadgeVariant, string> = {
  default: "border-white/12 bg-white/[0.07] text-slate-200",
  success: "border-lime-300/20 bg-lime-300/[0.1] text-lime-200",
  warning: "border-amber-300/20 bg-amber-300/[0.1] text-amber-100",
  muted: "border-white/8 bg-slate-800/70 text-slate-400",
  currency: "border-cyan-300/20 bg-cyan-300/[0.1] text-cyan-100",
}

export function Badge({
  className,
  variant = "default",
  dot = false,
  children,
  ...props
}: BadgeProps) {
  return (
    <span
      className={cn(
        "inline-flex w-fit items-center gap-1.5 rounded-full border px-2.5 py-1 text-[10px] font-bold uppercase tracking-[0.11em]",
        variantClasses[variant],
        className,
      )}
      {...props}
    >
      {dot ? <span aria-hidden className="size-1.5 rounded-full bg-current" /> : null}
      {children}
    </span>
  )
}

export type { BadgeVariant }

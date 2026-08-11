import type { ButtonHTMLAttributes, ReactNode } from "react"

import { cn } from "@/lib/utils"

type ButtonVariant = "primary" | "secondary" | "ghost" | "outline" | "danger"
type ButtonSize = "sm" | "md" | "lg" | "icon"

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant
  size?: ButtonSize
  loading?: boolean
  children?: ReactNode
}

const variantClasses: Record<ButtonVariant, string> = {
  primary:
    "border border-lime-300/80 bg-lime-300 text-slate-950 shadow-[0_0_0_1px_rgba(217,249,157,0.25),0_12px_34px_rgba(163,230,53,0.16)] hover:bg-lime-200",
  secondary:
    "border border-white/10 bg-white/[0.07] text-slate-100 hover:border-white/20 hover:bg-white/[0.12]",
  ghost: "text-slate-300 hover:bg-white/[0.06] hover:text-white",
  outline:
    "border border-white/15 bg-transparent text-slate-100 hover:border-lime-300/50 hover:bg-lime-300/[0.07]",
  danger: "border border-rose-400/30 bg-rose-400/10 text-rose-100 hover:bg-rose-400/20",
}

const sizeClasses: Record<ButtonSize, string> = {
  sm: "h-9 gap-2 px-3 text-xs",
  md: "h-10 gap-2 px-4 text-sm",
  lg: "h-12 gap-2.5 px-5 text-sm",
  icon: "size-10",
}

/** A compact, accessible action primitive for the dark protocol interface. */
export function Button({
  className,
  variant = "primary",
  size = "md",
  loading = false,
  disabled,
  children,
  type = "button",
  ...props
}: ButtonProps) {
  return (
    <button
      className={cn(
        "inline-flex shrink-0 items-center justify-center rounded-xl font-semibold tracking-[-0.01em] transition-[transform,background-color,border-color,color,box-shadow] duration-150 ease-out active:scale-[0.97] disabled:pointer-events-none disabled:cursor-not-allowed disabled:opacity-45 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-lime-300/80 focus-visible:ring-offset-2 focus-visible:ring-offset-slate-950",
        variantClasses[variant],
        sizeClasses[size],
        className,
      )}
      disabled={disabled || loading}
      type={type}
      {...props}
    >
      {loading ? (
        <span
          aria-label="Loading"
          className="size-3.5 animate-spin rounded-full border-2 border-current border-t-transparent"
          role="status"
        />
      ) : null}
      {children}
    </button>
  )
}

export type { ButtonSize, ButtonVariant }

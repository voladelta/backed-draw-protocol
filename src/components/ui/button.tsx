import * as stylex from "@stylexjs/stylex"
import type { StyleXStyles } from "@stylexjs/stylex"
import type { ButtonHTMLAttributes, ReactNode } from "react"

import { breakpoints, colors } from "../../styles/tokens.stylex"

type ButtonVariant = "primary" | "secondary" | "ghost" | "outline" | "danger"
type ButtonSize = "sm" | "md" | "lg" | "icon"

export interface ButtonProps extends Omit<
  ButtonHTMLAttributes<HTMLButtonElement>,
  "className" | "style"
> {
  variant?: ButtonVariant
  size?: ButtonSize
  loading?: boolean
  static?: boolean
  children?: ReactNode
  style?: StyleXStyles
}

const spin = stylex.keyframes({ to: { transform: "rotate(360deg)" } })

const styles = stylex.create({
  base: {
    display: "inline-flex",
    flexShrink: 0,
    alignItems: "center",
    justifyContent: "center",
    borderRadius: 12,
    fontWeight: 600,
    letterSpacing: "-0.01em",
    transitionProperty: "transform, background-color, border-color, color, box-shadow",
    transitionDuration: {
      default: "150ms",
      [breakpoints.reducedMotion]: "0.01ms",
    },
    transitionTimingFunction: "ease-out",
    pointerEvents: { default: "auto", ":disabled": "none" },
    cursor: { default: "pointer", ":disabled": "not-allowed" },
    opacity: { default: 1, ":disabled": 0.45 },
    outline: { default: "none", ":focus-visible": `2px solid ${colors.lime300}` },
    outlineOffset: { default: 0, ":focus-visible": 2 },
  },
  motion: {
    transform: { default: "scale(1)", ":active": "scale(0.96)" },
  },
  primary: {
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: "rgba(190, 242, 100, 0.8)",
    backgroundColor: { default: colors.lime300, ":hover": colors.lime200 },
    color: colors.slate950,
    boxShadow: "0 0 0 1px rgba(217,249,157,0.25), 0 12px 34px rgba(163,230,53,0.16)",
  },
  secondary: {
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: { default: "rgba(255,255,255,0.1)", ":hover": "rgba(255,255,255,0.2)" },
    backgroundColor: { default: "rgba(255,255,255,0.07)", ":hover": "rgba(255,255,255,0.12)" },
    color: colors.slate100,
  },
  ghost: {
    borderWidth: 0,
    backgroundColor: { default: "transparent", ":hover": "rgba(255,255,255,0.06)" },
    color: { default: colors.slate300, ":hover": colors.white },
  },
  outline: {
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: { default: "rgba(255,255,255,0.15)", ":hover": "rgba(190,242,100,0.5)" },
    backgroundColor: { default: "transparent", ":hover": "rgba(190,242,100,0.07)" },
    color: colors.slate100,
  },
  danger: {
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: "rgba(251,113,133,0.3)",
    backgroundColor: { default: "rgba(251,113,133,0.1)", ":hover": "rgba(251,113,133,0.2)" },
    color: colors.rose100,
  },
  sm: { height: 36, columnGap: 8, paddingInline: 12, fontSize: 12 },
  md: { height: 40, columnGap: 8, paddingInline: 16, fontSize: 14 },
  lg: { height: 48, columnGap: 10, paddingInline: 20, fontSize: 14 },
  icon: { width: 40, height: 40 },
  spinner: {
    width: 14,
    height: 14,
    borderRadius: "50%",
    borderWidth: 2,
    borderStyle: "solid",
    borderColor: "currentColor",
    borderTopColor: "transparent",
    animationName: spin,
    animationDuration: "1s",
    animationTimingFunction: "linear",
    animationIterationCount: "infinite",
  },
})

/** A compact, accessible action primitive for the dark protocol interface. */
export function Button({
  style,
  variant = "primary",
  size = "md",
  loading = false,
  static: staticMotion = false,
  disabled,
  children,
  type = "button",
  ...props
}: ButtonProps) {
  return (
    <button
      {...props}
      {...stylex.props(
        styles.base,
        !staticMotion && styles.motion,
        variant === "primary" && styles.primary,
        variant === "secondary" && styles.secondary,
        variant === "ghost" && styles.ghost,
        variant === "outline" && styles.outline,
        variant === "danger" && styles.danger,
        size === "sm" && styles.sm,
        size === "md" && styles.md,
        size === "lg" && styles.lg,
        size === "icon" && styles.icon,
        style,
      )}
      disabled={disabled || loading}
      aria-busy={loading || undefined}
      type={type}
    >
      {loading ? <span aria-hidden="true" {...stylex.props(styles.spinner)} /> : null}
      {children}
    </button>
  )
}

export type { ButtonSize, ButtonVariant }

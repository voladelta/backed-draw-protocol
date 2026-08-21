import * as stylex from "@stylexjs/stylex"
import type { StyleXStyles } from "@stylexjs/stylex"
import type { HTMLAttributes } from "react"

import { colors } from "../../styles/tokens.stylex"

type BadgeVariant = "default" | "success" | "warning" | "muted" | "currency"

export interface BadgeProps extends Omit<HTMLAttributes<HTMLSpanElement>, "className" | "style"> {
  variant?: BadgeVariant
  dot?: boolean
  style?: StyleXStyles
}

const styles = stylex.create({
  base: {
    display: "inline-flex",
    width: "fit-content",
    alignItems: "center",
    columnGap: 6,
    borderRadius: 9999,
    borderWidth: 1,
    borderStyle: "solid",
    paddingInline: 10,
    paddingBlock: 4,
    fontSize: 10,
    fontWeight: 700,
    textTransform: "uppercase",
    letterSpacing: "0.11em",
  },
  default: {
    borderColor: "rgba(255,255,255,0.12)",
    backgroundColor: "rgba(255,255,255,0.07)",
    color: colors.slate200,
  },
  success: {
    borderColor: "rgba(190,242,100,0.2)",
    backgroundColor: "rgba(190,242,100,0.1)",
    color: colors.lime200,
  },
  warning: {
    borderColor: "rgba(253,230,138,0.2)",
    backgroundColor: "rgba(253,230,138,0.1)",
    color: colors.amber100,
  },
  muted: {
    borderColor: "rgba(255,255,255,0.08)",
    backgroundColor: "rgba(30,41,59,0.7)",
    color: colors.slate400,
  },
  currency: {
    borderColor: "rgba(103,232,249,0.2)",
    backgroundColor: "rgba(103,232,249,0.1)",
    color: colors.cyan100,
  },
  dot: { width: 6, height: 6, borderRadius: "50%", backgroundColor: "currentColor" },
})

export function Badge({ style, variant = "default", dot = false, children, ...props }: BadgeProps) {
  return (
    <span
      {...props}
      {...stylex.props(
        styles.base,
        variant === "default" && styles.default,
        variant === "success" && styles.success,
        variant === "warning" && styles.warning,
        variant === "muted" && styles.muted,
        variant === "currency" && styles.currency,
        style,
      )}
    >
      {dot ? <span aria-hidden {...stylex.props(styles.dot)} /> : null}
      {children}
    </span>
  )
}

export type { BadgeVariant }

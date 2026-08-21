import * as stylex from "@stylexjs/stylex"
import type { StyleXStyles } from "@stylexjs/stylex"
import type { HTMLAttributes } from "react"

import { colors } from "../../styles/tokens.stylex"

type StyledDivProps = Omit<HTMLAttributes<HTMLDivElement>, "className" | "style"> & {
  style?: StyleXStyles
}

type StyledHeadingProps = Omit<HTMLAttributes<HTMLHeadingElement>, "className" | "style"> & {
  style?: StyleXStyles
}

type StyledParagraphProps = Omit<HTMLAttributes<HTMLParagraphElement>, "className" | "style"> & {
  style?: StyleXStyles
}

const styles = stylex.create({
  card: {
    borderRadius: 16,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: "rgba(255,255,255,0.09)",
    backgroundColor: "rgba(15,23,42,0.6)",
    boxShadow: "0 16px 50px rgba(0,0,0,0.18)",
    backdropFilter: "blur(24px)",
  },
  header: { display: "flex", flexDirection: "column", rowGap: 6, padding: 20 },
  title: { fontWeight: 600, letterSpacing: "-0.025em", color: colors.white },
  description: { fontSize: 14, lineHeight: 1.5, color: colors.slate400 },
  content: { padding: 20, paddingTop: 0 },
  footer: { display: "flex", alignItems: "center", padding: 20, paddingTop: 0 },
})

export function Card({ style, ...props }: StyledDivProps) {
  return <div {...props} {...stylex.props(styles.card, style)} />
}

export function CardHeader({ style, ...props }: StyledDivProps) {
  return <div {...props} {...stylex.props(styles.header, style)} />
}

export function CardTitle({ style, ...props }: StyledHeadingProps) {
  return <h3 {...props} {...stylex.props(styles.title, style)} />
}

export function CardDescription({ style, ...props }: StyledParagraphProps) {
  return <p {...props} {...stylex.props(styles.description, style)} />
}

export function CardContent({ style, ...props }: StyledDivProps) {
  return <div {...props} {...stylex.props(styles.content, style)} />
}

export function CardFooter({ style, ...props }: StyledDivProps) {
  return <div {...props} {...stylex.props(styles.footer, style)} />
}

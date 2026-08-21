import { Menu, Wallet } from "lucide-react"
import * as stylex from "@stylexjs/stylex"
import type { StyleXStyles } from "@stylexjs/stylex"
import type { ReactNode } from "react"

import { Button } from "@/components/ui/button"
import { breakpoints, colors } from "../../styles/tokens.stylex"

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
  style?: StyleXStyles
}

const defaultNavigation: NavigationItem[] = [
  { label: "Explore", href: "/", active: true },
  { label: "My positions", href: "/positions" },
  { label: "Rewards", href: "/rewards" },
  { label: "How it works", href: "/how-it-works" },
]

const styles = stylex.create({
  header: {
    position: "sticky",
    top: 0,
    zIndex: 40,
    borderBottomWidth: 1,
    borderBottomStyle: "solid",
    borderBottomColor: "oklch(0.88 0.03 140 / 0.13)",
    backgroundColor: "oklch(0.14 0.025 145 / 0.86)",
    backdropFilter: "blur(20px) saturate(130%)",
  },
  inner: {
    display: "flex",
    height: 72,
    minHeight: 72,
    maxWidth: 1280,
    alignItems: "center",
    justifyContent: "space-between",
    columnGap: 16,
    marginInline: "auto",
    paddingInline: {
      default: 16,
      [breakpoints.sm]: 24,
      [breakpoints.lg]: 32,
    },
  },
  brandLink: {
    display: "flex",
    flexShrink: 0,
    alignItems: "center",
    columnGap: 10,
    color: "inherit",
    textDecoration: "none",
  },
  desktopNav: {
    display: { default: "none", [breakpoints.md]: "flex" },
    alignItems: "center",
    columnGap: 4,
  },
  navLink: {
    minHeight: 40,
    display: "inline-flex",
    alignItems: "center",
    borderRadius: 8,
    paddingBlock: 8,
    paddingInline: 12,
    fontSize: 14,
    fontWeight: 500,
    transitionProperty: "background-color, color",
    transitionDuration: "150ms",
    transitionTimingFunction: "ease-out",
  },
  navLinkIdle: {
    backgroundColor: { default: "transparent", ":hover": "rgba(255,255,255,0.05)" },
    color: { default: colors.slate400, ":hover": colors.slate100 },
  },
  navLinkActive: { backgroundColor: "rgba(255,255,255,0.08)", color: colors.white },
  desktopWallet: {
    display: { default: "none", [breakpoints.sm]: "flex" },
    alignItems: "center",
    columnGap: 12,
  },
  mobileNav: {
    position: "relative",
    display: { default: "block", [breakpoints.md]: "none" },
  },
  mobileTrigger: {
    display: "flex",
    width: 40,
    height: 40,
    cursor: "pointer",
    listStyle: "none",
    alignItems: "center",
    justifyContent: "center",
    borderRadius: 12,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: "rgba(255,255,255,0.1)",
    backgroundColor: { default: "rgba(255,255,255,0.05)", ":hover": "rgba(255,255,255,0.1)" },
    color: colors.slate200,
    transitionProperty: "background-color, border-color, color",
    "::-webkit-details-marker": { display: "none" },
  },
  mobileMenu: {
    position: "absolute",
    right: 0,
    top: "calc(100% + 12px)",
    width: 256,
    borderRadius: 16,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: "oklch(0.88 0.03 140 / 0.13)",
    padding: 8,
    backgroundColor: "oklch(0.19 0.03 145 / 0.94)",
    boxShadow: "0 25px 50px -12px rgba(0,0,0,0.5)",
    backdropFilter: "blur(24px)",
  },
  mobileMenuNav: { display: "flex", flexDirection: "column" },
  mobileLink: {
    borderRadius: 12,
    paddingBlock: 10,
    paddingInline: 12,
    fontSize: 14,
    fontWeight: 500,
  },
  mobileLinkIdle: {
    backgroundColor: { default: "transparent", ":hover": "rgba(255,255,255,0.06)" },
    color: { default: colors.slate400, ":hover": colors.white },
  },
  mobileLinkActive: { backgroundColor: "rgba(255,255,255,0.09)", color: colors.white },
  mobileWalletButton: { width: "100%", marginTop: 8 },
  icon14: { width: 14, height: 14 },
  icon20: { width: 20, height: 20 },
  visuallyHidden: {
    position: "absolute",
    width: 1,
    height: 1,
    padding: 0,
    margin: -1,
    overflow: "hidden",
    clip: "rect(0, 0, 0, 0)",
    whiteSpace: "nowrap",
    borderWidth: 0,
  },
  brandIcon: {
    display: "grid",
    width: 36,
    height: 36,
    placeItems: "center",
    borderRadius: 12,
    backgroundColor: colors.lime300,
    color: colors.slate950,
    fontSize: 16,
    fontWeight: 900,
    letterSpacing: "-0.15em",
    boxShadow: "0 0 28px rgba(190,242,100,0.22)",
  },
  brandName: { color: colors.white, fontSize: 16, fontWeight: 700, letterSpacing: "-0.045em" },
  brandDot: { color: colors.lime300 },
})

export function Header({
  navigation = defaultNavigation,
  walletLabel = "Connect wallet",
  onConnectWallet,
  brand,
  walletSlot,
  style,
}: HeaderProps) {
  return (
    <header {...stylex.props(styles.header, style)}>
      <div {...stylex.props(styles.inner)}>
        <a aria-label="Draw protocol home" {...stylex.props(styles.brandLink)} href="/">
          {brand ?? <BrandMark />}
        </a>

        <nav aria-label="Primary navigation" {...stylex.props(styles.desktopNav)}>
          {navigation.map((item) => (
            <a
              {...stylex.props(
                styles.navLink,
                item.active ? styles.navLinkActive : styles.navLinkIdle,
              )}
              href={item.href}
              key={item.href}
              aria-current={item.active ? "page" : undefined}
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

        <div {...stylex.props(styles.desktopWallet)}>
          {walletSlot ?? (
            <Button onClick={onConnectWallet} size="sm">
              <Wallet aria-hidden {...stylex.props(styles.icon14)} />
              {walletLabel}
            </Button>
          )}
        </div>

        <details {...stylex.props(styles.mobileNav)}>
          <summary {...stylex.props(styles.mobileTrigger)}>
            <Menu aria-hidden {...stylex.props(styles.icon20)} />
            <span {...stylex.props(styles.visuallyHidden)}>Open navigation</span>
          </summary>
          <div {...stylex.props(styles.mobileMenu)}>
            <nav aria-label="Mobile navigation" {...stylex.props(styles.mobileMenuNav)}>
              {navigation.map((item) => (
                <a
                  {...stylex.props(
                    styles.mobileLink,
                    item.active ? styles.mobileLinkActive : styles.mobileLinkIdle,
                  )}
                  href={item.href}
                  key={item.href}
                  aria-current={item.active ? "page" : undefined}
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
              <Button style={styles.mobileWalletButton} onClick={onConnectWallet} size="sm">
                <Wallet aria-hidden {...stylex.props(styles.icon14)} />
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
      <span aria-hidden {...stylex.props(styles.brandIcon)}>
        B
      </span>
      <span {...stylex.props(styles.brandName)}>
        backed<span {...stylex.props(styles.brandDot)}>.</span>
      </span>
    </>
  )
}

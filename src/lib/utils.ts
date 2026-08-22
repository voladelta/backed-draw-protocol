export function compactAddress(address?: string) {
  return address ? `${address.slice(0, 6)}…${address.slice(-4)}` : "Connect"
}

export function formatValue(value: number, asset: "ETH" | "USDG") {
  return asset === "ETH"
    ? `${value.toFixed(value < 1 ? 3 : 2)} ETH`
    : `$${value.toLocaleString("en-US", { maximumFractionDigits: 0 })}`
}

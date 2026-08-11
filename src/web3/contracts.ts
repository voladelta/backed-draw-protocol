import { isAddress, zeroAddress, type Address } from "viem"
import type { SettlementAsset } from "@/types/protocol"

export const drawRouterAbi = [
  {
    type: "function",
    name: "swapAndPull",
    stateMutability: "payable",
    inputs: [
      { name: "marketAddress", type: "address" },
      { name: "inputAsset", type: "address" },
      { name: "maxAmountIn", type: "uint256" },
      {
        name: "order",
        type: "tuple",
        components: [
          { name: "receiver", type: "address" },
          { name: "drawCount", type: "uint32" },
          { name: "maxUnitPrice", type: "uint128" },
          { name: "maxTotalPrice", type: "uint128" },
          { name: "deadline", type: "uint48" },
          { name: "referralCode", type: "bytes32" },
        ],
      },
      { name: "routeData", type: "bytes" },
    ],
    outputs: [
      { name: "orderIndex", type: "uint256" },
      { name: "amountIn", type: "uint256" },
    ],
  },
] as const

const addressOrUndefined = (value?: string): Address | undefined =>
  value && isAddress(value) ? value : undefined

export const drawRouterAddress = addressOrUndefined(import.meta.env.VITE_DRAW_ROUTER_ADDRESS)
export const usdgAddress = addressOrUndefined(import.meta.env.VITE_USDG_ADDRESS)

const marketAddresses: Record<string, Address | undefined> = {
  "omnipool-eth": addressOrUndefined(import.meta.env.VITE_MARKET_OMNIPOOL_ETH_ADDRESS),
  "vaulted-tcg": addressOrUndefined(import.meta.env.VITE_MARKET_VAULTED_TCG_ADDRESS),
  "pixel-legends": addressOrUndefined(import.meta.env.VITE_MARKET_PIXEL_LEGENDS_ADDRESS),
}

export const marketAddressFor = (marketId: string) => marketAddresses[marketId]

type PullRouteConfig = {
  marketAddress: Address
  inputAsset: Address
  routeData: `0x${string}`
  nativeInput: boolean
}

const hexDataOrUndefined = (value?: string): `0x${string}` | undefined =>
  value && /^0x(?:[0-9a-fA-F]{2})*$/.test(value) ? (value as `0x${string}`) : undefined

/**
 * A transaction is only enabled when the UI has enough deployment data to tell
 * the router exactly how to fund the selected market. Missing configuration is
 * intentionally treated as preview mode instead of submitting a best guess.
 */
export function getPullRouteConfig(
  marketId: string,
  paymentAsset: SettlementAsset,
  settlementAsset: SettlementAsset,
): PullRouteConfig | undefined {
  const marketAddress = marketAddressFor(marketId)
  if (!drawRouterAddress || !marketAddress) return undefined

  if (paymentAsset === "ETH") {
    if (settlementAsset === "ETH") {
      return { marketAddress, inputAsset: zeroAddress, routeData: "0x", nativeInput: true }
    }
    const routeData = hexDataOrUndefined(import.meta.env.VITE_ETH_TO_USDG_ROUTE_DATA)
    return routeData
      ? { marketAddress, inputAsset: zeroAddress, routeData, nativeInput: true }
      : undefined
  }

  // `swapAndPull` uses transferFrom for ERC-20 inputs. Until the client owns an
  // explicit allowance/approval flow, keeping USDG in preview mode is safer than
  // sending a pull transaction that is guaranteed to revert.
  return undefined
}

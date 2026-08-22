# Backed Draw Protocol

Interactive frontend prototype for the ETH-and-USDG backed collectible draw protocol described in [SPECS.md](./SPECS.md).

Live demo: [backed-draw-protocol.pages.dev](https://backed-draw-protocol.pages.dev/)

The repository also contains the Foundry implementation of the protocol core. See [docs/CONTRACTS.md](./docs/CONTRACTS.md) for boundaries, flows, liabilities, and deployment order.

## Run locally

```bash
bun install
bun run dev
```

Production checks:

```bash
bun run build
bun run lint
bun run fmt:check
bun run test
bun run contracts:build
bun run contracts:test
```

## Web3 configuration

Copy `.env.example` to `.env.local` and supply the deployed `SwapAndPullRouter`, the selected market addresses, and the canonical USDG address. A wallet transaction is only enabled when the router, selected market, and payment route are all configured; otherwise the UI intentionally remains an interactive preview.

The Robinhood Chain RPC, explorer, chain ID, and WalletConnect project can all be replaced through environment variables. ETH and USDG are kept as distinct settlement assets in the UI and protocol model; native ETH routes can be submitted when their router and market configuration is complete. USDG remains in preview mode until the client implements its explicit ERC-20 approval flow. USDG amounts are encoded with six decimals, while ETH values use 18 decimals.

## Flagship economic target

The puller-first flagship target is a 2.5% markup, a 90% cash or `$DRAW` swap-input ratio, and a 99% keep ratio. These are immutable per-market settings (`markupBps = 250`, `cashPayoutBps = 9_000`, `keepPayoutBps = 9_900`) validated by the factory at market creation.

The token-independent cash-floor RTP is `90% / 102.5% = 87.8%` before gas, swaps, and payment routing. Collectible option value, `$DRAW` market value, and entertainment value are separate; none is a guaranteed addition to the cash floor. [SPECS.md](./SPECS.md) contains the legacy 10%/85% stress profile and lower-markup scenarios for sensitivity analysis. Those scenarios are not return, demand, or profitability promises.

## Architecture

- React 19 + Vite 8 + TypeScript
- TanStack Router with intent preloading and route-owned pages
- StyleX-compiled component primitives with typed style props and shared design tokens; see [the StyleX authoring guide](./src/stylex-authoring.md)
- wagmi + viem for wallet and contract interaction
- Zustand for app workflow state
- Pointer-driven React state and CSS transforms for the interactive collectible
- Pure economic functions with Vitest coverage
- Solidity 0.8.28 + OpenZeppelin Contracts 5.7.0 + Foundry

Install pinned Solidity dependencies in a fresh clone:

```bash
forge install OpenZeppelin/openzeppelin-contracts@v5.7.0 foundry-rs/forge-std@v1.12.0 --no-git --shallow
```

Market/indexer data currently comes from the typed mock adapter in `src/data/markets.ts`. It is preview data, not observed protocol performance. Replace that adapter with indexed protocol data without changing page contracts.

Before a paid flagship launch, the pre-pull confirmation must show the immutable ratios, cash-floor RTP, outcome-specific uncertainty, and excluded costs. The production indexer must support settlement mix, repeat/cohort demand, pull concentration, realized token-independent RTP, and public model-versus-reality tracking. Record the review window and scale/no-scale thresholds before launch; mock data and token-price movement do not satisfy this evidence gate.

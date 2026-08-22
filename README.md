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

Market/indexer data currently comes from the typed mock adapter in `src/data/markets.ts`. Replace that adapter with indexed protocol data without changing page contracts.

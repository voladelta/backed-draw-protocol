# Backed Draw Protocol

Backed Draw Protocol is a collectible draw system for ETH and USDG markets. Backers deposit a collectible and backing. Pullers pay a pool-derived price for a verifiably random position.

Each market uses one settlement asset. ETH and USDG never share a probability tree or liability ledger.

This repository contains:

- a React prototype for the user experience
- the Solidity contracts for the protocol core
- tests for pricing, settlement, solvency and liveness
- the [protocol specification](./SPECS.md)
- the [contract architecture guide](./docs/CONTRACTS.md)

You can also view the [Backed Draw Protocol demo](https://backed-draw-protocol.pages.dev/).

## Run the project locally

Install the dependencies and start the development server:

```bash
bun install
bun run dev
```

Run the production checks:

```bash
bun run build
bun run lint
bun run fmt:check
bun run test
bun run contracts:build
bun run contracts:test
```

Install the pinned Solidity dependencies in a fresh clone:

```bash
forge install OpenZeppelin/openzeppelin-contracts@v5.7.0 foundry-rs/forge-std@v1.12.0 --no-git --shallow
```

## Configure web3 connections

Copy `.env.example` to `.env.local`. Add the deployed router, market addresses and canonical USDG address.

The interface enables wallet transactions only when it can verify the full route. Otherwise, it stays in preview mode.

You can set the RPC URL, explorer, chain ID and WalletConnect project through environment variables.

The client uses 6 decimals for USDG and 18 decimals for ETH. Native ETH routes work when their router and market configuration is complete. USDG stays in preview mode until the client supports ERC-20 approval.

## Understand the flagship economics

The flagship market uses:

- a 2.5% markup
- a 90% cash or `$DRAW` swap-input ratio
- a 99% keep ratio

The factory stores these settings as `250 / 9,000 / 9,900` basis points. They cannot change after market creation.

The cash-floor return to player is `90% / 102.5% = 87.8%`. This figure excludes gas, swaps and payment routing.

The cash floor does not include collectible value, `$DRAW` value or entertainment value. These values are uncertain. The [economic model scenarios](./SPECS.md#economic-model-scenarios) explain the assumptions and comparison cases.

## Understand the architecture

The project uses:

- React 19, Vite 8 and TypeScript
- TanStack Router for route-owned pages and intent preloading
- StyleX for typed component styles and shared design tokens
- wagmi and viem for wallets and contract calls
- Zustand for interface workflow state
- Vitest for the pure economic model and frontend logic
- Solidity 0.8.28, OpenZeppelin Contracts 5.7.0 and Foundry

Use the [StyleX authoring guide](./src/stylex-authoring.md) when you change interface styles.

## Treat current market data as preview data

The interface reads typed mock data from `src/data/markets.ts`. This data does not show live protocol performance.

Replace the mock adapter with indexed protocol data before a paid launch. Keep the existing page contracts when you replace it.

Before launch, the interface must show:

- the market's fixed economic ratios
- the cash-floor return to player
- the uncertainty for each settlement choice
- gas and routing costs that the return figure excludes

The production indexer must measure:

- settlement choices
- repeat use by cohort
- pull concentration
- realised token-independent return to player
- differences between the model and observed results

Set the review period and launch thresholds before paid use. Mock data and token-price movement do not meet this evidence requirement.

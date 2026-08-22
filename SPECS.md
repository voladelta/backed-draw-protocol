# Backed Draw Protocol specification

Backed Draw Protocol supports separate ETH and USDG markets. It does not mix currencies within one market. It also keeps NFT custody and delayed settlement outside Uniswap hooks.

Backers deposit a collectible and backing. Their position earns from each draw while it stays active. Pullers pay a pool-derived price for a verifiably random position.

Each market settles in ETH or USDG. Users may pay or receive through either asset when a protected Uniswap route is available.

---

# 1. Currency decision

## Use one settlement asset for each market

One protocol can support many markets. Each market must use one settlement asset.

Examples:

```text
NFT Omnipool — ETH
NFT Omnipool — USDG
TCG Market — USDG
High-End Collectibles — ETH
Partner Collection Market — ETH
Partner Collection Market — USDG
```

Robinhood Chain uses ETH as its native gas token and has canonical WETH and USDG contracts. It also supports account abstraction, gas sponsorship, batching, and embedded wallets. This makes both settlement choices practical.

## Keep 4 currency concepts separate

| Concept          | Meaning                                                                        |
| ---------------- | ------------------------------------------------------------------------------ |
| settlement asset | the asset used for backing, odds, pricing, earnings and settlement liabilities |
| payment asset    | the asset the puller provides to the router                                    |
| payout asset     | the asset the user chooses after settlement                                    |
| display currency | an interface-only value shown in ETH, USD or another denomination              |

For example:

```text
Market settlement asset: ETH
User pays: USDG
Router: swaps USDG → ETH through Uniswap
Market receives: ETH
Random draw and settlement: entirely ETH-denominated
```

Or:

```text
Market settlement asset: USDG
User pays: ETH
Router: swaps ETH → USDG
Market receives: USDG
Random draw and settlement: entirely USDG-denominated
```

## Keep ETH and USDG in separate markets

A mixed ETH and USDG market would need:

- converting every backing into a common oracle value
- handling ETH price movement between payment and reveal
- deciding which currency funds cash settlement
- rebalancing reserves
- protecting against stale oracle updates
- handling cross-currency insolvency
- deciding who bears swap slippage

This would add risk without giving users another payment option. The router already gives users that choice at the market boundary.

## Choose a default settlement asset

| Asset category                              | Preferred settlement        |
| ------------------------------------------- | --------------------------- |
| Crypto-native NFTs                          | ETH                         |
| PFPs and art                                | ETH                         |
| Game assets                                 | ETH or USDG                 |
| Vaulted cards and physical collectibles     | USDG                        |
| Luxury goods and other dollar-priced assets | USDG                        |
| Partner-created markets                     | Creator chooses ETH or USDG |

Use ETH for the default flagship market. Use USDG as a full alternative, particularly for cards and physical collectibles.

---

# 2. Product definition

Backers deposit a collectible with ETH or USDG backing. The backing sets the position's draw weight. Each active position earns an equal share of base draw proceeds.

Pullers pay one pool-derived price. Verifiable randomness selects a position. After reveal, the puller can keep the collectible, take cash, take `$DRAW` or relist.

The protocol also uses staged deposits, a 24-hour decision period, backer rewards, referrals and one Crown for each market.

The flagship target uses a 2.5% markup, a 90% cash or `$DRAW` input ratio, and a 99% keep ratio. This is a launch assumption to test. It is not a promise of demand or profit.

---

# 3. The economic engine

## 3.1 Draw probability

For every active position \(i\):

\[
w_i = \frac{1}{b_i}
\]

\[
S = \sum_j w_j
\]

\[
p_i = \frac{w_i}{S}
\]

In these formulas:

- \(b_i\) is the position's normalised backing
- \(w_i\) is its draw weight
- \(p_i\) is its selection probability

Lower backing means higher selection probability. Higher backing means the position remains active longer on average and can earn from more draws.

---

## 3.2 Expected value

\[
EV = \sum_i p_i b_i
\]

Because:

\[
p_i b_i
=

\frac{1/b_i}{S} b_i
=

\frac{1}{S}
\]

every active position contributes the same amount to the expected value.

Therefore:

\[
EV = \frac{N}{S}
\]

and:

\[
\frac{EV}{N} = \frac{1}{S}
\]

The economic design uses this identity throughout.

---

## 3.3 Pull price

The flagship target uses \(m=2.5\%\):

\[
PullPrice = EV \times (1+m)
\]

Split it into:

```text
Base draw proceeds = EV
Markup              = EV × 2.5%
Total pull price    = EV + markup
```

The implementation accounts for the base \(EV\) and markup separately.

### Puller return labels

For a cash payout ratio \(c\), the token-independent cash-floor RTP is:

\[
CashFloorRTP = \frac{c}{1+m}
\]

This divides the cash entitlement by the pull price. It excludes gas, swap and payment-routing costs.

The interface and analytics must keep these values separate:

- guaranteed cash floor: the market's fixed cash entitlement before gas and routing costs
- collectible option value: the puller's own value for keeping the NFT instead of taking cash
- token-dependent return: the eventual value of `$DRAW`, which depends on execution and token price
- entertainment value: a personal benefit that must not appear as a financial return percentage

### Economic model scenarios

Use these scenarios to test sensitivity and compare the model with observed results. They are not forecasts or promises.

| Scenario                | Markup | Cash / `$DRAW` input | Keep | Cash-floor RTP |
| ----------------------- | -----: | -------------------: | ---: | -------------: |
| Legacy stress profile   |    10% |                  85% |  99% |          77.3% |
| Lower-markup comparison |     4% |                  90% |  99% |          86.5% |
| Flagship launch target  |   2.5% |                  90% |  99% |          87.8% |
| Puller-first experiment |   1.5% |                  90% |  99% |          88.7% |

The table shows only the cash floor. It excludes token-price changes, collectible value, entertainment value, gas and swaps.

Comparisons may inform these scenarios. They do not prove that one markup or payout ratio causes demand or retention.

---

# 4. Full pull-payment allocation

## 4.1 Base draw proceeds

Every position active for a draw receives an equal share of the EV component.

For an active position:

\[
BaseEarning_i = \frac{EV}{N} = \frac{1}{S}
\]

This split follows from the inverse-backing formula. Every position contributes the same amount to EV.

The base proceeds account for these facts:

- the backer supplies an NFT and backing
- selection removes one of those assets from the position
- base proceeds pay for the asset at risk over the position's expected life
- the markup provides the yield premium

The active-position accumulator becomes:

```solidity
accBasePerPosition += baseProceeds / activePositionCount;
```

The selected position receives its share from the draw that selected it before being removed.

---

## 4.2 Markup allocation

Recommended flagship-market policy:

```text
10% of markup
    → buys $DRAW for active positions

Remaining 90% of markup:
     5% → Crown pot
     1% → protocol
    94% → active positions, equally
```

At the flagship 2.5% markup, effective allocation is approximately:

| Recipient                       | Effective share of EV |
| ------------------------------- | --------------------: |
| Active-position base proceeds   |              100.000% |
| Active-position cash markup     |                2.115% |
| Active-position `$DRAW` rewards |                0.250% |
| Crown                           |                0.113% |
| Protocol from markup            |                0.023% |

The reward-token purchase is credited equally to positions active for that draw.

---

## 4.3 Settlement revenue

After selection, backing is divided according to the puller’s exit.

### Keep the collectible

```text
Buyer:
    receives NFT

Position owner:
    receives 99% of backing
    receives all accrued base proceeds
    receives all accrued cash markup
    receives all accrued $DRAW rewards

Settlement revenue:
    1% of backing
```

### Take cash

```text
Buyer:
    receives 90% of backing

Position owner:
    receives NFT back
    receives all accrued earnings

Settlement revenue:
    10% of backing
```

### Take `$DRAW`

```text
Buyer:
    receives $DRAW purchased with 90% of backing

Position owner:
    receives NFT back
    receives all accrued earnings

Settlement revenue:
    10% of backing
```

### Keep and relist

```text
Buyer:
    becomes new position owner
    chooses new backing
    supplies that backing

Previous owner:
    receives 99% of old backing
    receives all accrued earnings

Settlement revenue:
    1% of old backing
```

The flagship ratios are an immutable per-market policy. Other approved markets may use bounded scenario values and must disclose them before a pull.

---

## 4.4 Settlement-revenue waterfall

Recommended default:

| Recipient                                    | Share |
| -------------------------------------------- | ----: |
| Referrer or partner                          |   20% |
| Security and incident reserve                |   20% |
| `$DRAW` buyback and protocol-owned liquidity |   20% |
| Protocol treasury                            |   40% |

Where no referrer exists, the unallocated referral share goes to the security reserve.

This makes settlement revenue the primary protocol monetization source rather than extracting the buyer’s base expected-value payment.

---

## 4.5 Complete conservation of funds

Every unit entering the protocol has an explicit owner.

For a pull:

```text
EV:
    active position owners

Markup:
    active positions
    $DRAW rewards
    Crown
    protocol

Selected backing:
    depositor or puller
    referral
    insurance
    $DRAW liquidity
    protocol
```

There is no unexplained “market reserve” or admin-sweepable surplus.

The principal solvency invariant is:

\[
Assets \ge
BackingLiabilities

- PullRefundLiabilities
- PositionEarnings
- PendingSettlements
- CrownLiabilities
- ReferralLiabilities
- RewardLiabilities
  \]

---

# 5. Market architecture

## 5.1 Market identifier

Every market is keyed by:

```solidity
struct MarketKey {
    bytes32 collectionSetId;
    address settlementAsset;
    bytes32 economicPolicyId;
    bytes32 eligibilityPolicyId;
    bytes32 randomnessPolicyId;
    uint32 implementationVersion;
}
```

For native ETH markets, the vault converts ETH to canonical WETH. The router still provides native ETH deposits and withdrawals.

## 5.2 Immutable economic policy

Every market receives its economic parameters at creation:

```solidity
struct MarketConfig {
    // other identity, module, risk and timing fields
    uint16 markupBps;
    uint16 cashPayoutBps;
    uint16 keepPayoutBps;
}
```

`DrawMarket` owns the immutable `markupBps` policy, while its paired `SettlementEngine` owns the immutable `cashPayoutBps` and `keepPayoutBps` used for settlement. `MarketFactory.createMarket` rejects policies outside implementation-v1 safety bounds:

```text
markupBps <= 5,000
8,000 <= cashPayoutBps <= 9,500
9,500 <= keepPayoutBps <= 10,000
cashPayoutBps <= keepPayoutBps
```

These are implementation-v1 safety bounds, not universal economic truths. Governance can approve a new fixed implementation version with different bounds, but cannot silently change the ratios of an existing market. The flagship is created with `markupBps = 250`, `cashPayoutBps = 9_000`, and `keepPayoutBps = 9_900`.

## 5.3 Market classes

### Protocol flagship markets

Curated and governed through a timelock:

```text
NFT / ETH
NFT / USDG
TCG / USDG
Premium Collectibles / ETH
```

### Verified partner markets

Created by:

- collections
- game studios
- TCG vault providers
- luxury-goods issuers
- event organizers
- creator communities

Partners can receive a bounded revenue share.

### Permissionless markets

Anyone may create a market using approved templates.

Requirements:

- creator bond
- immutable settlement asset
- bounded fees
- isolated vault
- explicit risk label
- no appearance in curated discovery by default
- malicious collection contracts isolated from other markets

---

# 6. Collection and backing policies

Each collection has a market-specific configuration:

```solidity
struct CollectionConfig {
    address collection;
    TokenStandard standard;
    uint128 minBacking;
    uint128 maxBacking;
    uint32 maxActivePositions;
    uint32 perWalletPositionCap;
    uint16 riskTier;
    bool depositsEnabled;
    bool pullsEnabled;
    address valuationPolicy;
    address custodyAdapter;
}
```

## Backing bands

Backing bands should be enforced onchain.

For NFT collections:

```text
minimum backing: configurable percentage of reference floor
maximum backing: configurable multiple of reference floor
```

For vaulted physical items:

```text
minimum backing: percentage of authenticated valuation
maximum backing: percentage or multiple of authenticated valuation
```

Backing-band updates must:

- be timelocked
- apply only to new deposits and backing changes
- never force-liquidate an existing position
- become effective only between draw epochs

## Backing changes

A position owner may:

- add backing
- reduce backing
- change payout address
- change automatic reward preferences

Any backing change affecting probability is staged until the current epoch completes.

---

# 7. Position lifecycle

## Position states

```solidity
enum PositionStatus {
    Staged,
    Active,
    BackingChangeQueued,
    WithdrawalQueued,
    Selected,
    Settling,
    Closed,
    Withdrawn
}
```

## Deposit

The user submits:

```text
NFT
settlement market
backing
earnings recipient
reward preference
optional referral or partner attribution
```

The vault:

1. verifies collection and token standard;
2. receives the NFT;
3. receives ETH/WETH or USDG backing;
4. mints a `PositionNFT`;
5. stages or activates the position;
6. inserts its inverse-backing weight into the weighted tree.

## Position ownership

`PositionNFT` represents:

- ownership of the deposited position
- backing withdrawal rights
- accrued base proceeds
- accrued markup
- accrued `$DRAW`
- Crown rights, where applicable
- settlement rights if the position is selected

It may be transferred while staged or active.

It is frozen while selected or settling.

## Withdrawal

When no epoch is in flight, withdrawal is immediate.

When a draw is pending:

1. withdrawal is queued;
2. the position remains in the current locked snapshot;
3. it is removed after the epoch;
4. NFT, backing, and accrued earnings return to the current `PositionNFT` owner.

No administrator may block a valid withdrawal indefinitely.

---

# 8. Pull lifecycle

## 8.1 Pull request

A pull request contains:

```solidity
struct PullOrder {
    uint256 marketId;
    address buyer;
    address receiver;
    uint32 drawCount;
    uint128 maxUnitPrice;
    uint128 maxTotalPrice;
    uint48 deadline;
    bytes32 referralCode;
    PayoutPreference preference;
}
```

The buyer escrows their maximum acceptable amount in the market settlement asset.

A custom router may first swap another payment asset into that settlement asset.

## 8.2 Slippage protection

The order defines:

- maximum unit price
- maximum total price
- deadline
- minimum `$DRAW` output where relevant

If the active pool state produces a price above the buyer’s limit, the unexecuted draw is refunded.

The protocol must never reinterpret a failed price check as user consent to a more expensive draw.

## 8.3 Batch pricing

Draws are processed sequentially without replacement.

Before every individual draw:

1. calculate current \(N\);
2. calculate current total weight \(S\);
3. calculate current \(EV=N/S\);
4. calculate current price;
5. verify buyer limits;
6. distribute base proceeds and markup;
7. derive randomness;
8. select and remove a position.

This prevents a large batch from buying many draws at a stale initial price.

---

# 9. Epoch and batching model

Each market permits one active randomness epoch at a time.

## Epoch states

```solidity
enum EpochStatus {
    Idle,
    Collecting,
    RandomnessRequested,
    RandomnessReady,
    Resolving,
    Finalized,
    Cancelled
}
```

## Lifecycle

### Idle

- deposits can activate
- backing changes can apply
- withdrawals can execute
- first pull locks the active set

### Collecting

- active tree is frozen
- additional pull orders may join
- new deposits and withdrawals are staged
- tree root, active count, and total weight are committed

### Randomness requested

The coordinator requests randomness bound to:

```text
chain ID
market ID
epoch ID
active tree root
order root
active count
total weight
request block
```

### Resolving

Permissionless callers process bounded chunks:

```solidity
resolveEpoch(
    uint256 epochId,
    uint32 maxDraws
);
```

This prevents one large epoch from exceeding the block gas limit.

### Finalized

- selected positions remain in settlement state
- unselected queued withdrawals execute
- backing changes apply
- staged positions activate
- the next epoch can begin

The next epoch does not wait for every buyer's 24-hour settlement choice. Selected positions have already left the active draw tree.

---

# 10. Weighted selection implementation

Use a Fenwick tree, segment tree, or sortition-sum tree.

```text
leaf:
    inverse-backing weight

internal node:
    sum of child weights
```

Selection:

```solidity
uint256 target = randomValue % totalWeight;
uint256 selectedIndex = tree.findByCumulativeWeight(target);
tree.update(selectedIndex, 0);
```

Complexity:

| Operation       | Complexity |
| --------------- | ---------: |
| Insert position |   O(log N) |
| Change backing  |   O(log N) |
| Remove position |   O(log N) |
| Select position |   O(log N) |

## Numeric normalization

Normalize every settlement asset to 18-decimal internal accounting:

```solidity
normalizedBacking =
    settlementAssetDecimals == 18
        ? rawBacking
        : rawBacking * 10 ** (18 - settlementAssetDecimals);
```

Weight:

```solidity
weight = Math.mulDiv(
    WEIGHT_SCALE,
    1e18,
    normalizedBacking
);
```

Required rules:

- pull price rounds up
- user payouts round down
- reward allocations round down
- dust goes to the security reserve
- minimum backing prevents pathological weights
- total tree weight must never overflow its configured integer width

---

# 11. Randomness architecture

Robinhood Chain documentation warns that `block.prevrandao` and `block.difficulty` return a constant and must not be used as randomness.

Chainlink’s current product matrix lists CCIP and Data Streams for Robinhood Chain but does not presently list VRF there. The protocol therefore must not hard-code one provider into permanent market logic.

## Adapter interface

```solidity
interface IRandomnessAdapter {
    function requestRandomness(
        bytes32 commitment,
        uint32 wordCount
    ) external returns (bytes32 requestId);

    function verifyAndConsume(
        bytes32 requestId,
        bytes calldata proof
    ) external returns (uint256[] memory words);

    function isRequestPending(
        bytes32 requestId
    ) external view returns (bool);
}
```

## Provider requirements

A production provider must offer:

- cryptographically verifiable output
- no unilateral result selection
- public proof verification
- replay protection
- sufficient mainnet confirmations
- documented timeout rules
- audited Robinhood Chain deployment
- economic or cryptographic resistance to withholding

## Timeout rules

If randomness is not delivered before the immutable timeout:

1. cancel the epoch;
2. refund every unexecuted pull;
3. restore normal position operations;
4. reject any late callback.

Do not allow governance or a keeper to insert a replacement seed.

Once a valid seed is accepted, it is binding. The randomness-request timeout no longer permits
cancellation from `RandomnessReady` or `Resolving`, so no buyer or third party can compare the known
result with a refund before deciding how to progress the epoch. Resolution remains permissionless after
the timeout.

An unexpected atomic market resolution failure commits the epoch to irreversible, permissionless
`Refunding` recovery in that same call. The coordinator restores the failed attempt's escrow debit before
the transition, preserves selections completed by earlier calls, and refunds only each unresolved suffix.
Recovery processes an explicit order budget per call, then unlocks the epoch and processes the ordinary
boundary queues. Resolution cannot resume from `Refunding`.

Every market resolution attempt receives the same protocol-defined gas stipend. The coordinator rejects a
caller that cannot also retain the recovery reserve, before debiting escrow or calling the market. A caller
therefore cannot manufacture `Refunding` by supplying less gas than another caller would have provided.

## Finality tiers

Robinhood Chain offers fast sequencer confirmations, followed by Ethereum posting and eventual Ethereum finality. High-value markets can require stronger confirmation before requesting randomness or recognizing deposits.

Recommended tiers:

| Market                            | Confirmation policy                                |
| --------------------------------- | -------------------------------------------------- |
| Low-value game assets             | Sequencer confirmation                             |
| Standard NFT markets              | Posted-to-Ethereum confirmation for large deposits |
| High-value TCG or physical assets | Posted-to-Ethereum or full-finality threshold      |
| Exceptional-value items           | Dedicated high-security market                     |

---

# 12. Settlement window

The default buyer decision window is 24 hours, matching NFW’s current design.

During the window, only the current `PullReceipt` owner may select the outcome.

After expiry:

```text
default settlement = KEEP
NFT → pull receiver
99% backing → position owner
1% backing → settlement revenue
all earnings → position owner
```

`forceKeep()` must be permissionless.

The caller may receive a small keeper reimbursement from the settlement revenue, subject to a cap.

---

# 13. Pull receipts

Every successful draw mints a unique `PullReceipt`.

```solidity
struct PullReceiptData {
    uint256 marketId;
    uint256 epochId;
    uint256 positionId;
    address originalBuyer;
    address receiver;
    uint128 chargedPrice;
    uint128 selectedBacking;
    uint48 revealedAt;
    uint48 decisionDeadline;
    PullStatus status;
}
```

Recommended transfer policy:

| Stage                           | Transferable                     |
| ------------------------------- | -------------------------------- |
| Before reveal                   | No                               |
| After reveal, before settlement | Optional market flag             |
| After settlement                | Receipt becomes historical proof |

Flagship markets should disable trading of unrevealed receipts. Transferable sealed lottery tickets expand the regulatory surface and create a secondary market that is not necessary for the core product.

---

# 14. Reward system

## 14.1 `$DRAW`

`$DRAW` is the liquid protocol token.

It should have:

- fixed or capped supply
- no guaranteed redemption floor
- no claim on user backing
- no role in protocol solvency
- Uniswap v4 liquidity against WETH and USDG

Utility:

- protocol governance
- market-creator bonds
- curator staking
- partner-market creation
- fee discounts funded by protocol revenue
- boosted referral tiers
- protocol-owned liquidity participation
- dispute or challenge bonds

## 14.2 Reward purchases

The reward share of pull markup is accumulated per market.

A permissionless executor periodically:

1. reads a manipulation-resistant quote;
2. enforces maximum price impact;
3. swaps market settlement asset into `$DRAW`;
4. allocates `$DRAW` through the per-position accumulator.

When a position exits, accrued reward-purchase input is normally queued to the position's earnings
recipient for a later protected `$DRAW` purchase. If that queue operation fails, the exit must remain
live: the same amount becomes an exactly backed, owner-bound claim in the market settlement asset.
This is a final cash fallback, not a retryable `$DRAW`-funding liability. Only the earnings recipient
may redirect its delivery.

ETH markets buy through `$DRAW/WETH`.

USDG markets buy through `$DRAW/USDG` or route through the deeper canonical pool.

## 14.3 Take `$DRAW` settlement

When the puller selects `$DRAW`:

1. the market's `cashPayoutBps` share of selected backing becomes swap input (90% in the flagship target);
2. the settlement router executes a bounded v4 swap;
3. `$DRAW` is delivered to the puller;
4. the NFT returns to the position owner.

The user provides `minDrawOut`.

If the protected swap cannot execute, the settlement remains unconsumed. The user may retry or choose the market settlement asset instead.

## 14.4 Points

Points should be:

- nontransferable
- derived entirely from onchain events
- reproducible by anyone
- not required by core market execution

Point categories:

```text
pull volume
base proceeds earned
markup earned
settlement volume
Crown income
market creation
active-day streaks
referrals
verified physical redemption
```

Published oracle data converts cross-currency points offchain at the event time. A stale points oracle must never stop a draw.

---

# 15. Crown system

Each market has one Crown. There is no cross-currency Crown.

The deepest active backing holds the Crown.

```text
Crown challenger backing
    >= incumbent backing × 110%
```

Crown revenue:

```text
5% of markup remaining after reward allocation
```

The pot pays when:

- another position displaces the Crown
- the Crown position is selected
- the Crown position withdraws
- the collection is retired
- the market enters wind-down

A staged position cannot take the Crown until it becomes active.

A global protocol leaderboard may compare Crown activity in USD terms, but global financial rewards should not depend on cross-currency oracle conversion.

---

# 16. Referral and partner system

## Onchain referral binding

A wallet can bind once to:

- a referrer address
- a partner code
- a creator market
- a campaign identifier

Binding is permanent after the user’s first economically meaningful action.

```solidity
function bindReferral(
    bytes32 referralCode,
    bytes calldata signature
) external;
```

## Referral earnings

Referral income comes only from realised settlement revenue.

Default:

```text
20% of keep settlement fee
20% of cash settlement spread
20% of reward settlement spread
20% of relist settlement fee
```

The protocol should pay referrals onchain and continuously rather than rely on monthly manual distributions.

Self-referral using the same address is prohibited. Complete sybil prevention is not possible at the contract layer, so referral rates must remain economically bounded.

---

# 17. Full contract architecture

| Contract                    | Responsibility                                                            |
| --------------------------- | ------------------------------------------------------------------------- |
| `ProtocolRegistry`          | Approved versions, modules, currencies, policies, and canonical addresses |
| `MarketFactory`             | Deploys isolated, immutable-version `DrawMarket` instances                |
| `DrawMarket`                | Coordinates positions, pull orders, epochs, and state transitions         |
| `MarketVault`               | Custodies NFTs and settlement assets for one market                       |
| `PositionNFT`               | Transferable ownership and earnings rights for positions                  |
| `PullReceipt`               | Buyer’s revealed or pending settlement right                              |
| `WeightedTree`              | O(log N) weighted selection                                               |
| `FeeAccounting`             | Base proceeds, cash markup, reward, Crown, and protocol accumulators      |
| `EpochCoordinator`          | Locks active state and resolves draw batches                              |
| `RandomnessCoordinator`     | Provider-independent requests, callbacks, and timeouts                    |
| `SettlementEngine`          | Keep, cash, reward, relist, and forced settlement                         |
| `CollectionRegistry`        | Accepted contracts, backing bands, risk tiers, and limits                 |
| `EligibilityPolicyRegistry` | Optional access, geography, partner, or compliance policies               |
| `CrownManager`              | Per-market Crown ownership and accrued pot                                |
| `ReferralRegistry`          | Immutable referral binding and claimable revenue                          |
| `RewardController`          | `$DRAW` purchases and distribution                                        |
| `InsuranceVault`            | Security reserve funded by settlement revenue                             |
| `DrawRouter`                | Direct ETH, WETH, USDG, Permit2, and batched interactions                 |
| `V4SwapAdapter`             | Protected payment and settlement conversions                              |
| `RevenueHook`               | `$DRAW` liquidity, protocol-owned liquidity, and fee routing              |
| `PullIntakeHook`            | Optional custom-accounting entry point for v4-native pull orders          |
| `MarketGovernor`            | Timelocked registry and policy governance                                 |
| `EmergencyGuardian`         | Intake pause only; cannot seize assets or block exits                     |

---

# 18. Upgradeability model

Do not make custody markets arbitrarily upgradeable.

## Recommended structure

- registries and factories may be upgradeable through a timelock
- each `DrawMarket` is deployed against a fixed implementation version
- new logic means a new market implementation version
- existing users are never silently migrated
- markets can enter wind-down and users can voluntarily migrate
- external adapters may be changed only between epochs and after notice

Immutable per-market parameters:

```text
settlement asset
weight formula version
markup formula and markupBps
keepPayoutBps
cashPayoutBps
decision window
position-earning entitlement
maximum creator fee
```

The factory validates payout ratios against the fixed implementation version's bounds before deployment. The market passes the accepted ratios into its paired settlement engine; neither ratio is a global constant or a post-deployment governance setting.

Governable with notice:

```text
accepted collections
backing bands
randomness adapter
market caps
new-deposit availability
new-pull availability
reward execution parameters
```

---

# 19. Uniswap v4’s role

The protocol uses Uniswap v4 for routing and liquidity. It keeps NFT custody and the 24-hour settlement state outside `PoolManager` callbacks.

Uniswap v4 custom accounting can replace standard swap pricing. AsyncSwap hooks can take input before the economic action finishes. Version 4 pools also support native ETH.

## 19.1 Required: `SwapAndPullRouter`

Canonical consumer flow:

```text
user payment asset
      ↓
Uniswap v4 route
      ↓
market settlement asset
      ↓
DrawMarket.requestPull()
```

Capabilities:

- ETH → ETH market
- ETH → USDG market
- USDG → ETH market
- USDG → USDG market
- arbitrary approved ERC-20 → market asset
- exact-output and maximum-input protection
- Permit2
- account-abstraction batching
- dust refunds

## 19.2 Required: settlement routing

After reveal:

```text
cash entitlement
      ↓
optional Uniswap v4 conversion
      ↓
ETH / USDG / $DRAW
```

The core market first establishes a settlement-asset entitlement. Conversion happens as a separate bounded step so swap failure cannot corrupt settlement accounting.

## 19.3 Required: `$DRAW` liquidity hook

`RevenueHook` can manage:

- protocol-owned `$DRAW/WETH` liquidity
- protocol-owned `$DRAW/USDG` liquidity
- fee collection
- fee compounding
- bounded protocol buybacks
- insurance-fund contributions
- reporting of hook-owned reserves

## 19.4 Optional: v4-native pull intake

A specialized AsyncSwap-style hook may:

1. accept exact-input ETH or USDG;
2. validate a trusted router;
3. bypass ordinary concentrated-liquidity output;
4. create a `PullOrder`;
5. mint an external `PullReceipt`;
6. return with all PoolManager deltas resolved.

This is an interoperability surface, not the source of truth.

Hooks see the PoolManager/router path rather than the original user directly, so trusted-router authentication is required.

The direct `DrawRouter` remains canonical because a random NFT settlement is not semantically an ordinary interchangeable-token swap.

---

# 20. ETH implementation

For the consumer, it is an ETH market.

Internally:

```text
native ETH received
    → wrapped into canonical WETH
    → accounted in MarketVault
```

Advantages:

- uniform ERC-20 accounting
- safer transfer handling
- compatibility with yield or liquidity modules
- no accidental ETH transfer ambiguity

On payout:

```text
WETH entitlement
    → optionally unwrap
    → send native ETH
```

Users choose:

```solidity
enum EthPayoutMode {
    NativeETH,
    WETH
}
```

A failed native transfer must not block settlement. The fallback is claimable WETH.

---

# 21. USDG implementation

USDG markets use:

- canonical USDG
- Permit2
- exact balance-delta checks
- no fee-on-transfer assumptions
- direct USDG payouts

USDG is useful because:

- backing remains stable in dollar terms
- physical cards are normally appraised in dollars
- users can understand the cash exit without ETH-price movement
- collection backing bands are easier to operate

Users without ETH for gas can use sponsored account-abstraction transactions. Robinhood Chain supports gas sponsorship, batching, session keys, and embedded wallet infrastructure.

---

# 22. Account abstraction experience

The complete consumer interface should use ERC-4337 or EIP-7702 to make common operations single actions.

## Deposit action

```text
approve NFT
approve or transfer backing
deposit NFT
mint PositionNFT
```

## Pull action

```text
approve input token
swap into market asset
submit pull order
mint pending receipt
```

## Settlement action

```text
choose exit
settle position
swap payout if requested
deliver asset
```

## Relist action

```text
settle old position
provide new backing
create new position
retain NFT in vault
```

The application can sponsor low-cost interactions while setting spend limits and preventing arbitrary sponsored calls.

---

# 23. Full frontend

## Primary pages

### Explore

- curated markets
- ETH/USDG selector
- active inventory
- pull price
- aggregate backing
- recent jackpots
- verified physical assets
- partner markets

### Market

- live position cards
- exact probability
- backing
- collection
- historical earnings
- Crown holder
- current EV and markup
- recent draws
- verifiable active-tree root

### Pull

- number of draws
- settlement market
- payment asset
- maximum spend
- expected price
- immutable markup, cash payout, and keep payout ratios
- token-independent cash-floor RTP, using `cashPayoutBps / (10,000 + markupBps)`
- possible payout range, with collectible value and `$DRAW` output labelled as estimates
- gas, swap, and payment-routing costs that are excluded from the cash-floor RTP
- legal disclosure
- referral attribution

### Reveal

- randomness provider
- request commitment
- proof
- selected weight
- cumulative-weight target
- selected position
- verification code or transaction link

### Position management

- backing
- probability
- earnings
- accrued `$DRAW`
- Crown status
- queue status
- change backing
- withdraw
- transfer `PositionNFT`

### Settlement

- keep
- cash
- `$DRAW`
- relist
- countdown
- estimated payout
- swap slippage
- force-settlement status

### Rewards

- points
- `$DRAW`
- referrals
- Crown history
- partner revenue
- season rankings

### Market creation

- collection set
- ETH or USDG
- fees within protocol bounds
- creator bond
- eligibility policy
- market branding
- partner revenue
- risk disclosures

---

# 24. Indexing and data services

Onchain state is authoritative, but the application needs a production indexing layer.

Required services:

| Service                 | Purpose                                         |
| ----------------------- | ----------------------------------------------- |
| Event indexer           | Positions, epochs, pulls, settlements, earnings |
| Metadata service        | NFT and physical-asset metadata                 |
| Collection risk service | Backing bands and collection state              |
| Quote service           | Fast UI previews verified against onchain views |
| Randomness watcher      | Callback and timeout monitoring                 |
| Settlement keeper       | Permissionless forced settlements               |
| Reward executor         | Bounded `$DRAW` purchases                       |
| Market analytics        | Volume, earnings, retention, settlement choices |
| Verification API        | Reproduce odds and selections                   |
| Archive data pipeline   | Historical points and leaderboards              |

Every UI quote must still include an onchain maximum price.

## 24.1 Meet the paid launch evidence requirement

Before a paid flagship launch, show these terms before each pull:

- the fixed markup, cash and keep ratios
- the cash-floor return to player
- the difference between cash, collectible and `$DRAW` outcomes
- gas and routing costs excluded from the cash floor

The production indexer must measure:

- cash, keep, `$DRAW`, relist and forced settlement choices
- repeat pulls by wallet cohort and period
- the share of pulls from the largest wallets or cohorts
- realised token-independent return from entitlements and pull prices
- differences between modelled and observed volume, settlement choices and retention

The current frontend adapter contains mock data. It does not meet this evidence requirement.

Publish model inputs beside observed results when indexed data exists. State the sample period and cohort definitions.

Set the review period and launch thresholds before paid use. Contract tests and token-price changes do not show sustainable demand. Market comparisons can inform the test, but they do not prove cause.

---

# 25. Security invariants

## Accounting

```text
vault assets >= all user and protocol liabilities
```

## Position uniqueness

An NFT may exist in exactly one state:

```text
staged
active
selected
closed
withdrawn
```

Never two.

## Tree consistency

```text
tree.totalWeight
    == sum(weight of every active position)

activeCount
    == number of nonzero active leaves
```

## Draw uniqueness

A selected leaf is set to zero before any external interaction.

The same position cannot be selected twice in one or multiple epochs.

## Earnings

A position active for a draw receives:

```text
exactly one base share
exactly one depositor-markup share
exactly one reward-token share
```

## Settlement

A pull receipt may settle exactly once.

Every settlement consumes the selected backing liability.

## Admin restrictions

No administrator can:

- transfer an NFT from the vault
- sweep backing
- redirect position earnings
- alter a resolved draw
- replace randomness
- block an eligible withdrawal permanently
- modify the economic policy of an existing market

## Pausing

A guardian may pause:

- new deposits
- new backing changes
- new pull requests
- new market creation

A guardian may not pause:

- withdrawals from unselected positions
- claims
- revealed settlements
- forced keep
- refunds after randomness failure

---

# 26. Collection-contract threats

Markets must defend against:

- malicious `onERC721Received` callbacks
- reentrant NFT contracts
- mutable metadata
- frozen or blacklistable assets
- counterfeit collections
- ERC-1155 quantity inconsistencies
- fee-on-transfer settlement tokens
- rebasing tokens
- callback-heavy token standards
- physical issuer insolvency

Recommended controls:

- isolated vault per market
- collection allowlist
- reentrancy guards
- checks-effects-interactions
- collection-specific custody adapters
- actual-balance-delta verification
- no arbitrary delegatecall modules
- emergency collection retirement at epoch boundaries
- explicit issuer and redemption disclosures for vaulted assets

---

# 27. Physical collectibles and RWA support

The full protocol can support:

- vaulted trading cards
- watches
- sneakers
- game items
- digital memberships
- redeemable collectibles
- authenticated luxury goods

The NFT must represent a legally and operationally enforceable claim against a vault or issuer.

Required issuer data:

```text
custodian
redemption procedure
redemption fees
insurance status
jurisdiction
asset identifier
grade or authentication report
freeze authority
replacement policy
proof-of-reserve method
```

Robinhood Stock Tokens are ERC-20 debt securities with jurisdiction and transfer restrictions, not ordinary collectible NFTs. They should not be placed into paid randomized draw markets without a separate regulated product structure.

---

# 28. Eligibility and compliance layer

Paid randomized acquisition can be treated differently across jurisdictions. NFW itself describes its mechanism as a gacha-style randomized acquisition product, restricts interface use to adults, and requires users to determine whether paid random draws are legal where they live.

The full architecture should therefore support optional `IEligibilityPolicy` modules:

```solidity
interface IEligibilityPolicy {
    function canDeposit(
        address user,
        uint256 marketId
    ) external view returns (bool);

    function canPull(
        address user,
        uint256 marketId
    ) external view returns (bool);

    function canReceive(
        address user,
        uint256 positionId
    ) external view returns (bool);
}
```

Possible policies:

- permissionless
- partner allowlist
- age or identity attestation
- jurisdiction attestation
- accredited or qualified participant
- game-community membership
- issuer-specific RWA restrictions

The core protocol remains neutral and composable, while individual regulated markets can enforce the policy they require.

---

# 29. Recommended complete configuration

## Flagship economics

```text
Weight:
    inverse backing

Base pull proceeds:
    100% equally to active positions

Markup:
    2.5% of EV (markupBps = 250)

Reward allocation:
    10% of markup buys $DRAW for active positions

Remaining markup:
     5% Crown
     1% protocol
    94% active positions

Keep payout:
    99% of selected backing (keepPayoutBps = 9,900)

Cash payout:
    90% of selected backing (cashPayoutBps = 9,000)

$DRAW payout:
    $DRAW purchased using 90% of selected backing

Cash-floor RTP:
    90% / 102.5% = 87.8%, before gas and routing costs

Decision period:
    24 hours

Forced outcome:
    Keep

Crown takeover:
    110% of incumbent backing
```

## Settlement-revenue policy

```text
20% referral
20% security reserve
20% $DRAW buyback / protocol-owned liquidity
40% protocol treasury
```

## Market model

```text
single settlement asset per market
ETH and USDG both supported
payment routing through Uniswap v4
isolated vault per market
one in-flight randomness epoch per market
draws without replacement
permissionless chunked resolution
versioned non-upgradeable market instances
```

## Token model

```text
$DRAW:
    liquid fixed/capped supply token
    no guaranteed redemption
    no claim on user backing

Points:
    nontransferable
    reconstructed from onchain history

PositionNFT:
    transferable position ownership

PullReceipt:
    nontransferable before reveal
```

---

# 30. Final architecture decision

The product to build is:

Backed Draw Protocol provides separate ETH and USDG collectible markets on Robinhood Chain. Each position supplies an NFT and backing. It earns an equal share of expected-value proceeds and fee yield while active.

Pullers choose one of 4 settlement options after reveal. Uniswap v4 provides payment routing, payout conversion and reward-token liquidity. It can also provide an optional custom-accounting entry point.

The critical boundaries are:

1. Keep ETH and USDG in separate settlement markets.
2. Let users pay with either asset through protected routing.
3. Allocate every part of the pull payment.
4. Divide the EV component equally between active positions.
5. Fund protocol incentives from markup and settlement revenue.
6. Keep randomness, NFT custody and delayed settlement outside `PoolManager`.
7. Use Uniswap v4 without placing asynchronous NFT state in a swap callback.
8. Keep each market isolated, versioned and non-seizable.
9. Support flagship, partner and permissionless markets.
10. Include the Crown, referrals, points, `$DRAW`, physical assets, account abstraction, verification and optional eligibility rules.

Agree this specification before dividing the remaining implementation work.

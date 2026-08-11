# Full Target Specification: Multi-Currency Backed Draw Protocol

The final product should **not** be a USDG-only port and should **not** force the entire mechanism into a Uniswap hook.

The correct end-state is:

> A multi-market protocol where users deposit an NFT together with backing, earn from every draw while active, and pullers pay a mathematically derived price for a verifiably random position. Every market settles in one currency—ETH or USDG—but users may pay and receive through either currency using Uniswap routing.

The protocol supports both ETH and USDG from the beginning, but **never mixes them inside the same probability tree or liability ledger**.

---

# 1. Currency decision

## Final rule

> **One protocol, many markets. One market, one settlement asset.**

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

## Separate four currency concepts

| Concept              | Meaning                                                                                          |
| -------------------- | ------------------------------------------------------------------------------------------------ |
| **Settlement asset** | The currency in which backing, odds, pricing, earnings, and settlement liabilities are accounted |
| **Payment asset**    | What the puller provides to the router                                                           |
| **Payout asset**     | What the user elects to receive after settlement                                                 |
| **Display currency** | ETH, USD, or another UI-only denomination                                                        |

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

## Why ETH and USDG must not coexist in one market

A mixed ETH/USDG market would require:

- converting every backing into a common oracle numeraire;
- handling ETH price movement between payment and reveal;
- determining which currency funds cash settlement;
- rebalancing reserves;
- protecting against stale oracle updates;
- handling cross-currency insolvency;
- defining who bears swap slippage.

That complexity adds no meaningful consumer benefit. A routing layer gives users the same payment choice without contaminating the core mechanism.

## Recommended defaults

| Asset category                              | Preferred settlement        |
| ------------------------------------------- | --------------------------- |
| Crypto-native NFTs                          | ETH                         |
| PFPs and art                                | ETH                         |
| Game assets                                 | ETH or USDG                 |
| Vaulted cards and physical collectibles     | USDG                        |
| Luxury goods and other dollar-priced assets | USDG                        |
| Partner-created markets                     | Creator chooses ETH or USDG |

**ETH should be the default flagship market.** USDG should be a first-class alternative, particularly for TCG and physical collectibles.

---

# 2. Product definition

Working protocol description:

> Deposit a collectible with ETH or USDG backing. The backing determines how often the position is likely to be drawn. While active, the position earns an equal share of draw proceeds and fees. Pullers pay one transparent pool-derived price and receive a verifiably random position. After reveal, they choose the collectible, a discounted cash settlement, the protocol token, or immediate relisting.

NFW currently uses inverse-backing odds, an expected-value pull price plus a 10% markup, four settlement exits, staged deposits, a 24-hour decision period, depositor rewards, referrals, and a Crown mechanism.

Our target preserves those recognizable mechanics but makes the accounting, currency architecture, modularity, and ownership of every payment explicit.

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

where:

- \(b_i\) is the position’s normalized backing;
- \(w_i\) is its draw weight;
- \(p_i\) is its probability of being selected.

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

every active position contributes **exactly the same amount** to the expected value.

Therefore:

\[
EV = \frac{N}{S}
\]

and:

\[
\frac{EV}{N} = \frac{1}{S}
\]

This identity should drive the complete economic design.

---

## 3.3 Pull price

With a default markup \(m=10\%\):

\[
PullPrice = EV \times (1+m)
\]

Split it into:

```text
Base draw proceeds = EV
Markup              = EV × 10%
Total pull price    = EV + markup
```

NFW publicly describes the expected-value-plus-markup model and distributes the markup among depositors, its reward mechanism, the Crown, and the protocol.

Our implementation should additionally account for the base \(EV\) explicitly.

---

# 4. Full pull-payment allocation

## 4.1 Base draw proceeds

**100% of the EV component is divided equally among every position active for that draw.**

For an active position:

\[
BaseEarning_i = \frac{EV}{N} = \frac{1}{S}
\]

This is not an arbitrary equal split. It follows directly from the inverse-backing formula: every position contributes the same amount to EV.

This corrects the depositor economics:

- the depositor supplies both an NFT and backing;
- when selected, one of those two legs leaves the position;
- over the position’s expected lifetime, base draw proceeds compensate it for the leg at risk;
- markup becomes the actual yield premium.

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

If markup is 10% of EV, effective allocation is approximately:

| Recipient                       | Effective share of EV |
| ------------------------------- | --------------------: |
| Active-position base proceeds   |              100.000% |
| Active-position cash markup     |                8.460% |
| Active-position `$DRAW` rewards |                1.000% |
| Crown                           |                0.450% |
| Protocol from markup            |                0.090% |

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
    receives 85% of backing

Position owner:
    receives NFT back
    receives all accrued earnings

Settlement revenue:
    15% of backing
```

### Take `$DRAW`

```text
Buyer:
    receives $DRAW purchased with 85% of backing

Position owner:
    receives NFT back
    receives all accrued earnings

Settlement revenue:
    15% of backing
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

These keep and cash ratios match NFW’s current public design.

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

For native-looking ETH markets, the vault should normalize ETH to canonical WETH internally while the router exposes native ETH deposits and withdrawals.

## 5.2 Market classes

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

- collections;
- game studios;
- TCG vault providers;
- luxury-goods issuers;
- event organizers;
- creator communities.

Partners can receive a bounded revenue share.

### Permissionless markets

Anyone may create a market using approved templates.

Requirements:

- creator bond;
- immutable settlement asset;
- bounded fees;
- isolated vault;
- explicit risk label;
- no appearance in curated discovery by default;
- malicious collection contracts isolated from other markets.

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

- be timelocked;
- apply only to new deposits and backing changes;
- never force-liquidate an existing position;
- become effective only between draw epochs.

## Backing changes

A position owner may:

- add backing;
- reduce backing;
- change payout address;
- change automatic reward preferences.

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

- ownership of the deposited position;
- backing withdrawal rights;
- accrued base proceeds;
- accrued markup;
- accrued `$DRAW`;
- Crown rights, where applicable;
- settlement rights if the position is selected.

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

- maximum unit price;
- maximum total price;
- deadline;
- minimum `$DRAW` output where relevant.

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

- deposits can activate;
- backing changes can apply;
- withdrawals can execute;
- first pull locks the active set.

### Collecting

- active tree is frozen;
- additional pull orders may join;
- new deposits and withdrawals are staged;
- tree root, active count, and total weight are committed.

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

- selected positions remain in settlement state;
- unselected queued withdrawals execute;
- backing changes apply;
- staged positions activate;
- the next epoch can begin.

The next epoch does **not** need to wait for every buyer’s 24-hour settlement choice. Selected positions are already removed from the active draw tree.

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

- pull price rounds up;
- user payouts round down;
- reward allocations round down;
- dust goes to the security reserve;
- minimum backing prevents pathological weights;
- total tree weight must never overflow its configured integer width.

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

- cryptographically verifiable output;
- no unilateral result selection;
- public proof verification;
- replay protection;
- sufficient mainnet confirmations;
- documented timeout behavior;
- audited Robinhood Chain deployment;
- economic or cryptographic resistance to withholding.

## Timeout behavior

If randomness is not delivered before the immutable timeout:

1. cancel the epoch;
2. refund every unexecuted pull;
3. restore normal position operations;
4. reject any late callback.

Do not allow governance or a keeper to insert a replacement seed.

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

- fixed or capped supply;
- no guaranteed redemption floor;
- no claim on user backing;
- no role in protocol solvency;
- Uniswap v4 liquidity against WETH and USDG.

Utility:

- protocol governance;
- market-creator bonds;
- curator staking;
- partner-market creation;
- fee discounts funded by protocol revenue;
- boosted referral tiers;
- protocol-owned liquidity participation;
- dispute or challenge bonds.

## 14.2 Reward purchases

The reward share of pull markup is accumulated per market.

A permissionless executor periodically:

1. reads a manipulation-resistant quote;
2. enforces maximum price impact;
3. swaps market settlement asset into `$DRAW`;
4. allocates `$DRAW` through the per-position accumulator.

ETH markets buy through `$DRAW/WETH`.

USDG markets buy through `$DRAW/USDG` or route through the deeper canonical pool.

## 14.3 Take `$DRAW` settlement

When the puller selects `$DRAW`:

1. 85% of selected backing becomes swap input;
2. the settlement router executes a bounded v4 swap;
3. `$DRAW` is delivered to the puller;
4. the NFT returns to the position owner.

The user provides `minDrawOut`.

If the protected swap cannot execute, the settlement remains unconsumed. The user may retry or choose the market settlement asset instead.

## 14.4 Points

Points should be:

- nontransferable;
- derived entirely from onchain events;
- reproducible by anyone;
- not required by core market execution.

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

Cross-currency points are normalized offchain at the event timestamp using published oracle data. The core draw must never fail because a points oracle is stale.

---

# 15. Crown system

There should be **one Crown per market**, not one cross-currency Crown.

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

- another position displaces the Crown;
- the Crown position is selected;
- the Crown position withdraws;
- the collection is retired;
- the market enters wind-down.

A staged position cannot take the Crown until it becomes active.

A global protocol leaderboard may compare Crown activity in USD terms, but global financial rewards should not depend on cross-currency oracle conversion.

---

# 16. Referral and partner system

## Onchain referral binding

A wallet can bind once to:

- a referrer address;
- a partner code;
- a creator market;
- a campaign identifier.

Binding is permanent after the user’s first economically meaningful action.

```solidity
function bindReferral(
    bytes32 referralCode,
    bytes calldata signature
) external;
```

## Referral earnings

Referral income is funded only from realized settlement revenue.

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

- registries and factories may be upgradeable through a timelock;
- each `DrawMarket` is deployed against a fixed implementation version;
- new logic means a new market implementation version;
- existing users are never silently migrated;
- markets can enter wind-down and users can voluntarily migrate;
- external adapters may be changed only between epochs and after notice.

Immutable per-market parameters:

```text
settlement asset
weight formula version
markup formula
keep payout ratio
cash payout ratio
decision window
position-earning entitlement
maximum creator fee
```

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

The draw protocol should be **v4-integrated**, but its NFT custody and 24-hour settlement state should not be trapped inside a PoolManager callback.

Uniswap v4 custom accounting can replace standard swap pricing, and AsyncSwap hooks can take swap input while economic fulfillment happens later. Native ETH is also supported by v4 pools.

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

- ETH → ETH market;
- ETH → USDG market;
- USDG → ETH market;
- USDG → USDG market;
- arbitrary approved ERC-20 → market asset;
- exact-output and maximum-input protection;
- Permit2;
- account-abstraction batching;
- dust refunds.

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

- protocol-owned `$DRAW/WETH` liquidity;
- protocol-owned `$DRAW/USDG` liquidity;
- fee collection;
- fee compounding;
- bounded protocol buybacks;
- insurance-fund contributions;
- reporting of hook-owned reserves.

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

- uniform ERC-20 accounting;
- safer transfer handling;
- compatibility with yield or liquidity modules;
- no accidental ETH transfer ambiguity.

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

- canonical USDG;
- Permit2;
- exact balance-delta checks;
- no fee-on-transfer assumptions;
- direct USDG payouts.

USDG is useful because:

- backing remains stable in dollar terms;
- physical cards are normally appraised in dollars;
- users can understand the cash exit without ETH-price movement;
- collection backing bands are easier to operate.

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

- curated markets;
- ETH/USDG selector;
- active inventory;
- pull price;
- aggregate backing;
- recent jackpots;
- verified physical assets;
- partner markets.

### Market

- live position cards;
- exact probability;
- backing;
- collection;
- historical earnings;
- Crown holder;
- current EV and markup;
- recent draws;
- verifiable active-tree root.

### Pull

- number of draws;
- settlement market;
- payment asset;
- maximum spend;
- expected price;
- possible payout range;
- markup;
- legal disclosure;
- referral attribution.

### Reveal

- randomness provider;
- request commitment;
- proof;
- selected weight;
- cumulative-weight target;
- selected position;
- verification code or transaction link.

### Position management

- backing;
- probability;
- earnings;
- accrued `$DRAW`;
- Crown status;
- queue status;
- change backing;
- withdraw;
- transfer `PositionNFT`.

### Settlement

- keep;
- cash;
- `$DRAW`;
- relist;
- countdown;
- estimated payout;
- swap slippage;
- force-settlement status.

### Rewards

- points;
- `$DRAW`;
- referrals;
- Crown history;
- partner revenue;
- season rankings.

### Market creation

- collection set;
- ETH or USDG;
- fees within protocol bounds;
- creator bond;
- eligibility policy;
- market branding;
- partner revenue;
- risk disclosures.

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

- transfer an NFT from the vault;
- sweep backing;
- redirect position earnings;
- alter a resolved draw;
- replace randomness;
- block an eligible withdrawal permanently;
- modify the economic policy of an existing market.

## Pausing

A guardian may pause:

- new deposits;
- new backing changes;
- new pull requests;
- new market creation.

A guardian may not pause:

- withdrawals from unselected positions;
- claims;
- revealed settlements;
- forced keep;
- refunds after randomness failure.

---

# 26. Collection-contract threats

Markets must defend against:

- malicious `onERC721Received` callbacks;
- reentrant NFT contracts;
- mutable metadata;
- frozen or blacklistable assets;
- counterfeit collections;
- ERC-1155 quantity inconsistencies;
- fee-on-transfer settlement tokens;
- rebasing tokens;
- callback-heavy token standards;
- physical issuer insolvency.

Recommended controls:

- isolated vault per market;
- collection allowlist;
- reentrancy guards;
- checks-effects-interactions;
- collection-specific custody adapters;
- actual-balance-delta verification;
- no arbitrary delegatecall modules;
- emergency collection retirement at epoch boundaries;
- explicit issuer and redemption disclosures for vaulted assets.

---

# 27. Physical collectibles and RWA support

The full protocol can support:

- vaulted trading cards;
- watches;
- sneakers;
- game items;
- digital memberships;
- redeemable collectibles;
- authenticated luxury goods.

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

- permissionless;
- partner allowlist;
- age or identity attestation;
- jurisdiction attestation;
- accredited or qualified participant;
- game-community membership;
- issuer-specific RWA restrictions.

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
    10% of EV

Reward allocation:
    10% of markup buys $DRAW for active positions

Remaining markup:
     5% Crown
     1% protocol
    94% active positions

Keep payout:
    99% of selected backing

Cash payout:
    85% of selected backing

$DRAW payout:
    $DRAW purchased using 85% of selected backing

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

> **A full ETH-and-USDG-backed randomized collectible market on Robinhood Chain. Positions contribute an NFT and backing, earn their exact equal contribution to every draw’s expected value plus fee yield, and settle through four consumer choices. Uniswap v4 provides payment routing, payout conversion, reward-token liquidity, protocol-owned liquidity, and an optional custom-accounting pull entry point.**

The critical boundaries are:

1. **ETH and USDG are separate settlement markets.**
2. **Users may still pay with either asset through routing.**
3. **The entire pull payment is explicitly allocated.**
4. **The EV component belongs equally to active positions.**
5. **Only the markup and settlement spreads fund protocol incentives.**
6. **Randomness, NFT custody, and 24-hour settlement live outside PoolManager.**
7. **Uniswap v4 remains deeply integrated without forcing asynchronous NFT state into a swap callback.**
8. **Every market is isolated, versioned, and non-seizable.**
9. **The protocol supports flagship, partner, and permissionless markets.**
10. **The full system includes Crown, referrals, points, `$DRAW`, physical collectibles, account abstraction, verification tooling, and optional eligibility policies.**

This is the end-state specification to freeze before dividing implementation into workstreams.

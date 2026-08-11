import {
  ArrowUpRight,
  BadgeCheck,
  Boxes,
  Clock3,
  Coins,
  Crown,
  Gift,
  Plus,
  ReceiptText,
  ShieldCheck,
  Sparkles,
  Trophy,
  WalletCards,
} from "lucide-react"
import { markets, recentDraws } from "@/data/markets"
import { formatValue } from "@/lib/utils"

export function PoolsPage({ onPull }: { onPull: (marketId: string) => void }) {
  return (
    <PageFrame eyebrow="All live pools" title="Explore live pools.">
      <div className="support-grid market-list">
        {markets.map((market) => (
          <article className="support-market" key={market.id}>
            <img alt="" src={market.heroImage} />
            <div>
              <span>
                {market.asset} settlement · {market.activePositions} live positions
              </span>
              <h2>{market.name}</h2>
              <p>{market.description}</p>
              <button onClick={() => onPull(market.id)} type="button">
                Pull for {formatValue(market.pullPrice, market.asset)} <ArrowUpRight />
              </button>
            </div>
          </article>
        ))}
      </div>
      <section className="info-banner">
        <ShieldCheck />
        <div>
          <strong>Every position is backed.</strong>
          <span>
            Pool inventory, prices, and draw roots are committed before a pull request enters
            randomness.
          </span>
        </div>
      </section>
    </PageFrame>
  )
}

export function ActivityPage() {
  return (
    <PageFrame eyebrow="Your pull history" title="Activity, with receipts.">
      <section className="activity-summary">
        <div>
          <ReceiptText />
          <span>Verified pulls</span>
          <strong>12</strong>
        </div>
        <div>
          <Trophy />
          <span>Collectibles kept</span>
          <strong>4</strong>
        </div>
        <div>
          <Coins />
          <span>Cash settlements</span>
          <strong>3.14 ETH</strong>
        </div>
      </section>
      <section className="activity-list">
        {recentDraws.map((draw, index) => (
          <article key={draw.name}>
            <img alt="" src={draw.image} />
            <div>
              <span>
                {draw.market} · {draw.ago} ago
              </span>
              <h2>{draw.name}</h2>
              <small>
                <ShieldCheck /> Randomness receipt verified
              </small>
            </div>
            <strong>{draw.value}</strong>
            <button aria-label={`Open ${draw.name} receipt`} type="button">
              <ArrowUpRight />
            </button>
            {index === 0 ? <em>Latest</em> : null}
          </article>
        ))}
      </section>
    </PageFrame>
  )
}

export function BackerPage({ onPull }: { onPull: () => void }) {
  const position = markets[0].positions[2]
  return (
    <PageFrame eyebrow="Backer vault" title="Put your collection to work.">
      <section className="backer-overview">
        <div>
          <p>Total position value</p>
          <strong>
            52.84 <small>ETH</small>
          </strong>
          <span>≈ $184,940 across active backing</span>
        </div>
        <div>
          <p>Unclaimed proceeds</p>
          <strong className="lime">
            0.84 <small>ETH</small>
          </strong>
          <button type="button">Claim earnings</button>
        </div>
        <button className="deposit-action" onClick={onPull} type="button">
          <Plus /> Deposit a collectible
        </button>
      </section>
      <section className="position-management">
        <div className="manage-image">
          <img alt={position.name} src={position.image} />
          <span>Active</span>
        </div>
        <div>
          <p>{position.collection}</p>
          <h2>{position.name}</h2>
          <span className="position-pool">NFT Omnipool · ETH settlement</span>
        </div>
        <dl>
          <div>
            <dt>Backing</dt>
            <dd>31.0 ETH</dd>
          </div>
          <div>
            <dt>Draw probability</dt>
            <dd>0.24%</dd>
          </div>
          <div>
            <dt>Earned to date</dt>
            <dd className="lime">+4.1 ETH</dd>
          </div>
        </dl>
        <div className="position-actions">
          <button type="button">Manage backing</button>
          <button type="button">Withdraw</button>
          <button type="button">Redeem</button>
        </div>
      </section>
      <section className="backer-tip">
        <Crown />
        <div>
          <p>Crown watch</p>
          <strong>Add 42.0 ETH backing to take the NFT Omnipool Crown.</strong>
        </div>
        <button type="button">
          View race <ArrowUpRight />
        </button>
      </section>
    </PageFrame>
  )
}

export function RewardsHub() {
  return (
    <PageFrame eyebrow="Season 01 · 43 days left" title="Rewards move with every draw.">
      <section className="reward-spotlight">
        <div>
          <p>Your season points</p>
          <strong>24,810</strong>
          <span>Top 8% of 12,491 participants</span>
        </div>
        <div className="reward-orb">
          <Sparkles />
          <b>8%</b>
          <small>rank</small>
        </div>
        <button type="button">
          Invite a friend <ArrowUpRight />
        </button>
      </section>
      <div className="reward-stat-grid">
        <Reward icon={Gift} title="$DRAW earned" value="1,248" detail="≈ 0.42 ETH" />
        <Reward
          icon={WalletCards}
          title="Backer rewards"
          value="0.84 ETH"
          detail="Ready to claim"
        />
        <Reward icon={Crown} title="Crown income" value="0.00 ETH" detail="Challenge the Crown" />
      </div>
      <section className="reward-rules">
        <div>
          <Clock3 />
          <strong>Rewards accrue per active position.</strong>
        </div>
        <span>
          Base draw proceeds and eligible markup are distributed equally while your position is in
          the active tree.
        </span>
      </section>
    </PageFrame>
  )
}

export function HowItWorksPage() {
  return (
    <PageFrame eyebrow="The draw protocol" title="A collectible pool with rules you can inspect.">
      <p className="how-lede">
        Each pool settles in one asset. ETH and USDG can both be used across the protocol, but their
        backing, odds, and liabilities never mix inside a pool.
      </p>
      <section className="how-steps" aria-label="How a backed draw works">
        <HowStep icon={Boxes} number="01" title="Deposit a collectible and backing">
          Deposit an NFT into a chosen market with ETH or USDG backing. The protocol mints a
          PositionNFT so ownership, earnings, and withdrawal rights stay with the depositor.
        </HowStep>
        <HowStep icon={Sparkles} number="02" title="Backing sets the draw odds">
          Every active position has inverse-backing weight: lower backing is selected more often;
          deeper backing is likely to stay active longer and earn from more draws.
        </HowStep>
        <HowStep icon={Coins} number="03" title="Pull price is pool-derived">
          A pull costs the pool’s expected value plus a 10% markup. The base expected-value proceeds
          are shared equally among active positions; the markup funds backers, DRAW rewards, the
          Crown, and protocol operations.
        </HowStep>
        <HowStep icon={ShieldCheck} number="04" title="The active tree locks for an epoch">
          A pull locks the committed active set. The market requests verifiable randomness, then
          maps the random target through the committed inverse-backing tree. The proof and tree root
          belong to the pull receipt.
        </HowStep>
        <HowStep icon={BadgeCheck} number="05" title="Reveal the position, then choose">
          After reveal, the receipt holder can keep the collectible, take discounted cash, swap to
          DRAW, or immediately relist the position. There is a 24-hour decision window; forceKeep
          makes the collectible the default if no selection is made.
        </HowStep>
      </section>
      <section className="how-outcomes" aria-labelledby="settlement-outcomes">
        <div className="how-outcomes-heading">
          <p>After the reveal</p>
          <h2 id="settlement-outcomes">Choose how the position settles.</h2>
        </div>
        <div>
          <article>
            <strong>Keep</strong>
            <span>You receive the collectible. The backer receives 99% of backing.</span>
          </article>
          <article>
            <strong>Cash</strong>
            <span>You receive 85% of backing. The collectible returns to its backer.</span>
          </article>
          <article>
            <strong>$DRAW</strong>
            <span>85% of backing is swapped into $DRAW with protected routing.</span>
          </article>
          <article>
            <strong>Relist</strong>
            <span>You become the new backer and choose fresh backing for the position.</span>
          </article>
        </div>
        <small>
          You have 24 hours to decide. After that, anyone can call forceKeep; Keep becomes the
          default outcome.
        </small>
      </section>
      <section className="how-ledger">
        <div>
          <p>For pullers</p>
          <h2>One transparent price, one verifiable result.</h2>
          <span>
            You may pay through ETH or USDG routing, while the chosen market itself remains
            accounted entirely in its settlement asset.
          </span>
        </div>
        <div>
          <p>For backers</p>
          <h2>Your position earns while it remains active.</h2>
          <span>
            Base draw proceeds, cash markup, and DRAW rewards accrue per active position. The
            selected position receives that draw’s share before it leaves the tree.
          </span>
        </div>
      </section>
      <section className="how-currency-note">
        <WalletCards />
        <div>
          <strong>ETH and USDG have isolated ledgers.</strong>
          <p>
            A market chooses ETH or USDG once. Payment routing can convert at the edge, but odds,
            pricing, backing, and settlement never blend currencies inside the probability tree.
          </p>
        </div>
      </section>
    </PageFrame>
  )
}

function HowStep({
  icon: Icon,
  number,
  title,
  children,
}: {
  icon: typeof Boxes
  number: string
  title: string
  children: React.ReactNode
}) {
  return (
    <article>
      <span className="how-step-number">{number}</span>
      <Icon />
      <h2>{title}</h2>
      <p>{children}</p>
    </article>
  )
}

function PageFrame({
  eyebrow,
  title,
  children,
}: {
  eyebrow: string
  title: string
  children: React.ReactNode
}) {
  return (
    <div className="support-page">
      <p className="support-eyebrow">{eyebrow}</p>
      <h1>{title}</h1>
      {children}
    </div>
  )
}
function Reward({
  icon: Icon,
  title,
  value,
  detail,
}: {
  icon: typeof Gift
  title: string
  value: string
  detail: string
}) {
  return (
    <article className="reward-stat">
      <Icon />
      <span>{title}</span>
      <strong>{value}</strong>
      <small>{detail}</small>
    </article>
  )
}

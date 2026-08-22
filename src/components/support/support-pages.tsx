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
          <button type="button">Manage</button>
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
    <PageFrame eyebrow="How it works" title="Back a collectible or pull one">
      <p className="how-lede">
        Each market uses ETH or USDG. It never mixes assets in its backing, odds or settlement
        records.
      </p>
      <section className="how-steps" aria-label="How a backed draw works">
        <HowStep icon={Boxes} number="01" title="Back a collectible">
          Choose a market and deposit an NFT with backing. You receive a PositionNFT that records
          your ownership, earnings and withdrawal rights.
        </HowStep>
        <HowStep icon={Sparkles} number="02" title="Backing sets the selection chance">
          Lower backing gives a position a higher chance of selection. Higher backing usually keeps
          it active for longer, so it can earn from more draws.
        </HowStep>
        <HowStep icon={Coins} number="03" title="Check the price and terms">
          The market shows its price and settlement ratios before you pay. The flagship price is
          expected value plus 2.5%. Active positions share the base proceeds equally.
        </HowStep>
        <HowStep icon={ShieldCheck} number="04" title="Verify the draw">
          The market locks the active positions and requests verifiable randomness. It records the
          proof and committed tree root on the pull receipt.
        </HowStep>
        <HowStep icon={BadgeCheck} number="05" title="Choose an outcome">
          After reveal, you can keep the collectible, take cash, take $DRAW or relist. You have 24
          hours to choose. Keep becomes the default after the deadline.
        </HowStep>
      </section>
      <section className="how-outcomes" aria-labelledby="settlement-outcomes">
        <div className="how-outcomes-heading">
          <p>Flagship market</p>
          <h2 id="settlement-outcomes">Choose an outcome after reveal</h2>
        </div>
        <div>
          <article>
            <strong>Keep the collectible</strong>
            <span>You receive the collectible. The backer receives 99% of its backing.</span>
          </article>
          <article>
            <strong>Take cash</strong>
            <span>You receive 90% of the backing. The collectible returns to its backer.</span>
          </article>
          <article>
            <strong>Take $DRAW</strong>
            <span>The protocol swaps 90% of the backing through a protected route.</span>
          </article>
          <article>
            <strong>Relist the collectible</strong>
            <span>You become the new backer and provide new backing for the position.</span>
          </article>
        </div>
        <small>
          Ratios can vary by market. The market shows them before payment. After 24 hours, anyone
          can call forceKeep and complete the default Keep outcome.
        </small>
      </section>
      <section className="how-ledger">
        <div>
          <p>For pullers</p>
          <h2>See the price before you pay</h2>
          <span>
            You can pay through an approved ETH or USDG route. The market still records everything
            in its chosen settlement asset.
          </span>
        </div>
        <div>
          <p>For backers</p>
          <h2>Earn while your position stays active</h2>
          <span>
            Your active position earns base proceeds, cash markup and $DRAW rewards. It receives its
            final draw share before it leaves the active set.
          </span>
        </div>
      </section>
      <section className="how-currency-note">
        <WalletCards />
        <div>
          <strong>Each market keeps one settlement asset</strong>
          <p>
            A market chooses ETH or USDG when it is created. Routing can convert payment at the
            boundary. It cannot mix currencies in the market's odds, price, backing or settlement.
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
      <h1 tabIndex={-1}>{title}</h1>
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

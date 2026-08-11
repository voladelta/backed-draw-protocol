import { ArrowUpRight, Crown, Gift, Sparkles, Users } from "lucide-react"

export function RewardsPage() {
  const ranks = [
    ["01", "0x71…3F2A", "184,920"],
    ["02", "0xAC…947E", "162,410"],
    ["03", "0x4B…A120", "139,870"],
    ["18", "You", "24,810"],
  ]
  return (
    <main className="content-page rewards-page">
      <div className="page-kicker">Season 01 · 43 days left</div>
      <h1>Rewards</h1>
      <p className="page-lede">Every draw, deposit, and referral moves you forward.</p>
      <section className="reward-hero">
        <div>
          <span>Your season points</span>
          <strong>24,810</strong>
          <p>Top 8% of 12,491 participants</p>
        </div>
        <div className="reward-ring">
          <Sparkles />
          <b>8%</b>
          <small>rank</small>
        </div>
      </section>
      <section className="reward-cards">
        <RewardCard icon={<Gift />} title="$DRAW earned" value="1,248" detail="≈ 0.42 ETH" />
        <RewardCard
          icon={<Users />}
          title="Referral earnings"
          value="0.18 ETH"
          detail="7 active referrals"
        />
        <RewardCard
          icon={<Crown />}
          title="Crown income"
          value="0.00 ETH"
          detail="Take the Crown"
        />
      </section>
      <section className="leaderboard">
        <div className="section-heading">
          <div>
            <span className="eyebrow">Live standings</span>
            <h2>Season leaderboard</h2>
          </div>
          <button className="secondary-action">
            How points work <ArrowUpRight />
          </button>
        </div>
        {ranks.map(([rank, wallet, points]) => (
          <div className={wallet === "You" ? "rank-row is-you" : "rank-row"} key={rank}>
            <b>{rank}</b>
            <span>{wallet}</span>
            <strong>{points} pts</strong>
          </div>
        ))}
      </section>
    </main>
  )
}

function RewardCard({
  icon,
  title,
  value,
  detail,
}: {
  icon: React.ReactNode
  title: string
  value: string
  detail: string
}) {
  return (
    <article className="reward-card">
      <div>{icon}</div>
      <span>{title}</span>
      <strong>{value}</strong>
      <small>{detail}</small>
    </article>
  )
}

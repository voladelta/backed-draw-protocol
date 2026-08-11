import { ArrowUpRight, CircleDollarSign, Crown, Layers3, Plus, WalletCards } from "lucide-react"
import { markets } from "@/data/markets"
import { formatValue } from "@/lib/utils"

export function PortfolioPage({ onExplore }: { onExplore: () => void }) {
  const position = markets[0].positions[2]
  return (
    <main className="content-page">
      <div className="page-kicker">Your vault</div>
      <h1>Portfolio</h1>
      <p className="page-lede">Deposits, earnings, and draw rights in one place.</p>
      <section className="portfolio-summary">
        <div>
          <span>Total position value</span>
          <strong>52.84 ETH</strong>
          <small>≈ $184,940</small>
        </div>
        <div>
          <span>Lifetime earnings</span>
          <strong className="lime">+3.72 ETH</strong>
          <small>Across 146 draws</small>
        </div>
        <button className="primary-action" onClick={onExplore}>
          <Plus size={16} /> Deposit collectible
        </button>
      </section>
      <div className="dashboard-grid">
        <section className="dashboard-panel wide">
          <div className="panel-title">
            <div>
              <span>Active positions</span>
              <h2>1 position earning</h2>
            </div>
            <Layers3 />
          </div>
          <article className="owned-position">
            <img src={position.image} alt={position.name} />
            <div>
              <small>{position.collection}</small>
              <h3>{position.name}</h3>
              <p>
                <span className="live-dot" /> Active · NFT Omnipool
              </p>
            </div>
            <div className="owned-stat">
              <span>Backing</span>
              <strong>{formatValue(position.backing, "ETH")}</strong>
            </div>
            <div className="owned-stat">
              <span>Draw probability</span>
              <strong>{position.probability}%</strong>
            </div>
            <div className="owned-stat">
              <span>Unclaimed</span>
              <strong className="lime">0.84 ETH</strong>
            </div>
            <button className="icon-button">
              <ArrowUpRight />
            </button>
          </article>
        </section>
        <section className="dashboard-panel">
          <div className="panel-title">
            <div>
              <span>Claims</span>
              <h2>Ready to collect</h2>
            </div>
            <CircleDollarSign />
          </div>
          <div className="claim-amount">
            0.84 <small>ETH</small>
          </div>
          <p>Base proceeds and cash markup earned from active draws.</p>
          <button className="secondary-action full">Claim earnings</button>
        </section>
        <section className="dashboard-panel">
          <div className="panel-title">
            <div>
              <span>Protocol rewards</span>
              <h2>$DRAW balance</h2>
            </div>
            <WalletCards />
          </div>
          <div className="claim-amount">
            1,248 <small>DRAW</small>
          </div>
          <p>Purchased with your equal share of market markup.</p>
          <button className="secondary-action full">View rewards</button>
        </section>
        <section className="dashboard-panel wide crown-panel">
          <div className="crown-orb">
            <Crown />
          </div>
          <div>
            <span>Crown watch</span>
            <h2>Go deeper to become the market Crown.</h2>
            <p>The NFT Omnipool Crown currently earns 5% of eligible markup.</p>
          </div>
          <button className="secondary-action">View Crown</button>
        </section>
      </div>
    </main>
  )
}

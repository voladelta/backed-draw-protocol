import {
  createRootRoute,
  createRoute,
  createRouter,
  Outlet,
  RouterProvider,
  useNavigate,
  useRouterState,
} from "@tanstack/react-router"
import { AppShell } from "@/components/shell"
import { PullExperience } from "@/components/pull/pull-experience"
import {
  ActivityPage,
  BackerPage,
  HowItWorksPage,
  PoolsPage,
  RewardsHub,
} from "@/components/support/support-pages"
import { WalletButton } from "@/components/web3/wallet-button"
import { markets } from "@/data/markets"
import { useProtocolStore } from "@/store/use-protocol-store"

function RootLayout() {
  const navigate = useNavigate()
  const pathname = useRouterState({ select: (state) => state.location.pathname })
  const nav = [
    { label: "Pull", href: "/", active: pathname === "/", onClick: () => navigate({ to: "/" }) },
    {
      label: "Pools",
      href: "/pools",
      active: pathname === "/pools",
      onClick: () => navigate({ to: "/pools" }),
    },
    {
      label: "Backer",
      href: "/backer",
      active: pathname === "/backer",
      onClick: () => navigate({ to: "/backer" }),
    },
    {
      label: "Rewards",
      href: "/rewards",
      active: pathname === "/rewards",
      onClick: () => navigate({ to: "/rewards" }),
    },
    {
      label: "How it works",
      href: "/how-it-works",
      active: pathname === "/how-it-works",
      onClick: () => navigate({ to: "/how-it-works" }),
    },
  ]
  return (
    <AppShell mainClassName="app-main" navigation={nav} walletSlot={<WalletButton />}>
      <Outlet />
    </AppShell>
  )
}

function PullRoute() {
  const store = useProtocolStore()
  const market = markets.find((item) => item.id === store.selectedMarketId) ?? markets[0]
  return (
    <PullExperience
      count={store.pullCount}
      market={market}
      onCount={store.setPullCount}
      onMarketChange={store.selectMarket}
      onPaymentAsset={store.setPaymentAsset}
      onReset={store.resetPull}
      onReveal={store.reveal}
      onSettle={store.settle}
      onStage={store.setPullStage}
      paymentAsset={store.paymentAsset}
      revealedPositionId={store.revealedPositionId}
      settlementChoice={store.settlementChoice}
      stage={store.pullStage}
    />
  )
}

function PoolsRoute() {
  const store = useProtocolStore()
  const navigate = useNavigate()
  return (
    <PoolsPage
      onPull={(marketId) => {
        store.openPull(marketId)
        navigate({ to: "/" })
      }}
    />
  )
}
function BackerRoute() {
  const navigate = useNavigate()
  return <BackerPage onPull={() => navigate({ to: "/pools" })} />
}

const rootRoute = createRootRoute({ component: RootLayout })
const indexRoute = createRoute({ getParentRoute: () => rootRoute, path: "/", component: PullRoute })
const poolsRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/pools",
  component: PoolsRoute,
})
const activityRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/activity",
  component: ActivityPage,
})
const backerRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/backer",
  component: BackerRoute,
})
const rewardsRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/rewards",
  component: RewardsHub,
})
const howItWorksRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/how-it-works",
  component: HowItWorksPage,
})
const routeTree = rootRoute.addChildren([
  indexRoute,
  poolsRoute,
  activityRoute,
  backerRoute,
  rewardsRoute,
  howItWorksRoute,
])
const router = createRouter({ routeTree, defaultPreload: "intent", scrollRestoration: true })

declare module "@tanstack/react-router" {
  interface Register {
    router: typeof router
  }
}
export function App() {
  return <RouterProvider router={router} />
}

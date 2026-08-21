import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import { App } from "./App"
import { Web3Provider } from "./web3/web3-provider"
import "./styles.css"

if (import.meta.env.DEV) {
  const stylexStylesheet = document.createElement("link")
  stylexStylesheet.rel = "stylesheet"
  stylexStylesheet.href = "/virtual:stylex.css"
  document.head.append(stylexStylesheet)
  void import("virtual:stylex:css-only")
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <Web3Provider>
      <App />
    </Web3Provider>
  </StrictMode>,
)

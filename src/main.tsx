import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import { App } from "./App"
import { Web3Provider } from "./web3/web3-provider"
import "./styles.css"

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <Web3Provider>
      <App />
    </Web3Provider>
  </StrictMode>,
)

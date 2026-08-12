import { afterEach, describe, expect, it, vi } from "vitest"

const { addConfetti, constructConfetti } = vi.hoisted(() => ({
  addConfetti: vi.fn().mockResolvedValue(undefined),
  constructConfetti: vi.fn(),
}))

vi.mock("js-confetti", () => ({
  default: class MockJSConfetti {
    constructor() {
      constructConfetti()
    }

    addConfetti = addConfetti
  },
}))

afterEach(() => {
  vi.clearAllMocks()
  vi.resetModules()
  vi.unstubAllGlobals()
})

describe("reveal confetti", () => {
  it("reuses one confetti canvas across reveals", async () => {
    vi.stubGlobal("window", {
      matchMedia: vi.fn().mockReturnValue({ matches: false }),
    })
    const { launchRevealConfetti } = await import("./reveal-confetti")

    await launchRevealConfetti()
    await launchRevealConfetti()

    expect(constructConfetti).toHaveBeenCalledTimes(1)
    expect(addConfetti).toHaveBeenCalledTimes(2)
    expect(addConfetti).toHaveBeenCalledWith({
      confettiColors: ["#caff3a", "#eeffd2", "#70b9ff", "#ffffff", "#ffd166"],
      confettiNumber: 140,
      confettiRadius: 6,
    })
  })

  it("does not load confetti when reduced motion is requested", async () => {
    vi.stubGlobal("window", {
      matchMedia: vi.fn().mockReturnValue({ matches: true }),
    })
    const { launchRevealConfetti } = await import("./reveal-confetti")

    await launchRevealConfetti()

    expect(constructConfetti).not.toHaveBeenCalled()
    expect(addConfetti).not.toHaveBeenCalled()
  })
})

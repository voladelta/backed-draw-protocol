import type JSConfetti from "js-confetti"

const confettiByCanvas = new WeakMap<HTMLCanvasElement, Promise<JSConfetti>>()

const getConfetti = (canvas: HTMLCanvasElement) => {
  const existing = confettiByCanvas.get(canvas)
  if (existing) return existing

  const confetti = import("js-confetti").then(
    ({ default: JSConfetti }) => new JSConfetti({ canvas }),
  )
  confettiByCanvas.set(canvas, confetti)
  return confetti
}

export async function launchRevealConfetti(canvas: HTMLCanvasElement) {
  if (
    typeof window === "undefined" ||
    window.matchMedia("(prefers-reduced-motion: reduce)").matches
  ) {
    return
  }

  const confetti = await getConfetti(canvas)
  await confetti.addConfetti({
    confettiColors: ["#caff3a", "#eeffd2", "#70b9ff", "#ffffff", "#ffd166"],
    confettiNumber: 140,
    confettiRadius: 6,
  })
}

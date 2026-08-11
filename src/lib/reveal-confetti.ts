import type JSConfetti from "js-confetti"

let confettiPromise: Promise<JSConfetti> | undefined

const getConfetti = () =>
  (confettiPromise ??= import("js-confetti").then(({ default: JSConfetti }) => new JSConfetti()))

export async function launchRevealConfetti() {
  if (
    typeof window === "undefined" ||
    window.matchMedia("(prefers-reduced-motion: reduce)").matches
  ) {
    return
  }

  const confetti = await getConfetti()
  await confetti.addConfetti({
    confettiColors: ["#caff3a", "#eeffd2", "#70b9ff", "#ffffff", "#ffd166"],
    confettiNumber: 90,
    confettiRadius: 5,
  })
}

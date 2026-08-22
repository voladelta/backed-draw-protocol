export type DeckRelease = {
  commit: boolean
  direction: -1 | 1
  projectedDistance: number
}

export const wrapIndex = (value: number, length: number) => {
  if (length <= 0) return 0
  return ((value % length) + length) % length
}

export const deckOrder = (length: number, activeIndex: number) =>
  Array.from({ length }, (_, offset) => wrapIndex(activeIndex + offset, length))

export const nextDeckIndex = (activeIndex: number, length: number) =>
  wrapIndex(activeIndex + 1, length)

export const projectDrag = (distance: number, velocity: number, projectionSeconds = 0.12) =>
  distance + velocity * projectionSeconds

export const rubberBandDrag = (distance: number, boundary = 72, resistance = 0.35) => {
  const magnitude = Math.abs(distance)
  if (magnitude <= boundary) return distance
  return Math.sign(distance) * (boundary + (magnitude - boundary) * resistance)
}

export function resolveDeckRelease(
  distance: number,
  velocity: number,
  threshold = 72,
): DeckRelease {
  const projectedDistance = projectDrag(distance, velocity)
  const directionSource = Math.abs(velocity) >= 90 ? velocity : distance
  return {
    commit: Math.abs(projectedDistance) >= threshold,
    direction: directionSource < 0 ? -1 : 1,
    projectedDistance,
  }
}

/** Final card order after the two packets have been interleaved left-first. */
export function riffleOrder(length: number) {
  const split = Math.ceil(length / 2)
  const left = Array.from({ length: split }, (_, index) => index)
  const right = Array.from({ length: length - split }, (_, index) => split + index)
  return Array.from({ length }, (_, index) =>
    index % 2 === 0 ? left[Math.floor(index / 2)] : right[Math.floor(index / 2)],
  ).filter((index): index is number => index !== undefined)
}

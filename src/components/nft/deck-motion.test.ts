import { describe, expect, it } from "vitest"
import {
  deckOrder,
  resolveDeckRelease,
  riffleOrder,
  rubberBandDrag,
  wrapIndex,
} from "./deck-motion"

describe("deck order", () => {
  it("wraps the active card and preserves every card exactly once", () => {
    expect(deckOrder(5, 3)).toEqual([3, 4, 0, 1, 2])
    expect(deckOrder(5, -1)).toEqual([4, 0, 1, 2, 3])
    expect(wrapIndex(8, 5)).toBe(3)
  })

  it("creates a stable left-first riffle order for odd and even packs", () => {
    expect(riffleOrder(6)).toEqual([0, 3, 1, 4, 2, 5])
    expect(riffleOrder(5)).toEqual([0, 3, 1, 4, 2])
  })
})

describe("deck release", () => {
  it("returns a short peek to the pack", () => {
    expect(resolveDeckRelease(25, 60)).toMatchObject({ commit: false, direction: 1 })
  })

  it("commits a deliberate drag in either direction", () => {
    expect(resolveDeckRelease(80, 0)).toMatchObject({ commit: true, direction: 1 })
    expect(resolveDeckRelease(-80, 0)).toMatchObject({ commit: true, direction: -1 })
  })

  it("uses projected momentum for a flick", () => {
    expect(resolveDeckRelease(20, 500)).toMatchObject({ commit: true, direction: 1 })
    expect(resolveDeckRelease(-20, -500)).toMatchObject({ commit: true, direction: -1 })
  })
})

describe("deck drag", () => {
  it("tracks the pointer directly inside the commit boundary", () => {
    expect(rubberBandDrag(48)).toBe(48)
    expect(rubberBandDrag(-48)).toBe(-48)
  })

  it("adds resistance beyond the commit boundary", () => {
    expect(rubberBandDrag(112)).toBe(86)
    expect(rubberBandDrag(-112)).toBe(-86)
  })
})

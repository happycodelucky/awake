# Menu Bar Composited NSImage Label

**Date:** 2026-03-08
**Status:** Approved

## Problem

`MenuBarExtra`'s label closure only renders `Image` and `Text` views. Custom views
like `HStack`, `Canvas`, and styled views are silently ignored. The current label
uses an `HStack` containing a styled `Image` and a `Canvas`-based `MenuBarBadge`,
so nothing renders correctly in the menu bar.

## Solution

Composite the mug SF Symbol and optional countdown pill badge into a single
`NSImage`. The `MenuBarExtra` label becomes `Image(nsImage: compositeImage)`.

## Rendering Pipeline

1. **SF Symbol** — `NSImage(systemSymbolName:accessibilityDescription:)` for the
   mug icon. Tinted green when the power assertion is active via drawing with
   `NSColor` lock-focus.

2. **Pill badge** (when `hasSession`) — `NSAttributedString` with rounded bold
   font measures the countdown text. A rounded rect pill is drawn behind it with
   semi-transparent fill, then the text on top.

3. **Compositing** — An `NSImage` sized to fit icon + spacing + pill (or icon
   only). Drawn via `NSGraphicsContext` / `lockFocus`. NOT set as template so
   custom colors are preserved.

4. **Integration** — A computed property on `AwakeMenuBarApp` rebuilds the
   `NSImage` whenever `controller.hasSession`, `controller.menuBarClockText`, or
   `controller.powerAssertionIsActive` change. The label returns
   `Image(nsImage:)`.

## Key Dimensions

| Element         | Value                                          |
|-----------------|------------------------------------------------|
| Icon height     | ~16pt (within ~22pt menu bar)                  |
| Spacing         | ~4pt between icon and pill                     |
| Pill h-padding  | 6pt                                            |
| Pill v-padding  | 2pt                                            |
| Pill radius     | height / 2 (fully rounded)                     |
| Font            | System rounded, 11pt, bold                     |
| Active color    | Green icon, green 16% opacity pill background  |
| Inactive color  | Primary icon, primary 12% opacity pill         |

## File Changes

Only `Sources/AwakeMenuBarApp/AwakeMenuBarApp.swift`:

- Remove `MenuBarBadge` struct
- Add compositing helper (function or extension)
- Simplify `MenuBarExtra` label to `Image(nsImage:)`
- Adapt color computed properties from `Color` to `NSColor`

## Retina Handling

Use `NSImage` representations that respect `backingScaleFactor` of the main
screen, or draw at 2x and let AppKit scale. `NSImage(size:flipped:drawingHandler:)`
is a good fit since it defers drawing and handles scale automatically.

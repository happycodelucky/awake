// MARK: - RacetrackRingShape
// Custom InsettableShape that draws the rounded racetrack used by the timer ring.

import SwiftUI

/// Draws the rounded racetrack path used by the timer ring.
struct RacetrackRingShape: InsettableShape {
  var insetAmount: CGFloat = 0

  /// Produces the racetrack outline fitted to the provided rectangle.
  /// - Parameter rect: The bounding rectangle for the shape.
  /// - Returns: A racetrack-shaped path.
  func path(in rect: CGRect) -> Path {
    let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
    let radius = insetRect.height / 2
    let minX = insetRect.minX
    let maxX = insetRect.maxX
    let minY = insetRect.minY
    let maxY = insetRect.maxY
    let midX = insetRect.midX

    var path = Path()
    path.move(to: CGPoint(x: midX, y: minY))
    path.addLine(to: CGPoint(x: maxX - radius, y: minY))
    path.addArc(
      center: CGPoint(x: maxX - radius, y: insetRect.midY),
      radius: radius,
      startAngle: .degrees(-90),
      endAngle: .degrees(90),
      clockwise: false
    )
    path.addLine(to: CGPoint(x: minX + radius, y: maxY))
    path.addArc(
      center: CGPoint(x: minX + radius, y: insetRect.midY),
      radius: radius,
      startAngle: .degrees(90),
      endAngle: .degrees(270),
      clockwise: false
    )
    path.addLine(to: CGPoint(x: midX, y: minY))
    return path
  }

  /// Returns a copy of the shape inset by the requested amount.
  /// - Parameter amount: The inset distance to apply.
  /// - Returns: A shape with an increased inset.
  func inset(by amount: CGFloat) -> some InsettableShape {
    var copy = self
    copy.insetAmount += amount
    return copy
  }
}

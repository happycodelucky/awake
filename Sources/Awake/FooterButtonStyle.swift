// MARK: - FooterButtonStyle
// Button style for the footer Quit action.

import SwiftUI

/// Styles the footer button with `.regularMaterial` fill, a subtle border,
/// and a press-state scale animation. Used for the Quit action.
struct FooterButtonStyle: ButtonStyle {
  /// Builds the styled footer button body.
  /// - Parameter configuration: The button configuration supplied by SwiftUI.
  /// - Returns: The styled button view.
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 18, weight: .semibold, design: .rounded))
      .frame(maxWidth: .infinity)
      .frame(height: 44)
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(.regularMaterial)
          .opacity(configuration.isPressed ? 0.72 : 1)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .strokeBorder(Color.secondary.opacity(0.12))
      )
      .scaleEffect(configuration.isPressed ? 0.99 : 1)
  }
}

// MARK: - FooterIconButtonStyle
// Button style for square icon buttons in the footer row.

import SwiftUI

/// Styles a square icon button used alongside the footer quit button.
struct FooterIconButtonStyle: ButtonStyle {
  /// Builds the styled icon button body.
  /// - Parameter configuration: The button configuration supplied by SwiftUI.
  /// - Returns: The styled button view.
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 16, weight: .semibold))
      .frame(width: 44, height: 44)
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

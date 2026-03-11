// MARK: - PresetButtonStyle
// Button style for timer preset duration buttons.

import SwiftUI

/// Styles preset duration buttons with `.regularMaterial` fill, a border,
/// and a slightly smaller scale factor (0.985) than the footer for subtlety.
struct PresetButtonStyle: ButtonStyle {
  /// Builds the styled preset button body.
  /// - Parameter configuration: The button configuration supplied by SwiftUI.
  /// - Returns: The styled button view.
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(.regularMaterial)
          .opacity(configuration.isPressed ? 0.72 : 1)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .strokeBorder(Color.secondary.opacity(0.12))
      )
      .scaleEffect(configuration.isPressed ? 0.985 : 1)
  }
}

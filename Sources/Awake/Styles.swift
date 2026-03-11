// MARK: - Styles
// Custom ButtonStyle implementations for presets, footer, and update card actions.

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

/// Styles the Done button shown at the bottom of the settings view.
/// Blue filled background with white text, 44px height, full-width.
struct DoneButtonStyle: ButtonStyle {
  /// Builds the styled Done button body.
  /// - Parameter configuration: The button configuration supplied by SwiftUI.
  /// - Returns: The styled button view.
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 18, weight: .semibold, design: .rounded))
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity)
      .frame(height: 44)
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(Color.blue.opacity(configuration.isPressed ? 0.78 : 1))
      )
      .scaleEffect(configuration.isPressed ? 0.99 : 1)
  }
}

/// Styles the primary action button shown in update notices.
struct UpdateCardPrimaryButtonStyle: ButtonStyle {
  /// Builds the styled primary update button body.
  /// - Parameter configuration: The button configuration supplied by SwiftUI.
  /// - Returns: The styled button view.
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12, weight: .semibold, design: .rounded))
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity)
      .frame(height: 32)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(Color.blue.opacity(configuration.isPressed ? 0.78 : 1))
      )
      .scaleEffect(configuration.isPressed ? 0.99 : 1)
  }
}

/// Styles the secondary action button shown in update notices.
struct UpdateCardSecondaryButtonStyle: ButtonStyle {
  /// Builds the styled secondary update button body.
  /// - Parameter configuration: The button configuration supplied by SwiftUI.
  /// - Returns: The styled button view.
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12, weight: .semibold, design: .rounded))
      .frame(maxWidth: .infinity)
      .frame(height: 32)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(.regularMaterial)
          .opacity(configuration.isPressed ? 0.72 : 1)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(Color.secondary.opacity(0.12))
      )
      .scaleEffect(configuration.isPressed ? 0.99 : 1)
  }
}

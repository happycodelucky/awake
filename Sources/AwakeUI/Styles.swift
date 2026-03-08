import SwiftUI

/// Styles the footer button used for the quit action.
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

/// Styles timer preset buttons in the preset grid.
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

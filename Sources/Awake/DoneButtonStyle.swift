// MARK: - DoneButtonStyle
// Button style for the settings panel Done action.

import SwiftUI

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

// MARK: - Button Styles
// Collection of button styles used throughout the Awake menu bar app.
//
// AGENT: ButtonStyle.makeBody is a plain function, not a View.body property, so
// @Environment property wrappers cannot be used directly on the ButtonStyle struct.
// Each style delegates to a private styled body view (named *StyleBody to avoid
// shadowing the protocol's synthesized Body associated type) that holds
// @Environment(\.designTokens) inside the SwiftUI view graph. This guarantees
// design tokens respond to runtime theme changes just like any other
// environment-reading view.

import SwiftUI

// MARK: - DoneButtonStyle

/// Styles the Done button shown at the bottom of the settings view.
/// Blue filled background with white text, 44px height, full-width.
struct DoneButtonStyle: ButtonStyle {
    /// Builds the styled Done button body.
    /// - Parameter configuration: The button configuration supplied by SwiftUI.
    /// - Returns: The styled button view.
    func makeBody(configuration: Configuration) -> some View {
        DoneStyleBody(configuration: configuration)
    }
    
    /// Environment-aware body for `DoneButtonStyle`.
    /// Reads `\.designTokens` from the view graph so typography updates propagate correctly.
    private struct DoneStyleBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.designTokens) private var designTokens
        
        var body: some View {
            configuration.label
                .font(designTokens.typography.titleLarge)
                .foregroundStyle(designTokens.colors.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(designTokens.colors.accent.opacity(configuration.isPressed ? 0.78 : 1))
                )
                .scaleEffect(configuration.isPressed ? 0.99 : 1)
        }
    }
}



// MARK: - FooterButtonStyle

/// Styles the footer button with `.regularMaterial` fill, a subtle border,
/// and a press-state scale animation. Used for the Quit action.
struct FooterButtonStyle: ButtonStyle {
    /// Builds the styled footer button body.
    /// - Parameter configuration: The button configuration supplied by SwiftUI.
    /// - Returns: The styled button view.
    func makeBody(configuration: Configuration) -> some View {
        FooterStyleBody(configuration: configuration)
    }
    
    /// Environment-aware body for `FooterButtonStyle`.
    /// Reads `\.designTokens` from the view graph so typography updates propagate correctly.
    private struct FooterStyleBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.designTokens) private var designTokens
        
        var body: some View {
            configuration.label
                .font(designTokens.typography.titleLarge)
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
}



// MARK: - FooterIconButtonStyle

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

// MARK: - PresetButtonStyle

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

// MARK: - UpdateCardButtonStyles

/// Styles the primary action button shown in update notices.
struct UpdateCardPrimaryButtonStyle: ButtonStyle {
    /// Builds the styled primary update button body.
    /// - Parameter configuration: The button configuration supplied by SwiftUI.
    /// - Returns: The styled button view.
    func makeBody(configuration: Configuration) -> some View {
        UpdateCardPrimaryStyleBody(configuration: configuration)
    }
    
    /// Environment-aware body for `UpdateCardPrimaryButtonStyle`.
    /// Reads `\.designTokens` from the view graph so typography updates propagate correctly.
    private struct UpdateCardPrimaryStyleBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.designTokens) private var designTokens
        
        var body: some View {
            configuration.label
                .font(designTokens.typography.cardButton)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(configuration.isPressed ? 0.78 : 1))
                )
                .scaleEffect(configuration.isPressed ? 0.99 : 1)
        }
    }
}



/// Styles the secondary action button shown in update notices.
struct UpdateCardSecondaryButtonStyle: ButtonStyle {
    /// Builds the styled secondary update button body.
    /// - Parameter configuration: The button configuration supplied by SwiftUI.
    /// - Returns: The styled button view.
    func makeBody(configuration: Configuration) -> some View {
        UpdateCardSecondaryStyleBody(configuration: configuration)
    }
    
    /// Environment-aware body for `UpdateCardSecondaryButtonStyle`.
    /// Reads `\.designTokens` from the view graph so typography updates propagate correctly.
    private struct UpdateCardSecondaryStyleBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.designTokens) private var designTokens
        
        var body: some View {
            configuration.label
                .font(designTokens.typography.cardButton)
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
}



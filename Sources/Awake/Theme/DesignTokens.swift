// MARK: - Styles
// Button styles have been consolidated into ButtonStyles.swift:
//   DoneButtonStyle
//   FooterButtonStyle
//   FooterIconButtonStyle
//   PresetButtonStyle
//   UpdateCardPrimaryButtonStyle
//   UpdateCardSecondaryButtonStyle

import SwiftUI

struct DesignTokens {
    let colors: ColorTokens
    let typography: TypographyTokens
    let spacing: SpacingTokens
    let buttonStyles: ButtonStyleTokens
    
    // MARK: - Initializer
    
    init(colorScheme: ColorScheme?) {
        switch colorScheme {
        case .light:
            self.colors = ColorTokens.light
        case .dark:
            self.colors = ColorTokens.dark
        default:
            self.colors = ColorTokens.universal
        }
        self.typography = TypographyTokens()
        self.spacing = SpacingTokens.defaults
        self.buttonStyles = ButtonStyleTokens(colors: self.colors, typography: self.typography, spacing: self.spacing)
    }
}

extension DesignTokens {
    static let universal: DesignTokens = DesignTokens(colorScheme: nil)
    static let dark: DesignTokens = universal
    static let light: DesignTokens = universal
}

struct ButtonStyleTokens {
    let colors: ColorTokens
    let typography: TypographyTokens
    let spacing: SpacingTokens

    // Provide access to common button styles
    lazy var footerStyle: FooterButtonStyle = FooterButtonStyle()

    init(colors: ColorTokens, typography: TypographyTokens, spacing: SpacingTokens) {
        self.colors = colors
        self.typography = typography
        self.spacing = spacing
    }
}

struct ColorTokens {
    let primary: Color
    let secondary: Color
    let accent: Color
    let info: Color
    let warning: Color
    let error: Color
    let background: Color
}

extension ColorTokens {
    /// Universal color tokens - defaults for light/dark
    fileprivate static let universal = ColorTokens(
        primary: .primary,
        secondary: .secondary,
        accent: .accentColor,
        info: .blue,
        warning: .orange,
        error: .red,
        background: .clear
    )
    
    /// Light mode color tokens
    fileprivate static let light = universal
    
    /// Dark mode color tokens
    fileprivate static let dark = universal
}

// MARK: - ColorTokens specifics

/// Color toen
extension ColorTokens {
    /// General label color
    var label: Color { primary }
    /// General label secondary color
    var labelSecondary: Color { secondary }

    var elementMaterial: Material { .regular }
    var elementStroke: Color { secondary.opacity(0.12) }
    var elementBackground: Color { .clear }
    var elementHighlightStroke: Color { primary.opacity(0.22) }
    var elementHighlightBackground: Color { .clear }
    
    var infoLabel: Color { primary }
    var infoLabelSecondary: Color { secondary }
    var infoCardStroke: Color { info.opacity(0.24) }
    var infoCardBackground: Color { info.opacity(0.08) }
    var infoCardMaterial: Material { .regular }
    
    var warningLabel: Color { primary }
    var warningLabelSecondary: Color { secondary }
    var warningCardStroke: Color { warning.opacity(0.24) }
    var warningCardBackground: Color { warning.opacity(0.08) }
    var warningCardMaterial: Material { .regular }
}

struct TypographyTokens {
    // MARK: - Display & Hero Level

    /// Large hero display text. Used for prominent time displays and major UI elements.
    /// Example: Timer countdown display (46pt heavy rounded)
    let displayLarge = Font.system(size: 46, weight: .heavy, design: .rounded)

    // MARK: - Title & Heading Hierarchy

    /// Large title for app headers and primary buttons.
    /// Example: "Awake" app title, done/quit button text (18pt semibold rounded)
    let titleLarge = Font.system(size: 18, weight: .semibold, design: .rounded)

    /// Medium title for grid/list item titles.
    /// Example: Preset button titles in the grid (15pt semibold rounded)
    let titleMedium = Font.system(size: 15, weight: .semibold, design: .rounded)

    /// Small title for labels, control headings, and field labels.
    /// Example: Settings toggle labels, port input field label (13pt semibold rounded)
    let titleSmall = Font.system(size: 13, weight: .semibold, design: .rounded)

    // MARK: - Body & Descriptive Text

    /// Regular body text for card content and descriptions.
    /// Example: Preset mode description, update card message (12pt medium rounded)
    let bodyMedium = Font.system(size: 12, weight: .medium, design: .rounded)

    /// Small body text for secondary information and helper text.
    /// Example: Status line, toggle descriptions, coming soon notes (11pt medium rounded)
    let bodySmall = Font.system(size: 12, weight: .regular, design: .rounded)

    // MARK: - Labels & Accents

    /// Large label for status badges and small cards.
    /// Example: Status label above timer ("TIME LEFT" at 12pt bold) (12pt bold rounded)
    let labelLarge = Font.system(size: 12, weight: .bold, design: .rounded)

    /// Medium label for section headers and card titles.
    /// Example: "Presets", "Behavior", "Settings" section headers (11pt semibold rounded)
    let labelMedium = Font.system(size: 11, weight: .semibold, design: .rounded)

    /// Small label for button text and subsection markers.
    /// Example: "More"/"Less" expandable button, subsection headers (10pt bold rounded)
    let labelSmall = Font.system(size: 10, weight: .bold, design: .rounded)

    // MARK: - Card & Component Specific

    /// Card title text for update and warning cards.
    /// Example: "Known Issues", "Likely Causes", update card titles (12pt semibold rounded)
    let cardTitle = Font.system(size: 12, weight: .semibold, design: .rounded)

    /// Button text for card action buttons.
    /// Example: Update and secondary action buttons on cards (12pt semibold rounded)
    let cardButton = Font.system(size: 12, weight: .semibold, design: .rounded)

    /// Body text within card content areas.
    /// Example: Card descriptions, warning disclaimers (11pt medium rounded)
    let cardBody = Font.system(size: 11, weight: .medium, design: .rounded)

    // MARK: - Section Headers

    /// Section header text (typically used with uppercase and tracking).
    /// Example: "Presets", "Update", "Behavior" sections in main menu (11pt semibold rounded)
    /// Note: Apply `.tracking(1.4)` and `.textCase(.uppercase)` modifiers when using
    let sectionHeader = Font.system(size: 11, weight: .semibold, design: .rounded)

    // MARK: - Monospaced (Time Displays)

    /// Large monospaced display for timer countdowns.
    /// Uses monospacedDigit() modifier for consistent digit alignment.
    /// Example: Hero timer display (46pt heavy rounded with monospaced digits)
    let monospaceDisplayLarge = Font.system(size: 46, weight: .heavy, design: .rounded).monospacedDigit()

    /// Small monospaced text for time values in lists and small displays.
    /// Uses monospacedDigit() modifier for consistent digit alignment.
    /// Example: Remaining time in external session rows (11pt medium rounded with monospaced digits)
    let monospaceBodySmall = Font.system(size: 11, weight: .medium, design: .rounded).monospacedDigit()
}

extension TypographyTokens {
    
}

///
struct SpacingTokens {
    let xxs: CGFloat = 2
    let xs: CGFloat = 4
    let sm: CGFloat = 8
    let md: CGFloat = 12
    let lg: CGFloat = 16
    let xl: CGFloat = 24
    let xxl: CGFloat = 32
    
    fileprivate static let defaults = SpacingTokens()
}

import SwiftUI

enum Theme {
    static let background = Color.black
    static let surface = Color.white.opacity(0.08)
    static let surfaceHover = Color.white.opacity(0.14)
    static let text = Color.white
    static let secondaryText = Color.white.opacity(0.55)
    static let tertiaryText = Color.white.opacity(0.3)

    static func accent(for tab: NotchTab) -> Color {
        switch tab {
        case .notes: return Color(red: 1.0, green: 0.82, blue: 0.25)
        case .tasks: return Color(red: 0.35, green: 0.85, blue: 0.5)
        case .pomodoro: return Color(red: 1.0, green: 0.42, blue: 0.35)
        }
    }

    static func accent(for phase: PomodoroPhase) -> Color {
        switch phase {
        case .focus: return accent(for: .pomodoro)
        case .shortBreak: return Color(red: 0.4, green: 0.75, blue: 1.0)
        case .longBreak: return Color(red: 0.65, green: 0.55, blue: 1.0)
        }
    }
}

extension FolderColor {
    var color: Color {
        switch self {
        case .red: return Color(red: 1.0, green: 0.42, blue: 0.40)
        case .orange: return Color(red: 1.0, green: 0.62, blue: 0.28)
        case .yellow: return Color(red: 1.0, green: 0.84, blue: 0.30)
        case .green: return Color(red: 0.38, green: 0.84, blue: 0.50)
        case .teal: return Color(red: 0.30, green: 0.80, blue: 0.80)
        case .blue: return Color(red: 0.40, green: 0.66, blue: 1.0)
        case .purple: return Color(red: 0.70, green: 0.55, blue: 1.0)
        case .pink: return Color(red: 1.0, green: 0.50, blue: 0.75)
        case .gray: return Color(white: 0.62)
        }
    }
}

/// A small, flat icon button used across the panel.
struct IconButton: View {
    let symbol: String
    var help: String = ""
    var tint: Color = Theme.secondaryText
    var size: CGFloat = 13
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(hovering ? Theme.text : tint)
                .frame(width: 26, height: 26)
                .background(hovering ? Theme.surfaceHover : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Clicking an icon must not pull keyboard focus out of a text field.
        .focusable(false)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// A pill-shaped text button.
struct PillButton: View {
    let title: String
    var symbol: String? = nil
    var tint: Color = Theme.text
    var prominent = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .bold)) }
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(prominent ? Color.black : tint)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                prominent ? tint : (hovering ? Theme.surfaceHover : Theme.surface),
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

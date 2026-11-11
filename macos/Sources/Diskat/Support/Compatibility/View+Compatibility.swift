import SwiftUI

// Keep native styles on current macOS and supply fallbacks only where needed.
private struct BigSurProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundColor(.white)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(configuration.isPressed ? 0.65 : 1)))
            .opacity(isEnabled ? 1 : 0.45)
    }
}
extension View {
    @ViewBuilder func compatibleProminentButton() -> some View {
        if #available(macOS 12, *) { buttonStyle(.borderedProminent) }
        else { buttonStyle(BigSurProminentButtonStyle()) }
    }
    @ViewBuilder func compatibleTint(_ color: Color) -> some View {
        if #available(macOS 12, *) { tint(color) } else { accentColor(color) }
    }
    @ViewBuilder func compatibleMonospacedDigit() -> some View {
        if #available(macOS 12, *) { monospacedDigit() } else { self }
    }
    func compatibleOverlay<V: View>(@ViewBuilder content: () -> V) -> some View { overlay(content()) }
    @ViewBuilder func compatibleControlSize(_ size: ControlSize) -> some View {
        if #available(macOS 12, *) { controlSize(size) } else { self }
    }
    @ViewBuilder func compatibleTextSelection() -> some View {
        if #available(macOS 12, *) { textSelection(.enabled) } else { self }
    }
}

struct CompatibleTitleAndIconStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { configuration.icon; configuration.title }
    }
}

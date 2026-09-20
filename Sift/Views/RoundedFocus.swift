import SwiftUI

/// Скругляет системную Tab-обводку под форму кнопки.
/// Не отключает focus effect — иначе на macOS обводка часто пропадает целиком.
struct RoundedKeyboardFocus<Content: View>: View {
    var cornerRadius: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(macOS 14.0, *) {
            content()
                .contentShape(
                    .focusEffect,
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        } else {
            content()
        }
    }
}

struct RoundedFocusButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 12
    var pressedOpacity: Double = 0.88

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func roundedKeyboardFocus(cornerRadius: CGFloat = 12, inset: CGFloat = -3) -> some View {
        // inset сохранён в API для совместимости вызовов; форму задаёт cornerRadius.
        RoundedKeyboardFocus(cornerRadius: cornerRadius) { self }
    }
}

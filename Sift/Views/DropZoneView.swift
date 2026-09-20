import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    let folderName: String?
    let onChoose: () -> Void
    let onClear: () -> Void
    let onDrop: ([NSItemProvider]) -> Bool

    @EnvironmentObject private var l10n: LocalizationManager
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: folderName == nil ? "folder.badge.plus" : "folder.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Theme.accent)

            if let folderName {
                Text(folderName)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    linkButton(l10n.t("drop.change"), action: onChoose)
                    linkButton(l10n.t("drop.clear"), action: onClear, muted: true)
                }
            } else {
                Text(l10n.t("drop.hint"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)

                Text(l10n.t("drop.or"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)

                linkButton(l10n.t("drop.choose"), action: onChoose, emphasized: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isTargeted ? Theme.accentSoft : Theme.row)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isTargeted ? Theme.accent : Theme.line,
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: folderName == nil ? [6, 5] : [])
                )
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted, perform: onDrop)
    }

    private func linkButton(
        _ title: String,
        action: @escaping () -> Void,
        muted: Bool = false,
        emphasized: Bool = false
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: emphasized ? 13 : 12, weight: .semibold))
                .padding(.horizontal, emphasized ? 12 : 10)
                .padding(.vertical, emphasized ? 8 : 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(emphasized ? Theme.accentSoft : Color.clear)
                )
        }
        .buttonStyle(RoundedFocusButtonStyle(cornerRadius: 8))
        .foregroundStyle(muted ? Theme.muted : Theme.accent)
        .roundedKeyboardFocus(cornerRadius: 8, inset: -2)
    }
}

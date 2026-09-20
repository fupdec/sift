import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var model = OrganizerViewModel()
    @State private var ageSettings = AgeSettingsSnapshot.load()
    @State private var showAgeSettings = false
    @State private var showSchedule = false
    @State private var showRemoveAutomation = false
    @State private var automationJob = AutomationStore.loadJob()

    var body: some View {
        GeometryReader { geo in
            // После ignoresSafeArea(top) insets.top — высота ряда светофора / зоны перетаскивания.
            let titlebarHeight = max(geo.safeAreaInsets.top, TitlebarClearance.minimumHeight)

            ZStack {
                background

                HStack(spacing: 0) {
                    sidebar
                        .padding(.top, titlebarHeight)
                        .frame(width: 300)

                    Rectangle()
                        .fill(Theme.line)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)

                    preview
                        .padding(.top, titlebarHeight)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay(alignment: .top) {
                TitlebarClearance(height: titlebarHeight)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showAgeSettings) {
            AgeSettingsSheet(
                settings: $ageSettings,
                isPresented: $showAgeSettings,
                onSave: { model.refresh() }
            )
        }
        .sheet(isPresented: $showSchedule) {
            ScheduleSheet(
                folderURL: model.folderURL,
                folderName: model.folderName.isEmpty ? automationJob.folderName : model.folderName,
                mode: model.folderURL == nil ? automationJob.mode : model.mode,
                includeSubfolders: model.folderURL == nil ? automationJob.includeSubfolders : model.includeSubfolders,
                isPresented: $showSchedule,
                onChange: {
                    automationJob = AutomationStore.loadJob()
                    model.statusMessage = automationJob.lastMessage
                }
            )
        }
        .confirmationDialog("Убрать автоматизацию?", isPresented: $showRemoveAutomation) {
            Button("Убрать", role: .destructive) {
                do {
                    try ScheduleInstaller.remove()
                    automationJob = AutomationStore.loadJob()
                    model.statusMessage = "Сценарий Автоматора и расписание удалены."
                } catch {
                    model.errorMessage = error.localizedDescription
                }
            }
        } message: {
            Text("Сценарий будет удалён из Автоматора, фоновый запуск остановится.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .siftDidAutoOrganize)) { note in
            automationJob = AutomationStore.loadJob()
            if let message = note.object as? String {
                model.statusMessage = message
            }
            if model.folderURL?.path == automationJob.folderPath {
                model.refresh()
            }
        }
        .alert("Много файлов", isPresented: $model.showLargeFolderWarning) {
            Button("Продолжить") { model.confirmLargeScan() }
            Button("Отмена", role: .cancel) { model.cancelLargeScan() }
        } message: {
            Text("Найдено \(model.alertFileCount.formatted()) файлов. Предпросмотр и разбор могут занять заметное время и нагрузить Mac. Продолжить?")
        }
        .alert("Слишком много файлов", isPresented: $model.showHardLimitAlert) {
            Button("OK", role: .cancel) { model.acknowledgeHardLimit() }
        } message: {
            Text("Обнаружено больше \(ScanLimits.hardLimit.formatted()) файлов. Сканирование остановлено. Отключите «включая подпапки» или выберите меньшую папку.")
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [Theme.bgTop, Theme.bgBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sift")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.ink)

                        Text("Разбор файлов по дате или типу")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Theme.muted)
                    }

                    DropZoneView(
                        folderName: model.folderName.isEmpty ? nil : model.folderName,
                        onChoose: model.chooseFolder,
                        onClear: model.clearFolder,
                        onDrop: model.handleDrop
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Как разобрать")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.muted)
                                .textCase(.uppercase)
                                .tracking(0.6)

                            Spacer()

                            Button {
                                showAgeSettings = true
                            } label: {
                                Label("Время", systemImage: "slider.horizontal.3")
                                    .font(.system(size: 11, weight: .semibold))
                                    .labelStyle(.titleAndIcon)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Theme.accentSoft)
                                    .foregroundStyle(Theme.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(RoundedFocusButtonStyle(cornerRadius: 8))
                            .roundedKeyboardFocus(cornerRadius: 8, inset: -2)
                            .help("Настройки порогов давности")
                        }

                        ForEach(SortMode.allCases) { mode in
                            ModeCard(
                                mode: mode,
                                subtitle: mode.subtitle(settings: ageSettings),
                                isSelected: model.mode == mode
                            ) {
                                model.modeChanged(to: mode)
                            }
                        }
                    }

                    Toggle(isOn: $model.includeSubfolders) {
                        Text("Включая подпапки")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .toggleStyle(.switch)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.row.opacity(0.001))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .roundedKeyboardFocus(cornerRadius: 10, inset: -2)
                    .disabled(model.isBusy)
                    .onChange(of: model.includeSubfolders) { _ in
                        model.includeSubfoldersChanged()
                    }

                    AutomationCard(
                        job: automationJob,
                        hasFolder: model.folderURL != nil,
                        onConfigure: { showSchedule = true },
                        onRemove: { showRemoveAutomation = true }
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }

            VStack(alignment: .leading, spacing: 10) {
                if let status = model.statusMessage {
                    Text(status)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let error = model.errorMessage {
                    Text(error)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: model.organize) {
                    HStack {
                        Spacer()
                        if model.isBusy {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Разобрать")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .background(model.canOrganize ? Theme.accent : Theme.accent.opacity(0.35))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(RoundedFocusButtonStyle(cornerRadius: 12))
                .roundedKeyboardFocus(cornerRadius: 12, inset: -3)
                .disabled(!model.canOrganize)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, 4)
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Предпросмотр")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)

                Spacer()

                if model.folderURL != nil {
                    Button {
                        model.refresh()
                    } label: {
                        Text("Обновить")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Theme.accentSoft)
                            )
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(RoundedFocusButtonStyle(cornerRadius: 8))
                    .roundedKeyboardFocus(cornerRadius: 8, inset: -2)
                    .disabled(model.isBusy)
                }
            }

            if model.folderURL == nil {
                emptyState(
                    title: "Папка ещё не выбрана",
                    detail: "Перетащите папку слева или нажмите «Выбрать папку»."
                )
            } else if model.isBusy {
                emptyState(
                    title: "Сканирование…",
                    detail: model.statusMessage ?? "Читаем файлы в фоне, интерфейс не блокируется."
                )
            } else if model.showLargeFolderWarning {
                emptyState(
                    title: "Нужно подтверждение",
                    detail: "Найдено много файлов. Подтвердите действие в диалоге, чтобы продолжить."
                )
            } else if model.plans.isEmpty {
                emptyState(
                    title: "Нечего перемещать",
                    detail: "В этой папке нет файлов под текущие правила, либо они уже на месте."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(model.previewGroups, id: \.name) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Text(group.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.ink)
                                    Text("\(group.total)")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(Theme.chip)
                                        .clipShape(Capsule())
                                        .foregroundStyle(Theme.muted)
                                }

                                ForEach(group.items) { plan in
                                    HStack(spacing: 10) {
                                        Image(systemName: "doc")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(Theme.accent)
                                            .frame(width: 20)

                                        Text(plan.fileName)
                                            .font(.system(size: 13))
                                            .foregroundStyle(Theme.ink)
                                            .lineLimit(1)

                                        Spacer(minLength: 8)

                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Theme.muted.opacity(0.7))

                                        Text(plan.destinationFolder)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(Theme.muted)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(Theme.row)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                        }

                        if model.hiddenPreviewCount > 0 {
                            Text("…и ещё \(model.hiddenPreviewCount.formatted()) файлов в предпросмотре скрыто")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.muted)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func emptyState(title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ModeCard: View {
    let mode: SortMode
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.accent : Theme.muted)
                    .font(.system(size: 16))

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(isSelected ? Theme.accentSoft : Theme.row)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Theme.accent.opacity(0.35) : Theme.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(RoundedFocusButtonStyle(cornerRadius: 12))
        .roundedKeyboardFocus(cornerRadius: 12, inset: -3)
    }
}

struct AgeSettingsSheet: View {
    @Binding var settings: AgeSettingsSnapshot
    @Binding var isPresented: Bool

    @State private var keepUnderDays: Int = 3
    @State private var midSplitDays: Int = 7
    @State private var archiveAfterDays: Int = 30

    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.5)
            Form {
                Section {
                    stepperRow(
                        title: "Оставлять на месте",
                        detail: "Файлы младше этого срока не перемещаются",
                        value: $keepUnderDays,
                        range: 1...365,
                        unit: "дн."
                    )

                    stepperRow(
                        title: "Граница средней папки",
                        detail: "До этого срока → папка «\(midSplitDays) дней»",
                        value: $midSplitDays,
                        range: keepUnderDays...max(keepUnderDays, archiveAfterDays),
                        unit: "дн."
                    )

                    stepperRow(
                        title: "В архив старше",
                        detail: "Файлы старше этого срока → «Архив»",
                        value: $archiveAfterDays,
                        range: (keepUnderDays + 1)...3650,
                        unit: "дн."
                    )
                } header: {
                    Text("Пороги по давности")
                } footer: {
                    Text(summaryText)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 4)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider().opacity(0.5)
            footer
        }
        .frame(width: 440, height: 420)
        .background(Theme.bgTop)
        .onAppear {
            keepUnderDays = settings.keepUnderDays
            midSplitDays = settings.midSplitDays
            archiveAfterDays = settings.archiveAfterDays
        }
        .onChange(of: keepUnderDays) { _ in clampValues() }
        .onChange(of: midSplitDays) { _ in clampValues() }
        .onChange(of: archiveAfterDays) { _ in clampValues() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Настройки времени")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text("Правила для режима «По давности»")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Button {
                keepUnderDays = 3
                midSplitDays = 7
                archiveAfterDays = 30
            } label: {
                Text("Сбросить")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Отмена") {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)
            .buttonStyle(.plain)
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Button("Сохранить") {
                var next = AgeSettingsSnapshot(
                    keepUnderDays: keepUnderDays,
                    midSplitDays: midSplitDays,
                    archiveAfterDays: archiveAfterDays
                )
                next.normalize()
                next.save()
                settings = next
                isPresented = false
                onSave()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(RoundedFocusButtonStyle(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.accent)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .roundedKeyboardFocus(cornerRadius: 10, inset: -2)
        }
        .padding(16)
    }

    private var summaryText: String {
        """
        • младше \(keepUnderDays) дн. — остаются в папке
        • \(keepUnderDays)–\(midSplitDays) дн. → «\(midSplitDays) дней»
        • \(midSplitDays + 1)–\(archiveAfterDays) дн. → «\(archiveAfterDays) дней»
        • старше \(archiveAfterDays) дн. → «Архив»
        """
    }

    private func stepperRow(
        title: String,
        detail: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        unit: String
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text("\(value.wrappedValue) \(unit)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.accent)
                .frame(minWidth: 56, alignment: .trailing)

            Stepper("", value: value, in: range)
                .labelsHidden()
                .frame(width: 80)
        }
        .padding(.vertical, 4)
    }

    private func clampValues() {
        if archiveAfterDays <= keepUnderDays {
            archiveAfterDays = keepUnderDays + 1
        }
        if midSplitDays < keepUnderDays {
            midSplitDays = keepUnderDays
        }
        if midSplitDays > archiveAfterDays {
            midSplitDays = archiveAfterDays
        }
    }
}

enum Theme {
    static let bgTop = Color(red: 0.96, green: 0.97, blue: 0.98)
    static let bgBottom = Color(red: 0.91, green: 0.94, blue: 0.95)
    static let ink = Color(red: 0.12, green: 0.16, blue: 0.20)
    static let muted = Color(red: 0.42, green: 0.48, blue: 0.52)
    static let accent = Color(red: 0.10, green: 0.45, blue: 0.48)
    static let accentSoft = Color(red: 0.10, green: 0.45, blue: 0.48).opacity(0.10)
    static let row = Color.white.opacity(0.72)
    static let chip = Color.black.opacity(0.05)
    static let line = Color.black.opacity(0.06)
    static let danger = Color(red: 0.75, green: 0.22, blue: 0.22)
}

/// Невидимая полоса перетаскивания в зоне светофора. Не участвует в вёрстке колонок —
/// разделитель идёт до края окна, контент начинается сразу под этой полосой.
private struct TitlebarClearance: View {
    static let minimumHeight: CGFloat = 28

    var height: CGFloat

    var body: some View {
        WindowDragHandle()
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
    }
}

/// Позволяет перетаскивать окно за верхнюю зону при hiddenTitleBar.
private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragRegionView {
        DragRegionView()
    }

    func updateNSView(_ nsView: DragRegionView, context: Context) {}
}

private final class DragRegionView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }
}

#Preview {
    ContentView()
}

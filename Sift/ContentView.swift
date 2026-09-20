import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var l10n: LocalizationManager
    @StateObject private var model = OrganizerViewModel()
    @State private var ageSettings = AgeSettingsSnapshot.load()
    @State private var showAgeSettings = false
    @State private var showSchedule = false
    @State private var showRemoveAutomation = false
    @State private var automationJob = AutomationStore.loadJob()

    var body: some View {
        GeometryReader { geo in
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
        .id(l10n.language)
        .sheet(isPresented: $showAgeSettings) {
            AgeSettingsSheet(
                settings: $ageSettings,
                isPresented: $showAgeSettings,
                onSave: { model.refresh() }
            )
            .environmentObject(l10n)
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
            .environmentObject(l10n)
        }
        .confirmationDialog(l10n.t("remove.automation.title"), isPresented: $showRemoveAutomation) {
            Button(l10n.t("action.remove"), role: .destructive) {
                do {
                    try ScheduleInstaller.remove()
                    automationJob = AutomationStore.loadJob()
                    model.statusMessage = l10n.t("remove.automation.done")
                } catch {
                    model.errorMessage = error.localizedDescription
                }
            }
        } message: {
            Text(l10n.t("remove.automation.message"))
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
        .onChange(of: l10n.language) { _ in
            if model.folderURL != nil {
                model.refresh()
            }
        }
        .alert(l10n.t("alert.large.title"), isPresented: $model.showLargeFolderWarning) {
            Button(l10n.t("action.continue")) { model.confirmLargeScan() }
            Button(l10n.t("action.cancel"), role: .cancel) { model.cancelLargeScan() }
        } message: {
            Text(l10n.t("alert.large.message", model.alertFileCount))
        }
        .alert(l10n.t("alert.hard.title"), isPresented: $model.showHardLimitAlert) {
            Button(l10n.t("action.ok"), role: .cancel) { model.acknowledgeHardLimit() }
        } message: {
            Text(l10n.t("alert.hard.message", ScanLimits.hardLimit))
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

                        Text(l10n.t("app.tagline"))
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
                            Text(l10n.t("sort.how"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.muted)
                                .textCase(.uppercase)
                                .tracking(0.6)

                            Spacer()

                            Button {
                                showAgeSettings = true
                            } label: {
                                Label(l10n.t("sort.time"), systemImage: "slider.horizontal.3")
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
                            .help(l10n.t("sort.time.help"))
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
                        Text(l10n.t("sort.include_subfolders"))
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

                    languagePicker
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
                            Text(l10n.t("action.organize"))
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

    private var languagePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.t("language.title"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .textCase(.uppercase)
                .tracking(0.6)

            Picker("", selection: $l10n.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.nativeName).tag(language)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(l10n.t("preview.title"))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)

                Spacer()

                if model.folderURL != nil {
                    Button {
                        model.refresh()
                    } label: {
                        Text(l10n.t("action.refresh"))
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
                    title: l10n.t("preview.empty.title"),
                    detail: l10n.t("preview.empty.detail")
                )
            } else if model.isBusy {
                emptyState(
                    title: l10n.t("preview.scanning.title"),
                    detail: model.statusMessage ?? l10n.t("preview.scanning.detail")
                )
            } else if model.showLargeFolderWarning {
                emptyState(
                    title: l10n.t("preview.confirm.title"),
                    detail: l10n.t("preview.confirm.detail")
                )
            } else if model.plans.isEmpty {
                emptyState(
                    title: l10n.t("preview.nothing.title"),
                    detail: l10n.t("preview.nothing.detail")
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
                            Text(l10n.t("preview.hidden", model.hiddenPreviewCount))
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
    @EnvironmentObject private var l10n: LocalizationManager

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
                        title: l10n.t("age.keep.title"),
                        detail: l10n.t("age.keep.detail"),
                        value: $keepUnderDays,
                        range: 1...365,
                        unit: l10n.t("age.unit")
                    )

                    stepperRow(
                        title: l10n.t("age.mid.title"),
                        detail: l10n.t("age.mid.detail", l10n.daysFolderName(midSplitDays)),
                        value: $midSplitDays,
                        range: keepUnderDays...max(keepUnderDays, archiveAfterDays),
                        unit: l10n.t("age.unit")
                    )

                    stepperRow(
                        title: l10n.t("age.archive.title"),
                        detail: l10n.t("age.archive.detail", l10n.archiveFolderName),
                        value: $archiveAfterDays,
                        range: (keepUnderDays + 1)...3650,
                        unit: l10n.t("age.unit")
                    )
                } header: {
                    Text(l10n.t("age.section"))
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
                Text(l10n.t("age.sheet.title"))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text(l10n.t("age.sheet.subtitle"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Button {
                keepUnderDays = 3
                midSplitDays = 7
                archiveAfterDays = 30
            } label: {
                Text(l10n.t("action.reset"))
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
            Button(l10n.t("action.cancel")) {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)
            .buttonStyle(.plain)
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Button(l10n.t("action.save")) {
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
        l10n.t(
            "age.summary",
            keepUnderDays,
            midSplitDays,
            midSplitDays + 1,
            archiveAfterDays,
            l10n.archiveFolderName
        )
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
        .environmentObject(LocalizationManager.shared)
}

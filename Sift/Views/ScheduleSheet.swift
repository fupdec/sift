import ServiceManagement
import SwiftUI

struct AutomationCard: View {
    let job: AutomationJob
    let hasFolder: Bool
    let onConfigure: () -> Void
    let onRemove: () -> Void

    @EnvironmentObject private var l10n: LocalizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.t("automation.title"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .textCase(.uppercase)
                .tracking(0.6)

            if job.enabled {
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.scheduleSummary)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(l10n.t("automation.card.line", job.folderName, job.mode.title))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                    if let last = job.lastMessage {
                        Text(last)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 12) {
                    Button(l10n.t("action.change"), action: onConfigure)
                    Button(l10n.t("action.remove"), action: onRemove)
                        .foregroundStyle(Theme.danger)
                }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(RoundedFocusButtonStyle(cornerRadius: 8))
                .roundedKeyboardFocus(cornerRadius: 8, inset: -2)
            } else {
                Text(l10n.t("automation.blurb"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onConfigure) {
                    Label(l10n.t("automation.add"), systemImage: "clock.badge.checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Theme.accentSoft)
                        .foregroundStyle(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(RoundedFocusButtonStyle(cornerRadius: 10))
                .roundedKeyboardFocus(cornerRadius: 10, inset: -2)
                .disabled(!hasFolder)
                .help(hasFolder ? l10n.t("automation.add.help") : l10n.t("automation.need_folder.help"))
            }
        }
    }
}

struct ScheduleSheet: View {
    let folderURL: URL?
    let folderName: String
    let mode: SortMode
    let includeSubfolders: Bool
    @Binding var isPresented: Bool
    var onChange: () -> Void

    @EnvironmentObject private var l10n: LocalizationManager
    @State private var frequency: ScheduleFrequency = .daily
    @State private var time = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var weekday = Calendar.current.component(.weekday, from: Date())
    @State private var errorMessage: String?
    @State private var isWorking = false

    private var existing: AutomationJob { AutomationStore.loadJob() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.5)
            Form {
                Section {
                    LabeledContent(l10n.t("schedule.folder")) {
                        Text(folderName.isEmpty ? l10n.t("schedule.folder.none") : folderName)
                            .foregroundStyle(Theme.ink)
                    }
                    LabeledContent(l10n.t("schedule.mode")) {
                        Text(mode.title)
                    }
                    LabeledContent(l10n.t("schedule.subfolders")) {
                        Text(includeSubfolders ? l10n.t("schedule.subfolders.yes") : l10n.t("schedule.subfolders.no"))
                    }
                } header: {
                    Text(l10n.t("schedule.section.what"))
                } footer: {
                    Text(l10n.t("schedule.footer.what"))
                }

                Section {
                    Picker(l10n.t("schedule.frequency"), selection: $frequency) {
                        ForEach(ScheduleFrequency.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }

                    if frequency != .hourly {
                        DatePicker(l10n.t("schedule.time"), selection: $time, displayedComponents: .hourAndMinute)
                    }

                    if frequency == .weekly {
                        Picker(l10n.t("schedule.weekday"), selection: $weekday) {
                            ForEach(orderedWeekdays, id: \.self) { day in
                                Text(AutomationJob.weekdayName(day).capitalized).tag(day)
                            }
                        }
                    }
                } header: {
                    Text(l10n.t("schedule.section.when"))
                } footer: {
                    Text(l10n.t("schedule.footer.when"))
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Theme.danger)
                            .font(.system(size: 12, weight: .medium))
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider().opacity(0.5)
            footer
        }
        .frame(width: 460, height: 520)
        .background(Theme.bgTop)
        .onAppear(perform: loadExisting)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(l10n.t("schedule.sheet.title"))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text(l10n.t("schedule.sheet.subtitle"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
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

            Button {
                save()
            } label: {
                if isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Text(existing.enabled ? l10n.t("action.save") : l10n.t("automation.add"))
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(RoundedFocusButtonStyle(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(canSave ? Theme.accent : Theme.accent.opacity(0.35))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .roundedKeyboardFocus(cornerRadius: 10, inset: -2)
            .disabled(!canSave || isWorking)
        }
        .padding(16)
    }

    private var canSave: Bool {
        folderURL != nil || existing.enabled
    }

    private var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    private func loadExisting() {
        let job = existing
        guard job.enabled else { return }
        frequency = job.frequency
        weekday = job.weekday
        time = Calendar.current.date(bySettingHour: job.hour, minute: job.minute, second: 0, of: Date()) ?? time
    }

    private func save() {
        isWorking = true
        errorMessage = nil
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)

        do {
            let folder = try folderForInstall()
            let started = folder.startAccessingSecurityScopedResource()
            defer {
                if started { folder.stopAccessingSecurityScopedResource() }
            }

            _ = try ScheduleInstaller.install(
                folder: folder,
                mode: mode,
                includeSubfolders: includeSubfolders,
                frequency: frequency,
                hour: components.hour ?? 9,
                minute: components.minute ?? 0,
                weekday: weekday
            )
            if SMAppService.agent(plistName: ScheduleInstaller.bundledAgentPlist).status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
            isWorking = false
            onChange()
            isPresented = false
        } catch {
            isWorking = false
            errorMessage = error.localizedDescription
        }
    }

    private func folderForInstall() throws -> URL {
        if let folderURL { return folderURL }
        return try AutomationStore.resolveFolder()
    }
}

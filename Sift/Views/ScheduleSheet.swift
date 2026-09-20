import ServiceManagement
import SwiftUI

struct AutomationCard: View {
    let job: AutomationJob
    let hasFolder: Bool
    let onConfigure: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Автоматизация")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .textCase(.uppercase)
                .tracking(0.6)

            if job.enabled {
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.scheduleSummary)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("«\(job.folderName)» · \(job.mode.title)")
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
                    Button("Изменить", action: onConfigure)
                    Button("Убрать", action: onRemove)
                        .foregroundStyle(Theme.danger)
                }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(RoundedFocusButtonStyle(cornerRadius: 8))
                .roundedKeyboardFocus(cornerRadius: 8, inset: -2)
            } else {
                Text("Сценарий Автоматора и разбор по расписанию — те же правила, что в окне.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onConfigure) {
                    Label("Добавить в Автоматор", systemImage: "clock.badge.checkmark")
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
                .help(hasFolder ? "Сохранить сценарий и включить расписание" : "Сначала выберите папку")
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
                    LabeledContent("Папка") {
                        Text(folderName.isEmpty ? "не выбрана" : folderName)
                            .foregroundStyle(Theme.ink)
                    }
                    LabeledContent("Режим") {
                        Text(mode.title)
                    }
                    LabeledContent("Подпапки") {
                        Text(includeSubfolders ? "включая" : "только эта папка")
                    }
                } header: {
                    Text("Что будет запускаться")
                } footer: {
                    Text("По расписанию выполняются те же шаги, что кнопка «Разобрать»: сканирование, правила давности или расширения, создание папок и перемещение. Пороги из «Время» берутся актуальные.")
                }

                Section {
                    Picker("Как часто", selection: $frequency) {
                        ForEach(ScheduleFrequency.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }

                    if frequency != .hourly {
                        DatePicker("Время", selection: $time, displayedComponents: .hourAndMinute)
                    }

                    if frequency == .weekly {
                        Picker("День недели", selection: $weekday) {
                            ForEach(orderedWeekdays, id: \.self) { day in
                                Text(AutomationJob.weekdayName(day).capitalized).tag(day)
                            }
                        }
                    }
                } header: {
                    Text("Расписание")
                } footer: {
                    Text("Сценарий появится в Автоматоре (Службы и оповещения Календаря). Запуск идёт в фоне, результат — уведомлением.")
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
            Text("Автоматор и расписание")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text("Разбор выбранной папки без открытия окна")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
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

            Button {
                save()
            } label: {
                if isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Text(existing.enabled ? "Сохранить" : "Добавить в Автоматор")
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

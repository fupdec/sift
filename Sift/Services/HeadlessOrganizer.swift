import Foundation
import UserNotifications

enum HeadlessOrganizer {
    /// Сканирует сохранённую папку и выполняет те же перемещения, что кнопка «Разобрать».
    static func run(scheduled: Bool) async -> String? {
        var job = AutomationStore.loadJob()
        if scheduled {
            guard job.enabled else { return nil }
            guard job.isDue() else { return nil }
        } else {
            guard job.enabled || AutomationStore.loadBookmark() != nil else {
                return "Сначала добавьте папку в Автоматор через Sift."
            }
        }

        do {
            let folder = try AutomationStore.resolveFolder()
            guard folder.startAccessingSecurityScopedResource() else {
                throw AutomationError.noFolderAccess
            }
            defer { folder.stopAccessingSecurityScopedResource() }

            let message = try await organize(
                folder: folder,
                mode: job.mode,
                includeSubfolders: job.includeSubfolders
            )
            job.lastRunAt = Date()
            job.lastMessage = message
            AutomationStore.saveJob(job)
            await notify(message)
            return message
        } catch {
            let message = error.localizedDescription
            job.lastMessage = message
            AutomationStore.saveJob(job)
            await notify(message)
            return message
        }
    }

    private static func organize(
        folder: URL,
        mode: SortMode,
        includeSubfolders: Bool
    ) async throws -> String {
        let ageSettings = AgeSettingsSnapshot.load()

        return try await Task.detached(priority: .userInitiated) {
            let counted = try FolderScanner.countFiles(
                folder: folder,
                includeSubfolders: includeSubfolders,
                limit: ScanLimits.hardLimit
            )
            if counted.hitHardLimit {
                throw AutomationError.tooManyFiles(ScanLimits.hardLimit)
            }

            let scan = try FolderScanner.scan(
                folder: folder,
                includeSubfolders: includeSubfolders,
                limit: ScanLimits.hardLimit
            )
            if scan.hitHardLimit {
                throw AutomationError.tooManyFiles(ScanLimits.hardLimit)
            }

            let plans = FileOrganizer.plan(
                files: scan.files,
                root: folder,
                mode: mode,
                ageSettings: ageSettings
            )
            if plans.isEmpty {
                return "Нечего перемещать в «\(folder.lastPathComponent)»."
            }

            switch FileOrganizer.execute(plans: plans) {
            case .success(let moved, let skipped):
                return "Готово: перемещено \(moved), пропущено \(skipped) — «\(folder.lastPathComponent)»."
            case .failure(let message):
                throw NSError(
                    domain: "Sift",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }
        }.value
    }

    private static func notify(_ message: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Sift"
        content.body = message

        let request = UNNotificationRequest(
            identifier: "sift.auto.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}

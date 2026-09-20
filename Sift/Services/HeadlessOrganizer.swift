import Foundation
import UserNotifications

enum HeadlessOrganizer {
    /// Scans the saved folder and applies the same moves as the Organize button.
    static func run(scheduled: Bool) async -> String? {
        var job = AutomationStore.loadJob()
        let l10n = LocalizationSnapshot(language: AppLanguage.resolveInitial())

        if scheduled {
            guard job.enabled else { return nil }
            guard job.isDue() else { return nil }
        } else {
            guard job.enabled || AutomationStore.loadBookmark() != nil else {
                return l10n.t("auto.need_setup")
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
                includeSubfolders: job.includeSubfolders,
                l10n: l10n
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
        includeSubfolders: Bool,
        l10n: LocalizationSnapshot
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
                ageSettings: ageSettings,
                l10n: l10n
            )
            if plans.isEmpty {
                return l10n.t("auto.nothing", folder.lastPathComponent)
            }

            switch FileOrganizer.execute(plans: plans) {
            case .success(let moved, let skipped):
                return l10n.t("auto.done", moved, skipped, folder.lastPathComponent)
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

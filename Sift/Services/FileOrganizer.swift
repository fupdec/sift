import Foundation

enum FileOrganizer {
    static func plan(
        files: [ScannedFile],
        root: URL,
        mode: SortMode,
        ageSettings: AgeSettingsSnapshot = .default,
        l10n: LocalizationSnapshot
    ) -> [PlannedMove] {
        files.compactMap { file -> PlannedMove? in
            guard let group = groupName(for: file, mode: mode, ageSettings: ageSettings, l10n: l10n) else {
                return nil // stay put (recent)
            }
            let destinationFolder = root.appendingPathComponent(group, isDirectory: true)
            let destination = uniqueDestination(in: destinationFolder, preferredName: file.name, avoiding: file.url)
            return PlannedMove(
                id: file.url,
                source: file.url,
                destination: destination,
                groupName: group
            )
        }
        .filter { $0.source.path != $0.destination.path }
    }

    /// How many files “by age” leaves in place.
    static func keptRecentCount(
        files: [ScannedFile],
        mode: SortMode,
        ageSettings: AgeSettingsSnapshot = .default,
        l10n: LocalizationSnapshot
    ) -> Int {
        guard mode == .byAge else { return 0 }
        return files.reduce(into: 0) { count, file in
            if case .keep = AgeRule.rule(for: file.createdAt, settings: ageSettings, l10n: l10n) {
                count += 1
            }
        }
    }

    static func execute(plans: [PlannedMove]) -> OrganizeResult {
        let fm = FileManager.default
        var moved = 0
        var skipped = 0

        do {
            for plan in plans {
                let folder = plan.destination.deletingLastPathComponent()
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)

                if plan.source.path == plan.destination.path {
                    skipped += 1
                    continue
                }

                if fm.fileExists(atPath: plan.destination.path) {
                    skipped += 1
                    continue
                }

                try fm.moveItem(at: plan.source, to: plan.destination)
                moved += 1
            }
            return .success(moved: moved, skipped: skipped)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private static func groupName(
        for file: ScannedFile,
        mode: SortMode,
        ageSettings: AgeSettingsSnapshot,
        l10n: LocalizationSnapshot
    ) -> String? {
        switch mode {
        case .byAge:
            return AgeRule.rule(for: file.createdAt, settings: ageSettings, l10n: l10n).folderName(using: l10n)
        case .byExtension:
            return extensionFolderName(for: file.fileExtension, l10n: l10n)
        }
    }

    private static func extensionFolderName(for ext: String, l10n: LocalizationSnapshot) -> String {
        switch ext {
        case LocalizationManager.noExtensionToken:
            return l10n.noExtensionFolderName
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "tif", "tiff", "bmp":
            return "Images"
        case "mp4", "mov", "m4v", "avi", "mkv":
            return "Videos"
        case "mp3", "wav", "aac", "flac", "m4a", "aiff":
            return "Audio"
        case "pdf":
            return "PDF"
        case "doc", "docx", "txt", "rtf", "pages", "md", "odt":
            return "Documents"
        case "xls", "xlsx", "csv", "numbers":
            return "Spreadsheets"
        case "ppt", "pptx", "key":
            return "Presentations"
        case "zip", "rar", "7z", "tar", "gz", "dmg":
            return "Archives"
        case "swift", "js", "ts", "tsx", "jsx", "py", "rb", "go", "rs", "java", "kt", "c", "cpp", "h", "m", "mm", "html", "css", "json", "xml", "yml", "yaml", "sh":
            return "Code"
        case "app":
            return "Apps"
        default:
            return ext.uppercased()
        }
    }

    private static func uniqueDestination(in folder: URL, preferredName: String, avoiding source: URL) -> URL {
        let fm = FileManager.default
        let base = (preferredName as NSString).deletingPathExtension
        let ext = (preferredName as NSString).pathExtension

        var candidate = folder.appendingPathComponent(preferredName)
        var index = 2

        while fm.fileExists(atPath: candidate.path), candidate.path != source.path {
            let suffix = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
            candidate = folder.appendingPathComponent(suffix)
            index += 1
        }

        return candidate
    }
}

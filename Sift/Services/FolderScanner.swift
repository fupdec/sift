import Foundation

enum ScanLimits {
    /// Порог, после которого показываем предупреждение.
    static let warningCount = 2_000
    /// Жёсткий потолок: дальше не сканируем, чтобы не повесить приложение.
    static let hardLimit = 10_000
    /// Сколько строк максимум рисуем в предпросмотре.
    static let previewRowLimit = 400
}

struct ScanResult {
    let files: [ScannedFile]
    let hitHardLimit: Bool
}

struct CountResult {
    let count: Int
    let hitHardLimit: Bool
}

enum FolderScanner {
    /// Быстрый подсчёт файлов без чтения дат и построения модели.
    static func countFiles(
        folder: URL,
        includeSubfolders: Bool,
        limit: Int = ScanLimits.hardLimit,
        shouldCancel: @escaping () -> Bool = { false }
    ) throws -> CountResult {
        let enumerator = try makeEnumerator(
            folder: folder,
            includeSubfolders: includeSubfolders,
            resourceKeys: [.isRegularFileKey, .isHiddenKey]
        )

        var count = 0
        for case let fileURL as URL in enumerator {
            if shouldCancel() { throw ScannerError.cancelled }

            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isHiddenKey])
            guard values.isRegularFile == true else { continue }
            if values.isHidden == true { continue }
            if fileURL.lastPathComponent == ".DS_Store" { continue }

            count += 1
            if count > limit {
                return CountResult(count: limit, hitHardLimit: true)
            }
        }

        return CountResult(count: count, hitHardLimit: false)
    }

    static func scan(
        folder: URL,
        includeSubfolders: Bool,
        limit: Int = ScanLimits.hardLimit,
        shouldCancel: @escaping () -> Bool = { false }
    ) throws -> ScanResult {
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isDirectoryKey,
            .creationDateKey,
            .contentModificationDateKey,
            .isHiddenKey
        ]

        let enumerator = try makeEnumerator(
            folder: folder,
            includeSubfolders: includeSubfolders,
            resourceKeys: Array(resourceKeys)
        )

        var files: [ScannedFile] = []
        files.reserveCapacity(min(limit, 1_024))
        var hitHardLimit = false

        for case let fileURL as URL in enumerator {
            if shouldCancel() {
                throw ScannerError.cancelled
            }

            let values = try fileURL.resourceValues(forKeys: resourceKeys)
            guard values.isRegularFile == true else { continue }
            if values.isHidden == true { continue }
            if fileURL.lastPathComponent == ".DS_Store" { continue }

            let created = values.creationDate ?? values.contentModificationDate ?? Date()
            files.append(ScannedFile(url: fileURL, createdAt: created))

            if files.count >= limit {
                hitHardLimit = true
                break
            }
        }

        if shouldCancel() {
            throw ScannerError.cancelled
        }

        files.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return ScanResult(files: files, hitHardLimit: hitHardLimit)
    }

    private static func makeEnumerator(
        folder: URL,
        includeSubfolders: Bool,
        resourceKeys: [URLResourceKey]
    ) throws -> FileManager.DirectoryEnumerator {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ScannerError.notAFolder
        }

        let options: FileManager.DirectoryEnumerationOptions = includeSubfolders
            ? [.skipsHiddenFiles, .skipsPackageDescendants]
            : [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants]

        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: resourceKeys,
            options: options
        ) else {
            throw ScannerError.enumerationFailed
        }

        return enumerator
    }

    enum ScannerError: LocalizedError {
        case notAFolder
        case enumerationFailed
        case cancelled

        var errorDescription: String? {
            switch self {
            case .notAFolder: return "Выбранный путь не является папкой."
            case .enumerationFailed: return "Не удалось прочитать содержимое папки."
            case .cancelled: return nil
            }
        }
    }
}

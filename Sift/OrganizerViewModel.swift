import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func cancel() {
        lock.lock()
        _value = true
        lock.unlock()
    }
}

@MainActor
final class OrganizerViewModel: ObservableObject {
    @Published var folderURL: URL?
    @Published var folderName: String = ""
    @Published var mode: SortMode = .byAge
    @Published var includeSubfolders = false
    @Published var files: [ScannedFile] = []
    @Published var plans: [PlannedMove] = []
    @Published var isBusy = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    @Published var showLargeFolderWarning = false
    @Published var showHardLimitAlert = false
    @Published var alertFileCount = 0
    @Published private(set) var previewGroups: [(name: String, total: Int, items: [PlannedMove])] = []

    private var securityScopedURL: URL?
    private var refreshTask: Task<Void, Never>?
    private var ignoreNextSubfolderToggle = false
    /// Пользователь уже согласился на большой скан для текущей папки + режима подпапок.
    private var largeScanConfirmedKey: String?

    var canOrganize: Bool {
        !plans.isEmpty && !isBusy && folderURL != nil
    }

    var hiddenPreviewCount: Int {
        max(0, plans.count - ScanLimits.previewRowLimit)
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Выбрать"
        panel.message = "Выберите папку для разбора"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        setFolder(url)
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let str = item as? String {
                url = URL(fileURLWithPath: str)
            } else if let value = item as? URL {
                url = value
            } else {
                url = nil
            }

            guard let url else { return }
            Task { @MainActor in
                self.setFolder(url)
            }
        }
        return true
    }

    func setFolder(_ url: URL) {
        releaseSecurityScope()

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            errorMessage = "Нужна именно папка."
            return
        }

        _ = url.startAccessingSecurityScopedResource()
        securityScopedURL = url
        folderURL = url
        folderName = url.lastPathComponent
        errorMessage = nil
        statusMessage = nil
        largeScanConfirmedKey = nil
        clearAlertFlags()
        refresh()
    }

    func includeSubfoldersChanged() {
        if ignoreNextSubfolderToggle {
            ignoreNextSubfolderToggle = false
            return
        }
        largeScanConfirmedKey = nil
        clearAlertFlags()
        refresh()
    }

    func modeChanged(to newMode: SortMode) {
        mode = newMode
        clearAlertFlags()
        refresh()
    }

    func refresh() {
        refreshTask?.cancel()
        clearAlertFlags()

        guard let folderURL else {
            resetResults()
            statusMessage = nil
            return
        }

        let scanRoot = folderURL
        let scanMode = mode
        let scanSubfolders = includeSubfolders
        let confirmationKey = "\(scanRoot.path)|\(scanSubfolders)"
        let alreadyConfirmed = largeScanConfirmedKey == confirmationKey
        let cancelFlag = CancelFlag()

        isBusy = true
        errorMessage = nil
        statusMessage = scanSubfolders
            ? "Подсчёт файлов в папке и подпапках…"
            : "Подсчёт файлов…"

        refreshTask = Task {
            let countOutcome: Result<CountResult, Error> = await withTaskCancellationHandler {
                await Task.detached(priority: .userInitiated) {
                    do {
                        let counted = try FolderScanner.countFiles(
                            folder: scanRoot,
                            includeSubfolders: scanSubfolders,
                            limit: ScanLimits.hardLimit,
                            shouldCancel: { cancelFlag.isCancelled }
                        )
                        return .success(counted)
                    } catch {
                        return .failure(error)
                    }
                }.value
            } onCancel: {
                cancelFlag.cancel()
            }

            guard !Task.isCancelled else { return }

            switch countOutcome {
            case .failure(let error):
                handleScanFailure(error)
                return

            case .success(let counted):
                if counted.hitHardLimit {
                    resetResults()
                    isBusy = false
                    alertFileCount = ScanLimits.hardLimit
                    showHardLimitAlert = true
                    statusMessage = "Слишком много файлов (>\(ScanLimits.hardLimit.formatted()))."
                    return
                }

                if counted.count >= ScanLimits.warningCount, !alreadyConfirmed {
                    resetResults()
                    isBusy = false
                    alertFileCount = counted.count
                    showLargeFolderWarning = true
                    statusMessage = "Найдено \(counted.count.formatted()) файлов — нужно подтверждение."
                    return
                }

                statusMessage = "Сканирование \(counted.count.formatted()) файлов…"
                await performFullScan(
                    root: scanRoot,
                    mode: scanMode,
                    includeSubfolders: scanSubfolders,
                    cancelFlag: cancelFlag
                )
            }
        }
    }

    func confirmLargeScan() {
        guard let folderURL else {
            clearAlertFlags()
            return
        }

        showLargeFolderWarning = false
        largeScanConfirmedKey = "\(folderURL.path)|\(includeSubfolders)"

        let scanRoot = folderURL
        let scanMode = mode
        let scanSubfolders = includeSubfolders
        let cancelFlag = CancelFlag()

        isBusy = true
        statusMessage = "Сканирование \(alertFileCount.formatted()) файлов…"

        refreshTask?.cancel()
        refreshTask = Task {
            await withTaskCancellationHandler {
                await performFullScan(
                    root: scanRoot,
                    mode: scanMode,
                    includeSubfolders: scanSubfolders,
                    cancelFlag: cancelFlag
                )
            } onCancel: {
                cancelFlag.cancel()
            }
        }
    }

    func cancelLargeScan() {
        clearAlertFlags()
        resetResults()
        statusMessage = nil
        largeScanConfirmedKey = nil

        if includeSubfolders {
            ignoreNextSubfolderToggle = true
            includeSubfolders = false
            refresh()
        } else {
            isBusy = false
        }
    }

    func acknowledgeHardLimit() {
        showHardLimitAlert = false
        resetResults()
        largeScanConfirmedKey = nil

        if includeSubfolders {
            ignoreNextSubfolderToggle = true
            includeSubfolders = false
            refresh()
        } else {
            isBusy = false
            statusMessage = "Выберите меньшую папку или отключите подпапки."
        }
    }

    func organize() {
        guard canOrganize else { return }
        let plansSnapshot = plans

        isBusy = true
        statusMessage = "Перемещение файлов…"

        refreshTask?.cancel()
        refreshTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                FileOrganizer.execute(plans: plansSnapshot)
            }.value

            guard !Task.isCancelled else { return }

            switch result {
            case .success(let moved, let skipped):
                errorMessage = nil
                statusMessage = "Готово: перемещено \(moved), пропущено \(skipped)"
                isBusy = false
                refresh()
            case .failure(let message):
                isBusy = false
                errorMessage = message
            }
        }
    }

    func clearFolder() {
        refreshTask?.cancel()
        refreshTask = nil
        releaseSecurityScope()
        folderURL = nil
        folderName = ""
        resetResults()
        statusMessage = nil
        errorMessage = nil
        isBusy = false
        largeScanConfirmedKey = nil
        clearAlertFlags()
    }

    private func performFullScan(
        root: URL,
        mode: SortMode,
        includeSubfolders: Bool,
        cancelFlag: CancelFlag
    ) async {
        let ageSettings = AgeSettingsSnapshot.load()
        let outcome: Result<(files: [ScannedFile], plans: [PlannedMove], hitHardLimit: Bool), Error> =
            await Task.detached(priority: .userInitiated) {
                do {
                    let scan = try FolderScanner.scan(
                        folder: root,
                        includeSubfolders: includeSubfolders,
                        limit: ScanLimits.hardLimit,
                        shouldCancel: { cancelFlag.isCancelled }
                    )
                    let planned = FileOrganizer.plan(
                        files: scan.files,
                        root: root,
                        mode: mode,
                        ageSettings: ageSettings
                    )
                    return .success((scan.files, planned, scan.hitHardLimit))
                } catch {
                    return .failure(error)
                }
            }.value

        guard !Task.isCancelled else { return }

        switch outcome {
        case .failure(let error):
            handleScanFailure(error)

        case .success(let result):
            if result.hitHardLimit {
                resetResults()
                isBusy = false
                alertFileCount = ScanLimits.hardLimit
                showHardLimitAlert = true
                statusMessage = "Слишком много файлов (>\(ScanLimits.hardLimit.formatted()))."
                return
            }
            await applyScan(files: result.files, plans: result.plans)
        }
    }

    private func handleScanFailure(_ error: Error) {
        if let scannerError = error as? FolderScanner.ScannerError,
           case .cancelled = scannerError {
            return
        }
        resetResults()
        isBusy = false
        let description = error.localizedDescription
        if !description.isEmpty {
            errorMessage = description
        }
        statusMessage = nil
    }

    private func applyScan(files: [ScannedFile], plans: [PlannedMove]) async {
        let groups = await Task.detached(priority: .userInitiated) {
            Self.makePreviewGroups(from: plans)
        }.value

        guard !Task.isCancelled else { return }

        self.files = files
        self.plans = plans
        self.previewGroups = groups
        isBusy = false
        errorMessage = nil

        var status = "\(files.count.formatted()) файлов · \(plans.count.formatted()) к перемещению · \(Set(plans.map(\.groupName)).count) папок"
        let kept = FileOrganizer.keptRecentCount(
            files: files,
            mode: mode,
            ageSettings: AgeSettingsSnapshot.load()
        )
        if kept > 0 {
            status += " · \(kept.formatted()) свежих оставлены"
        }
        if plans.count > ScanLimits.previewRowLimit {
            status += " · в списке первые \(ScanLimits.previewRowLimit.formatted())"
        }
        statusMessage = status
    }

    private nonisolated static func makePreviewGroups(
        from plans: [PlannedMove]
    ) -> [(name: String, total: Int, items: [PlannedMove])] {
        let grouped = Dictionary(grouping: plans, by: \.groupName)
            .map { key, value -> (name: String, total: Int, items: [PlannedMove]) in
                let sorted = value.sorted {
                    $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending
                }
                return (name: key, total: sorted.count, items: sorted)
            }
            .sorted(by: previewGroupIsBefore)

        var remaining = ScanLimits.previewRowLimit
        var result: [(name: String, total: Int, items: [PlannedMove])] = []

        for group in grouped {
            if remaining <= 0 { break }
            let slice = Array(group.items.prefix(remaining))
            remaining -= slice.count
            result.append((group.name, group.total, slice))
        }

        return result
    }

    /// «7 дней» → «30 дней» → «Архив»; остальные группы — по имени.
    private nonisolated static func previewGroupIsBefore(
        _ lhs: (name: String, total: Int, items: [PlannedMove]),
        _ rhs: (name: String, total: Int, items: [PlannedMove])
    ) -> Bool {
        let left = previewGroupRank(lhs.name)
        let right = previewGroupRank(rhs.name)
        if left.bucket != right.bucket { return left.bucket < right.bucket }
        if left.days != right.days { return left.days < right.days }
        return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
    }

    private nonisolated static func previewGroupRank(_ name: String) -> (bucket: Int, days: Int, name: String) {
        if name.caseInsensitiveCompare("Архив") == .orderedSame {
            return (2, 0, name)
        }
        let digits = name.prefix { $0.isNumber }
        if let days = Int(digits), !digits.isEmpty {
            return (0, days, name)
        }
        return (1, 0, name)
    }

    private func resetResults() {
        files = []
        plans = []
        previewGroups = []
    }

    private func clearAlertFlags() {
        showLargeFolderWarning = false
        showHardLimitAlert = false
        alertFileCount = 0
    }

    private func releaseSecurityScope() {
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
    }
}

import AppKit
import Foundation
import ServiceManagement
import UserNotifications

enum ScheduleInstaller {
    static let serviceWorkflowName = "Разобрать файлы Sift.workflow"
    static let calendarWorkflowName = "Sift.workflow"
    static let launchAgentLabel = "com.sift.app.schedule"
    static let launchAgentFileName = "com.sift.app.schedule.plist"
    static let bundledAgentPlist = "com.sift.app.schedule.plist"

    @discardableResult
    static func install(
        folder: URL,
        mode: SortMode,
        includeSubfolders: Bool,
        frequency: ScheduleFrequency,
        hour: Int,
        minute: Int,
        weekday: Int
    ) throws -> String {
        let bookmark = try folder.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        try installAutomatorWorkflows()
        try installScheduleAgent()
        requestNotificationPermission()

        AutomationStore.saveBookmark(bookmark)
        var job = AutomationJob(
            enabled: true,
            frequency: frequency,
            hour: hour,
            minute: minute,
            weekday: weekday,
            mode: mode,
            includeSubfolders: includeSubfolders,
            folderName: folder.lastPathComponent,
            folderPath: folder.path,
            installedAt: Date(),
            lastRunAt: Date(),
            lastMessage: nil
        )
        job.lastMessage = "Сценарий добавлен в Автоматор. \(job.scheduleSummary)."
        AutomationStore.saveJob(job)
        return job.lastMessage ?? "Готово"
    }

    static func remove() throws {
        try removeScheduleAgent()
        removeAutomatorWorkflows()
        AutomationStore.clear()
    }

    static func installAutomatorWorkflows() throws {
        let command = "open -g \"sift://organize\""
        let fm = FileManager.default

        let servicesDir = RealHome.url
            .appendingPathComponent("Library/Services", isDirectory: true)
        try fm.createDirectory(at: servicesDir, withIntermediateDirectories: true)
        try writeWorkflow(
            at: servicesDir.appendingPathComponent(serviceWorkflowName, isDirectory: true),
            command: command,
            kind: .quickAction
        )
        NSUpdateDynamicServices()

        let calendarDir = RealHome.url
            .appendingPathComponent("Library/Workflows/Applications/Calendar", isDirectory: true)
        try fm.createDirectory(at: calendarDir, withIntermediateDirectories: true)
        try writeWorkflow(
            at: calendarDir.appendingPathComponent(calendarWorkflowName, isDirectory: true),
            command: command,
            kind: .calendarAlarm
        )
    }

    private static func removeAutomatorWorkflows() {
        let fm = FileManager.default
        let service = RealHome.url
            .appendingPathComponent("Library/Services/\(serviceWorkflowName)", isDirectory: true)
        let calendar = RealHome.url
            .appendingPathComponent("Library/Workflows/Applications/Calendar/\(calendarWorkflowName)", isDirectory: true)
        try? fm.removeItem(at: service)
        try? fm.removeItem(at: calendar)
        NSUpdateDynamicServices()
    }

    private static func installScheduleAgent() throws {
        let service = SMAppService.agent(plistName: bundledAgentPlist)
        switch service.status {
        case .enabled, .requiresApproval:
            try? unloadFallbackLaunchAgent()
            return
        default:
            break
        }

        do {
            try service.register()
            try? unloadFallbackLaunchAgent()
        } catch {
            try installFallbackLaunchAgent()
        }
    }

    private static func removeScheduleAgent() throws {
        try? SMAppService.agent(plistName: bundledAgentPlist).unregister()
        try unloadFallbackLaunchAgent()
    }

    private static func installFallbackLaunchAgent() throws {
        let plistURL = launchAgentURL()
        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let appPath = Bundle.main.bundlePath
        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": [
                "/usr/bin/open",
                "-g",
                "-a",
                appPath,
                "sift://organize?scheduled=1"
            ],
            "StartInterval": 600,
            "RunAtLoad": false
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)
        try launchctl(arguments: ["bootout", "gui/\(getuid())", launchAgentLabel], ignoreFailure: true)
        try launchctl(arguments: ["bootstrap", "gui/\(getuid())", plistURL.path])
    }

    private static func unloadFallbackLaunchAgent() throws {
        try launchctl(arguments: ["bootout", "gui/\(getuid())", launchAgentLabel], ignoreFailure: true)
        try? FileManager.default.removeItem(at: launchAgentURL())
    }

    private static func launchAgentURL() -> URL {
        RealHome.url.appendingPathComponent("Library/LaunchAgents/\(launchAgentFileName)")
    }

    private static func launchctl(arguments: [String], ignoreFailure: Bool = false) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0, !ignoreFailure {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw AutomationError.launchAgentFailed(
                message?.isEmpty == false
                    ? message!
                    : "Не удалось включить расписание. Разрешите Sift в «Настройки → Основные → Объекты входа»."
            )
        }
    }

    private static func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private enum WorkflowKind {
        case quickAction
        case calendarAlarm
    }

    private static func writeWorkflow(at url: URL, command: String, kind: WorkflowKind) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)

        let info: [String: Any]
        switch kind {
        case .quickAction:
            info = [
                "NSServices": [[
                    "NSBackgroundColorName": "background",
                    "NSIconName": "NSActionTemplate",
                    "NSMenuItem": ["default": "Разобрать файлы (Sift)"],
                    "NSMessage": "runWorkflowAsService"
                ]]
            ]
        case .calendarAlarm:
            info = [:] as [String: Any]
        }
        let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try infoData.write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)

        let wflow = makeWorkflowDocument(command: command, kind: kind)
        let wflowData = try PropertyListSerialization.data(fromPropertyList: wflow, format: .xml, options: 0)
        try wflowData.write(to: contents.appendingPathComponent("document.wflow"), options: .atomic)
    }

    private static func makeWorkflowDocument(command: String, kind: WorkflowKind) -> [String: Any] {
        let inputUUID = UUID().uuidString
        let outputUUID = UUID().uuidString
        let actionUUID = UUID().uuidString

        let typeIdentifier: String
        let inputType: String
        switch kind {
        case .quickAction:
            typeIdentifier = "com.apple.Automator.servicesMenu"
            inputType = "com.apple.Automator.nothing"
        case .calendarAlarm:
            typeIdentifier = "com.apple.Automator.calendar"
            inputType = "com.apple.Automator.nothing"
        }

        return [
            "AMApplicationBuild": "533",
            "AMApplicationVersion": "2.10",
            "AMDocumentVersion": "2",
            "actions": [[
                "action": [
                    "AMAccepts": [
                        "Container": "List",
                        "Optional": true,
                        "Types": ["com.apple.cocoa.string"]
                    ],
                    "AMActionVersion": "2.0.3",
                    "AMApplication": ["Automator"],
                    "AMParameterProperties": [
                        "COMMAND_STRING": [:] as [String: Any],
                        "CheckedForUserDefaultShell": [:] as [String: Any],
                        "inputMethod": [:] as [String: Any],
                        "shell": [:] as [String: Any],
                        "source": [:] as [String: Any]
                    ],
                    "AMProvides": [
                        "Container": "List",
                        "Types": ["com.apple.cocoa.string"]
                    ],
                    "ActionBundlePath": "/System/Library/Automator/Run Shell Script.action",
                    "ActionName": "Запустить скрипт оболочки",
                    "ActionParameters": [
                        "COMMAND_STRING": command,
                        "CheckedForUserDefaultShell": true,
                        "inputMethod": 0,
                        "shell": "/bin/zsh",
                        "source": ""
                    ],
                    "BundleIdentifier": "com.apple.RunShellScript",
                    "CFBundleVersion": "2.0.3",
                    "CanShowSelectedItemsWhenRun": false,
                    "CanShowWhenRun": true,
                    "Category": ["AMCategoryUtilities"],
                    "Class Name": "RunShellScriptAction",
                    "InputUUID": inputUUID,
                    "Keywords": ["Оболочка", "Скрипт", "Команда", "Запустить", "Unix"],
                    "OutputUUID": outputUUID,
                    "UUID": actionUUID,
                    "UnlocalizedApplications": ["Automator"],
                    "isViewVisible": 1,
                    "nibPath": "/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib"
                ] as [String: Any],
                "isViewVisible": 1
            ]],
            "connectors": [:] as [String: Any],
            "workflowMetaData": [
                "applicationBundleIDsByPath": [:] as [String: Any],
                "applicationPaths": [] as [String],
                "inputTypeIdentifier": inputType,
                "outputTypeIdentifier": "com.apple.Automator.nothing",
                "presentationMode": 15,
                "processesInput": false,
                "serviceInputTypeIdentifier": inputType,
                "serviceOutputTypeIdentifier": "com.apple.Automator.nothing",
                "serviceProcessesInput": false,
                "systemImageName": "NSActionTemplate",
                "useAutomaticInputType": false,
                "workflowTypeIdentifier": typeIdentifier
            ] as [String: Any]
        ] as [String: Any]
    }
}

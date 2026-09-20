import Foundation

enum ScheduleFrequency: String, Codable, CaseIterable, Identifiable {
    case hourly
    case daily
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hourly: return "Каждый час"
        case .daily: return "Каждый день"
        case .weekly: return "Каждую неделю"
        }
    }
}

struct AutomationJob: Codable, Equatable {
    var enabled: Bool
    var frequency: ScheduleFrequency
    var hour: Int
    var minute: Int
    /// `Calendar` weekday: 1 = воскресенье … 7 = суббота.
    var weekday: Int
    var mode: SortMode
    var includeSubfolders: Bool
    var folderName: String
    var folderPath: String
    var installedAt: Date
    var lastRunAt: Date?
    var lastMessage: String?

    static let disabled = AutomationJob(
        enabled: false,
        frequency: .daily,
        hour: 9,
        minute: 0,
        weekday: Calendar.current.component(.weekday, from: Date()),
        mode: .byAge,
        includeSubfolders: false,
        folderName: "",
        folderPath: "",
        installedAt: Date(),
        lastRunAt: nil,
        lastMessage: nil
    )

    var scheduleSummary: String {
        let time = String(format: "%02d:%02d", hour, minute)
        switch frequency {
        case .hourly:
            return "Каждый час"
        case .daily:
            return "Каждый день в \(time)"
        case .weekly:
            return "Каждый \(Self.weekdayName(weekday)) в \(time)"
        }
    }

    static func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.standaloneWeekdaySymbols
        let index = (weekday - 1) % max(symbols.count, 1)
        guard symbols.indices.contains(index) else { return "день" }
        return symbols[index].lowercased()
    }

    func isDue(at now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard enabled else { return false }
        let reference = lastRunAt ?? installedAt

        switch frequency {
        case .hourly:
            return now.timeIntervalSince(reference) >= 3_600

        case .daily:
            guard let scheduledToday = calendar.date(
                bySettingHour: hour,
                minute: minute,
                second: 0,
                of: now
            ) else { return false }
            return now >= scheduledToday && reference < scheduledToday

        case .weekly:
            guard let occurrence = latestWeeklyOccurrence(onOrBefore: now, calendar: calendar) else {
                return false
            }
            return now >= occurrence && reference < occurrence
        }
    }

    private func latestWeeklyOccurrence(onOrBefore now: Date, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        components.weekday = weekday
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard var date = calendar.date(from: components) else { return nil }
        if date > now {
            date = calendar.date(byAdding: .weekOfYear, value: -1, to: date) ?? date
        }
        return date
    }
}

enum AutomationStore {
    private static let jobKey = "automation.job"
    private static let bookmarkKey = "automation.bookmark"

    static func loadJob() -> AutomationJob {
        guard let data = UserDefaults.standard.data(forKey: jobKey) else {
            return .disabled
        }
        return (try? JSONDecoder().decode(AutomationJob.self, from: data)) ?? .disabled
    }

    static func saveJob(_ job: AutomationJob) {
        if let data = try? JSONEncoder().encode(job) {
            UserDefaults.standard.set(data, forKey: jobKey)
        }
    }

    static func saveBookmark(_ data: Data) {
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    static func loadBookmark() -> Data? {
        UserDefaults.standard.data(forKey: bookmarkKey)
    }

    static func resolveFolder() throws -> URL {
        guard let data = loadBookmark() else {
            throw AutomationError.noBookmark
        }
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        if isStale {
            let refreshed = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            saveBookmark(refreshed)
        }
        return url
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: jobKey)
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }
}

enum AutomationError: LocalizedError {
    case noBookmark
    case noFolderAccess
    case notAFolder
    case tooManyFiles(Int)
    case launchAgentFailed(String)

    var errorDescription: String? {
        switch self {
        case .noBookmark:
            return "Нет сохранённой папки для авторазбора. Добавьте расписание заново."
        case .noFolderAccess:
            return "Нет доступа к сохранённой папке. Откройте Sift и добавьте расписание ещё раз."
        case .notAFolder:
            return "Сохранённый путь больше не является папкой."
        case .tooManyFiles(let limit):
            return "Авторазбор пропущен: больше \(limit.formatted()) файлов."
        case .launchAgentFailed(let message):
            return message
        }
    }
}

enum RealHome {
    static var url: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}

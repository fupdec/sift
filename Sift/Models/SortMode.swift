import Foundation

enum SortMode: String, Codable, CaseIterable, Identifiable {
    case byAge
    case byExtension

    var id: String { rawValue }

    var title: String {
        switch self {
        case .byAge: return "По давности"
        case .byExtension: return "По расширению"
        }
    }

    func subtitle(settings: AgeSettingsSnapshot) -> String {
        switch self {
        case .byAge:
            return settings.subtitle
        case .byExtension:
            return "PDF, Images, Documents и другие"
        }
    }
}

/// Пороги сортировки по давности. Хранятся в UserDefaults.
struct AgeSettingsSnapshot: Equatable {
    var keepUnderDays: Int
    var midSplitDays: Int
    var archiveAfterDays: Int

    static let `default` = AgeSettingsSnapshot(keepUnderDays: 3, midSplitDays: 7, archiveAfterDays: 30)

    private enum Keys {
        static let keepUnderDays = "ageSettings.keepUnderDays"
        static let midSplitDays = "ageSettings.midSplitDays"
        static let archiveAfterDays = "ageSettings.archiveAfterDays"
    }

    var subtitle: String {
        "До \(keepUnderDays) дн. — на месте, до \(archiveAfterDays) — по папкам, старше — Архив"
    }

    static func load() -> AgeSettingsSnapshot {
        let defaults = UserDefaults.standard
        var value = AgeSettingsSnapshot(
            keepUnderDays: defaults.object(forKey: Keys.keepUnderDays) as? Int ?? Self.default.keepUnderDays,
            midSplitDays: defaults.object(forKey: Keys.midSplitDays) as? Int ?? Self.default.midSplitDays,
            archiveAfterDays: defaults.object(forKey: Keys.archiveAfterDays) as? Int ?? Self.default.archiveAfterDays
        )
        value.normalize()
        return value
    }

    func save() {
        var value = self
        value.normalize()
        let defaults = UserDefaults.standard
        defaults.set(value.keepUnderDays, forKey: Keys.keepUnderDays)
        defaults.set(value.midSplitDays, forKey: Keys.midSplitDays)
        defaults.set(value.archiveAfterDays, forKey: Keys.archiveAfterDays)
    }

    mutating func normalize() {
        keepUnderDays = min(max(keepUnderDays, 1), 365)
        archiveAfterDays = min(max(archiveAfterDays, keepUnderDays + 1), 3650)
        midSplitDays = min(max(midSplitDays, keepUnderDays), archiveAfterDays)
    }
}

/// Правила сортировки по давности создания.
enum AgeRule {
    case keep
    case sort(folderName: String)
    case archive

    var folderName: String? {
        switch self {
        case .keep:
            return nil
        case .sort(let folderName):
            return folderName
        case .archive:
            return "Архив"
        }
    }

    static func rule(
        for date: Date,
        settings: AgeSettingsSnapshot,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AgeRule {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0

        if days < settings.keepUnderDays {
            return .keep
        }
        if days > settings.archiveAfterDays {
            return .archive
        }
        if days <= settings.midSplitDays {
            return .sort(folderName: "\(settings.midSplitDays) дней")
        }
        return .sort(folderName: "\(settings.archiveAfterDays) дней")
    }
}

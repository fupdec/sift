import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "en"
    case spanish = "es"
    case chinese = "zh-Hans"
    case russian = "ru"

    var id: String { rawValue }

    /// Name shown in the language picker (native).
    var nativeName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        case .chinese: return "中文"
        case .russian: return "Русский"
        }
    }

    var locale: Locale {
        switch self {
        case .english: return Locale(identifier: "en_US")
        case .spanish: return Locale(identifier: "es_ES")
        case .chinese: return Locale(identifier: "zh_CN")
        case .russian: return Locale(identifier: "ru_RU")
        }
    }

    static func resolveInitial() -> AppLanguage {
        if let saved = UserDefaults.standard.string(forKey: LocalizationManager.storageKey),
           let language = AppLanguage(rawValue: saved) {
            return language
        }
        return .english
    }
}

/// Thread-safe string lookup for a fixed language (safe in `Task.detached`).
struct LocalizationSnapshot: Sendable {
    let language: AppLanguage

    func t(_ key: String) -> String {
        LocalizationManager.string(key, language: language)
    }

    func t(_ key: String, _ args: CVarArg...) -> String {
        let format = t(key)
        return String(format: format, locale: language.locale, arguments: args)
    }

    var archiveFolderName: String { t("folder.archive") }

    func daysFolderName(_ days: Int) -> String {
        t("folder.days", days)
    }

    var noExtensionFolderName: String { t("folder.no_extension") }

    func isArchiveFolderName(_ name: String) -> Bool {
        LocalizationManager.isArchiveFolderName(name)
    }
}

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    static let storageKey = "app.language"

    /// Sentinel stored on scanned files with no extension.
    static let noExtensionToken = "__none__"

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
        }
    }

    var snapshot: LocalizationSnapshot { LocalizationSnapshot(language: language) }

    private init() {
        language = .resolveInitial()
    }

    func t(_ key: String) -> String {
        Self.string(key, language: language)
    }

    func t(_ key: String, _ args: CVarArg...) -> String {
        let format = t(key)
        return String(format: format, locale: language.locale, arguments: args)
    }

    var archiveFolderName: String { t("folder.archive") }

    func daysFolderName(_ days: Int) -> String {
        t("folder.days", days)
    }

    var noExtensionFolderName: String { t("folder.no_extension") }

    nonisolated static func string(_ key: String, language: AppLanguage) -> String {
        table[language]?[key] ?? table[.english]?[key] ?? key
    }

    nonisolated static func isArchiveFolderName(_ name: String) -> Bool {
        AppLanguage.allCases.contains { lang in
            name.caseInsensitiveCompare(table[lang]?["folder.archive"] ?? "Archive") == .orderedSame
        }
    }

    private static let table: [AppLanguage: [String: String]] = [
        .english: english,
        .spanish: spanish,
        .chinese: chinese,
        .russian: russian
    ]

    // MARK: - English (default)

    private static let english: [String: String] = [
        "app.tagline": "Sort files by date or type",
        "language.title": "Language",

        "drop.change": "Change",
        "drop.clear": "Clear",
        "drop.hint": "Drop a folder here",
        "drop.or": "or",
        "drop.choose": "Choose Folder",

        "sort.how": "How to sort",
        "sort.time": "Timing",
        "sort.time.help": "Age threshold settings",
        "sort.by_age": "By age",
        "sort.by_extension": "By extension",
        "sort.by_extension.subtitle": "PDF, Images, Documents, and more",
        "sort.age.subtitle": "Under %d days stay put, up to %d go into folders, older → Archive",
        "sort.include_subfolders": "Include subfolders",

        "action.organize": "Organize",
        "action.refresh": "Refresh",
        "action.cancel": "Cancel",
        "action.save": "Save",
        "action.reset": "Reset",
        "action.continue": "Continue",
        "action.ok": "OK",
        "action.choose": "Choose",
        "action.change": "Edit",
        "action.remove": "Remove",

        "preview.title": "Preview",
        "preview.empty.title": "No folder selected",
        "preview.empty.detail": "Drop a folder on the left or click “Choose Folder”.",
        "preview.scanning.title": "Scanning…",
        "preview.scanning.detail": "Reading files in the background — the UI stays responsive.",
        "preview.confirm.title": "Confirmation needed",
        "preview.confirm.detail": "Many files found. Confirm in the dialog to continue.",
        "preview.nothing.title": "Nothing to move",
        "preview.nothing.detail": "No files match the current rules, or they are already in place.",
        "preview.hidden": "…and %d more files hidden from preview",

        "alert.large.title": "Many files",
        "alert.large.message": "Found %d files. Preview and organizing may take a while and load your Mac. Continue?",
        "alert.hard.title": "Too many files",
        "alert.hard.message": "More than %d files found. Scan stopped. Turn off “Include subfolders” or pick a smaller folder.",

        "remove.automation.title": "Remove automation?",
        "remove.automation.message": "The Automator workflow will be deleted and background runs will stop.",
        "remove.automation.done": "Automator workflow and schedule removed.",

        "age.sheet.title": "Timing settings",
        "age.sheet.subtitle": "Rules for “By age” mode",
        "age.section": "Age thresholds",
        "age.keep.title": "Keep in place",
        "age.keep.detail": "Files younger than this stay put",
        "age.mid.title": "Middle folder boundary",
        "age.mid.detail": "Up to this age → folder “%@”",
        "age.archive.title": "Archive older than",
        "age.archive.detail": "Files older than this → “%@”",
        "age.unit": "d",
        "age.summary": "• under %1$d days — stay in folder\n• %1$d–%2$d days → “%2$d days”\n• %3$d–%4$d days → “%4$d days”\n• older than %4$d days → “%@”",

        "folder.archive": "Archive",
        "folder.days": "%d days",
        "folder.no_extension": "No Extension",

        "panel.choose": "Choose",
        "panel.message": "Choose a folder to organize",
        "error.need_folder": "Please choose a folder.",

        "status.counting_subfolders": "Counting files in folder and subfolders…",
        "status.counting": "Counting files…",
        "status.too_many": "Too many files (>%d).",
        "status.need_confirm": "Found %d files — confirmation needed.",
        "status.scanning": "Scanning %d files…",
        "status.pick_smaller": "Choose a smaller folder or turn off subfolders.",
        "status.moving": "Moving files…",
        "status.done": "Done: moved %d, skipped %d",
        "status.summary": "%d files · %d to move · %d folders",
        "status.kept_fresh": " · %d recent kept",
        "status.preview_cap": " · showing first %d",

        "automation.title": "Automation",
        "automation.blurb": "Automator workflow and scheduled runs — same rules as in the window.",
        "automation.add": "Add to Automator",
        "automation.add.help": "Save workflow and enable schedule",
        "automation.need_folder.help": "Choose a folder first",
        "automation.card.line": "“%@” · %@",

        "schedule.sheet.title": "Automator & schedule",
        "schedule.sheet.subtitle": "Organize the selected folder without opening the window",
        "schedule.section.what": "What will run",
        "schedule.section.when": "Schedule",
        "schedule.folder": "Folder",
        "schedule.folder.none": "not selected",
        "schedule.mode": "Mode",
        "schedule.subfolders": "Subfolders",
        "schedule.subfolders.yes": "included",
        "schedule.subfolders.no": "this folder only",
        "schedule.footer.what": "On schedule, the same steps as “Organize” run: scan, age or extension rules, create folders, and move. Timing thresholds stay current.",
        "schedule.frequency": "How often",
        "schedule.time": "Time",
        "schedule.weekday": "Weekday",
        "schedule.footer.when": "A workflow appears in Automator (Services and Calendar alarms). It runs in the background; results arrive as a notification.",
        "schedule.installed": "Workflow added to Automator. %@.",
        "schedule.done": "Done",
        "schedule.launch_failed": "Could not enable the schedule. Allow Sift in Settings → General → Login Items.",
        "schedule.service_menu": "Organize Files (Sift)",
        "schedule.service_workflow": "Organize Files Sift.workflow",
        "schedule.calendar_workflow": "Sift.workflow",

        "freq.hourly": "Every hour",
        "freq.daily": "Every day",
        "freq.weekly": "Every week",
        "freq.daily_at": "Every day at %@",
        "freq.weekly_at": "Every %@ at %@",
        "freq.day_fallback": "day",

        "auto.no_bookmark": "No saved folder for auto-organize. Add a schedule again.",
        "auto.no_access": "No access to the saved folder. Open Sift and add the schedule again.",
        "auto.not_folder": "The saved path is no longer a folder.",
        "auto.too_many": "Auto-organize skipped: more than %d files.",
        "auto.need_setup": "Add a folder to Automator in Sift first.",
        "auto.nothing": "Nothing to move in “%@”.",
        "auto.done": "Done: moved %d, skipped %d — “%@”.",

        "scan.not_folder": "The selected path is not a folder.",
        "scan.enumeration_failed": "Could not read the folder contents.",

        "info.apple_events": "Sift adds an Automator workflow and organizes files on a schedule.",
    ]

    // MARK: - Spanish

    private static let spanish: [String: String] = [
        "app.tagline": "Organiza archivos por fecha o tipo",
        "language.title": "Idioma",

        "drop.change": "Cambiar",
        "drop.clear": "Quitar",
        "drop.hint": "Suelta una carpeta aquí",
        "drop.or": "o",
        "drop.choose": "Elegir carpeta",

        "sort.how": "Cómo organizar",
        "sort.time": "Tiempo",
        "sort.time.help": "Ajustes de umbrales de antigüedad",
        "sort.by_age": "Por antigüedad",
        "sort.by_extension": "Por extensión",
        "sort.by_extension.subtitle": "PDF, Images, Documents y más",
        "sort.age.subtitle": "Menos de %d días se quedan; hasta %d van a carpetas; más viejos → Archivo",
        "sort.include_subfolders": "Incluir subcarpetas",

        "action.organize": "Organizar",
        "action.refresh": "Actualizar",
        "action.cancel": "Cancelar",
        "action.save": "Guardar",
        "action.reset": "Restablecer",
        "action.continue": "Continuar",
        "action.ok": "OK",
        "action.choose": "Elegir",
        "action.change": "Editar",
        "action.remove": "Quitar",

        "preview.title": "Vista previa",
        "preview.empty.title": "Aún no hay carpeta",
        "preview.empty.detail": "Suelta una carpeta a la izquierda o pulsa “Elegir carpeta”.",
        "preview.scanning.title": "Escaneando…",
        "preview.scanning.detail": "Leyendo archivos en segundo plano; la interfaz no se bloquea.",
        "preview.confirm.title": "Se necesita confirmación",
        "preview.confirm.detail": "Hay muchos archivos. Confirma en el diálogo para continuar.",
        "preview.nothing.title": "Nada que mover",
        "preview.nothing.detail": "Ningún archivo cumple las reglas actuales, o ya están en su sitio.",
        "preview.hidden": "…y %d archivos más ocultos en la vista previa",

        "alert.large.title": "Muchos archivos",
        "alert.large.message": "Se encontraron %d archivos. La vista previa y la organización pueden tardar y cargar el Mac. ¿Continuar?",
        "alert.hard.title": "Demasiados archivos",
        "alert.hard.message": "Más de %d archivos. Escaneo detenido. Desactiva “Incluir subcarpetas” o elige una carpeta más pequeña.",

        "remove.automation.title": "¿Quitar automatización?",
        "remove.automation.message": "Se eliminará el flujo de Automator y se detendrán las ejecuciones en segundo plano.",
        "remove.automation.done": "Flujo de Automator y programación eliminados.",

        "age.sheet.title": "Ajustes de tiempo",
        "age.sheet.subtitle": "Reglas del modo “Por antigüedad”",
        "age.section": "Umbrales de antigüedad",
        "age.keep.title": "Dejar en su sitio",
        "age.keep.detail": "Los archivos más recientes que esto no se mueven",
        "age.mid.title": "Límite de carpeta media",
        "age.mid.detail": "Hasta esta edad → carpeta “%@”",
        "age.archive.title": "Archivar mayores de",
        "age.archive.detail": "Archivos más viejos → “%@”",
        "age.unit": "d",
        "age.summary": "• menos de %1$d días — se quedan\n• %1$d–%2$d días → “%2$d días”\n• %3$d–%4$d días → “%4$d días”\n• más de %4$d días → “%@”",

        "folder.archive": "Archivo",
        "folder.days": "%d días",
        "folder.no_extension": "Sin extensión",

        "panel.choose": "Elegir",
        "panel.message": "Elige una carpeta para organizar",
        "error.need_folder": "Necesitas una carpeta.",

        "status.counting_subfolders": "Contando archivos en la carpeta y subcarpetas…",
        "status.counting": "Contando archivos…",
        "status.too_many": "Demasiados archivos (>%d).",
        "status.need_confirm": "Se encontraron %d archivos — se necesita confirmación.",
        "status.scanning": "Escaneando %d archivos…",
        "status.pick_smaller": "Elige una carpeta más pequeña o desactiva subcarpetas.",
        "status.moving": "Moviendo archivos…",
        "status.done": "Listo: movidos %d, omitidos %d",
        "status.summary": "%d archivos · %d a mover · %d carpetas",
        "status.kept_fresh": " · %d recientes dejados",
        "status.preview_cap": " · mostrando los primeros %d",

        "automation.title": "Automatización",
        "automation.blurb": "Flujo de Automator y ejecución programada — las mismas reglas que en la ventana.",
        "automation.add": "Añadir a Automator",
        "automation.add.help": "Guardar flujo y activar programación",
        "automation.need_folder.help": "Elige una carpeta primero",
        "automation.card.line": "“%@” · %@",

        "schedule.sheet.title": "Automator y programación",
        "schedule.sheet.subtitle": "Organiza la carpeta sin abrir la ventana",
        "schedule.section.what": "Qué se ejecutará",
        "schedule.section.when": "Programación",
        "schedule.folder": "Carpeta",
        "schedule.folder.none": "no seleccionada",
        "schedule.mode": "Modo",
        "schedule.subfolders": "Subcarpetas",
        "schedule.subfolders.yes": "incluidas",
        "schedule.subfolders.no": "solo esta carpeta",
        "schedule.footer.what": "Según la programación se ejecutan los mismos pasos que “Organizar”: escaneo, reglas de antigüedad o extensión, crear carpetas y mover. Los umbrales de Tiempo se usan actualizados.",
        "schedule.frequency": "Con qué frecuencia",
        "schedule.time": "Hora",
        "schedule.weekday": "Día de la semana",
        "schedule.footer.when": "Aparece un flujo en Automator (Servicios y alarmas de Calendario). Corre en segundo plano; el resultado llega como notificación.",
        "schedule.installed": "Flujo añadido a Automator. %@.",
        "schedule.done": "Listo",
        "schedule.launch_failed": "No se pudo activar la programación. Permite Sift en Ajustes → General → Elementos de inicio.",
        "schedule.service_menu": "Organizar archivos (Sift)",
        "schedule.service_workflow": "Organizar archivos Sift.workflow",
        "schedule.calendar_workflow": "Sift.workflow",

        "freq.hourly": "Cada hora",
        "freq.daily": "Cada día",
        "freq.weekly": "Cada semana",
        "freq.daily_at": "Cada día a las %@",
        "freq.weekly_at": "Cada %@ a las %@",
        "freq.day_fallback": "día",

        "auto.no_bookmark": "No hay carpeta guardada para autoorganización. Vuelve a añadir la programación.",
        "auto.no_access": "Sin acceso a la carpeta guardada. Abre Sift y vuelve a añadir la programación.",
        "auto.not_folder": "La ruta guardada ya no es una carpeta.",
        "auto.too_many": "Autoorganización omitida: más de %d archivos.",
        "auto.need_setup": "Primero añade una carpeta a Automator en Sift.",
        "auto.nothing": "Nada que mover en “%@”.",
        "auto.done": "Listo: movidos %d, omitidos %d — “%@”.",

        "scan.not_folder": "La ruta seleccionada no es una carpeta.",
        "scan.enumeration_failed": "No se pudo leer el contenido de la carpeta.",

        "info.apple_events": "Sift añade un flujo de Automator y organiza archivos según un horario.",
    ]

    // MARK: - Chinese (Simplified)

    private static let chinese: [String: String] = [
        "app.tagline": "按日期或类型整理文件",
        "language.title": "语言",

        "drop.change": "更换",
        "drop.clear": "清除",
        "drop.hint": "将文件夹拖到此处",
        "drop.or": "或",
        "drop.choose": "选择文件夹",

        "sort.how": "整理方式",
        "sort.time": "时间",
        "sort.time.help": "新旧阈值设置",
        "sort.by_age": "按新旧",
        "sort.by_extension": "按扩展名",
        "sort.by_extension.subtitle": "PDF、Images、Documents 等",
        "sort.age.subtitle": "%d 天内保留；至 %d 天归入文件夹；更旧 → 归档",
        "sort.include_subfolders": "包含子文件夹",

        "action.organize": "整理",
        "action.refresh": "刷新",
        "action.cancel": "取消",
        "action.save": "保存",
        "action.reset": "重置",
        "action.continue": "继续",
        "action.ok": "好",
        "action.choose": "选择",
        "action.change": "更改",
        "action.remove": "移除",

        "preview.title": "预览",
        "preview.empty.title": "尚未选择文件夹",
        "preview.empty.detail": "将文件夹拖到左侧，或点击“选择文件夹”。",
        "preview.scanning.title": "正在扫描…",
        "preview.scanning.detail": "在后台读取文件，界面不会卡住。",
        "preview.confirm.title": "需要确认",
        "preview.confirm.detail": "文件很多。请在对话框中确认以继续。",
        "preview.nothing.title": "无需移动",
        "preview.nothing.detail": "没有符合当前规则的文件，或它们已在正确位置。",
        "preview.hidden": "…预览中还隐藏了 %d 个文件",

        "alert.large.title": "文件很多",
        "alert.large.message": "找到 %d 个文件。预览和整理可能较慢并加重 Mac 负担。继续吗？",
        "alert.hard.title": "文件过多",
        "alert.hard.message": "超过 %d 个文件。扫描已停止。请关闭“包含子文件夹”或选择更小的文件夹。",

        "remove.automation.title": "移除自动化？",
        "remove.automation.message": "将删除 Automator 流程并停止后台运行。",
        "remove.automation.done": "已删除 Automator 流程和计划。",

        "age.sheet.title": "时间设置",
        "age.sheet.subtitle": "“按新旧”模式的规则",
        "age.section": "新旧阈值",
        "age.keep.title": "保留在原处",
        "age.keep.detail": "新于此期限的文件不移动",
        "age.mid.title": "中间文件夹边界",
        "age.mid.detail": "不晚于此 → 文件夹“%@”",
        "age.archive.title": "归档早于",
        "age.archive.detail": "更早的文件 → “%@”",
        "age.unit": "天",
        "age.summary": "• 少于 %1$d 天 — 留在原文件夹\n• %1$d–%2$d 天 → “%2$d 天”\n• %3$d–%4$d 天 → “%4$d 天”\n• 超过 %4$d 天 → “%@”",

        "folder.archive": "归档",
        "folder.days": "%d 天",
        "folder.no_extension": "无扩展名",

        "panel.choose": "选择",
        "panel.message": "选择要整理的文件夹",
        "error.need_folder": "请选择文件夹。",

        "status.counting_subfolders": "正在统计文件夹及子文件夹中的文件…",
        "status.counting": "正在统计文件…",
        "status.too_many": "文件过多（>%d）。",
        "status.need_confirm": "找到 %d 个文件 — 需要确认。",
        "status.scanning": "正在扫描 %d 个文件…",
        "status.pick_smaller": "请选择更小的文件夹或关闭子文件夹。",
        "status.moving": "正在移动文件…",
        "status.done": "完成：已移动 %d，跳过 %d",
        "status.summary": "%d 个文件 · %d 待移动 · %d 个文件夹",
        "status.kept_fresh": " · 保留 %d 个较新文件",
        "status.preview_cap": " · 列表显示前 %d 个",

        "automation.title": "自动化",
        "automation.blurb": "Automator 流程与按计划整理 — 规则与窗口中相同。",
        "automation.add": "添加到 Automator",
        "automation.add.help": "保存流程并启用计划",
        "automation.need_folder.help": "请先选择文件夹",
        "automation.card.line": "“%@” · %@",

        "schedule.sheet.title": "Automator 与计划",
        "schedule.sheet.subtitle": "无需打开窗口即可整理所选文件夹",
        "schedule.section.what": "将运行的内容",
        "schedule.section.when": "计划",
        "schedule.folder": "文件夹",
        "schedule.folder.none": "未选择",
        "schedule.mode": "模式",
        "schedule.subfolders": "子文件夹",
        "schedule.subfolders.yes": "包含",
        "schedule.subfolders.no": "仅此文件夹",
        "schedule.footer.what": "按计划执行与“整理”相同的步骤：扫描、新旧或扩展名规则、创建文件夹并移动。时间阈值始终使用最新设置。",
        "schedule.frequency": "频率",
        "schedule.time": "时间",
        "schedule.weekday": "星期",
        "schedule.footer.when": "流程会出现在 Automator（服务与日历提醒）中。在后台运行，结果以通知显示。",
        "schedule.installed": "已将流程添加到 Automator。%@。",
        "schedule.done": "完成",
        "schedule.launch_failed": "无法启用计划。请在“设置 → 通用 → 登录项”中允许 Sift。",
        "schedule.service_menu": "整理文件 (Sift)",
        "schedule.service_workflow": "整理文件 Sift.workflow",
        "schedule.calendar_workflow": "Sift.workflow",

        "freq.hourly": "每小时",
        "freq.daily": "每天",
        "freq.weekly": "每周",
        "freq.daily_at": "每天 %@",
        "freq.weekly_at": "每%@ %@",
        "freq.day_fallback": "天",

        "auto.no_bookmark": "没有用于自动整理的已保存文件夹。请重新添加计划。",
        "auto.no_access": "无法访问已保存的文件夹。请打开 Sift 并重新添加计划。",
        "auto.not_folder": "已保存的路径不再是文件夹。",
        "auto.too_many": "已跳过自动整理：超过 %d 个文件。",
        "auto.need_setup": "请先在 Sift 中将文件夹添加到 Automator。",
        "auto.nothing": "“%@” 中无需移动。",
        "auto.done": "完成：已移动 %d，跳过 %d — “%@”。",

        "scan.not_folder": "所选路径不是文件夹。",
        "scan.enumeration_failed": "无法读取文件夹内容。",

        "info.apple_events": "Sift 会添加 Automator 流程，并按计划整理文件。",
    ]

    // MARK: - Russian

    private static let russian: [String: String] = [
        "app.tagline": "Разбор файлов по дате или типу",
        "language.title": "Язык",

        "drop.change": "Сменить",
        "drop.clear": "Сбросить",
        "drop.hint": "Перетащите папку сюда",
        "drop.or": "или",
        "drop.choose": "Выбрать папку",

        "sort.how": "Как разобрать",
        "sort.time": "Время",
        "sort.time.help": "Настройки порогов давности",
        "sort.by_age": "По давности",
        "sort.by_extension": "По расширению",
        "sort.by_extension.subtitle": "PDF, Images, Documents и другие",
        "sort.age.subtitle": "До %d дн. — на месте, до %d — по папкам, старше — Архив",
        "sort.include_subfolders": "Включая подпапки",

        "action.organize": "Разобрать",
        "action.refresh": "Обновить",
        "action.cancel": "Отмена",
        "action.save": "Сохранить",
        "action.reset": "Сбросить",
        "action.continue": "Продолжить",
        "action.ok": "OK",
        "action.choose": "Выбрать",
        "action.change": "Изменить",
        "action.remove": "Убрать",

        "preview.title": "Предпросмотр",
        "preview.empty.title": "Папка ещё не выбрана",
        "preview.empty.detail": "Перетащите папку слева или нажмите «Выбрать папку».",
        "preview.scanning.title": "Сканирование…",
        "preview.scanning.detail": "Читаем файлы в фоне, интерфейс не блокируется.",
        "preview.confirm.title": "Нужно подтверждение",
        "preview.confirm.detail": "Найдено много файлов. Подтвердите действие в диалоге, чтобы продолжить.",
        "preview.nothing.title": "Нечего перемещать",
        "preview.nothing.detail": "В этой папке нет файлов под текущие правила, либо они уже на месте.",
        "preview.hidden": "…и ещё %d файлов в предпросмотре скрыто",

        "alert.large.title": "Много файлов",
        "alert.large.message": "Найдено %d файлов. Предпросмотр и разбор могут занять заметное время и нагрузить Mac. Продолжить?",
        "alert.hard.title": "Слишком много файлов",
        "alert.hard.message": "Обнаружено больше %d файлов. Сканирование остановлено. Отключите «включая подпапки» или выберите меньшую папку.",

        "remove.automation.title": "Убрать автоматизацию?",
        "remove.automation.message": "Сценарий будет удалён из Автоматора, фоновый запуск остановится.",
        "remove.automation.done": "Сценарий Автоматора и расписание удалены.",

        "age.sheet.title": "Настройки времени",
        "age.sheet.subtitle": "Правила для режима «По давности»",
        "age.section": "Пороги по давности",
        "age.keep.title": "Оставлять на месте",
        "age.keep.detail": "Файлы младше этого срока не перемещаются",
        "age.mid.title": "Граница средней папки",
        "age.mid.detail": "До этого срока → папка «%@»",
        "age.archive.title": "В архив старше",
        "age.archive.detail": "Файлы старше этого срока → «%@»",
        "age.unit": "дн.",
        "age.summary": "• младше %1$d дн. — остаются в папке\n• %1$d–%2$d дн. → «%2$d дней»\n• %3$d–%4$d дн. → «%4$d дней»\n• старше %4$d дн. → «%@»",

        "folder.archive": "Архив",
        "folder.days": "%d дней",
        "folder.no_extension": "Без расширения",

        "panel.choose": "Выбрать",
        "panel.message": "Выберите папку для разбора",
        "error.need_folder": "Нужна именно папка.",

        "status.counting_subfolders": "Подсчёт файлов в папке и подпапках…",
        "status.counting": "Подсчёт файлов…",
        "status.too_many": "Слишком много файлов (>%d).",
        "status.need_confirm": "Найдено %d файлов — нужно подтверждение.",
        "status.scanning": "Сканирование %d файлов…",
        "status.pick_smaller": "Выберите меньшую папку или отключите подпапки.",
        "status.moving": "Перемещение файлов…",
        "status.done": "Готово: перемещено %d, пропущено %d",
        "status.summary": "%d файлов · %d к перемещению · %d папок",
        "status.kept_fresh": " · %d свежих оставлены",
        "status.preview_cap": " · в списке первые %d",

        "automation.title": "Автоматизация",
        "automation.blurb": "Сценарий Автоматора и разбор по расписанию — те же правила, что в окне.",
        "automation.add": "Добавить в Автоматор",
        "automation.add.help": "Сохранить сценарий и включить расписание",
        "automation.need_folder.help": "Сначала выберите папку",
        "automation.card.line": "«%@» · %@",

        "schedule.sheet.title": "Автоматор и расписание",
        "schedule.sheet.subtitle": "Разбор выбранной папки без открытия окна",
        "schedule.section.what": "Что будет запускаться",
        "schedule.section.when": "Расписание",
        "schedule.folder": "Папка",
        "schedule.folder.none": "не выбрана",
        "schedule.mode": "Режим",
        "schedule.subfolders": "Подпапки",
        "schedule.subfolders.yes": "включая",
        "schedule.subfolders.no": "только эта папка",
        "schedule.footer.what": "По расписанию выполняются те же шаги, что кнопка «Разобрать»: сканирование, правила давности или расширения, создание папок и перемещение. Пороги из «Время» берутся актуальные.",
        "schedule.frequency": "Как часто",
        "schedule.time": "Время",
        "schedule.weekday": "День недели",
        "schedule.footer.when": "Сценарий появится в Автоматоре (Службы и оповещения Календаря). Запуск идёт в фоне, результат — уведомлением.",
        "schedule.installed": "Сценарий добавлен в Автоматор. %@.",
        "schedule.done": "Готово",
        "schedule.launch_failed": "Не удалось включить расписание. Разрешите Sift в «Настройки → Основные → Объекты входа».",
        "schedule.service_menu": "Разобрать файлы (Sift)",
        "schedule.service_workflow": "Разобрать файлы Sift.workflow",
        "schedule.calendar_workflow": "Sift.workflow",

        "freq.hourly": "Каждый час",
        "freq.daily": "Каждый день",
        "freq.weekly": "Каждую неделю",
        "freq.daily_at": "Каждый день в %@",
        "freq.weekly_at": "Каждый %@ в %@",
        "freq.day_fallback": "день",

        "auto.no_bookmark": "Нет сохранённой папки для авторазбора. Добавьте расписание заново.",
        "auto.no_access": "Нет доступа к сохранённой папке. Откройте Sift и добавьте расписание ещё раз.",
        "auto.not_folder": "Сохранённый путь больше не является папкой.",
        "auto.too_many": "Авторазбор пропущен: больше %d файлов.",
        "auto.need_setup": "Сначала добавьте папку в Автоматор через Sift.",
        "auto.nothing": "Нечего перемещать в «%@».",
        "auto.done": "Готово: перемещено %d, пропущено %d — «%@».",

        "scan.not_folder": "Выбранный путь не является папкой.",
        "scan.enumeration_failed": "Не удалось прочитать содержимое папки.",

        "info.apple_events": "Sift добавляет сценарий в Автоматор и запускает разбор файлов по расписанию.",
    ]
}

/// Prefer `LocalizationManager.shared` from UI; this is a thin @MainActor shorthand.
enum L10n {
    @MainActor
    static func t(_ key: String) -> String {
        LocalizationManager.shared.t(key)
    }

    @MainActor
    static func t(_ key: String, _ args: CVarArg...) -> String {
        let format = LocalizationManager.shared.t(key)
        return String(format: format, locale: LocalizationManager.shared.language.locale, arguments: args)
    }
}

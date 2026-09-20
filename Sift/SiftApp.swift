import AppKit
import Carbon
import SwiftUI
import UserNotifications

extension Notification.Name {
    static let siftDidAutoOrganize = Notification.Name("siftDidAutoOrganize")
}

@main
struct SiftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(LocalizationManager.shared)
                .frame(minWidth: 780, minHeight: 560)
                .onAppear {
                    if appDelegate.backgroundMode {
                        NSApp.windows.forEach { $0.orderOut(nil) }
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 640)
        .handlesExternalEvents(matching: ["organize"])
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject {
    @Published var backgroundMode = CommandLine.arguments.contains("--auto-organize")

    private var didFinishLaunching = false
    private var organizeInFlight = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        if backgroundMode {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = icon
        }
        didFinishLaunching = true
        if CommandLine.arguments.contains("--auto-organize") {
            Task { await runOrganize(scheduled: true, quitWhenDone: true) }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(handle(url:))
    }

    @objc private func handleGetURLEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string) else { return }
        handle(url: url)
    }

    private func handle(url: URL) {
        guard url.scheme == "sift" else { return }
        let scheduled = isScheduled(url)
        let launchedForSchedule = scheduled && !didFinishLaunching

        if launchedForSchedule {
            backgroundMode = true
            NSApp.setActivationPolicy(.accessory)
            NSApp.windows.forEach { $0.orderOut(nil) }
        }

        Task { await runOrganize(scheduled: scheduled, quitWhenDone: launchedForSchedule) }
    }

    private func isScheduled(_ url: URL) -> Bool {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .contains { $0.name == "scheduled" && ($0.value == "1" || $0.value == "true") }
            ?? false
    }

    @MainActor
    private func runOrganize(scheduled: Bool, quitWhenDone: Bool) async {
        if organizeInFlight { return }
        organizeInFlight = true
        defer { organizeInFlight = false }

        let message = await HeadlessOrganizer.run(scheduled: scheduled)
        if let message {
            NotificationCenter.default.post(name: .siftDidAutoOrganize, object: message)
        }
        if quitWhenDone {
            NSApp.terminate(nil)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

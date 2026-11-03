import AppKit
import SwiftUI
import ServiceManagement
import UserNotifications
import CoreImage.CIFilterBuiltins

@MainActor
final class Preferences: ObservableObject {
    @Published var autoOpen: Bool { didSet { UserDefaults.standard.set(autoOpen, forKey: "autoOpen") } }
    @Published var notifications: Bool { didSet { UserDefaults.standard.set(notifications, forKey: "notifications") } }
    @Published var loginEnabled = false
    @Published var loginMessage = ""

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["autoOpen": true, "notifications": true])
        autoOpen = defaults.bool(forKey: "autoOpen")
        notifications = defaults.bool(forKey: "notifications")
        refreshLogin()
    }
    func refreshLogin() {
        loginEnabled = SMAppService.mainApp.status == .enabled
        loginMessage = SMAppService.mainApp.status == .requiresApproval ? "请在系统设置的登录项中批准。" : ""
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshLogin()
        } catch {
            refreshLogin()
            loginMessage = "无法修改登录项：\(error.localizedDescription)"
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var resultWindow: NSWindow?
    private var capture: CaptureSession?
    private var busy = false
    private let preferences = Preferences()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "qrcode.viewfinder", accessibilityDescription: "QRScanner 扫描二维码")
            button.toolTip = "QRScanner：左键扫描，右键设置"
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        if !UserDefaults.standard.bool(forKey: "hasLaunched") || CommandLine.arguments.contains("--settings") {
            showSettings()
            UserDefaults.standard.set(true, forKey: "hasLaunched")
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) { capture?.cancel() }

    @objc private func statusClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            let menu = NSMenu()
            menu.addItem(withTitle: "扫描屏幕二维码", action: #selector(scan), keyEquivalent: "")
            menu.addItem(.separator())
            let login = menu.addItem(withTitle: "开机启动", action: #selector(toggleLogin), keyEquivalent: "")
            preferences.refreshLogin()
            login.state = preferences.loginEnabled ? .on : .off
            let auto = menu.addItem(withTitle: "自动打开网页链接", action: #selector(toggleAutoOpen), keyEquivalent: "")
            auto.state = preferences.autoOpen ? .on : .off
            let notifications = menu.addItem(withTitle: "扫描完成通知", action: #selector(toggleNotifications), keyEquivalent: "")
            notifications.state = preferences.notifications ? .on : .off
            menu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",")
            menu.addItem(.separator())
            menu.addItem(withTitle: "退出 QRScanner", action: #selector(quit), keyEquivalent: "q")
            menu.items.forEach { $0.target = self }
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else { scan() }
    }

    @objc private func toggleLogin() {
        preferences.setLogin(!preferences.loginEnabled)
        if !preferences.loginMessage.isEmpty { showSettings() }
    }
    @objc private func toggleAutoOpen() { preferences.autoOpen.toggle() }
    @objc private func toggleNotifications() {
        preferences.notifications.toggle()
        if preferences.notifications { requestNotifications() }
    }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc func scan() {
        guard !busy else { return }
        if !CGPreflightScreenCaptureAccess() {
            // The system request is deliberately made only when the user starts a scan.
            if !CGRequestScreenCaptureAccess() {
                let alert = NSAlert()
                alert.messageText = "需要屏幕录制权限"
                alert.informativeText = "请在系统设置 → 隐私与安全性 → 屏幕与系统音频录制中允许 QRScanner。授权后如系统要求，请退出并重新打开应用。"
                alert.addButton(withTitle: "打开系统设置")
                alert.addButton(withTitle: "取消")
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn { openScreenPermissionSettings() }
                return
            }
            // Permission may require restarting; ScreenCaptureKit reports any remaining failure.
        }
        settingsWindow?.orderOut(nil)
        resultWindow?.orderOut(nil)
        busy = true
        setBusy(true)
        let session = CaptureSession()
        capture = session
        Task { [self] in
            do {
                try await session.start { [weak self] result in
                    guard let self else { return }
                    self.capture = nil
                    guard let result else { self.completeScan(); return }
                    switch result {
                    case .success(let image):
                        Task {
                            do {
                                let results = try await Task.detached(priority: .userInitiated) {
                                    try QRDecoder.decode(image)
                                }.value
                                self.handle(results)
                            } catch { self.showError(error) }
                            self.completeScan()
                        }
                    case .failure(let error): self.showError(error); self.completeScan()
                    }
                }
            } catch {
                session.cancel()
                showError(error)
                completeScan()
            }
        }
    }
    private func setBusy(_ busy: Bool) {
        statusItem.button?.image = NSImage(systemSymbolName: busy ? "viewfinder" : "qrcode.viewfinder",
                                           accessibilityDescription: busy ? "正在扫描" : "QRScanner 扫描二维码")
    }
    private func completeScan() { busy = false; setBusy(false) }

    private func handle(_ results: [String]) {
        guard !results.isEmpty else {
            showResults([], message: "没有发现二维码", detail: "请将完整二维码及四周留白包含在选区内，然后重试。")
            notify(title: "未发现二维码", body: "请重新选择窗口或区域。")
            return
        }
        if results.count == 1, preferences.autoOpen, let url = PayloadPolicy.webURL(results[0]) {
            if NSWorkspace.shared.open(url) {
                notify(title: "已识别并打开网页", body: "已交给默认浏览器打开。")
            } else {
                showResults(results, message: "浏览器未能打开链接", detail: "你可以复制链接后手动打开。")
                notify(title: "已识别二维码", body: "浏览器未能打开，请查看结果。")
            }
        } else {
            showResults(results, message: results.count == 1 ? "已识别二维码" : "发现 \(results.count) 个二维码",
                        detail: "选择要打开或复制的内容。")
            notify(title: "二维码识别完成", body: results.count == 1 ? "结果已显示，可以打开或复制。" : "发现多个结果，请选择。")
        }
    }
    private func showResults(_ results: [String], message: String, detail: String) {
        resultWindow?.close()
        let view = ResultsView(results: results, message: message, detail: detail,
                              scanAgain: { [weak self] in self?.scan() })
        let window = makeWindow(title: "QRScanner · 识别结果", size: NSSize(width: 520, height: 360), view: view)
        resultWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func showError(_ error: Error) {
        showResults([], message: "扫描未完成", detail: error.localizedDescription)
        notify(title: "扫描未完成", body: "请打开 QRScanner 查看详情。")
    }
    @objc func showSettings() {
        preferences.refreshLogin()
        if settingsWindow == nil {
            let view = SettingsView(preferences: preferences,
                requestNotifications: { [weak self] in self?.requestNotifications() })
            settingsWindow = makeWindow(title: "QRScanner 设置", size: NSSize(width: 360, height: 220), view: view)
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func makeWindow<V: View>(title: String, size: NSSize, view: V) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = title
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
    private func requestNotifications() {
        Task {
            do {
                let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                if !allowed {
                    let alert = NSAlert()
                    alert.messageText = "系统通知未开启"
                    alert.informativeText = "扫描仍可正常使用。你可以在系统设置 → 通知 → QRScanner 中开启通知。"
                    alert.runModal()
                }
            } catch { showError(error) }
        }
    }
    private func notify(title: String, body: String) {
        guard preferences.notifications else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            do {
                let settings = await center.notificationSettings()
                if settings.authorizationStatus == .notDetermined {
                    guard try await center.requestAuthorization(options: [.alert, .sound]) else { return }
                }
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            } catch {
                NSLog("Notification delivery failed: %@", error.localizedDescription)
            }
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse) async {
        await MainActor.run { self.showSettings() }
    }
}

@MainActor
func openScreenPermissionSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
        NSWorkspace.shared.open(url)
    }
}

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    let requestNotifications: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("开机启动", isOn: Binding(get: { preferences.loginEnabled }, set: preferences.setLogin))
            if !preferences.loginMessage.isEmpty {
                Text(preferences.loginMessage).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle("识别到单个网页链接后自动打开", isOn: $preferences.autoOpen)
            Toggle("扫描完成后发送系统通知", isOn: $preferences.notifications)
                .onChange(of: preferences.notifications) { _, enabled in if enabled { requestNotifications() } }
            HStack {
                Button("屏幕录制权限…") { openScreenPermissionSettings() }
                Button("通知权限…", action: requestNotifications)
            }
            Text("v0.1.0").font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 360)
    }
}

struct ResultsView: View {
    let results: [String]
    let message: String
    let detail: String
    let scanAgain: () -> Void
    @State private var copied: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(message, systemImage: results.isEmpty ? "qrcode.viewfinder" : "checkmark.circle.fill")
                .font(.title2.bold())
            Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !results.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(results, id: \.self) { payload in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(payload).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                HStack {
                                    if let url = PayloadPolicy.webURL(payload) {
                                        Button("在浏览器打开") { NSWorkspace.shared.open(url) }
                                    }
                                    Button(copied == payload ? "已复制" : "复制内容") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(payload, forType: .string)
                                        copied = payload
                                    }
                                }
                            }.padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            HStack { Spacer(); Button("重新扫描", action: scanAgain).buttonStyle(.borderedProminent) }
        }.padding(24).frame(width: 520, height: 360)
    }
}

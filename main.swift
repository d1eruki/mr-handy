import AppKit

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class Background: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 20, yRadius: 20).fill()
        NSBezierPath(rect: NSRect(x: 0, y: bounds.height - 20, width: bounds.width, height: 20)).fill()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel!
    private var button: NSButton!
    private var label: NSTextField!
    private var item: NSStatusItem!
    private var timer: Timer?
    private var outsideSince: Date?
    private var open = false
    private var busy = false
    private var task: Process?
    private var screen: NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 108),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let background = Background(frame: NSRect(x: 0, y: 0, width: 320, height: 108))
        background.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = background
        button = NSButton(title: "Перезапустить звук", target: self, action: #selector(restart))
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: 15, weight: .medium)
        button.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.keyEquivalent = "\r"
        button.setAccessibilityLabel("Перезапустить звук")
        button.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(button)
        label = NSTextField(labelWithString: "Mr Handy · звук без треска")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(label)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            button.topAnchor.constraint(equalTo: background.topAnchor, constant: 18),
            button.widthAnchor.constraint(equalToConstant: 260),
            button.heightAnchor.constraint(equalToConstant: 36),
            label.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 10),
            label.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -16)
        ])
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "Mr Handy")
        item.button?.toolTip = "Mr Handy — перезапуск звука"
        let menu = NSMenu()
        for (title, action, key) in [
            ("Показать панель", #selector(showFromMenu), ""),
            ("Перезапустить звук", #selector(restart), ""),
            ("Выйти из Mr Handy", #selector(quit), "q")
        ] {
            let entry = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            entry.target = self
        }
        item.menu = menu
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.track() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        show()
    }

    private func geometry(_ screen: NSScreen) -> (panel: NSRect, trigger: NSRect) {
        let frame = screen.frame
        let inset = screen.safeAreaInsets.top
        var center = frame.midX
        var width: CGFloat = 180
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, inset > 0 {
            center = (left.maxX + right.minX) / 2
            width = max(160, right.minX - left.maxX)
        }
        let top = frame.maxY - (inset > 0 ? inset : NSStatusBar.system.thickness)
        return (NSRect(x: center - 160, y: top - 108, width: 320, height: 108),
                NSRect(x: center - width / 2, y: top - 8, width: width, height: frame.maxY - top + 8))
    }

    private func track() {
        guard let screen else { return }
        let area = geometry(screen)
        let point = NSEvent.mouseLocation
        if area.trigger.contains(point) || (open && area.panel.insetBy(dx: -6, dy: -6).contains(point)) || busy {
            outsideSince = nil
            if area.trigger.contains(point) { show() }
        } else if open {
            if outsideSince == nil { outsideSince = Date() }
            if let outsideSince, Date().timeIntervalSince(outsideSince) > 0.65 {
                open = false
                panel.orderOut(nil)
            }
        }
    }

    private func show() {
        guard !open, let screen else { return }
        open = true
        outsideSince = nil
        let frame = geometry(screen).panel
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(reduced ? frame : frame.offsetBy(dx: 0, dy: 18), display: false)
        panel.alphaValue = reduced ? 1 : 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduced ? 0 : 0.18
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }
    }

    @objc private func screenChanged() {
        if open, let screen { panel.setFrame(geometry(screen).panel, display: true) }
    }
    @objc private func showFromMenu() { show(); panel.makeKey() }
    @objc private func quit() { if !busy { NSApp.terminate(nil) } }

    @objc private func restart() {
        guard !busy else { return }
        busy = true
        show()
        button.isEnabled = false
        button.title = "Перезапускаем…"
        label.stringValue = "Подтверди запрос macOS. Звук прервётся."
        let process = Process()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"/usr/bin/killall coreaudiod\" with administrator privileges"]
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        task = process
        process.terminationHandler = { [weak self] process in
            let error = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let code = process.terminationStatus
            DispatchQueue.main.async { self?.completed(code: code, error: error) }
        }
        do { try process.run() }
        catch { completed(code: -1, error: error.localizedDescription) }
    }

    private func completed(code: Int32, error: String) {
        task = nil
        if code == 0 {
            label.stringValue = "Ждём запуска звуковой службы…"
            verify(attempt: 0)
        } else {
            finish(error.contains("-128") ? "Перезапуск отменён" : "Не удалось перезапустить звук")
            if !error.contains("-128") {
                let alert = NSAlert()
                alert.messageText = "Не удалось перезапустить звук"
                alert.informativeText = String(error.prefix(1200))
                alert.addButton(withTitle: "Закрыть")
                alert.runModal()
            }
        }
    }

    private func verify(attempt: Int) {
        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        check.arguments = ["-x", "coreaudiod"]
        check.standardOutput = FileHandle.nullDevice
        check.standardError = FileHandle.nullDevice
        check.terminationHandler = { [weak self] process in
            let code = process.terminationStatus
            DispatchQueue.main.async {
                guard let self else { return }
                if code == 0 { self.finish("Служба запущена. Проверь звук 🔊") }
                else if attempt < 9 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.verify(attempt: attempt + 1) }
                } else { self.finish("Служба пока не запустилась. Попробуй ещё раз.") }
            }
        }
        do { try check.run() }
        catch { finish("Перезапуск отправлен. Проверь звук.") }
    }

    private func finish(_ message: String) {
        busy = false
        button.isEnabled = true
        button.title = "Перезапустить звук"
        label.stringValue = message
        outsideSince = nil
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}

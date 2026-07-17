import AppKit
import SwiftUI

@MainActor
final class PreviewWindowController {
    static let shared = PreviewWindowController()

    private var window: NSWindow?

    func show(store: StatusStore) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingView = NSHostingView(rootView: PreviewView(store: store))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Code CCTV 全局预览"
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class FloatingPanelController: NSObject, ObservableObject {
    private let panel: NSPanel
    private let store: StatusStore
    private let originKey = "CodeCCTV.floatingPanelOrigin"
    private let collapsedSize = NSSize(width: 154, height: 38)
    @Published private(set) var isExpanded = false
    private var collapseWorkItem: DispatchWorkItem?
    private var dismissedStateID = ""

    init(store: StatusStore) {
        self.store = store
        self.panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: collapsedSize.width, height: collapsedSize.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        let hostingView = NSHostingView(rootView: FloatingPanelView(
            controller: self,
            store: store,
            onOpen: {
                PreviewWindowController.shared.show(store: store)
            },
            onMove: { [weak self] delta in
                self?.move(by: delta)
            },
            onMoveEnd: { [weak self] in
                self?.persistOrigin()
            },
            onResize: { [weak self] size in
                self?.resize(to: size)
            }
        ))
        panel.contentView = hostingView
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        // SwiftUI owns drag movement; native background dragging would move the panel twice.
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
    }

    func show() {
        isExpanded = false
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        if let saved = UserDefaults.standard.array(forKey: originKey) as? [Double], saved.count == 2 {
            let savedFrame = NSRect(origin: NSPoint(x: saved[0], y: saved[1]), size: size)
            if savedFrame.intersects(frame) {
                panel.setFrameOrigin(savedFrame.origin)
            } else {
                placeAtDefault(frame: frame, size: size)
            }
        } else {
            placeAtDefault(frame: frame, size: size)
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        collapseWorkItem?.cancel()
        isExpanded = false
        panel.orderOut(nil)
    }

    func presentBubble(for stateID: String? = nil) {
        if let stateID, stateID == dismissedStateID {
            return
        }
        isExpanded = true
        collapseWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.isExpanded = false
        }
        collapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: workItem)
    }

    func collapseBubble() {
        collapseWorkItem?.cancel()
        isExpanded = false
    }

    func dismissBubble(stateID: String) {
        dismissedStateID = stateID
        collapseBubble()
    }

    deinit {
        collapseWorkItem?.cancel()
    }

    private func resize(to size: CGSize) {
        let nextSize = NSSize(width: size.width, height: size.height)
        let oldFrame = panel.frame
        guard oldFrame.size != nextSize else { return }

        let topRight = NSPoint(x: oldFrame.maxX, y: oldFrame.maxY)
        let nextOrigin = NSPoint(x: topRight.x - nextSize.width, y: topRight.y - nextSize.height)
        let nextFrame = NSRect(origin: nextOrigin, size: nextSize)
        panel.setFrame(nextFrame, display: true, animate: true)
        UserDefaults.standard.set([nextOrigin.x, nextOrigin.y], forKey: originKey)
    }

    private func placeAtDefault(frame: NSRect, size: NSSize) {
        panel.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 18, y: frame.maxY - size.height - 18))
    }

    private func move(by delta: CGSize) {
        let origin = panel.frame.origin
        let next = NSPoint(x: origin.x + delta.width, y: origin.y - delta.height)
        panel.setFrameOrigin(next)
    }

    private func persistOrigin() {
        let origin = panel.frame.origin
        UserDefaults.standard.set([origin.x, origin.y], forKey: originKey)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = StatusStore.shared
    private var floatingPanel: FloatingPanelController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        floatingPanel = FloatingPanelController(store: store)
        floatingPanel?.show()

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "video.fill", accessibilityDescription: "Code CCTV")
        let menu = NSMenu()
        menu.addItem(menuItem(title: "打开全局预览", action: #selector(openPreview), image: "rectangle.3.group"))
        menu.addItem(menuItem(title: "显示浮窗", action: #selector(showFloatingPanel), image: "eye"))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "退出 Code CCTV", action: #selector(quitApp), image: "power"))
        statusItem.menu = menu
        self.statusItem = statusItem
    }

    private func menuItem(title: String, action: Selector, image: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: image, accessibilityDescription: title)
        return item
    }

    @objc private func openPreview() {
        PreviewWindowController.shared.show(store: store)
    }

    @objc private func showFloatingPanel() {
        floatingPanel?.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

@main
struct CodeCCTVApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

import AppKit
import SwiftUI
import Combine
import QuartzCore

final class DesktopIslandPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

private final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A native drag surface keeps the rest of the SwiftUI panel interactive.
private final class IslandDragHandle: NSView {
    var onClick: (() -> Void)?
    var onDragFinished: (() -> Void)?
    var canDrag: (() -> Bool)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard canDrag?() != false, let window else { return }
        let before = window.frame.origin
        window.performDrag(with: event)
        if hypot(window.frame.origin.x - before.x, window.frame.origin.y - before.y) > 2 {
            onDragFinished?()
        } else { onClick?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}

@MainActor
final class DesktopIslandController: NSObject, NSWindowDelegate {
    let model = IslandModel()
    let store: SceneStore
    let workspace: WorkspaceService
    let panel: DesktopIslandPanel
    private var managementWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var dragHandle: IslandDragHandle?
    private var toggleMenuItem: NSMenuItem?
    private var hideMenuItem: NSMenuItem?
    private var subscriptions = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var anchor: CGPoint
    private var isHidden = false
    private static let positionKey = "XuZhuo.desktopIslandPosition"

    init(store: SceneStore, workspace: WorkspaceService) {
        self.store = store
        self.workspace = workspace
        let screen = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        if let saved = UserDefaults.standard.array(forKey: Self.positionKey) as? [Double], saved.count == 2 {
            anchor = CGPoint(x: saved[0], y: saved[1])
        } else { anchor = IslandPlacement.defaultAnchor(in: screen) }
        let frame = IslandPlacement.frame(size: IslandPlacement.collapsedSize, anchor: anchor, visibleFrames: NSScreen.screens.map(\.visibleFrame))
        panel = DesktopIslandPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.title = L("续桌岛", "Resume Island")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.animationBehavior = .none
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.collapse() }

        let content = NSView(frame: CGRect(origin: .zero, size: frame.size))
        let hosting = IslandHostingView(rootView: DesktopIslandView(model: model, store: store, workspace: workspace,
                                                               onManage: { [weak self] in self?.showManagement() },
                                                               onSettings: { [weak self] in self?.showSettings() },
                                                               onQuit: { NSApp.terminate(nil) })
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .preferredColorScheme(.dark))
        hosting.frame = content.bounds
        hosting.autoresizingMask = [.width, .height]
        content.addSubview(hosting)
        let handle = IslandDragHandle(frame: CGRect(x: frame.width / 2 - 40, y: frame.height - 44, width: 80, height: 44))
        handle.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        handle.toolTip = L("点击展开或收起，按住这里拖动位置", "Click to expand or collapse. Drag to reposition.")
        handle.setAccessibilityElement(true)
        handle.setAccessibilityRole(.button)
        handle.setAccessibilityLabel(L("展开或拖动续桌岛", "Expand or drag Resume Island"))
        handle.onClick = { [weak self] in self?.toggle() }
        handle.canDrag = { [weak self] in self?.model.busy == false }
        handle.onDragFinished = { [weak self] in self?.savePosition() }
        content.addSubview(handle)
        dragHandle = handle
        panel.contentView = content
        model.$expanded.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] expanded in self?.resize(expanded: expanded) }.store(in: &subscriptions)
        model.$page.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] page in
            guard let self, self.panel.isVisible, !self.isHidden else { return }
            self.resize(expanded: self.model.expanded)
            guard page != .scenes else { return }
            // Data entry is an explicit user action. Keep typing in the panel,
            // while the collapsed desktop entry never activates the application.
            NSApp.activate(ignoringOtherApps: true)
            self.panel.makeKeyAndOrderFront(nil)
        }.store(in: &subscriptions)
        installMenus()
        LanguageSettings.shared.$language.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            self.installMenus()
            self.panel.title = L("续桌岛", "Resume Island")
            self.managementWindow?.title = L("续桌 · 管理存档", "Resume · Library")
            self.settingsWindow?.title = L("续桌 · 设置", "Resume · Settings")
            self.dragHandle?.toolTip = L("点击展开或收起，按住这里拖动位置", "Click to expand or collapse. Drag to reposition.")
            self.dragHandle?.setAccessibilityLabel(L("展开或拖动续桌岛", "Expand or drag Resume Island"))
        }.store(in: &subscriptions)
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resize(expanded: self?.model.expanded ?? false, animated: false) }
        })
    }

    func show() {
        isHidden = false
        resize(expanded: model.expanded, animated: false)
        panel.orderFrontRegardless()
        updateMenuTitles()
    }

    private func toggle() {
        guard !model.busy else { return }
        if isHidden { show(); model.expanded = true }
        else { model.expanded.toggle() }
    }

    private func collapse() {
        guard !model.busy else { return }
        model.expanded = false
    }

    private func resize(expanded: Bool, animated: Bool = true) {
        let size = expanded ? (model.page == .scenes ? IslandPlacement.expandedSize : IslandPlacement.workflowSize) : IslandPlacement.collapsedSize
        let frame = IslandPlacement.frame(size: size, anchor: anchor, visibleFrames: NSScreen.screens.map(\.visibleFrame))
        if animated, panel.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else { panel.setFrame(frame, display: true) }
        if expanded, !isHidden { panel.makeKeyAndOrderFront(nil) }
        else if panel.isKeyWindow { panel.resignKey() }
        updateMenuTitles()
    }

    private func savePosition() {
        anchor = IslandPlacement.centerTop(of: panel.frame)
        let frame = IslandPlacement.frame(size: panel.frame.size, anchor: anchor, visibleFrames: NSScreen.screens.map(\.visibleFrame))
        panel.setFrame(frame, display: true)
        anchor = IslandPlacement.centerTop(of: frame)
        UserDefaults.standard.set([Double(anchor.x), Double(anchor.y)], forKey: Self.positionKey)
    }

    private func showManagement() {
        guard !model.busy else { return }
        collapse()
        if managementWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1280, height: 850),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = L("续桌 · 管理存档", "Resume · Library")
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.minSize = CGSize(width: 1000, height: 700)
            window.contentView = NSHostingView(rootView: ContentView(store: store, workspace: workspace).preferredColorScheme(.light))
            window.center()
            managementWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        managementWindow?.makeKeyAndOrderFront(nil)
    }

    private func showSettings() {
        guard !model.busy else { return }
        collapse()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 610, height: 680), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = L("续桌 · 设置", "Resume · Settings")
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PermissionsView(service: workspace, onClose: { [weak self] in self?.settingsWindow?.orderOut(nil) }).preferredColorScheme(.light))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func installMenus() {
        let menu = NSMenu(title: L("续桌", "Resume"))
        let toggle = menuItem(L("展开续桌岛", "Expand Island"), action: #selector(toggleFromMenu))
        toggleMenuItem = toggle
        menu.addItem(toggle)
        let save = menuItem(L("保存当前现场…", "Save Workspace…"), action: #selector(saveFromMenu), key: "s")
        save.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(save)
        menu.addItem(.separator())
        menu.addItem(menuItem(L("管理存档…", "Workspace Library…"), action: #selector(manageFromMenu), key: "1"))
        menu.addItem(menuItem(L("设置与恢复支持…", "Settings & Restore Support…"), action: #selector(settingsFromMenu), key: ","))
        menu.addItem(.separator())
        menu.addItem(menuItem(L("移回屏幕顶部", "Move to Top of Screen"), action: #selector(resetPosition)))
        let hide = menuItem(L("隐藏续桌岛", "Hide Island"), action: #selector(toggleVisibility))
        hideMenuItem = hide
        menu.addItem(hide)
        menu.addItem(.separator())
        menu.addItem(menuItem(L("退出续桌", "Quit Resume"), action: #selector(quitFromMenu), key: "q"))
        let languages = NSMenu(title: L("界面语言", "Language"))
        for (language, selector) in [(AppLanguage.chinese, #selector(useChinese)), (AppLanguage.english, #selector(useEnglish))] {
            let option = menuItem(language.nativeName, action: selector)
            option.state = LanguageSettings.shared.language == language ? .on : .off
            languages.addItem(option)
        }
        let languageItem = NSMenuItem(title: L("界面语言", "Language"), action: nil, keyEquivalent: "")
        languageItem.submenu = languages
        menu.insertItem(languageItem, at: menu.numberOfItems - 2)
        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.stack.fill", accessibilityDescription: L("续桌岛", "Resume Island"))
        item.button?.toolTip = L("续桌 · 桌面存档入口", "Resume · Desktop Workspaces")
        item.menu = menu
        statusItem = item
        let main = NSMenu()
        let appItem = NSMenuItem(title: L("续桌", "Resume"), action: nil, keyEquivalent: "")
        main.addItem(appItem)
        appItem.submenu = menu.copy() as? NSMenu
        let editItem = NSMenuItem(title: L("编辑", "Edit"), action: nil, keyEquivalent: "")
        let edit = NSMenu(title: L("编辑", "Edit"))
        for (title, selector, key) in [(L("撤销", "Undo"), "undo:", "z"), (L("重做", "Redo"), "redo:", "Z"), (L("剪切", "Cut"), "cut:", "x"),
                                        (L("复制", "Copy"), "copy:", "c"), (L("粘贴", "Paste"), "paste:", "v"), (L("全选", "Select All"), "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: NSSelectorFromString(selector), keyEquivalent: key))
        }
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
        updateMenuTitles()
    }

    private func menuItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func updateMenuTitles() {
        toggleMenuItem?.title = model.expanded && !isHidden ? L("收起续桌岛", "Collapse Island") : L("展开续桌岛", "Expand Island")
        hideMenuItem?.title = isHidden ? L("显示续桌岛", "Show Island") : L("隐藏续桌岛", "Hide Island")
        for item in NSApp.mainMenu?.items.first?.submenu?.items ?? [] {
            if item.action == #selector(toggleFromMenu) { item.title = toggleMenuItem?.title ?? L("展开续桌岛", "Expand Island") }
            if item.action == #selector(toggleVisibility) { item.title = hideMenuItem?.title ?? L("隐藏续桌岛", "Hide Island") }
        }
    }

    @objc private func useChinese() { LanguageSettings.shared.language = .chinese }
    @objc private func useEnglish() { LanguageSettings.shared.language = .english }
    @objc private func toggleFromMenu() { toggle() }
    @objc private func saveFromMenu() {
        guard !model.busy else { return }
        model.saveRequest = UUID()
        show()
        model.expanded = true
    }
    @objc private func manageFromMenu() { showManagement() }
    @objc private func settingsFromMenu() { showSettings() }
    @objc private func quitFromMenu() { NSApp.terminate(nil) }
    @objc private func resetPosition() {
        guard !model.busy else { return }
        let screen = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame
        guard let screen else { return }
        anchor = IslandPlacement.defaultAnchor(in: screen)
        UserDefaults.standard.removeObject(forKey: Self.positionKey)
        show()
    }
    @objc private func toggleVisibility() {
        guard !model.busy else { return }
        if isHidden { show() }
        else { isHidden = true; model.expanded = false; panel.orderOut(nil); updateMenuTitles() }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === panel { toggleVisibility(); return false }
        return true
    }
}

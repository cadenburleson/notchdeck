import AppKit
import SwiftUI
import Combine

/// A borderless, non-activating panel that floats above the menu bar.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// AppKit normally shoves windows below the menu bar; we live *in* it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private struct Placement: Equatable {
    let edge: NotchEdge
    let offset: Double
}

/// Delivers the first click straight to SwiftUI instead of swallowing it to focus the window.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class NotchWindowController {
    let viewModel: NotchViewModel
    private let store: AppStore
    private let pomodoro: PomodoroEngine
    private var panel: NotchPanel!
    private var hostingView: NotchHostingView<AnyView>!
    private var collapseWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private var mouseMonitors: [Any] = []
    private var mouseInside = false

    private(set) var isVisible = false

    init(store: AppStore, pomodoro: PomodoroEngine) {
        self.store = store
        self.pomodoro = pomodoro
        self.viewModel = NotchViewModel(geometry: NotchGeometry.current(edge: store.settings.edge,
                                                                         edgeOffset: store.settings.edgeOffset))
        buildPanel()
        observe()
    }

    deinit {
        mouseMonitors.forEach { NSEvent.removeMonitor($0) }
    }

    // MARK: - Setup

    private func buildPanel() {
        let panel = NotchPanel(contentRect: viewModel.geometry.windowFrame(for: viewModel.collapsedSize),
                               styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                               backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        // We sit above the menu bar so the notch strip is ours.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.animationBehavior = .none
        // The shadow is drawn by SoftShadow (plain geometry). Neither the
        // window-server shadow (too faint for a non-key panel) nor SwiftUI's
        // `.shadow` filter (dropped by the compositor for this transparent
        // panel) render acceptably here.
        panel.hasShadow = false
        // Start click-through; the mouse monitor enables events when the cursor is over the shape.
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let root = NotchRootView()
            .environmentObject(viewModel)
            .environmentObject(store)
            .environmentObject(pomodoro)
        let hosting = NotchHostingView(rootView: AnyView(root))
        panel.contentView = hosting

        self.panel = panel
        self.hostingView = hosting
    }

    private func observe() {
        // Tracking areas are unreliable for a window parked inside the menu bar,
        // so hover is derived from the global mouse position instead.
        let handler: (NSEvent) -> Void = { [weak self] _ in self?.mouseDidMove() }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handler) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { e in handler(e); return e }) {
            mouseMonitors.append(local)
        }

        // Re-anchor when displays change.
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshGeometry() }
            .store(in: &cancellables)

        // Placement settings move the window.
        let placement: AnyPublisher<Placement, Never> = store.$settings
            .map { Placement(edge: $0.edge, offset: $0.edgeOffset) }
            .removeDuplicates()
            .dropFirst()
            .eraseToAnyPublisher()
        placement
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (_: Placement) in self?.refreshGeometry() }
            .store(in: &cancellables)

        // Collapsed indicators change the collapsed window size.
        Publishers.CombineLatest3(store.$tasks, store.$settings, pomodoro.$isRunning)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in self?.updateWingWidth() }
            .store(in: &cancellables)
        pomodoro.$remaining
            .map { _ in () }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateWingWidth() }
            .store(in: &cancellables)

        // Pinning from inside the SwiftUI view.
        viewModel.$isPinned
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pinned in
                guard let self else { return }
                if pinned { self.expand() } else if !self.mouseInside { self.collapse() }
            }
            .store(in: &cancellables)

        pomodoro.onPhaseCompleted = { [weak self] finished, next in
            guard let self else { return }
            if finished == .focus { self.store.totalFocusSessions += 1 }
            let sound = self.store.settings.pomodoro.playSound
            let title = finished == .focus ? "Focus session complete" : "Break's over"
            let body = finished == .focus ? "Time for a \(next.title.lowercased())." : "Back to focus."
            NotificationService.shared.notify(title: title, body: body, playSound: sound)
        }
    }

    // MARK: - Public

    func show() {
        refreshGeometry()
        panel.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        collapse(force: true)
        panel.orderOut(nil)
        isVisible = false
    }

    func open(tab: NotchTab) {
        viewModel.selectedTab = tab
        viewModel.showingSettings = false
        if !isVisible { show() }
        viewModel.isPinned = true
        expand()
    }

    func setPinned(_ pinned: Bool) {
        viewModel.isPinned = pinned
    }

    /// Screen rect of the visible shape (the window is larger to fit the shadow).
    private var shapeFrame: NSRect { viewModel.geometry.frame(for: viewModel.currentSize) }

    // MARK: - Hover handling

    private func mouseDidMove() {
        guard isVisible else { return }
        let inside = shapeFrame.contains(NSEvent.mouseLocation)
        guard inside != mouseInside else { return }
        mouseInside = inside
        // Only the visible shape should catch clicks; the shadow margin lets
        // them fall through to whatever is underneath.
        panel.ignoresMouseEvents = !inside
        inside ? mouseEntered() : mouseExited()
    }

    private func mouseEntered() {
        collapseWorkItem?.cancel()
        guard store.settings.openOnHover || viewModel.isPinned else { return }
        expand()
    }

    private func mouseExited() {
        guard !viewModel.isPinned else { return }
        let work = DispatchWorkItem { [weak self] in self?.collapse() }
        collapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func expand() {
        collapseWorkItem?.cancel()
        guard !viewModel.isExpanded else { return }
        panel.setFrame(viewModel.geometry.windowFrame(for: viewModel.expandedSize), display: true)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            viewModel.isExpanded = true
        }
    }

    private func collapse(force: Bool = false) {
        collapseWorkItem?.cancel()
        guard viewModel.isExpanded || force else { return }
        if force { viewModel.isPinned = false }
        viewModel.showingSettings = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            viewModel.isExpanded = false
        }
        // Give keyboard focus back to whatever app the user was using.
        if panel.isKeyWindow {
            panel.makeFirstResponder(nil)
            panel.orderOut(nil)
            if isVisible || !force { panel.orderFrontRegardless() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            guard let self, !self.viewModel.isExpanded else { return }
            self.panel.setFrame(self.viewModel.geometry.windowFrame(for: self.viewModel.collapsedSize), display: true)
            self.mouseInside = self.shapeFrame.contains(NSEvent.mouseLocation)
            self.panel.ignoresMouseEvents = !self.mouseInside
        }
    }

    // MARK: - Layout

    private func refreshGeometry() {
        let wasExpanded = viewModel.isExpanded
        let geometry = NotchGeometry.current(edge: store.settings.edge, edgeOffset: store.settings.edgeOffset)
        let edgeChanged = geometry.edge != viewModel.geometry.edge
        viewModel.geometry = geometry
        if edgeChanged, wasExpanded {
            // Snap closed at the new location; the user is mid-settings so keep it pinned open there.
            viewModel.isExpanded = false
            panel.setFrame(geometry.windowFrame(for: viewModel.collapsedSize), display: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.viewModel.isPinned = true
                self?.expand()
                self?.viewModel.showingSettings = true
            }
            return
        }
        updateWingWidth()
        panel.setFrame(geometry.windowFrame(for: viewModel.currentSize), display: true)
        mouseInside = shapeFrame.contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !mouseInside
    }

    private func updateWingWidth() {
        let showTimer = store.settings.showTimerInNotch && !pomodoro.isIdle
        let showTasks = store.settings.showTaskCountInNotch && store.pendingTaskCount > 0
        let width: CGFloat
        if viewModel.edge == .top {
            width = (showTimer || showTasks) ? 64 : 0
        } else {
            width = (showTimer ? 20 : 0) + (showTasks ? 14 : 0)
        }
        guard width != viewModel.collapsedWingWidth else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            viewModel.collapsedWingWidth = width
        }
        if !viewModel.isExpanded {
            panel.setFrame(viewModel.geometry.windowFrame(for: viewModel.collapsedSize), display: true)
        }
    }
}

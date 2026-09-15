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

extension NotchPanel {
    /// The panel only becomes key when a text field is clicked. Call this before
    /// focusing a field programmatically so keystrokes land in the panel.
    static func makeKeyForTyping() {
        NSApp.windows.first { $0 is NotchPanel }?.makeKey()
    }
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
    private var phaseWork: [DispatchWorkItem] = []
    private var cancellables = Set<AnyCancellable>()
    private var mouseMonitors: [Any] = []
    private var mouseInside = false
    /// A left-button press that began on the panel (a drag, a text selection...).
    /// Hover state is frozen until it ends so the panel can't collapse or turn
    /// click-through mid-gesture when the pointer strays outside the shape.
    private var pressBeganInside = false

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
        if let down = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] e in
            if let self, self.shapeFrame.contains(NSEvent.mouseLocation) { self.pressBeganInside = true }
            return e
        }) {
            mouseMonitors.append(down)
        }
        let released: (NSEvent) -> Void = { [weak self] _ in
            guard let self, self.pressBeganInside else { return }
            self.pressBeganInside = false
            DispatchQueue.main.async { self.mouseDidMove() }
        }
        if let upLocal = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp], handler: { e in released(e); return e }) {
            mouseMonitors.append(upLocal)
        }
        if let upGlobal = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp], handler: released) {
            mouseMonitors.append(upGlobal)
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
        guard isVisible, !pressBeganInside else { return }
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
        scheduleCollapse(after: 0.25)
    }

    /// Collapses shortly after the pointer leaves, but not while a menu is open:
    /// a context menu's window sits outside the shape, so using it "leaves" the
    /// panel. Menus run an event-tracking run loop, which is checked directly
    /// rather than inferred from menu notifications.
    private func scheduleCollapse(after delay: TimeInterval) {
        collapseWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.viewModel.isPinned else { return }
            if RunLoop.current.currentMode == .eventTracking {
                self.scheduleCollapse(after: 0.25)
                return
            }
            if self.shapeFrame.contains(NSEvent.mouseLocation) {
                // Back over the panel, e.g. after closing a menu: stay open.
                self.mouseInside = true
                self.panel.ignoresMouseEvents = false
                return
            }
            self.collapse()
        }
        collapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func expand() {
        collapseWorkItem?.cancel()
        cancelPhases()
        if viewModel.isExpanded {
            // Re-entered during a collapse's fade-out: just bring the content back.
            withAnimation(.easeOut(duration: 0.15)) { viewModel.showExpandedContent = true }
            return
        }
        panel.setFrame(viewModel.geometry.windowFrame(for: viewModel.expandedSize), display: true)
        hostingView.layoutSubtreeIfNeeded()
        withoutAnimation { viewModel.showCollapsedContent = false }
        let open = store.settings.openDuration
        withAnimation(.spring(response: open, dampingFraction: 0.86)) {
            viewModel.isExpanded = true
        }
        // Content fades in once the shape has grown; clip/mask modifiers snap to
        // the final size instead of animating, so earlier would leak outside.
        after(open * 0.94) { [weak self] in
            withAnimation(.easeOut(duration: min(0.15, open / 2))) { self?.viewModel.showExpandedContent = true }
        }
    }

    private func collapse(force: Bool = false) {
        collapseWorkItem?.cancel()
        cancelPhases()
        guard viewModel.isExpanded || force else { return }
        if force { viewModel.isPinned = false }
        viewModel.showingSettings = false

        // Give keyboard focus back to whatever app the user was using.
        if panel.isKeyWindow {
            panel.makeFirstResponder(nil)
            panel.orderOut(nil)
            if isVisible || !force { panel.orderFrontRegardless() }
        }

        let close = store.settings.closeDuration
        let fadeOut = min(0.1, close / 3)
        let shrink: () -> Void = { [weak self] in
            guard let self else { return }
            withAnimation(.spring(response: close, dampingFraction: 0.9)) {
                self.viewModel.isExpanded = false
            }
            self.after(close) { [weak self] in
                guard let self, !self.viewModel.isExpanded else { return }
                // Resize the window (margin only; the shape stays put on screen) and
                // lay out synchronously. The fade below starts on the next tick so
                // SwiftUI does not fold the resize into that animation.
                self.panel.setFrame(self.viewModel.geometry.windowFrame(for: self.viewModel.collapsedSize), display: true)
                self.hostingView.layoutSubtreeIfNeeded()
                self.mouseInside = self.shapeFrame.contains(NSEvent.mouseLocation)
                self.panel.ignoresMouseEvents = !self.mouseInside
                self.after(0.02) { [weak self] in
                    withAnimation(.easeIn(duration: 0.15)) { self?.viewModel.showCollapsedContent = true }
                }
            }
        }

        if force {
            withoutAnimation {
                viewModel.showExpandedContent = false
                viewModel.isExpanded = false
                viewModel.showCollapsedContent = true
            }
            panel.setFrame(viewModel.geometry.windowFrame(for: viewModel.collapsedSize), display: true)
        } else {
            // Phase 1: fade the content out. Phase 2: shrink the shape.
            withAnimation(.easeOut(duration: fadeOut)) { viewModel.showExpandedContent = false }
            after(fadeOut, shrink)
        }
    }

    // MARK: - Animation phases

    private func after(_ delay: TimeInterval, _ block: @escaping () -> Void) {
        let work = DispatchWorkItem(block: block)
        phaseWork.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPhases() {
        phaseWork.forEach { $0.cancel() }
        phaseWork.removeAll()
    }

    private func withoutAnimation(_ body: () -> Void) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t, body)
    }

    // MARK: - Layout

    private func refreshGeometry() {
        let wasExpanded = viewModel.isExpanded
        let geometry = NotchGeometry.current(edge: store.settings.edge, edgeOffset: store.settings.edgeOffset)
        let edgeChanged = geometry.edge != viewModel.geometry.edge
        viewModel.geometry = geometry
        if edgeChanged, wasExpanded {
            // Snap closed at the new location; the user is mid-settings so keep it pinned open there.
            withoutAnimation {
                viewModel.showExpandedContent = false
                viewModel.isExpanded = false
                viewModel.showCollapsedContent = true
            }
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

import AppKit

/// Describes where the panel lives: which screen, which edge, and the size of
/// the physical notch (or the virtual pill that stands in for it).
struct NotchGeometry: Equatable {
    let screenFrame: NSRect
    let visibleFrame: NSRect
    let edge: NotchEdge
    /// 0...1 position along a side edge (0 = top). Ignored for `.top`.
    let edgeOffset: Double
    let hasNotch: Bool
    /// Width of the physical notch (or of the virtual pill on notch-less displays).
    let notchWidth: CGFloat
    /// Height of the menu bar / notch strip.
    let notchHeight: CGFloat

    static let fallbackWidth: CGFloat = 200
    /// Thickness of the collapsed pill when docked to a side edge.
    static let sideThickness: CGFloat = 40
    /// Base length of the collapsed side pill before live indicators are added.
    static let sideBaseLength: CGFloat = 96

    static func current(edge: NotchEdge, edgeOffset: Double) -> NotchGeometry {
        let screens = NSScreen.screens
        let screen = screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? screens.first!
        return NotchGeometry(screen: screen, edge: edge, edgeOffset: edgeOffset)
    }

    init(screen: NSScreen, edge: NotchEdge, edgeOffset: Double) {
        screenFrame = screen.frame
        visibleFrame = screen.visibleFrame
        self.edge = edge
        self.edgeOffset = min(1, max(0, edgeOffset))
        let inset = screen.safeAreaInsets.top
        if inset > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            hasNotch = true
            notchWidth = screen.frame.width - left.width - right.width
            notchHeight = inset
        } else {
            hasNotch = false
            notchWidth = NotchGeometry.fallbackWidth
            notchHeight = NSApplication.shared.mainMenu?.menuBarHeight ?? 24
        }
    }

    init(screenFrame: NSRect, edge: NotchEdge = .top, edgeOffset: Double = 0.5,
         hasNotch: Bool, notchWidth: CGFloat, notchHeight: CGFloat) {
        self.screenFrame = screenFrame
        self.visibleFrame = screenFrame
        self.edge = edge
        self.edgeOffset = edgeOffset
        self.hasNotch = hasNotch
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
    }

    /// Transparent margin around the shape so the drop shadow has room to fade
    /// out completely before the window edge (the shadow reaches ~50pt; a
    /// smaller margin shows as a hard rectangle around the panel). The window
    /// ignores mouse events while the cursor is in this margin.
    static let shadowMargin: CGFloat = 80

    /// Window frame: the shape frame plus shadow margin on every side that is
    /// not glued to the screen edge.
    func windowFrame(for size: CGSize) -> NSRect {
        let m = NotchGeometry.shadowMargin
        var f = frame(for: size)
        switch edge {
        case .top:
            f.origin.x -= m; f.size.width += 2 * m
            f.origin.y -= m; f.size.height += m
        case .left:
            f.size.width += m
            f.origin.y -= m; f.size.height += 2 * m
        case .right:
            f.origin.x -= m; f.size.width += m
            f.origin.y -= m; f.size.height += 2 * m
        }
        return f
    }

    /// Frame of the visible notch shape for a panel of the given size, hugging the configured edge.
    func frame(for size: CGSize) -> NSRect {
        switch edge {
        case .top:
            return NSRect(x: (screenFrame.midX - size.width / 2).rounded(),
                          y: screenFrame.maxY - size.height,
                          width: size.width, height: size.height)
        case .left, .right:
            // Anchor the panel's vertical centre at `edgeOffset` along the visible
            // area (so it never hides under the menu bar or Dock), then clamp.
            let centerY = visibleFrame.maxY - CGFloat(edgeOffset) * visibleFrame.height
            var y = (centerY - size.height / 2).rounded()
            y = min(max(y, visibleFrame.minY), visibleFrame.maxY - size.height)
            let x = edge == .left ? screenFrame.minX : screenFrame.maxX - size.width
            return NSRect(x: x, y: y, width: size.width, height: size.height)
        }
    }
}

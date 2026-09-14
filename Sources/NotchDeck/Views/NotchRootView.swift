import SwiftUI

struct NotchRootView: View {
    @EnvironmentObject var vm: NotchViewModel

    private var shape: NotchShape {
        NotchShape(edge: vm.edge,
                   earRadius: NotchViewModel.earRadius,
                   bottomRadius: vm.isExpanded ? NotchViewModel.bottomRadius : 12)
    }

    /// The collapsed top pill stays flat so it blends into the hardware notch.
    private var shadowStrength: Double {
        if vm.isExpanded { return 1 }
        return vm.edge == .top ? 0 : 0.7
    }

    var body: some View {
        ZStack(alignment: vm.alignment) {
            ShadowedNotch(size: vm.currentSize, edge: vm.edge,
                          bottomRadius: vm.isExpanded ? NotchViewModel.bottomRadius : 12,
                          strength: shadowStrength)

            // Content is laid out at its final size; the controller fades it out
            // before the shape shrinks and fades it in after the shape has grown,
            // so nothing is drawn outside the black mid-animation.
            Group {
                if vm.isExpanded {
                    ExpandedContent()
                        .frame(width: vm.expandedSize.width, height: vm.expandedSize.height)
                        .opacity(vm.showExpandedContent ? 1 : 0)
                        .transition(.identity)
                } else {
                    CollapsedContent()
                        .frame(width: vm.collapsedSize.width, height: vm.collapsedSize.height)
                        .opacity(vm.showCollapsedContent ? 1 : 0)
                        .transition(.identity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: vm.alignment)
            // Mask with the very same animated drawing as the black fill, so the
            // content can never show outside the shape, even mid-animation.
            .mask(ShadowedNotch(size: vm.currentSize, edge: vm.edge,
                                bottomRadius: vm.isExpanded ? NotchViewModel.bottomRadius : 12,
                                strength: 0))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: vm.alignment)
        .preferredColorScheme(.dark)
    }
}

/// Draws the notch silhouette with a soft drop shadow, rasterized with Core
/// Graphics in a Canvas that spans the whole window. SwiftUI's `.shadow`
/// truncates the blur about one radius out, which shows as a faint hard
/// rectangle on flat backgrounds and pops when the renderer switches between
/// its animating and static paths; a CG shadow fades all the way out.
struct ShadowedNotch: View, Animatable {
    var size: CGSize
    var edge: NotchEdge
    var bottomRadius: CGFloat
    var strength: Double

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(size.width, size.height), bottomRadius) }
        set { size = CGSize(width: newValue.first.first, height: newValue.first.second); bottomRadius = newValue.second }
    }

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, canvasSize in
            let rect = shapeRect(in: canvasSize)
            let path = NotchShape(edge: edge, earRadius: NotchViewModel.earRadius, bottomRadius: bottomRadius)
                .path(in: rect).cgPath
            context.withCGContext { cg in
                if strength > 0 {
                    // Soft ambient shadow, offset slightly downwards (the Canvas context is flipped).
                    cg.saveGState()
                    cg.setShadow(offset: CGSize(width: 0, height: 6), blur: 30,
                                 color: CGColor(gray: 0, alpha: 0.6 * strength))
                    cg.addPath(path)
                    cg.setFillColor(CGColor(gray: 0, alpha: 1))
                    cg.fillPath()
                    cg.restoreGState()
                    // Tight contact shadow.
                    cg.saveGState()
                    cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 3,
                                 color: CGColor(gray: 0, alpha: 0.5 * strength))
                    cg.addPath(path)
                    cg.fillPath()
                    cg.restoreGState()
                }
                cg.addPath(path)
                cg.setFillColor(CGColor(gray: 0, alpha: 1))
                cg.fillPath()
            }
        }
        .allowsHitTesting(false)
    }

    private func shapeRect(in window: CGSize) -> CGRect {
        switch edge {
        case .top: return CGRect(x: (window.width - size.width) / 2, y: 0, width: size.width, height: size.height)
        case .left: return CGRect(x: 0, y: (window.height - size.height) / 2, width: size.width, height: size.height)
        case .right: return CGRect(x: window.width - size.width, y: (window.height - size.height) / 2, width: size.width, height: size.height)
        }
    }
}

private extension Alignment {
    var unitPoint: UnitPoint {
        switch self {
        case .leading: return .leading
        case .trailing: return .trailing
        default: return .top
        }
    }
}

// MARK: - Collapsed

/// Tiny live indicators shown while the panel is closed. On the top edge they
/// flank the camera; on a side edge they stack vertically.
struct CollapsedContent: View {
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var pomodoro: PomodoroEngine

    private var showTasks: Bool { store.settings.showTaskCountInNotch && store.pendingTaskCount > 0 }
    private var showTimer: Bool { store.settings.showTimerInNotch && !pomodoro.isIdle }

    var body: some View {
        if vm.edge == .top {
            HStack(spacing: 0) {
                HStack(spacing: 4) { if showTasks { taskBadge } }
                    .frame(width: vm.collapsedWingWidth)
                Spacer().frame(width: vm.geometry.notchWidth)
                HStack(spacing: 5) { if showTimer { timerRing; timerText } }
                    .frame(width: vm.collapsedWingWidth)
            }
            .padding(.horizontal, NotchViewModel.earRadius)
            .frame(height: vm.geometry.notchHeight)
        } else {
            VStack(spacing: 10) {
                if showTimer {
                    VStack(spacing: 3) { timerRing; timerText }
                }
                Image(systemName: "rectangle.grid.1x2")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryText)
                if showTasks {
                    VStack(spacing: 2) { taskBadge }
                }
            }
            .frame(width: NotchGeometry.sideThickness)
        }
    }

    private var taskBadge: some View {
        Group {
            Image(systemName: "checklist")
                .font(.system(size: 10, weight: .bold))
            Text("\(store.pendingTaskCount)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(Theme.accent(for: .tasks))
    }

    private var timerRing: some View {
        ProgressRing(progress: pomodoro.progress, lineWidth: 2.5, tint: Theme.accent(for: pomodoro.phase))
            .frame(width: 12, height: 12)
    }

    private var timerText: some View {
        Text(pomodoro.remaining.clockString)
            .font(.system(size: vm.edge == .top ? 11 : 9, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(pomodoro.isRunning ? Theme.text : Theme.secondaryText)
    }
}

// MARK: - Expanded

struct ExpandedContent: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                if vm.showingSettings {
                    SettingsPane()
                } else {
                    switch vm.selectedTab {
                    case .notes: NotesWidget()
                    case .tasks: TasksWidget()
                    case .pomodoro: PomodoroWidget()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            .padding(.top, 10)
        }
        .padding(.leading, vm.edge == .left ? NotchViewModel.earRadius : 0)
        .padding(.trailing, vm.edge == .right ? NotchViewModel.earRadius : 0)
    }

    /// On the top edge the tab strip sits left of the camera and the controls to
    /// its right; on a side edge it is a plain toolbar.
    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(NotchTab.allCases) { tab in
                    TabButton(tab: tab, selected: !vm.showingSettings && vm.selectedTab == tab) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            vm.showingSettings = false
                            vm.selectedTab = tab
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: vm.edge == .top ? .trailing : .leading)

            if vm.edge == .top {
                Spacer().frame(width: vm.geometry.notchWidth)
            }

            HStack(spacing: 2) {
                IconButton(symbol: vm.isPinned ? "pin.fill" : "pin",
                           help: vm.isPinned ? "Unpin (close on mouse out)" : "Keep open",
                           tint: vm.isPinned ? Theme.text : Theme.secondaryText) {
                    vm.isPinned.toggle()
                }
                IconButton(symbol: "gearshape",
                           help: "Settings",
                           tint: vm.showingSettings ? Theme.text : Theme.secondaryText) {
                    withAnimation(.easeOut(duration: 0.15)) { vm.showingSettings.toggle() }
                }
            }
            .frame(maxWidth: vm.edge == .top ? .infinity : nil, alignment: .leading)
        }
        .padding(.horizontal, NotchViewModel.earRadius + 8)
        .padding(.top, vm.edge == .top ? 0 : 10)
        .frame(height: vm.edge == .top ? max(vm.geometry.notchHeight, 32) : 42)
    }
}

private struct TabButton: View {
    let tab: NotchTab
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 12, weight: .semibold))
                if selected {
                    Text(tab.title)
                        .font(.system(size: 12, weight: .semibold))
                        .fixedSize()
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .foregroundStyle(selected ? Theme.accent(for: tab) : (hovering ? Theme.text : Theme.secondaryText))
            .padding(.horizontal, selected ? 10 : 7)
            .frame(height: 26)
            .background(selected || hovering ? Theme.surface : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tab.title)
    }
}

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 6
    var tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(Theme.surface, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: progress)
        }
    }
}

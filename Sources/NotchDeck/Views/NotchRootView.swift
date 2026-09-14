import SwiftUI

struct NotchRootView: View {
    @EnvironmentObject var vm: NotchViewModel

    private var shape: NotchShape {
        NotchShape(edge: vm.edge,
                   earRadius: NotchViewModel.earRadius,
                   bottomRadius: vm.isExpanded ? NotchViewModel.bottomRadius : 12)
    }

    var body: some View {
        ZStack(alignment: vm.alignment) {
            shape
                .fill(Theme.background)
                .frame(width: vm.currentSize.width, height: vm.currentSize.height)
                .shadow(color: .black.opacity(vm.isExpanded ? 0.45 : 0), radius: 18,
                        x: vm.edge == .left ? 6 : (vm.edge == .right ? -6 : 0),
                        y: vm.edge == .top ? 8 : 0)

            Group {
                if vm.isExpanded {
                    ExpandedContent()
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: vm.alignment.unitPoint)))
                } else {
                    CollapsedContent()
                        .transition(.opacity)
                }
            }
            .frame(width: vm.currentSize.width, height: vm.currentSize.height)
            .clipShape(shape)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: vm.alignment)
        .preferredColorScheme(.dark)
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

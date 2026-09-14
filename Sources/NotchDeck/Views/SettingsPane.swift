import SwiftUI

struct SettingsPane: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var pomodoro: PomodoroEngine
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        ScrollView(.vertical) {
            columns
        }
        .scrollIndicators(.never)
        .onChange(of: store.settings.pomodoro) { _, _ in pomodoro.settingsDidChange() }
    }

    private var columns: some View {
        HStack(alignment: .top, spacing: 20) {
            section("Pomodoro") {
                durationRow("Focus", value: $store.settings.pomodoro.focusMinutes, range: 1...120)
                durationRow("Short break", value: $store.settings.pomodoro.shortBreakMinutes, range: 1...60)
                durationRow("Long break", value: $store.settings.pomodoro.longBreakMinutes, range: 1...90)
                stepperRow("Sessions before long break", value: $store.settings.pomodoro.sessionsBeforeLongBreak, range: 1...12, suffix: "")
                toggleRow("Auto-start next phase", isOn: $store.settings.pomodoro.autoStartNext)
                toggleRow("Play sound when a phase ends", isOn: $store.settings.pomodoro.playSound)
            }

            section("Placement") {
                Picker("", selection: $store.settings.edge) {
                    ForEach(NotchEdge.allCases) { edge in
                        Image(systemName: edge.symbol).tag(edge)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                Text(store.settings.edge.title)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                if store.settings.edge.isSide {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.tertiaryText)
                        Slider(value: $store.settings.edgeOffset, in: 0.05...0.95)
                            .controlSize(.mini)
                            .tint(Theme.accent(for: .pomodoro))
                        Image(systemName: "arrow.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.tertiaryText)
                    }
                }
                toggleRow("Open on hover", isOn: $store.settings.openOnHover)
                toggleRow("Show pending task count", isOn: $store.settings.showTaskCountInNotch)
                toggleRow("Show timer while running", isOn: $store.settings.showTimerInNotch)
                toggleRow("Launch at login", isOn: $launchAtLogin)
                    .disabled(!LaunchAtLogin.isAvailable)
                    .onChange(of: launchAtLogin) { _, v in LaunchAtLogin.isEnabled = v }

                animationSection
                    .padding(.top, 6)

                Text("Data lives in ~/Library/Application Support/NotchDeck")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
    }

    private var isDefaultAnimation: Bool {
        store.settings.openDuration == AppSettings.defaultOpenDuration
            && store.settings.closeDuration == AppSettings.defaultCloseDuration
    }

    private var animationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ANIMATION")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Theme.tertiaryText)
                Spacer()
                Button("Reset to default") {
                    store.settings.openDuration = AppSettings.defaultOpenDuration
                    store.settings.closeDuration = AppSettings.defaultCloseDuration
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isDefaultAnimation ? Theme.tertiaryText : Theme.accent(for: .pomodoro))
                .disabled(isDefaultAnimation)
            }
            durationSlider("Open", value: $store.settings.openDuration)
            durationSlider("Close", value: $store.settings.closeDuration)
        }
    }

    private func durationSlider(_ label: String, value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .frame(width: 40, alignment: .leading)
            Slider(value: value, in: AppSettings.durationRange, step: 0.01)
                .controlSize(.mini)
                .tint(Theme.accent(for: .pomodoro))
            Text(String(format: "%.2f s", value.wrappedValue))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 44, alignment: .trailing)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(Theme.tertiaryText)
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func durationRow(_ label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        stepperRow(label, value: value, range: range, suffix: " min")
    }

    private func stepperRow(_ label: String, value: Binding<Int>, range: ClosedRange<Int>, suffix: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.text)
            Spacer()
            HStack(spacing: 0) {
                IconButton(symbol: "minus", size: 10) { value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1) }
                Text("\(value.wrappedValue)\(suffix)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .frame(minWidth: 48)
                IconButton(symbol: "plus", size: 10) { value.wrappedValue = min(range.upperBound, value.wrappedValue + 1) }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.text)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .tint(Theme.accent(for: .pomodoro))
    }
}

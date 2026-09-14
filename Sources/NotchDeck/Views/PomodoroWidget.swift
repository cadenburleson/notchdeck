import SwiftUI

struct PomodoroWidget: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var pomodoro: PomodoroEngine

    private var tint: Color { Theme.accent(for: pomodoro.phase) }

    var body: some View {
        HStack(spacing: 24) {
            ZStack {
                ProgressRing(progress: pomodoro.progress, lineWidth: 9, tint: tint)
                VStack(spacing: 2) {
                    Text(pomodoro.remaining.clockString)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                    Text(pomodoro.phase.title.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(tint)
                }
            }
            .frame(width: 170, height: 170)
            .padding(.leading, 6)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(pomodoro.phase.isBreak ? "Take a breather" : "Deep work")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    ForEach(0..<max(1, store.settings.pomodoro.sessionsBeforeLongBreak), id: \.self) { i in
                        Capsule()
                            .fill(i < pomodoro.completedInCycle ? Theme.accent(for: .pomodoro) : Theme.surfaceHover)
                            .frame(width: 22, height: 5)
                    }
                    Text("\(pomodoro.completedInCycle)/\(store.settings.pomodoro.sessionsBeforeLongBreak)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.tertiaryText)
                        .padding(.leading, 4)
                }

                HStack(spacing: 8) {
                    PillButton(title: pomodoro.isRunning ? "Pause" : (pomodoro.isIdle ? "Start" : "Resume"),
                               symbol: pomodoro.isRunning ? "pause.fill" : "play.fill",
                               tint: tint, prominent: true) {
                        pomodoro.toggle()
                    }
                    IconButton(symbol: "arrow.counterclockwise", help: "Reset phase") { pomodoro.reset() }
                    IconButton(symbol: "forward.end.fill", help: "Skip to next phase") { pomodoro.skip() }
                }

                Text("\(store.totalFocusSessions) focus sessions total")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    private var subtitle: String {
        let s = store.settings.pomodoro
        switch pomodoro.phase {
        case .focus: return "\(s.focusMinutes) min of focus, then a \(s.shortBreakMinutes) min break."
        case .shortBreak: return "\(s.shortBreakMinutes) min break before the next session."
        case .longBreak: return "You earned \(s.longBreakMinutes) min. Step away from the screen."
        }
    }
}

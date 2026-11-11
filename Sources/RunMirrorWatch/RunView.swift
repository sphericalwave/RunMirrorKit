//
//  RunView.swift
//  RunMirrorKit
//
//  The hold or rest in progress, glanced at mid-hold: what it is, which
//  side and which are done, a big countdown, the round, and ⏮ ⏯ ⏭ as large as the screen
//  allows. ⏮ once starts the hold over, twice goes back one; ⏭ goes on —
//  the phone's own buttons, run on the phone. Paused long enough, it asks
//  "Still training?" instead (`LongPause`).
//

#if os(watchOS)
import RunMirrorKit
import SwiftUI

public struct RunView: View {
    let mirror: RunMirror
    let state: WatchRunState

    public init(mirror: RunMirror, state: WatchRunState) {
        self.mirror = mirror
        self.state = state
    }

    public var body: some View {
        if mirror.longPause == .none {
            clockView
        } else {
            stillTraining
        }
    }

    /// Resume or End, the phone's own; End needs no second ask, this is one.
    private var stillTraining: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Still training?")
                    .font(.headline)
                Text(mirror.longPause == .end
                     ? "Workout ended on the watch to save battery. Resume starts a new one."
                     : "The workout has been paused a while.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    mirror.send(.toggle)
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(role: .destructive) {
                    mirror.send(.end)
                } label: {
                    Text("End Workout")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(!mirror.phone.isReachable)
        }
    }

    private var clockView: some View {
        VStack(spacing: 2) {
            heading
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                VStack(spacing: 0) {
                    countdown(at: context.date)
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(state.isResting ? .secondary : .primary)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    status(at: context.date)
                }
            }
            Spacer(minLength: 0)
            controls
        }
        .padding(.horizontal, 4)
    }

    /// Counts itself down while running — on the Always On display too,
    /// where the timeline slows to once a minute.
    @ViewBuilder
    private func countdown(at date: Date) -> some View {
        if let endsAt = state.endsAt, endsAt > date {
            Text(timerInterval: date...endsAt, countsDown: true)
        } else {
            Text(clock(state.remainingSec(at: date)))
        }
    }

    @ViewBuilder
    private var heading: some View {
        if state.isResting {
            HStack(spacing: 6) {
                Text("Rest")
                    .font(.headline)
                    .foregroundStyle(.tint)
                if !state.sides.isEmpty {
                    SideBadges(sides: state.sides)
                }
            }
            if let next = state.next {
                Text("next: \(next)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        } else {
            Text(state.exercise)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
            if !state.side.isEmpty {
                HStack(spacing: 6) {
                    Text(state.side)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                    if !state.sides.isEmpty {
                        SideBadges(sides: state.sides)
                    }
                }
            }
        }
    }

    /// The round and heart rate — or, when something's wrong with the link,
    /// that instead, since then it matters more.
    @ViewBuilder
    private func status(at date: Date) -> some View {
        if !mirror.phone.isReachable {
            Label("Phone not connected", systemImage: "iphone.slash")
                .font(.footnote)
                .foregroundStyle(.orange)
        } else if mirror.phoneIsSilent(at: date) {
            Label("Waiting for iPhone…", systemImage: "hourglass")
                .font(.footnote)
                .foregroundStyle(.orange)
        } else {
            HStack(spacing: 8) {
                Text(state.isPaused ? "Paused" : "Round \(state.round)/\(state.rounds)")
                if let bpm = mirror.workout.heartRate {
                    Label("\(bpm)", systemImage: "heart.fill")
                        .foregroundStyle(.red)
                        .accessibilityLabel("Heart rate \(bpm)")
                }
            }
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 4) {
            button("backward.end.fill", label: "Back", .back)
                .accessibilityHint("Starts this hold over. Twice goes to the one before.")
            button(state.isPaused ? "play.fill" : "pause.fill",
                   label: state.isPaused ? "Resume" : "Pause", .toggle)
            button("forward.end.fill", label: state.isResting ? "Go now" : "Forward", .forward)
        }
        .disabled(!mirror.phone.isReachable)
    }

    private func button(_ systemImage: String, label: String, _ command: WatchRunCommand) -> some View {
        Button {
            mirror.send(command)
        } label: {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .accessibilityLabel(label)
    }

    private func clock(_ seconds: Int) -> String {
        "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}
#endif

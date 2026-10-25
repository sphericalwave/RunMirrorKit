//
//  RunView.swift
//  RunMirrorKit
//
//  The hold or rest in progress, glanced at mid-hold: what it is, which
//  side, a big countdown, the round, and ⏮ ⏯ ⏭ as large as the screen
//  allows. ⏮ once starts the hold over, twice goes back one; ⏭ goes on —
//  the phone's own buttons, run on the phone.
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
            Text("Rest")
                .font(.headline)
                .foregroundStyle(.tint)
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
                Text(state.side)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tint)
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

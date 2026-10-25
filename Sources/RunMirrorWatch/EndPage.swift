//
//  EndPage.swift
//  RunMirrorKit
//
//  End, a swipe from the clock and asked twice, so a brush of the wrist
//  can't stop a run. With the phone in reach it ends the run there, for its
//  review. Without, it can only end the workout on the wrist — the run on
//  the phone is left as it is.
//

#if os(watchOS)
import RunMirrorKit
import SwiftUI

public struct EndPage: View {
    let mirror: RunMirror
    @State private var confirming = false

    public init(mirror: RunMirror) {
        self.mirror = mirror
    }

    public var body: some View {
        VStack(spacing: 8) {
            if let summary {
                Text(summary)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button(role: .destructive) {
                confirming = true
            } label: {
                Label(reachable ? "End" : "End on watch", systemImage: "stop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .tint(.red)
            if !reachable {
                Text("Phone not connected. This ends the watch workout; the run stays on your iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if mirror.phone.sendFailed {
                Text("Didn't reach your iPhone. Try again.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 4)
        .confirmationDialog(reachable ? wording.endTitle : "End on watch?", isPresented: $confirming) {
            Button(reachable ? "End" : "End on watch", role: .destructive) {
                if reachable {
                    mirror.send(.end)
                } else {
                    mirror.endOnWatch()
                }
            }
        } message: {
            Text(reachable ? wording.endMessage : "Your iPhone's run carries on.")
        }
    }

    private var reachable: Bool { mirror.phone.isReachable }

    private var wording: WatchRunBrand.Wording { mirror.brand.wording }

    private var summary: String? {
        guard mirror.workout.isActive else { return nil }
        let kcal = "\(Int(mirror.workout.activeKcal)) kcal"
        return mirror.workout.heartRate.map { "\(kcal) · ♥ \($0)" } ?? kcal
    }
}
#endif

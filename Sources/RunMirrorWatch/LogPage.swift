//
//  LogPage.swift
//  RunMirrorKit
//
//  A rated set just ended: log it on the wrist. Reps, then technique,
//  effort and discomfort, each starting from the phone's guess, then where
//  the next round goes — down a level, the same, or up — with the phone's
//  suggestion picked. Log sends it; the phone takes it from there, exactly as
//  if it had been logged on the phone.
//

#if os(watchOS)
import RunMirrorKit
import SwiftUI

struct LogPage: View {
    let mirror: RunMirror
    let request: WatchSetLogRequest

    @State private var reps: Int
    @State private var rpt: Int
    @State private var rpe: Int
    @State private var rpd: Int
    @State private var decision: WatchSetDecision

    init(mirror: RunMirror, request: WatchSetLogRequest) {
        self.mirror = mirror
        self.request = request
        _reps = State(initialValue: request.reps)
        _rpt = State(initialValue: request.rpt)
        _rpe = State(initialValue: request.rpe)
        _rpd = State(initialValue: request.rpd)
        _decision = State(initialValue: request.suggestion)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(request.exercise)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                counter("Reps", value: $reps, range: 0...99)
                counter("Technique", value: $rpt, range: 1...10)
                counter("Effort", value: $rpe, range: 1...10)
                counter("Discomfort", value: $rpd, range: 0...10)
                decisions
                Button {
                    mirror.log(WatchSetLog(requestID: request.id, reps: reps, rpt: rpt, rpe: rpe, rpd: rpd,
                                           decision: decision))
                } label: {
                    Label("Log", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!mirror.phone.isReachable)
                if !mirror.phone.isReachable {
                    Label("Phone not connected", systemImage: "iphone.slash")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
        .onChange(of: request.id) {
            reps = request.reps
            rpt = request.rpt
            rpe = request.rpe
            rpd = request.rpd
            decision = request.suggestion
        }
    }

    /// − value +, the buttons big enough for a fingertip.
    private func counter(_ label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 4) {
            Button {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1)
            } label: {
                Image(systemName: "minus").frame(width: 36, height: 32)
            }
            .disabled(value.wrappedValue <= range.lowerBound)
            .accessibilityLabel("Less \(label.lowercased())")
            VStack(spacing: 0) {
                Text("\(value.wrappedValue)")
                    .font(.title3.bold().monospacedDigit())
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            Button {
                value.wrappedValue = min(range.upperBound, value.wrappedValue + 1)
            } label: {
                Image(systemName: "plus").frame(width: 36, height: 32)
            }
            .disabled(value.wrappedValue >= range.upperBound)
            .accessibilityLabel("More \(label.lowercased())")
        }
        .buttonStyle(.bordered)
    }

    /// Down a level, the same, or up — for the next round.
    private var decisions: some View {
        VStack(spacing: 4) {
            Text("Next round")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                choice(.regress, systemImage: "arrow.down", enabled: request.regressTo != nil)
                choice(.repeat, systemImage: "equal", enabled: true)
                choice(.progress, systemImage: "arrow.up", enabled: request.progressTo != nil)
            }
            if let to = target(decision) {
                Text(to)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func target(_ d: WatchSetDecision) -> String? {
        switch d {
        case .regress: request.regressTo
        case .repeat: nil
        case .progress: request.progressTo
        }
    }

    private func choice(_ d: WatchSetDecision, systemImage: String, enabled: Bool) -> some View {
        Button {
            decision = d
        } label: {
            Image(systemName: systemImage)
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.bordered)
        .tint(decision == d ? .accentColor : .gray)
        .overlay(alignment: .topTrailing) {
            if d == request.suggestion {
                Circle().fill(.green).frame(width: 6, height: 6).padding(3)
            }
        }
        .disabled(!enabled)
        .accessibilityLabel(d == .regress ? "Regress" : d == .progress ? "Progress" : "Repeat")
        .accessibilityAddTraits(decision == d ? .isSelected : [])
    }
}
#endif

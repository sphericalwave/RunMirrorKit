//
//  RunRootView.swift
//  RunMirrorKit
//
//  Whichever the run is: going (the clock, with End a swipe away, where the
//  Workout app keeps its controls), done, put away for later, or not
//  started — then there's only one thing to say.
//

#if os(watchOS)
import RunMirrorKit
import SwiftUI

public struct RunRootView: View {
    let mirror: RunMirror
    /// The clock is page 1; End is page 0, to its left.
    @State private var page = 1

    public init(mirror: RunMirror) {
        self.mirror = mirror
    }

    private var wording: WatchRunBrand.Wording { mirror.brand.wording }

    public var body: some View {
        Group {
            if let state = mirror.state {
                switch state.status {
                case .running:
                    TabView(selection: $page) {
                        EndPage(mirror: mirror).tag(0)
                        RunView(mirror: mirror, state: state).tag(1)
                    }
                    .tabViewStyle(.page)
                case .finished:
                    message(wording.doneTitle, detail: wording.doneDetail,
                            systemImage: "checkmark.circle.fill", tint: .green,
                            note: mirror.workout.notSaved)
                case .left:
                    message(wording.leftTitle, detail: wording.leftDetail,
                            systemImage: "pause.circle.fill", tint: .orange)
                }
            } else {
                message(wording.idleTitle, detail: wording.idleDetail,
                        systemImage: wording.idleSymbol, tint: .accentColor,
                        note: mirror.workout.notSaved)
            }
        }
        .onChange(of: mirror.state?.runID) { page = 1 }
        .onChange(of: mirror.state?.status) { page = 1 }
    }

    /// `note`: why the workout just ended wasn't kept in Health.
    private func message(_ title: String, detail: String, systemImage: String, tint: Color,
                         note: String? = nil) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(tint)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
}
#endif

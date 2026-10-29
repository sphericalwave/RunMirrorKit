//
//  SideBadges.swift
//  RunMirrorKit
//
//  An exercise's sides as letters in circles — filled once held, ringed
//  while held, faint until then — for telling at a glance whether the right's
//  been done yet. Sized to sit on the side's own line, so the countdown keeps
//  its room.
//

#if os(watchOS)
import RunMirrorKit
import SwiftUI

struct SideBadges: View {
    let sides: [WatchRunState.Side]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(sides.enumerated()), id: \.offset) { _, side in
                badge(side)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sides.map { "\($0.name) \(spoken($0.status))" }.joined(separator: ", "))
    }

    private func badge(_ side: WatchRunState.Side) -> some View {
        Text(side.label)
            .font(.system(size: 11, weight: side.status == .upcoming ? .medium : .bold, design: .rounded))
            .foregroundStyle(letterStyle(side.status))
            .frame(width: 20, height: 20)
            .background {
                switch side.status {
                case .done: Circle().fill(.tint)
                case .current: Circle().strokeBorder(.tint, lineWidth: 2)
                case .upcoming: Circle().strokeBorder(.secondary.opacity(0.6), lineWidth: 1)
                }
            }
    }

    private func letterStyle(_ status: WatchRunState.Side.Status) -> AnyShapeStyle {
        switch status {
        case .done: AnyShapeStyle(.black)
        case .current: AnyShapeStyle(.tint)
        case .upcoming: AnyShapeStyle(.secondary)
        }
    }

    private func spoken(_ status: WatchRunState.Side.Status) -> String {
        switch status {
        case .done: "done"
        case .current: "now"
        case .upcoming: "to do"
        }
    }
}
#endif

//
//  WatchWorkoutSaveRule.swift
//  RunMirrorKit
//
//  Whether the watch keeps its workout in Health at the end of a run. Only
//  the watch ever saves one — a run on the phone alone saves nothing — and
//  even then not when it would be a duplicate or wouldn't mean anything:
//
//  - the setting's off, or the run was under a minute;
//  - Flow recorded the same session (over a minute shared with one of its
//    workouts) — Flow's is the one with the strap's heart rate;
//  - any other app's workout covers more than half the run;
//  - the watch was off the wrist for most of it: heart rate readings cover
//    less than half the time the run was going.
//
//  The set logs are the phone's and are kept whatever this says.
//
//  `ownSourceApp` is the app's own `SWSourceApp` tag: a workout it saved
//  itself never counts against it.
//

import Foundation

public nonisolated enum WatchWorkoutSaveRule {
    public static let minimumDuration: TimeInterval = 60
    /// Shared with a Flow workout for longer than this, it's the same session.
    public static let flowOverlap: TimeInterval = 60
    /// Covered by any other app's workout for more than this share of the run.
    public static let otherOverlapShare = 0.5
    /// Heart rate covering less than this share of the run means off-wrist.
    public static let minimumHeartRateCoverage = 0.5
    /// How long a reading counts for. A workout reads heart rate every few
    /// seconds while the watch is on the wrist, and none at all while it's off.
    public static let heartRateReadingSpan: TimeInterval = 15
    /// Flow's iPhone app — the source of every workout it saves.
    public static let flowBundlePrefix = "com.sphericalwave.jiujitsu.flow"

    /// A workout already in Health that shares time with the run.
    public struct OtherWorkout: Equatable, Sendable {
        /// `ownApp`: saved by the app asking.
        public enum Source: Equatable, Sendable { case flow, ownApp, other }
        public let start: Date
        public let end: Date
        public let source: Source

        public init(start: Date, end: Date, source: Source) {
            self.start = start
            self.end = end
            self.source = source
        }

        public init(start: Date, end: Date, bundleID: String, sourceApp: String?, ownSourceApp: String) {
            let source: Source
            if sourceApp == ownSourceApp {
                source = .ownApp
            } else if bundleID.hasPrefix(WatchWorkoutSaveRule.flowBundlePrefix) {
                source = .flow
            } else {
                source = .other
            }
            self.init(start: start, end: end, source: source)
        }
    }

    public enum Decision: Equatable, Sendable {
        case save
        case turnedOff
        case tooShort
        case recordedByFlow
        case recordedElsewhere
        case offWrist

        /// What to tell the user when a workout they'd expect isn't saved.
        /// nil when there's nothing to explain.
        public var note: String? {
            switch self {
            case .save, .turnedOff, .tooShort: return nil
            case .recordedByFlow: return "Flow recorded this session — watch workout not saved"
            case .recordedElsewhere: return "Another app recorded this session — watch workout not saved"
            case .offWrist: return "Watch was off-wrist — workout not saved"
            }
        }
    }

    /// `activeDuration` is the run less its pauses, which read no heart rate.
    public static func decide(enabled: Bool, start: Date, end: Date, activeDuration: TimeInterval,
                       heartRateTimes: [Date], others: [OtherWorkout]) -> Decision {
        guard enabled else { return .turnedOff }
        let duration = end.timeIntervalSince(start)
        guard duration >= minimumDuration else { return .tooShort }
        let shared = others.filter { $0.source != .ownApp }
            .map { ($0.source, overlap(start, end, $0.start, $0.end)) }
        if shared.contains(where: { $0.0 == .flow && $0.1 > flowOverlap }) { return .recordedByFlow }
        if shared.contains(where: { $0.1 / duration > otherOverlapShare }) { return .recordedElsewhere }
        if heartRateCoverage(heartRateTimes, start: start, end: end, activeDuration: activeDuration)
            < minimumHeartRateCoverage {
            return .offWrist
        }
        return .save
    }

    /// Seconds two spans share.
    public static func overlap(_ aStart: Date, _ aEnd: Date, _ bStart: Date, _ bEnd: Date) -> TimeInterval {
        max(0, min(aEnd, bEnd).timeIntervalSince(max(aStart, bStart)))
    }

    /// The share of `activeDuration` the readings account for, each standing
    /// for `heartRateReadingSpan` after it, within the run. 0...1.
    public static func heartRateCoverage(_ times: [Date], start: Date, end: Date,
                                  activeDuration: TimeInterval) -> Double {
        guard activeDuration > 0 else { return 0 }
        var covered: TimeInterval = 0
        var reached = start
        for time in times.sorted() {
            let from = max(time, reached)
            let to = min(time.addingTimeInterval(heartRateReadingSpan), end)
            if to > from {
                covered += to.timeIntervalSince(from)
                reached = to
            }
        }
        return min(1, covered / activeDuration)
    }
}

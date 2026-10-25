//
//  MacWatchRunLink.swift
//  RunMirrorKit
//
//  macOS half: a Mac has no paired watch, so a run has nobody to mirror to.
//

#if os(macOS)
import Foundation
import HealthKit
import Observation
import RunMirrorKit

@Observable
public final class WatchRunLink {
    public static let shared = WatchRunLink()

    public private(set) var heartRate: Int?
    public private(set) var heartRateAt: Date?
    public private(set) var workoutNote: WatchWorkoutNote?
    @ObservationIgnored public var onCommand: ((WatchRunCommand) -> Void)?
    @ObservationIgnored public var onHeartRate: ((Int) -> Void)?

    private init() {}

    public func activate(activityType: HKWorkoutActivityType) {}
    public func claim() {}
    public func release() {}
    public func publish(_ state: WatchRunState) {}
}
#endif

//
//  WatchWorkout.swift
//  RunMirrorKit
//
//  The run as a workout on the wrist: an HKWorkoutSession, which keeps this
//  app running wrist-down — so the countdown and haptics carry on — and
//  measures heart rate and calories while it does. What kind of workout it
//  records as is the app's (`WatchRunBrand`).
//
//  At the end it's saved to Health or thrown away, as the phone's setting
//  and `WatchWorkoutSaveRule` say: not when Flow or another app recorded the
//  same session, nor when the watch spent most of it off the wrist (told by
//  how much of the run its heart rate readings cover). A saved one is tagged — the app's brand name, a sync identifier,
//  the workout's name — so another app reading Health (Flow, say) can tell
//  it's this app's and leave it be. One shorter than a minute is never
//  kept: that's a run opened and put away, not a workout.
//
//  Only this app ever saves a run's workout: the phone writes none.
//

#if os(watchOS)
import Foundation
import HealthKit
import Observation
import RunMirrorKit

@Observable
public final class WatchWorkout: NSObject {
    public let brand: WatchRunBrand

    /// The run this workout is for. nil for one started by the phone's
    /// launch before the run itself has arrived.
    public private(set) var runID: String?
    public private(set) var isActive = false
    public private(set) var heartRate: Int?
    public private(set) var activeKcal: Double = 0
    /// Why the workout couldn't start or save — the wrist is the only place
    /// to say so.
    public private(set) var problem: String?
    /// Why the last workout wasn't kept in Health, when there's a reason to give.
    public private(set) var notSaved: String?

    @ObservationIgnored public var onHeartRate: ((Int) -> Void)?
    @ObservationIgnored public var onNotSaved: ((WatchWorkoutNote) -> Void)?

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var planName = ""
    /// When each heart rate reading was taken — how long the watch was worn.
    @ObservationIgnored private var heartRateTimes: [Date] = []

    /// How a session is to end, decided before it has finished ending — by
    /// which time the next run's may have started.
    private struct Ending {
        let save: Bool
        let runID: String?
        let planName: String
        let heartRateTimes: [Date]
    }
    @ObservationIgnored private var ending: [ObjectIdentifier: Ending] = [:]

    public init(brand: WatchRunBrand) {
        self.brand = brand
        super.init()
    }

    public var configuration: HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = brand.activityType
        configuration.locationType = .indoor
        return configuration
    }

    public func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let heartRate = HKQuantityType(.heartRate)
        let energy = HKQuantityType(.activeEnergyBurned)
        do {
            // Workouts read too: another app's for the same session.
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType(), heartRate, energy],
                                                 read: [HKObjectType.workoutType(), heartRate, energy])
        } catch {
            problem = "Health access failed"
        }
    }

    public func start(runID: String?, planName: String) {
        guard !isActive, HKHealthStore.isHealthDataAvailable() else { return }
        let configuration = self.configuration
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            self.runID = runID
            self.planName = planName
            heartRate = nil
            activeKcal = 0
            heartRateTimes = []
            problem = nil
            notSaved = nil
            isActive = true
            let now = Date()
            session.startActivity(with: now)
            builder.beginCollection(withStart: now) { _, _ in }
        } catch {
            problem = "Couldn't start the workout"
        }
    }

    /// A workout the phone's launch started before the run arrived.
    public func adopt(runID: String, planName: String) {
        guard isActive, self.runID == nil else { return }
        self.runID = runID
        self.planName = planName
    }

    public func pause() {
        guard session?.state == .running else { return }
        session?.pause()
    }

    public func resume() {
        guard session?.state == .paused else { return }
        session?.resume()
    }

    /// Ends the session; the workout's saved or dropped once it has.
    public func end(save: Bool) {
        guard isActive, let session else { return }
        ending[ObjectIdentifier(session)] = Ending(save: save, runID: runID, planName: planName,
                                                   heartRateTimes: heartRateTimes)
        isActive = false
        self.session = nil
        builder = nil
        runID = nil
        session.end()
    }

    private func finish(_ session: HKWorkoutSession) async {
        guard let how = ending.removeValue(forKey: ObjectIdentifier(session)) else { return }
        let builder = session.associatedWorkoutBuilder()
        let end = Date()
        let start = builder.startDate ?? session.startDate ?? end
        do {
            try await builder.endCollection(at: end)
            let worthChecking = how.save && end.timeIntervalSince(start) >= WatchWorkoutSaveRule.minimumDuration
            let decision = WatchWorkoutSaveRule.decide(
                enabled: how.save, start: start, end: end,
                activeDuration: builder.elapsedTime(at: end),
                heartRateTimes: how.heartRateTimes,
                others: worthChecking ? await workouts(from: start, to: end) : [])
            if decision == .save {
                try await builder.addMetadata(Self.metadata(how, start: start, brand: brand.name))
                _ = try await builder.finishWorkout()
            } else {
                builder.discardWorkout()
                if let note = decision.note {
                    notSaved = note
                    onNotSaved?(WatchWorkoutNote(runID: how.runID ?? "", text: note))
                }
            }
        } catch {
            problem = "Couldn't save the workout to Health"
            builder.discardWorkout()
        }
    }

    /// Workouts in Health sharing any time with the run, from any app. None
    /// when reading workouts isn't allowed — Health doesn't say it isn't.
    private func workouts(from start: Date, to end: Date) async -> [WatchWorkoutSaveRule.OtherWorkout] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: []
        )
        let found = (try? await descriptor.result(for: store)) ?? []
        return found.map {
            WatchWorkoutSaveRule.OtherWorkout(start: $0.startDate, end: $0.endDate,
                                              bundleID: $0.sourceRevision.source.bundleIdentifier,
                                              sourceApp: $0.metadata?["SWSourceApp"] as? String,
                                              ownSourceApp: brand.name)
        }
    }

    /// What marks it as this app's. The sync identifier is the run plus
    /// when this part of it started, since a run picked up later is a
    /// second workout.
    private static func metadata(_ how: Ending, start: Date, brand: String) -> [String: Any] {
        let run = how.runID ?? "unknown"
        var metadata: [String: Any] = [
            HKMetadataKeyWorkoutBrandName: brand,
            HKMetadataKeyIndoorWorkout: true,
            HKMetadataKeySyncIdentifier: "\(brand).run.\(run).\(Int(start.timeIntervalSince1970))",
            HKMetadataKeySyncVersion: 1,
            "SWSourceApp": brand,
            "SWRunID": run,
        ]
        if !how.planName.isEmpty { metadata["SWWorkoutName"] = how.planName }
        return metadata
    }

    private func collected(bpm: Int?, at time: Date?, kcal: Double?) {
        if let kcal { activeKcal = kcal }
        guard let bpm else { return }
        if let time { heartRateTimes.append(time) }
        heartRate = bpm
        onHeartRate?(bpm)
    }
}

extension WatchWorkout: HKWorkoutSessionDelegate {
    public nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended else { return }
        Task { @MainActor in await self.finish(workoutSession) }
    }

    public nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.problem = "The workout stopped"
            self.end(save: WatchWorkoutSettings.saveToHealth)
        }
    }
}

extension WatchWorkout: HKLiveWorkoutBuilderDelegate {
    public nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                    didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heartRate = HKQuantityType(.heartRate)
        let energy = HKQuantityType(.activeEnergyBurned)
        let perMinute = HKUnit.count().unitDivided(by: .minute())
        let latest = collectedTypes.contains(heartRate) ? workoutBuilder.statistics(for: heartRate) : nil
        let bpm = (latest?.mostRecentQuantity()?.doubleValue(for: perMinute)).map { Int($0.rounded()) }
        let at = latest?.mostRecentQuantityDateInterval()?.start
        let kcal = collectedTypes.contains(energy)
            ? workoutBuilder.statistics(for: energy)?.sumQuantity()?.doubleValue(for: .kilocalorie())
            : nil
        Task { @MainActor in self.collected(bpm: bpm, at: at, kcal: kcal) }
    }

    public nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
#endif

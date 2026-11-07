//
//  RunMirror.swift
//  RunMirrorKit
//
//  The phone's run on the wrist. Takes each state the phone sends, counts
//  its hold or rest down locally from `endsAt`, taps the wrist as things
//  happen, and keeps a workout session going for as long as the run is.
//
//  Haptics: start as a hold begins, a click for each of its last three
//  seconds (a rest's too — it's leading into the next hold), stop as a rest
//  begins, success when the run's done. All of them play wrist-down, since
//  the workout session keeps the app running.
//

#if os(watchOS)
import Foundation
import Observation
import RunMirrorKit
import WatchKit

@Observable
public final class RunMirror {
    public private(set) var state: WatchRunState?
    public let phone = PhoneLink()
    public let workout: WatchWorkout
    public let brand: WatchRunBrand

    /// A hold this long overdue with nothing new from the phone means the
    /// phone isn't keeping up — closed, or out of reach.
    public static let silentAfter: TimeInterval = 20
    /// A run that ended longer ago than this isn't news: the app opens to
    /// its idle screen instead.
    public static let endedNewsFor: TimeInterval = 10 * 60

    @ObservationIgnored private var ticking: Task<Void, Never>?
    /// The last countdown second clicked, by segment, so each clicks once.
    @ObservationIgnored private var clicked: (segment: Int, second: Int)?
    /// When the phone was last asked for the run, so a silent one is asked
    /// every few seconds rather than every tick.
    @ObservationIgnored private var askedAt: Date?
    static let askEvery: TimeInterval = 5

    public init(brand: WatchRunBrand) {
        self.brand = brand
        workout = WatchWorkout(brand: brand)
        phone.onState = { [weak self] in self?.apply($0) }
        workout.onHeartRate = { [weak self] in self?.phone.send(heartRate: $0) }
        workout.onNotSaved = { [weak self] in self?.phone.send($0) }
        // The guess on the wrist may be wrong: whatever the phone has, as soon as it can say.
        phone.onCommandUndelivered = { [weak self] in self?.phone.requestState() }
    }

    public func activate() {
        phone.activate()
        Task {
            await workout.requestAuthorization()
            // A run that arrived while Health was asking.
            if let state { syncWorkout(state) }
        }
    }

    /// The phone launched this app into a workout for a run starting now;
    /// the run itself follows over WatchConnectivity.
    public func startLaunchedWorkout() {
        workout.start(runID: state?.status == .running ? state?.runID : nil,
                      planName: state?.planName ?? "")
    }

    /// ⏯ shows on the wrist straight away; the phone's answer, which comes
    /// back with the command's reply, confirms it or puts it right.
    public func send(_ command: WatchRunCommand) {
        WKInterfaceDevice.current().play(.click)
        if let guess = state?.applying(command, at: Date()) { apply(guess) }
        phone.send(command)
    }

    /// Phone out of reach: the workout on the wrist ends here, the run on the
    /// phone carries on untouched.
    public func endOnWatch() {
        workout.end(save: WatchWorkoutSettings.saveToHealth)
        state = nil
        stopTicking()
    }

    /// Running, not paused, and well past when the phone said it would end.
    public func phoneIsSilent(at date: Date) -> Bool {
        guard let state, state.status == .running, let endsAt = state.endsAt else { return false }
        return date.timeIntervalSince(endsAt) > Self.silentAfter
    }

    private func apply(_ new: WatchRunState) {
        let old = state
        // A message and the application context can cross; the older loses.
        if let old, old.runID == new.runID, new.sentAt < old.sentAt { return }
        if new.status != .running, Date().timeIntervalSince(new.sentAt) > Self.endedNewsFor {
            syncWorkout(new)
            state = nil
            stopTicking()
            return
        }
        state = new
        // Kept, so a workout ended without the phone follows its setting.
        UserDefaults.standard.set(new.saveToHealth, forKey: WatchWorkoutSettings.saveToHealthKey)
        cue(from: old, to: new)
        syncWorkout(new)
        if new.status == .running, !new.isPaused { startTicking() } else { stopTicking() }
    }

    private func syncWorkout(_ state: WatchRunState) {
        switch state.status {
        case .running:
            if workout.isActive, let runID = workout.runID, runID != state.runID {
                // A different run: the old one's over.
                workout.end(save: state.saveToHealth)
            }
            if workout.isActive {
                workout.adopt(runID: state.runID, planName: state.planName)
                state.isPaused ? workout.pause() : workout.resume()
            } else if !state.isPaused {
                workout.start(runID: state.runID, planName: state.planName)
            }
        case .finished, .left:
            workout.end(save: state.saveToHealth)
        }
    }

    private func cue(from old: WatchRunState?, to new: WatchRunState) {
        let sameRun = old?.runID == new.runID
        switch new.status {
        case .finished:
            if sameRun, old?.status == .running { play(.success) }
        case .left:
            break
        case .running:
            guard !sameRun || old?.segment != new.segment, let endsAt = new.endsAt else { return }
            // One well under way is the app catching up, not a start.
            guard endsAt.timeIntervalSinceNow > Double(new.durationSec) - 3 else { return }
            play(new.isResting ? .stop : .start)
        }
    }

    private func startTicking() {
        guard ticking == nil else { return }
        ticking = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func stopTicking() {
        ticking?.cancel()
        ticking = nil
    }

    private func tick() {
        guard let state, state.status == .running, !state.isPaused else { return }
        askIfStale(at: Date())
        let left = state.remainingSec(at: Date())
        guard (1...3).contains(left), clicked?.segment != state.segment || clicked?.second != left else { return }
        clicked = (state.segment, left)
        play(.click)
    }

    /// The hold or rest the watch has ran out and nothing newer came: the
    /// phone's run moved on without it, so ask for where it is now. The
    /// answer is whatever the phone would have sent; a phone that really is
    /// silent leaves "Waiting for iPhone…" up.
    private func askIfStale(at date: Date) {
        guard let endsAt = state?.endsAt, date > endsAt.addingTimeInterval(1) else { return }
        if let askedAt, date.timeIntervalSince(askedAt) < Self.askEvery { return }
        askedAt = date
        phone.requestState()
    }

    private func play(_ haptic: WKHapticType) {
        WKInterfaceDevice.current().play(haptic)
    }
}
#endif

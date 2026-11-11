//
//  WatchRunLink.swift
//  RunMirrorKit
//
//  iOS half: the phone's end of the watch app. Each change to the run goes
//  to the watch as application context — the latest wins, and it's waiting
//  whenever the watch app next wakes — and as a message too when the watch
//  is listening right now. The watch's buttons and heart rate come back as
//  messages (and, when the watch didn't keep its workout in Health, why),
//  which reach this app with the phone locked in a pocket since a
//  run keeps it going in the background with its audio.
//
//  A command is acted on the moment it lands — not on the run's next tick —
//  and the reply carries the run as it stands after it, so the watch is
//  right again within one round trip. Retries of one press share an id and
//  are acted on once; one that only made it as application context counts
//  if it's fresh (`WatchRunMessage.commandFreshFor`).
//
//  The first moment of a run also launches the watch app into its workout
//  (`startWatchApp`), so there's nothing to open on the wrist.
//
//  None of this touches the audio session: it works with the AirPods &
//  lock-screen controls off and music playing.
//
//  WCSession has one delegate. An app with something else on the session
//  (heart rate streamed from the watch, say) hands its delegate over with
//  `activate(…, sharingWith:)` before this takes it, or `claim()`s it back
//  for a run if the other took it later; anything that isn't the run's goes
//  on to that delegate.
//

#if os(iOS)
import Foundation
import HealthKit
import Observation
import RunMirrorKit
import WatchConnectivity

@Observable
public final class WatchRunLink: NSObject {
    public static let shared = WatchRunLink()

    /// The watch's latest reading, and when it came.
    public private(set) var heartRate: Int?
    public private(set) var heartRateAt: Date?
    /// Why the watch didn't keep its last workout in Health, for that run's review.
    public private(set) var workoutNote: WatchWorkoutNote?

    /// The run's ⏮ ⏯ ⏭ and End, while there's a run to send them to.
    /// Expected to `publish` the run as the command leaves it before it
    /// returns, so the reply can carry it.
    @ObservationIgnored public var onCommand: ((WatchRunCommand) -> Void)?
    @ObservationIgnored public var onHeartRate: ((Int) -> Void)?

    /// The last state sent, and the same before it was stamped — what the
    /// next one is compared with.
    @ObservationIgnored private var last: WatchRunState?
    @ObservationIgnored private var unstamped: WatchRunState?
    /// The run the watch app was last launched for, so it's launched once.
    @ObservationIgnored private var launchedFor: String?
    @ObservationIgnored private let health = HKHealthStore()
    /// What the watch app is launched into.
    @ObservationIgnored private var activityType = HKWorkoutActivityType.functionalStrengthTraining
    /// Whoever else listens on the session: what isn't the run's goes there.
    @ObservationIgnored private weak var other: WCSessionDelegate?
    /// The latest commands acted on, so a retry of one isn't acted on twice.
    @ObservationIgnored private var handledCommandIDs: [String] = []

    override private init() { super.init() }

    /// `activityType` is what the watch app's workout records as.
    public func activate(activityType: HKWorkoutActivityType) {
        self.activityType = activityType
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.delegate == nil else { return }
        session.delegate = self
        session.activate()
    }

    /// Takes the session back from whoever took it since — before a run, so
    /// the watch's buttons reach it. What isn't the run's is passed on.
    public func claim() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.delegate !== self else { return }
        if let current = session.delegate { other = current }
        session.delegate = self
        if session.activationState != .activated { session.activate() }
    }

    /// Hands the session back to whoever had it before `claim()`.
    public func release() {
        guard WCSession.isSupported(), WCSession.default.delegate === self, let other else { return }
        WCSession.default.delegate = other
    }

    /// Sends the run as it stands, unless the watch has it already.
    public func publish(_ state: WatchRunState) {
        guard state != unstamped else { return }
        // Paused long enough, the watch ended its workout: resuming is a new
        // one to launch, since the watch app may well be asleep by now.
        if let last, last.runID == state.runID, last.longPause(at: Date()) == .end {
            launchedFor = nil
        }
        unstamped = state
        var stamped = state
        stamped.sentAt = Date()
        last = stamped
        send(stamped)
        if state.status != .running {
            // Picked up again later, it's a new watch workout to launch.
            launchedFor = nil
        } else if !state.isPaused, launchedFor != state.runID {
            launchedFor = state.runID
            launchWatchApp()
        }
    }

    private func send(_ state: WatchRunState) {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }
        let message = WatchRunMessage.encode(state)
        try? session.updateApplicationContext(message)
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil, errorHandler: nil)
        }
    }

    /// Wakes the watch app straight into its workout. It's harmless when it
    /// fails — open on the wrist, the app starts the workout itself.
    private func launchWatchApp() {
        guard HKHealthStore.isHealthDataAvailable(), WCSession.isSupported(),
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType
        configuration.locationType = .indoor
        health.startWatchApp(with: configuration) { _, _ in }
    }

    /// Once per id: a command whose reply was lost comes again.
    private func perform(_ command: WatchRunCommand, id: String?) {
        if let id {
            guard !handledCommandIDs.contains(id) else { return }
            handledCommandIDs.append(id)
            if handledCommandIDs.count > 32 { handledCommandIDs.removeFirst() }
        }
        onCommand?(command)
    }

    private func handle(command: WatchRunCommand?, id: String? = nil, heartRate bpm: Int?,
                        note: WatchWorkoutNote? = nil) {
        if let note { workoutNote = note }
        if let command { perform(command, id: id) }
        if let bpm {
            heartRate = bpm
            heartRateAt = Date()
            onHeartRate?(bpm)
        }
    }
}

extension WatchRunLink: WCSessionDelegate {
    public nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in
            // A run published before the session was up goes now.
            if activationState == .activated, let last = self.last { self.send(last) }
            self.other?.session(session, activationDidCompleteWith: activationState, error: error)
        }
    }

    public nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Switched to another watch: start again with that one.
    public nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    public nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard WatchRunMessage.isRunMessage(message) else {
            Task { @MainActor in self.other?.session?(session, didReceiveMessage: message) }
            return
        }
        let command = WatchRunMessage.command(in: message)
        let id = WatchRunMessage.commandID(in: message)
        let bpm = WatchRunMessage.heartRate(in: message)
        let note = WatchRunMessage.workoutNote(in: message)
        Task { @MainActor in self.handle(command: command, id: id, heartRate: bpm, note: note) }
    }

    /// A command the watch couldn't get through as a message — acted on only
    /// if it's still news.
    public nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let command = WatchRunMessage.command(in: context) else {
            Task { @MainActor in self.other?.session?(session, didReceiveApplicationContext: context) }
            return
        }
        guard let sentAt = WatchRunMessage.commandSentAt(in: context),
              Date().timeIntervalSince(sentAt) < WatchRunMessage.commandFreshFor else { return }
        let id = WatchRunMessage.commandID(in: context)
        Task { @MainActor in self.handle(command: command, id: id, heartRate: nil) }
    }

    /// A note the watch queued while the phone was out of reach.
    public nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let note = WatchRunMessage.workoutNote(in: userInfo) else {
            Task { @MainActor in self.other?.session?(session, didReceiveUserInfo: userInfo) }
            return
        }
        Task { @MainActor in self.handle(command: nil, heartRate: nil, note: note) }
    }

    public nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        guard WatchRunMessage.isRunMessage(message) else {
            Task { @MainActor in
                if let other = self.other, other.responds(to: #selector(WCSessionDelegate.session(_:didReceiveMessage:replyHandler:))) {
                    other.session?(session, didReceiveMessage: message, replyHandler: replyHandler)
                } else {
                    replyHandler([:])
                    self.other?.session?(session, didReceiveMessage: message)
                }
            }
            return
        }
        if WatchRunMessage.isStateRequest(message) {
            // The watch's run ran out with nothing newer: the latest, again.
            Task { @MainActor in replyHandler(self.last.map(WatchRunMessage.encode) ?? [:]) }
            return
        }
        let command = WatchRunMessage.command(in: message)
        let id = WatchRunMessage.commandID(in: message)
        let bpm = WatchRunMessage.heartRate(in: message)
        guard command != nil else {
            replyHandler([:])
            Task { @MainActor in self.handle(command: nil, heartRate: bpm) }
            return
        }
        // Acted on now, and answered with the run as it's left.
        Task { @MainActor in
            self.handle(command: command, id: id, heartRate: bpm)
            replyHandler(self.last.map(WatchRunMessage.encode) ?? [:])
        }
    }

    /// The watch app opened mid-run: send it the run now rather than waiting
    /// for the next change.
    public nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.other?.sessionReachabilityDidChange?(session) }
        guard session.isReachable else { return }
        Task { @MainActor in
            if let last = self.last { self.send(last) }
        }
    }
}
#endif
